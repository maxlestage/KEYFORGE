# KeyForge pour iOS

**Forgez des clés incassables.** KeyForge génère des mots de passe, des phrases de passe et des
codes PIN, les range dans un coffre chiffré par le trousseau de l'iPhone, les partage **chiffrés en
post-quantique** (protocole Brocolis 🥦 v4 : X25519 + ML-KEM-768) et vérifie la robustesse de vos
mots de passe, sans jamais rien envoyer sur le réseau par elle-même.

Application SwiftUI pour iPhone et iPad, iOS 17 ou plus récent, sans aucune dépendance externe.

## Fonctionnalités

| Onglet | Ce qu'il fait |
|---|---|
| **Générer** | Trois modes. *Mot de passe* : 4 à 128 caractères (20 par défaut), majuscules, minuscules, chiffres, symboles `!@#$%^&*()-_=+[]{};:,.?/`, exclusion des caractères ambigus (`0 O o 1 l I \|`), au moins un caractère de chaque famille choisie. *Phrase de passe* : 3 à 12 mots (5 par défaut) tirés d'une liste de 1 024 mots français (10 bits par mot), séparateur `-` `.` `_` espace `/`, majuscules, chiffre en option. *Code PIN* : 4 à 12 chiffres (6 par défaut). Entropie en bits, niveau de robustesse, temps de craquage estimé, copie, enregistrement dans le coffre, historique de la session. |
| **Coffre** | Titre, identifiant, site web, mot de passe, notes, favori. Recherche, favoris, balayage pour supprimer ou mettre en favori, fiche détaillée (afficher/masquer, copier), formulaire avec générateur intégré. Déverrouillé par Face ID, Touch ID ou le code de l'appareil, verrouillé dès que l'app passe en arrière-plan. |
| **Analyse** | Estimation locale de l'entropie d'un mot de passe saisi : familles de caractères, longueur, pénalités pour les répétitions, les suites (`abc`, `123`), les rangées du clavier (`azerty`, `qwerty`) et ~55 mots de passe parmi les plus courants. Niveau, temps de craquage moyen à 10¹¹ essais par seconde, critères cochés et conseils. |
| **Réglages** | Verrouillage biométrique, effacement automatique du presse-papiers (jamais, 30 s, 1 min, 2 min), mode par défaut du générateur, retours haptiques, **chiffrement post-quantique** (mon identité, envoyer, recevoir), **sauvegarde chiffrée** du coffre (export et import au format Brocolis 🥦 v4), effacement du coffre (confirmé par Face ID), à propos. |
| **Envoyer chiffré** | Depuis le générateur (bouton *Envoyer*), la fiche d'une entrée du coffre ou les réglages : collez le paquet de clés du destinataire, KeyForge produit un message `[[BROCOLIS:v4:…]]` que seul son appareil ouvrira, à envoyer par n'importe quel canal. |
| **Recevoir** | Collez un message `[[BROCOLIS:v4:…]]` chiffré pour vous : le secret s'affiche avec l'empreinte de l'expéditeur, à copier ou à ranger dans le coffre. |

Niveaux de robustesse selon l'entropie : moins de 28 bits *Très faible*, moins de 36 *Faible*,
moins de 60 *Correcte*, moins de 128 *Forte*, 128 et plus *Excellente*.

Une présentation animée en trois écrans (Forgez, Protégez, Vérifiez) accueille le premier lancement.
L'interface est animée en 2D uniquement (ressorts, effets de symboles SF, `phaseAnimator`,
`keyframeAnimator`, `matchedGeometryEffect`, étincelles dessinées dans un `Canvas`) et s'apaise quand
*Réduire les animations* est activé. Dynamic Type et VoiceOver sont pris en charge.

## Prérequis

- Xcode 16 ou plus récent (le projet utilise les dossiers synchronisés d'Xcode 16 : un fichier
  ajouté dans `KeyForge/` ou `KeyForgeTests/` fait automatiquement partie de la cible) ;
- iOS 17.0 minimum.

## Lancer l'application

```sh
open ios/KeyForge.xcodeproj
```

