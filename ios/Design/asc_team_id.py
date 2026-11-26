#!/usr/bin/env python3
"""Trouve le Team ID avec une clé API App Store Connect (bibliothèque standard + openssl).

Usage : asc_team_id.py <fichier .p8> <key id> <issuer id> [bundle id]
        asc_team_id.py --app <fichier .p8> <key id> <issuer id> <bundle id>
        asc_team_id.py --register <fichier .p8> <key id> <issuer id>

Signe un jeton ES256, lit les identifiants d'app de l'équipe (GET /v1/bundleIds) et
affiche leur préfixe d'équipe (« seedId »), qui est le Team ID. Celui du bundle demandé
s'il est déjà enregistré, sinon celui du premier identifiant de l'équipe.
"""
import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """Signature ECDSA DER (SEQUENCE de deux INTEGER) → r ‖ s sur 32 octets chacun."""
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        length = der[i + 1]
        value = der[i + 2 : i + 2 + length].lstrip(b"\x00")
        out += value.rjust(32, b"\x00")
        i += 2 + length
    return out


def token(key_path: str, key_id: str, issuer: str) -> str:
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input, capture_output=True, check=True,
    ).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


def bundle_ids(jwt: str, identifier: str | None) -> list:
    query = {"limit": "200", "fields[bundleIds]": "identifier,seedId"}
    if identifier:
        query["filter[identifier]"] = identifier
    url = "https://api.appstoreconnect.apple.com/v1/bundleIds?" + urllib.parse.urlencode(query)
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {jwt}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response).get("data", [])


def api(jwt: str, method: str, path: str, body: dict | None = None) -> dict:
    """Un appel à l'API App Store Connect ; l'erreur d'Apple est affichée telle quelle."""
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            text = response.read()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise RuntimeError(f"{method} {path} : HTTP {error.code} {detail}") from None


def register(jwt: str, identifier: str, name: str, capabilities: list[str]) -> None:
    """Enregistre l'identifiant de bundle (s'il n'existe pas) et active ses capacités."""
    query = urllib.parse.urlencode({"filter[identifier]": identifier, "include": "bundleIdCapabilities"})
    found = [d for d in api(jwt, "GET", f"/v1/bundleIds?{query}").get("data", [])
             if d["attributes"]["identifier"] == identifier]
    if found:
        bundle_id = found[0]["id"]
        print(f"Identifiant déjà enregistré : {identifier}")
    else:
        created = api(jwt, "POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
            "identifier": identifier, "name": name, "platform": "IOS"}}})
        bundle_id = created["data"]["id"]
        print(f"Identifiant enregistré : {identifier}")
    existing = {c["attributes"]["capabilityType"]
                for c in api(jwt, "GET", f"/v1/bundleIds/{bundle_id}/bundleIdCapabilities").get("data", [])}
    for capability in capabilities:
        if capability in existing:
            print(f"  capacité déjà active : {capability}")
            continue
        try:
            api(jwt, "POST", "/v1/bundleIdCapabilities", {"data": {
                "type": "bundleIdCapabilities",
                "attributes": {"capabilityType": capability},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}}},
            }})
            print(f"  capacité activée : {capability}")
        except RuntimeError as error:
            print(f"::warning::{identifier} : capacité {capability} non activée ({error})")


def app_record(jwt: str, bundle: str) -> dict | None:
    """La fiche App Store Connect de l'app dont le bundle est `bundle`, ou None."""
    query = {"filter[bundleId]": bundle, "fields[apps]": "name,bundleId,sku"}
    url = "https://api.appstoreconnect.apple.com/v1/apps?" + urllib.parse.urlencode(query)
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {jwt}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = json.load(response).get("data", [])
    return data[0] if data else None


def main() -> None:
    if sys.argv[1] == "--register":
        # Les identifiants de l'app et de l'extension, avec le remplissage automatique.
        key_path, key_id, issuer = sys.argv[2:5]
        jwt = token(key_path, key_id, issuer)
        register(jwt, "com.maxlestage.KeyForge", "KeyForge", ["AUTOFILL_CREDENTIAL_PROVIDER"])
        register(jwt, "com.maxlestage.KeyForge.AutoFill", "KeyForge AutoFill", ["AUTOFILL_CREDENTIAL_PROVIDER"])
        return
    if sys.argv[1] == "--app":
        # Vérifie que l'app existe dans App Store Connect (sinon l'envoi échoue avec
        # « Error Downloading App Information »).
        key_path, key_id, issuer, bundle = sys.argv[2:6]
        record = app_record(token(key_path, key_id, issuer), bundle)
        if record is None:
            sys.exit(
                f"Aucune app {bundle} dans App Store Connect pour cette clé : créez-la "
                "(Apps → + → Nouvelle app, identifiant de bundle " + bundle + ")."
            )
        print(f"App trouvée : {record['attributes'].get('name')} ({bundle}, id {record['id']})")
        return
    key_path, key_id, issuer = sys.argv[1:4]
    wanted = sys.argv[4] if len(sys.argv) > 4 else None
    jwt = token(key_path, key_id, issuer)
    found = (bundle_ids(jwt, wanted) if wanted else []) or bundle_ids(jwt, None)
    for item in found:
        seed = item.get("attributes", {}).get("seedId")
        if seed:
            print(seed)
            return
    sys.exit("Aucun identifiant d'app dans l'équipe : renseignez le secret APPLE_TEAM_ID.")


if __name__ == "__main__":
    main()
