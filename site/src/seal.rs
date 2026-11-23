//! Le chiffrement de KeyForge, confié à [brocolis-proto](https://github.com/maxlestage/brocolis) 🥦.
//!
//! Un « secret scellé » est fait de deux jetons Brocolis, l'un sous l'autre :
//!
//! ```text
//! [[BROCOLIS-CLE:v2:…]]   une clé aléatoire de 32 octets, protégée par la phrase (Argon2id)
//! [[BROCOLIS:v1:…]]       le texte, chiffré en AES-256-GCM sous cette clé
//! ```
//!
//! C'est exactement le format de la sauvegarde chiffrée de l'app iOS, et les apps Brocolis
//! savent lire chacun des deux jetons. Rien ici n'est de la cryptographie maison : la
//! dérivation, le chiffrement et l'encodage sont ceux de brocolis-proto.

use brocolis_proto::cle_protegee::{self, Argon2Params};
use brocolis_proto::hasard::{CryptoRng, bytes};
use brocolis_proto::{Erreur, jetons};

pub use cle_protegee::PHRASE_MIN;

/// Les paramètres Argon2id utilisés pour sceller : ceux de Brocolis par défaut (64 Mio,
/// 3 passes, 1 voie).
pub const PARAMS: Argon2Params = Argon2Params::DEFAULT;

/// Scelle `text` sous `phrase`.
pub fn seal(
    text: &str,
    phrase: &str,
    params: Argon2Params,
    rng: &mut (impl CryptoRng + ?Sized),
) -> Result<String, Erreur> {
    if text.is_empty() {
        return Err(Erreur::Format);
    }
    let key: [u8; 32] = bytes(rng);
    let salt: [u8; 16] = bytes(rng);
    let nonce: [u8; 12] = bytes(rng);
    let protected = cle_protegee::protect_key_v2_with(&key, phrase, params, &salt, &nonce)?;
    let token = jetons::seal_token(text, &[key], rng).ok_or(Erreur::Format)?;
    Ok(format!("{protected}\n{token}"))
}

/// Le premier jeton `[[BROCOLIS:…]]` d'un texte collé.
fn token(blob: &str) -> Option<&str> {
    let start = blob.find(jetons::HEAD)?;
    let end = blob[start..].find("]]")? + start + 2;
    Some(&blob[start..end])
}

/// Ouvre un secret scellé (les deux jetons, n'importe où dans le texte collé).
pub fn open(blob: &str, phrase: &str) -> Result<String, Erreur> {
    let token = token(blob).ok_or(Erreur::JetonAbsent)?;
    let key = cle_protegee::unprotect_key(blob, phrase)?;
    let opened = jetons::open(token, &[*key]);
    if opened.opened == 1 {
        Ok(opened.text)
    } else {
        Err(Erreur::Dechiffrement)
    }
}

/// Vrai si le texte ressemble à un secret scellé.
pub fn is_sealed(blob: &str) -> bool {
    cle_protegee::has_protected_key(blob) && token(blob).is_some()
}

/// Les paramètres annoncés par un secret scellé, pour prévenir avant le calcul.
pub fn params_of(blob: &str) -> Option<Argon2Params> {
    cle_protegee::v2_params(blob).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use brocolis_proto::hasard::Deterministic;

    // Les vecteurs de brocolis-proto (proto/vectors.json) : le format n'a pas dérivé.
    const CLE_V2_MINIMUM: &str = "[[BROCOLIS-CLE:v2:AgAATAACATMzMzMzMzMzMzMzMzMzMzNERERERERERERERERAUxWgTZ6ZBUGbuMWWk5gln1V7GZgwoYOu0FWCX4KZU25GrK9aOSl+ZjCHSgr6Glk=]]";
    const JETON_V1: &str = "[[BROCOLIS:v1:rJ0bFC0ezvGOT/o9DTvx9YeDWhXv9HSWqp3ARMc9XcQLB7zbzVI=]]";
    const JETON_V1_CLE: &str = "42dacfb18bcfa86c9337ed322d188270dfe2d3e06334cdfd15960645332c1ee1";

    fn hex(s: &str) -> [u8; 32] {
        core::array::from_fn(|i| u8::from_str_radix(&s[2 * i..2 * i + 2], 16).unwrap())
    }

    #[test]
    fn the_brocolis_vectors_still_hold() {
        let key = cle_protegee::unprotect_key(CLE_V2_MINIMUM, "brocoli vert 2026").unwrap();
        assert_eq!(*key, core::array::from_fn::<u8, 32, _>(|i| i as u8));
        assert_eq!(
            cle_protegee::unprotect_key(CLE_V2_MINIMUM, "brocoli vert 2025"),
            Err(Erreur::Dechiffrement)
        );
        assert_eq!(
            jetons::open(JETON_V1, &[hex(JETON_V1_CLE)]).text,
            "Salut 🥦"
        );
    }

    #[test]
    fn seal_then_open() {
        let mut rng = Deterministic::new(b"keyforge");
        let blob = seal(
            "Galet-Phare7-Sorbet",
            "une phrase de passe",
            Argon2Params::MINIMUM,
            &mut rng,
        )
        .unwrap();
        assert!(blob.starts_with("[[BROCOLIS-CLE:v2:") && blob.contains("\n[[BROCOLIS:v1:"));
        assert!(is_sealed(&blob));
        assert_eq!(params_of(&blob), Some(Argon2Params::MINIMUM));
        // Collé au milieu d'un message, il s'ouvre aussi.
        let pasted = format!("Voici ma sauvegarde :\n{blob}\nÀ garder.");
        assert_eq!(
            open(&pasted, "une phrase de passe").unwrap(),
            "Galet-Phare7-Sorbet"
        );
        assert_eq!(open(&blob, "une autre phrase"), Err(Erreur::Dechiffrement));
        assert_eq!(
            open("rien", "une phrase de passe"),
            Err(Erreur::JetonAbsent)
        );
    }

    #[test]
    fn short_phrases_are_refused() {
        let mut rng = Deterministic::new(b"keyforge");
        assert_eq!(
            seal("x", "court", Argon2Params::MINIMUM, &mut rng),
            Err(Erreur::PhraseTropCourte)
        );
    }
}
