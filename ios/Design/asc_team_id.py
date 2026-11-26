#!/usr/bin/env python3
"""Trouve le Team ID avec une clé API App Store Connect (bibliothèque standard + openssl).

Usage : asc_team_id.py <fichier .p8> <key id> <issuer id> [bundle id]

Signe un jeton ES256, lit les identifiants d'app de l'équipe (GET /v1/bundleIds) et
affiche leur préfixe d'équipe (« seedId »), qui est le Team ID. Celui du bundle demandé
s'il est déjà enregistré, sinon celui du premier identifiant de l'équipe.
"""
import base64
import json
import subprocess
import sys
import time
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


def main() -> None:
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
