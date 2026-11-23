//! Le chiffrement post-quantique de KeyForge : le protocole **v4 de Brocolis 🥦**
//! ([brocolis-proto](https://github.com/maxlestage/brocolis)), utilisé tel quel.
//!
//! - Une **identité** : IK X25519 + Ed25519, une SPK X25519 signée et une PQPK
//!   **ML-KEM-768** signée. Son **paquet de clés** public (base64) se partage.
//! - **Chiffrer pour un paquet** : établissement hybride façon PQXDH — trois X25519 et une
//!   encapsulation ML-KEM-768 mélangés dans la clé de session —, identité de l'expéditeur
//!   cachée dans un préambule chiffré, en-têtes chiffrés : `[[BROCOLIS:v4:…]]` (type 0x01).
//!   Le secret tient tant que X25519 **ou** ML-KEM-768 tient : un ordinateur quantique qui
//!   casserait X25519 ne suffit pas.
//! - **Déchiffrer** : `Device::accept4`, avec la mémoire des premiers messages (rejeu refusé).
//!
//! Le hasard et l'heure sont fournis par l'appelant (`crypto.getRandomValues` et
//! `Date.now()` dans le navigateur), comme le veut la crate.

use brocolis_proto::hasard::CryptoRng;
use brocolis_proto::kdf::fingerprint;
use brocolis_proto::{Content, Device, Erreur, KeyBundle, Token4};

/// Le début d'un jeton v4.
pub const HEAD_V4: &str = "[[BROCOLIS:v4:";

/// Une nouvelle identité post-quantique (avec ML-KEM-768).
pub fn new_identity(rng: &mut (impl CryptoRng + ?Sized), now: u64) -> Device {
    Device::generate(rng, now, true)
}

/// Le paquet de clés publiques d'une identité, en base64 : ce qu'on donne aux autres.
pub fn bundle(device: &Device) -> Result<String, Erreur> {
    Ok(device.bundle()?.to_base64())
}

/// L'empreinte de l'identité (IK X25519 ‖ IK Ed25519), comme dans les apps Brocolis.
pub fn identity_fingerprint(device: &Device) -> String {
    device.identity().fingerprint()
}

/// L'empreinte de l'IK X25519 seule : celle qu'un destinataire voit sur un message reçu
/// (le préambule ne révèle que cette clé).
pub fn sender_fingerprint(device: &Device) -> String {
    fingerprint(&device.identity().dh)
}

/// Lit un paquet collé : vérifie ses signatures Ed25519 et qu'il propose ML-KEM-768.
pub fn read_bundle(text: &str) -> Result<KeyBundle, Erreur> {
    let compact: String = text.chars().filter(|c| !c.is_whitespace()).collect();
    let bundle = KeyBundle::from_base64(&compact)?;
    bundle.verify()?;
    if bundle.pq.is_none() {
        return Err(Erreur::PqIndisponible);
    }
    Ok(bundle)
}

/// Chiffre `text` pour le destinataire du paquet, de la part de `sender`.
pub fn encrypt_for(
    sender: &Device,
    recipient: &str,
    text: &str,
    rng: &mut (impl CryptoRng + ?Sized),
) -> Result<String, Erreur> {
    if text.is_empty() {
        return Err(Erreur::Format);
    }
    let bundle = read_bundle(recipient)?;
    let mut session = sender.initiate4(&bundle, rng)?;
    session.encrypt(text)
}

/// Le premier jeton v4 d'un texte collé.
pub fn find_v4(text: &str) -> Option<&str> {
    let start = text.find(HEAD_V4)?;
    let end = text[start..].find("]]")? + start + 2;
    Some(&text[start..end])
}

/// Un message reçu et ouvert.
#[derive(Debug, PartialEq)]
pub struct Received {
    pub text: String,
    /// L'empreinte X25519 de l'expéditeur (voir [`sender_fingerprint`]).
    pub from: String,
}

/// Déchiffre un premier message v4 adressé à `device`. Le même message ne s'ouvre
/// qu'une fois ([`Erreur::Rejoue`] ensuite).
pub fn decrypt(
    device: &mut Device,
    text: &str,
    now: u64,
    rng: &mut (impl CryptoRng + ?Sized),
) -> Result<Received, Erreur> {
    let token = Token4::decode(find_v4(text).ok_or(Erreur::JetonAbsent)?)?;
    let (session, content) = device.accept4(&token, now, rng)?;
    let from = session
        .peer_identity()
        .map(|ik| fingerprint(&ik))
        .unwrap_or_default();
    match content {
        Content::Text(text) => Ok(Received { text, from }),
        Content::Distribution(_) => Err(Erreur::Format),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use brocolis_proto::hasard::Deterministic;

    #[test]
    fn a_secret_crosses_post_quantum() {
        let mut rng = Deterministic::new(b"keyforge-pq");
        let alice = new_identity(&mut rng, 0);
        let mut bob = new_identity(&mut rng, 0);
        let paquet = bundle(&bob).unwrap();
        // Un paquet ML-KEM-768 : plus de 1 184 octets de clé d'encapsulation.
        assert!(paquet.len() > 1_600);
        let token = encrypt_for(&alice, &paquet, "Galet-Phare7-Sorbet 🥦", &mut rng).unwrap();
        assert!(token.starts_with(HEAD_V4));
        // L'identité d'Alice n'apparaît pas en clair.
        assert!(!token.contains(&sender_fingerprint(&alice)));
        let got = decrypt(&mut bob, &format!("Pour toi :\n{token}\n"), 10, &mut rng).unwrap();
        assert_eq!(got.text, "Galet-Phare7-Sorbet 🥦");
        assert_eq!(got.from, sender_fingerprint(&alice));
        // Rejeu refusé, et personne d'autre ne l'ouvre.
        assert_eq!(decrypt(&mut bob, &token, 11, &mut rng), Err(Erreur::Rejoue));
        let mut eve = new_identity(&mut rng, 0);
        assert_eq!(
            decrypt(&mut eve, &token, 12, &mut rng),
            Err(Erreur::CleInconnue)
        );
    }

    #[test]
    fn broken_bundles_are_refused() {
        let mut rng = Deterministic::new(b"keyforge-pq-2");
        let alice = new_identity(&mut rng, 0);
        assert!(encrypt_for(&alice, "pas un paquet", "x", &mut rng).is_err());
        let mut paquet = bundle(&alice).unwrap().into_bytes();
        // Une signature altérée : refusée.
        let i = paquet.len() / 2;
        paquet[i] = if paquet[i] == b'A' { b'B' } else { b'A' };
        assert!(read_bundle(&String::from_utf8(paquet).unwrap()).is_err());
        // Sans ML-KEM : refusé (pas de repli classique).
        let classic = Device::generate(&mut rng, 0, false);
        assert_eq!(
            read_bundle(&classic.bundle().unwrap().to_base64()).err(),
            Some(Erreur::PqIndisponible)
        );
    }

    #[test]
    fn the_identity_survives_a_reload() {
        let mut rng = Deterministic::new(b"keyforge-pq-3");
        let device = new_identity(&mut rng, 0);
        let json = device.to_json();
        let back = Device::from_json(&json).unwrap();
        assert_eq!(identity_fingerprint(&back), identity_fingerprint(&device));
        assert!(back.supports_pq());
    }
}