Choisissez le schéma **KeyForge** et un simulateur, puis ⌘R. Pour un appareil réel, sélectionnez
votre équipe dans *Signing & Capabilities* (aucune équipe n'est enregistrée dans le projet).

En ligne de commande :

```sh
cd ios
xcodebuild -project KeyForge.xcodeproj -scheme KeyForge \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Architecture

```text
ios/
├── KeyForge.xcodeproj           projet Xcode 16 (dossiers synchronisés) et schéma partagé
├── KeyForge/
│   ├── KeyForgeApp.swift        point d'entrée, injection des modèles
│   ├── Core/                    logique pure (Foundation seulement), testée aussi sous Linux
│   │   ├── Generator.swift          modes, options, génération (SystemRandomNumberGenerator)
│   │   ├── Entropy.swift            entropie et niveaux de robustesse
│   │   ├── PasswordAnalyzer.swift   analyse d'un mot de passe saisi
│   │   ├── CrackTime.swift          temps de craquage en français
│   │   ├── WordList.swift           liste de mots des phrases de passe
│   │   ├── VaultItem.swift          une entrée du coffre (Codable)
│   │   ├── Blake2b.swift            BLAKE2b (RFC 7693)
│   │   ├── Argon2.swift             Argon2id (RFC 9106, v0x13), en Swift pur
│   │   ├── Brocolis.swift           clés protégées Brocolis 🥦 et sauvegarde chiffrée du coffre
│   │   ├── BrocolisV4.swift         protocole Brocolis v4 : appareil, paquet de clés, messages
│   │   ├── MLKEM.swift              ML-KEM-768 (FIPS 203), en Swift pur
│   │   ├── Keccak.swift             SHA3-256/512, SHAKE128/256 (FIPS 202)
│   │   └── SHA256.swift             SHA-256, HMAC, HKDF (dérivations du protocole)
│   ├── Services/                trousseau (Security), Face ID (LocalAuthentication),
│   │                            presse-papiers, retours haptiques ; AES-GCM, X25519, Ed25519
│   │                            (CryptoKit) et PBKDF2 (CommonCrypto) pour Brocolis
│   ├── Stores/                  AppSettings, VaultStore, GeneratorModel, IdentityStore (@Observable)
│   ├── Theme/                   palette « forge », dégradés, cartes, apparitions
│   ├── Views/                   écrans (onboarding, générateur, coffre, analyse, réglages,
│   │                            sauvegarde, identité post-quantique, envoyer, recevoir)
│   │   └── Components/          logo, boutons, barre de robustesse, texte animé, fond, toasts
│   ├── Resources/wordlist-fr.txt    les 1 024 mots (copie de shared/wordlist-fr.txt)
│   ├── Assets.xcassets          icône 1024 × 1024 et couleur d'accent
│   └── PrivacyInfo.xcprivacy    manifeste de confidentialité
├── KeyForgeTests/               tests XCTest de la logique
└── Design/icon.svg              source de l'icône
```

## Modèle de sécurité

- **Aléa cryptographique** : `SystemRandomNumberGenerator` (le CSPRNG du système) et
  `Int.random(in:using:)`, qui tire sans biais de modulo.
- **Coffre** : toutes les entrées forment un JSON stocké dans *un* élément du trousseau
  (`kSecClassGenericPassword`, service `com.maxlestage.KeyForge.vault`), avec
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` : lisible seulement quand l'iPhone est déverrouillé,
  jamais synchronisé dans iCloud ni restauré sur un autre appareil. Les entrées ne sont en mémoire
  que pendant que le coffre est ouvert.
- **Verrouillage** : Face ID / Touch ID / code de l'appareil (`.deviceOwnerAuthentication`) à
  chaque ouverture si l'option est active (par défaut), verrouillage automatique en arrière-plan.
- **Presse-papiers** : copies `localOnly` (pas de presse-papiers universel) avec date d'expiration.
- **Confidentialité** : aucun code réseau, aucun compte, aucun traceur ; un écran flouté masque
  l'app dans le sélecteur d'applications ; l'historique de session est effacé en arrière-plan.

## Chiffrement post-quantique (Brocolis 🥦 v4)

KeyForge chiffre avec le **protocole v4 de [Brocolis 🥦](https://github.com/maxlestage/brocolis)**
(crate `brocolis-proto`), porté en Swift octet pour octet : le site de KeyForge (qui utilise la
crate Rust compilée en WebAssembly) et les apps Brocolis lisent les mêmes paquets et les mêmes
messages.

- **Identité** : un appareil Brocolis (identité X25519 + Ed25519, clé pré-signée X25519, clé
  ML-KEM-768 signée), créé une fois et gardé dans le trousseau (service
  `com.maxlestage.KeyForge.identity`, `ThisDeviceOnly`). Son **paquet de clés** (1 418 octets,
  partagé en base64 ou en QR code) ne contient que des clés publiques, signées ; on compare son
  empreinte (`SHA-256(IK X25519 ‖ IK Ed25519)[0..8]`) de vive voix.
- **Envoyer** (`BrocolisV4.encrypt`) : le premier message d'une session v4 (type `0x01`) :
  `SK = HKDF(FF³² ‖ DH1 ‖ DH2 ‖ DH3 ‖ SS)` mêle trois X25519 et le secret d'une encapsulation
  **ML-KEM-768** vers la clé du destinataire ; l'identité de l'expéditeur voyage dans un préambule
  chiffré, l'en-tête de cliquet est chiffré, le texte est rembourré à 160 octets et chiffré en
  AES-256-GCM. Le message est **hybride** : il reste confidentiel tant que X25519 *ou* ML-KEM-768
  tient, y compris face à un ordinateur quantique capable de casser X25519.
- **Recevoir** (`BrocolisV4.accept`) : ouvre un `0x01` chiffré pour mon appareil, refuse un
  message déjà ouvert (clés éphémères retenues 30 jours) et donne la clé d'échange de l'expéditeur.
- **Limites, honnêtement** : ce sont des messages « en un coup » — KeyForge n'entretient pas de
  conversation (pas de cliquet continu ni de réponses). Le paquet n'est pas renouvelé
  automatiquement : *Nouvelle identité* en crée un autre (les anciens messages ne s'ouvrent plus).
  Les signatures Ed25519 de CryptoKit peuvent varier d'un calcul à l'autre : le paquet publié est
  donc mémorisé tel quel. Un appareil compromis ou une empreinte non vérifiée restent hors de
  portée de toute cryptographie.
- **ML-KEM-768** (FIPS 203 : génération depuis la graine `d ‖ z`, encapsulation avec `m` donné,
  décapsulation à rejet implicite, contrôle de module de la clé) et **Keccak** sont écrits en Swift
  pur ; X25519, Ed25519 et AES-GCM viennent de CryptoKit, SHA-256/HMAC/HKDF sont en Swift pur.

## Sauvegarde chiffrée (format Brocolis 🥦)

Le coffre ne quitte jamais l'iPhone… sauf si vous décidez d'en garder une copie. *Réglages →
Sauvegarde chiffrée* l'exporte dans un fichier texte (`keyforge-sauvegarde.brocolis.txt`), chiffré
**sur l'appareil** avec les formats de [Brocolis 🥦](https://github.com/maxlestage/brocolis)
(crate `brocolis-proto`), repris octet pour octet :

```text
[[BROCOLIS-CLE:v2:<base64>]]   la clé K (32 octets aléatoires), protégée par votre phrase
[[BROCOLIS:v4:<base64>]]       le coffre en JSON : premier message d'une session v4 à clé partagée K
```

Une clé de 256 bits et AES-256 restent hors de portée d'un ordinateur quantique (l'algorithme de
Grover ne fait que diviser l'exposant par deux) ; le message v4 ajoute l'en-tête chiffré, le
remplissage et la clé ML-KEM-768 de cliquet du protocole. Les sauvegardes de l'ancien format
(`[[BROCOLIS:v1:…]]`) s'importent toujours.

- **Clé protégée v2** (83 octets) : `0x02 ‖ m (u32 BE) ‖ t ‖ p ‖ sel (16) ‖ nonce (12) ‖
  AES-256-GCM(K) + tag`, l'en-tête de 35 octets en données associées ; la clé de chiffrement est
  `Argon2id(phrase, sel, m = 64 Mio, t = 3, p = 1)`, sur 32 octets. À l'import, les paramètres sont
  bornés comme dans brocolis-proto (m de 19 Mio à 1 Gio, 2 à 16 passes) ; les clés protégées v1
  (PBKDF2-HMAC-SHA256, 600 000 tours) se lisent aussi.
- **Message v4 à clé partagée** (`BrocolisV4.encryptPSK` / `acceptPSK`) : `SK = HKDF(K,
  "Brocolis_v4_PSK_SHA-256")`, clés d'en-tête et de chaîne dérivées comme dans `session4.rs`.
- **Jeton v1** (lecture des anciennes sauvegardes) : `nonce (12) ‖ AES-256-GCM(JSON) ‖ tag`.
- **Phrase** : 8 caractères au moins ; le bouton *Générer une phrase de passe* en propose une de
  6 mots (environ 63 bits) avec le générateur de l'app.
- **Argon2id** est écrit en Swift pur (`Core/Argon2.swift`, `Core/Blake2b.swift`, sans
  dépendance) et tourne hors du fil principal ; AES-GCM vient de CryptoKit. L'import ajoute les
  entrées absentes du coffre (même identifiant : ignorée) et n'écrit jamais par-dessus un coffre
  illisible.

Les apps Brocolis lisent ces formats, et les tests vérifient les vecteurs officiels de
brocolis-proto (`proto/vectors.json`) : `BrocolisTests` (clés protégées v2 aux paramètres minimum
et par défaut, clé v1, jeton v1 « Salut 🥦 », paramètres refusés) et `BrocolisV4Tests` (ML-KEM-768,
paquet de clés, premiers messages v4 par paquet et à clé partagée reproduits octet pour octet,
rejeu, mauvais destinataire, aller-retour, sauvegarde v4 et import d'une sauvegarde v1).

## Tests

`KeyForgeTests` couvre la génération (longueurs, familles, caractères ambigus, mots, séparateurs,
PIN), l'entropie et les niveaux, l'analyseur (mots de passe courants, motifs), le temps de
craquage et les entrées du coffre ; `BrocolisTests` et `BrocolisV4Tests` vérifient Argon2id,
ML-KEM-768 et les formats Brocolis contre les vecteurs de brocolis-proto. Dans Xcode : ⌘U.

La logique de `Core/` n'importe que Foundation : elle se compile et se teste aussi avec Swift sous
Linux, dans un paquet SwiftPM qui reprend ces fichiers, avec
[swift-crypto](https://github.com/apple/swift-crypto) à la place de CryptoKit : les vecteurs v4 y
sont vérifiés octet pour octet, et des messages échangés dans les deux sens avec la crate Rust
`brocolis-proto` s'ouvrent de part et d'autre.

## Intégration continue

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) compile l'application pour le
simulateur et lance les tests sur un iPhone simulé (macOS 15, le Xcode le plus récent installé) à
chaque push qui touche `ios/`. En cas d'échec, le `.xcresult` est publié comme artefact.
