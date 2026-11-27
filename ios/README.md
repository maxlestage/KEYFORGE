# KeyForge pour iOS

**Forgez des clés incassables.** KeyForge génère des mots de passe, des phrases de passe et des
codes PIN, les range dans un coffre chiffré par le trousseau de l'iPhone, les partage **chiffrés en
post-quantique** (protocole Brocolis 🥦 v4 : X25519 + ML-KEM-768) et vérifie la robustesse de vos
mots de passe, sans jamais rien envoyer sur le réseau par elle-même.

Application SwiftUI pour iPhone et iPad, iOS 17 ou plus récent, sans aucune dépendance externe.

## Fonctionnalités

| Onglet | Ce qu'il fait |
|---|---|
| **Générer** | Quatre modes. *Mot de passe* : 4 à 128 caractères (20 par défaut), majuscules, minuscules, chiffres, symboles `!@#$%^&*()-_=+[]{};:,.?/`, exclusion des caractères ambigus (`0 O o 1 l I \|`), au moins un caractère de chaque famille choisie. *Phrase de passe* : 3 à 20 mots (5 par défaut) tirés d'une liste de 1 024 mots français (10 bits par mot), séparateur `-` `.` `_` espace `/`, majuscules, chiffre en option. *Code PIN* : 4 à 12 chiffres (6 par défaut). *Charabia* : 8 à 128 caractères (24 par défaut) tirés de 205 caractères, les 94 ASCII imprimables plus 111 lettres accentuées, grecques et symboles typographiques (un seul point de code NFC chacun, sans espace, caractère invisible ni sosie d'une lettre latine), soit 7,7 bits par caractère ; Unicode désactivable pour s'en tenir à l'ASCII. Tout le hasard vient de `BrocolisHasard`, le module `hasard` de brocolis-proto porté en Swift (le CSPRNG du système en production, le générateur déterministe des vecteurs dans les tests). Entropie en bits, niveau de robustesse, temps de craquage estimé, copie, enregistrement dans le coffre, historique de la session. |
| **Coffre** | Rangé **chiffré par Brocolis 🥦** : jamais de JSON en clair sur l'appareil (voir plus bas). Titre, identifiant, site web, mot de passe, notes, favori. Recherche, favoris, balayage pour supprimer ou mettre en favori, fiche détaillée (afficher/masquer, copier), formulaire avec générateur intégré. Déverrouillé par Face ID, Touch ID ou le code de l'appareil, verrouillé dès que l'app passe en arrière-plan. |
| **Analyse** | Estimation locale de l'entropie d'un mot de passe saisi : familles de caractères, longueur, pénalités pour les répétitions, les suites (`abc`, `123`), les rangées du clavier (`azerty`, `qwerty`) et ~55 mots de passe parmi les plus courants. Niveau, temps de craquage moyen à 10¹¹ essais par seconde, critères cochés et conseils. |
| **Réglages** | Verrouillage biométrique, effacement automatique du presse-papiers (jamais, 30 s, 1 min, 2 min), mode par défaut du générateur, retours haptiques, **chiffrement post-quantique** (mon identité, envoyer, recevoir), **sauvegarde chiffrée** du coffre (export et import au format Brocolis 🥦 v4), effacement du coffre (confirmé par Face ID), à propos. |
| **Envoyer chiffré** | Depuis le générateur (bouton *Envoyer*), la fiche d'une entrée du coffre ou les réglages : collez le paquet de clés du destinataire, KeyForge produit un message `[[BROCOLIS:v4:…]]` que seul son appareil ouvrira, à envoyer par n'importe quel canal. |
| **Remplissage automatique** | L'extension *KeyForgeAutoFill* fait de KeyForge un fournisseur d'identifiants d'iOS. Dans Safari et les apps, la barre au-dessus du clavier propose les identifiants du coffre pour le site ; toucher l'un d'eux demande Face ID / Touch ID / le code, puis remplit identifiant et mot de passe. Sinon, une liste (le site en tête, recherche dans tout le coffre). Sur iOS 18 et plus récent, *Remplir → Mots de passe* dans n'importe quel champ insère un secret forgé par le même moteur que l'app. À activer dans *Réglages → Général → Remplissage automatique et mots de passe* (raccourci dans les réglages de KeyForge). |
| **Vers Mots de passe** | Sur iOS 26 et plus récent, *Réglages → iPhone et Mots de passe → Transférer vers l'app Mots de passe* copie les identifiants du coffre (identifiant, mot de passe, site) dans l'app Mots de passe d'Apple ou un autre gestionnaire, par l'échange d'identifiants d'iOS (format CXF de la FIDO Alliance), après Face ID. Ils sont alors synchronisés par le trousseau iCloud et restent disponibles sans KeyForge. Les notes ne sont pas transférées. |
| **Codes de validation** | Chaque entrée peut porter un **code de validation (2FA)** : KeyForge calcule le code TOTP (RFC 6238 : SHA-1, SHA-256 ou SHA-512, 6 à 8 chiffres, période de 5 à 300 s) sur l'appareil. Ajout par le scanner de QR code, une clé secrète collée ou un lien `otpauth://` ; la fiche affiche le code du moment et son compte à rebours. KeyForge déclare le schéma `otpauth` : il peut être choisi dans *Réglages → Général → Remplissage automatique et mots de passe → Configurer les codes dans*, et les liens et QR codes de configuration s'y ouvrent alors. Sur iOS 18 et plus récent, l'extension propose le code au-dessus du clavier dans les champs de code de validation, après Face ID ; iOS ne reçoit que le site et un libellé, jamais le secret. |
| **Enregistrer** | Sur iOS 26.2 et plus récent, après une inscription ou un changement de mot de passe dans Safari ou une app, iOS propose d'enregistrer l'identifiant **dans KeyForge** (capacité `SupportsSavePasswordCredentials`, `ASSavePasswordRequest`). `VaultSave` décide : même site et même identifiant, le mot de passe est mis à jour ; sinon une nouvelle entrée ; déjà à jour, rien. Avec la clé du coffre dans la Secure Enclave, l'extension affiche une confirmation après Face ID ; avec le verrouillage biométrique coupé, un nouvel identifiant est enregistré sans rien afficher, et un remplacement demande toujours l'accord du propriétaire. |
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
- iOS 17.0 minimum (insertion d'un secret forgé : iOS 18 ; transfert vers Mots de passe : iOS 26).

Pour un appareil réel, activez dans *Signing & Capabilities*, pour la cible **KeyForge** comme
pour **KeyForgeAutoFill** : *AutoFill Credential Provider* et *Keychain Sharing* (groupe
`com.maxlestage.KeyForge.shared`). Les fichiers `KeyForge.entitlements` et
`KeyForgeAutoFill.entitlements` les déclarent déjà ; la CI compile sans signature.

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
├── KeyForgeAutoFill/            extension de remplissage automatique (ASCredentialProviderViewController) :
│                                liste, Face ID, insertion d'un secret forgé ; elle reprend de KeyForge/
│                                Core (générateur, coffre, correspondance des sites), le trousseau,
│                                Face ID et le thème
├── KeyForge.entitlements        remplissage automatique, trousseau partagé (app)
├── KeyForgeAutoFill.entitlements remplissage automatique, trousseau partagé (extension)
├── KeyForgeAutoFill-Info.plist  point d'extension et capacités du fournisseur d'identifiants
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
- **Coffre partagé avec l'extension** : l'élément du coffre vit dans le groupe de trousseau
  `com.maxlestage.KeyForge.shared`, lisible par l'app et par l'extension de remplissage
  automatique seulement, toujours `ThisDeviceOnly`. Un coffre d'une version précédente y est
  déplacé au lancement (nouvelle copie vérifiée avant de supprimer l'ancienne). L'identité
  post-quantique reste dans le groupe propre à l'app : l'extension ne peut pas la lire.
- **Remplissage automatique** : iOS ne connaît que le site et le nom d'utilisateur de chaque
  entrée (pour la barre QuickType) ; le mot de passe ne sort du coffre qu'après Face ID /
  Touch ID / le code, à chaque remplissage, même si le verrouillage biométrique de l'app est
  désactivé.
- **Transfert vers Mots de passe** : seulement à votre demande, après Face ID, par la feuille
  système d'iOS ; ensuite, les identifiants transférés suivent les règles du trousseau iCloud.
- **Verrouillage** : Face ID / Touch ID / code de l'appareil (`.deviceOwnerAuthentication`) à
  chaque ouverture si l'option est active (par défaut), verrouillage automatique en arrière-plan.
- **Presse-papiers** : copies `localOnly` (pas de presse-papiers universel) avec date d'expiration.
- **Confidentialité** : aucun code réseau, aucun compte, aucun traceur ; un écran flouté masque
  l'app dans le sélecteur d'applications ; l'historique de session est effacé en arrière-plan.

## Coffre chiffré par Brocolis 🥦

Sur l'iPhone, le coffre n'est jamais rangé en clair. Ses entrées (JSON) forment le premier
message d'une session **v4 à clé partagée** de Brocolis (`VaultSeal`, même format que la
sauvegarde chiffrée : `[[BROCOLIS:v4:…]]`, en-tête chiffré, AES-256-GCM, remplissage par blocs
de 160 octets, clé ML-KEM-768 de cliquet), scellé à nouveau avec une clé éphémère neuve à chaque
écriture. La clé du coffre (256 bits, tirée de `BrocolisHasard`) et le coffre scellé sont deux
éléments distincts du trousseau, dans le groupe partagé avec l'extension de remplissage
automatique, jamais synchronisés ni restaurés ailleurs (`WhenUnlockedThisDeviceOnly`) :
`BrocolisVault` les lit et les écrit pour l'app et pour l'extension, qui déchiffre après Face ID.

### La clé du coffre dans la Secure Enclave

Lire le trousseau ne suffit pas à ouvrir le coffre. Avec le verrouillage biométrique (actif par
défaut), la clé du coffre n'est pas rangée telle quelle : elle est enveloppée pour une clé
P-256 née dans la **Secure Enclave**, qui n'en sort jamais et que la puce n'utilise qu'après
Face ID, Touch ID ou le code (`userPresence`). `VaultEnclave` crée cette clé ; `VaultKeyWrap`
fait l'enveloppe (ECIES : clé éphémère P-256, ECDH, HKDF-SHA256, AES-256-GCM, 125 octets).
L'app et l'extension passent à l'enclave le contexte qui vient d'authentifier le propriétaire :
une seule demande Face ID, et aucune autre ne peut surgir ensuite (`interactionNotAllowed`).

- **Migration vérifiée** : à la première ouverture authentifiée, la clé est enveloppée, relue
  depuis le trousseau et rendue par l'enclave ; la clé telle quelle n'est effacée que si
  l'enclave a rendu exactement la même. Un échec ne casse rien : la clé reste dans le
  trousseau et la raison s'affiche dans *Réglages → Coffre*. Une interruption laisse les deux
  formes, et la clé telle quelle l'emporte.
- **Coffre ouvert** : la clé reste en mémoire le temps de la session, oubliée au verrouillage.
  **Coffre fermé** : ajouter une clé depuis le générateur ou importer une sauvegarde demande
  Face ID, puisque sceller à nouveau le coffre exige sa clé.
- **Verrouillage biométrique coupé** : après authentification, la clé retourne dans le
  trousseau (sans code sur l'iPhone ou sans Secure Enclave, elle y reste aussi).
- La clé dépend du code de l'iPhone : la **sauvegarde chiffrée** reste le filet de sécurité.

Un coffre d'une version précédente (JSON en clair) est scellé au premier lancement. Un coffre
scellé dont la clé manque n'est jamais écrasé : il reste fermé et l'erreur s'affiche. Effacer
le coffre supprime aussi sa clé. Tests : `BrocolisVaultTests` (vecteurs du générateur
déterministe de brocolis-proto, charabia, sceau, mauvaise clé, ancien format) et
`VaultEnclaveTests` (enveloppe, coffre dans le trousseau, coffre dans la Secure Enclave et
migration interrompue quand le banc d'essai fournit une enclave).

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

## TestFlight

[`.github/workflows/testflight.yml`](../.github/workflows/testflight.yml) archive, signe et
envoie l'app et son extension sur TestFlight, à la demande (*Actions → TestFlight → Run
workflow*, avec une version facultative). Le numéro de build augmente à chaque envoi.

Une fois pour toutes :

1. Dans App Store Connect, créez l'app (*Apps → +*), identifiant de bundle
   `com.maxlestage.KeyForge`.
2. *Utilisateurs et accès → Intégrations → API App Store Connect → Clés d'équipe → +* :
   rôle **Admin** (nécessaire pour que Xcode crée certificats et profils). Notez le
   **Key ID**, l'**Issuer ID** (en haut de la page) et téléchargez le fichier
   `AuthKey_XXXXXXXXXX.p8` (téléchargeable une seule fois).
3. Votre **Team ID** : developer.apple.com → *Account → Membership details*.
4. Dans GitHub, *Settings → Secrets and variables → Actions → New repository secret* :
   `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (tout le texte du fichier `.p8`, lignes
   `BEGIN`/`END` comprises) et `APPLE_TEAM_ID`.

La signature est automatique : Xcode enregistre les identifiants
`com.maxlestage.KeyForge` et `com.maxlestage.KeyForge.AutoFill` et active les capacités
des entitlements (remplissage automatique, partage de trousseau).

## Intégration continue

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) compile l'application pour le
simulateur et lance les tests sur un iPhone simulé (macOS 15, le Xcode le plus récent installé) à
chaque push qui touche `ios/`. En cas d'échec, le `.xcresult` est publié comme artefact.
