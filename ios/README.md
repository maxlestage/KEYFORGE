# KeyForge pour iOS

**Forgez des clés incassables.** KeyForge génère des mots de passe, des phrases de passe et des
codes PIN, les range dans un coffre chiffré par le trousseau de l'iPhone, et vérifie la robustesse
de vos mots de passe, sans jamais rien envoyer sur le réseau.

Application SwiftUI pour iPhone et iPad, iOS 17 ou plus récent, sans aucune dépendance externe.

## Fonctionnalités

| Onglet | Ce qu'il fait |
|---|---|
| **Générer** | Trois modes. *Mot de passe* : 4 à 128 caractères (20 par défaut), majuscules, minuscules, chiffres, symboles `!@#$%^&*()-_=+[]{};:,.?/`, exclusion des caractères ambigus (`0 O o 1 l I \|`), au moins un caractère de chaque famille choisie. *Phrase de passe* : 3 à 12 mots (5 par défaut) tirés d'une liste de 1 024 mots français (10 bits par mot), séparateur `-` `.` `_` espace `/`, majuscules, chiffre en option. *Code PIN* : 4 à 12 chiffres (6 par défaut). Entropie en bits, niveau de robustesse, temps de craquage estimé, copie, enregistrement dans le coffre, historique de la session. |
| **Coffre** | Titre, identifiant, site web, mot de passe, notes, favori. Recherche, favoris, balayage pour supprimer ou mettre en favori, fiche détaillée (afficher/masquer, copier), formulaire avec générateur intégré. Déverrouillé par Face ID, Touch ID ou le code de l'appareil, verrouillé dès que l'app passe en arrière-plan. |
| **Analyse** | Estimation locale de l'entropie d'un mot de passe saisi : familles de caractères, longueur, pénalités pour les répétitions, les suites (`abc`, `123`), les rangées du clavier (`azerty`, `qwerty`) et ~55 mots de passe parmi les plus courants. Niveau, temps de craquage moyen à 10¹¹ essais par seconde, critères cochés et conseils. |
| **Réglages** | Verrouillage biométrique, effacement automatique du presse-papiers (jamais, 30 s, 1 min, 2 min), mode par défaut du générateur, retours haptiques, **sauvegarde chiffrée** du coffre (export et import au format Brocolis 🥦), effacement du coffre (confirmé par Face ID), à propos. |

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
│   │   └── Brocolis.swift           formats Brocolis 🥦 et sauvegarde chiffrée du coffre
│   ├── Services/                trousseau (Security), Face ID (LocalAuthentication),
│   │                            presse-papiers, retours haptiques, AES-GCM (CryptoKit) et
│   │                            PBKDF2 (CommonCrypto) pour les formats Brocolis
│   ├── Stores/                  AppSettings, VaultStore, GeneratorModel (@Observable)
│   ├── Theme/                   palette « forge », dégradés, cartes, apparitions
│   ├── Views/                   écrans (onboarding, générateur, coffre, analyse, réglages)
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

## Sauvegarde chiffrée (format Brocolis 🥦)

Le coffre ne quitte jamais l'iPhone… sauf si vous décidez d'en garder une copie. *Réglages →
Sauvegarde chiffrée* l'exporte dans un fichier texte (`keyforge-sauvegarde.brocolis.txt`), chiffré
**sur l'appareil** avec les formats de [Brocolis 🥦](https://github.com/maxlestage/brocolis)
(crate `brocolis-proto`), repris octet pour octet :

```text
[[BROCOLIS-CLE:v2:<base64>]]   la clé K (32 octets aléatoires), protégée par votre phrase
[[BROCOLIS:v1:<base64>]]       le coffre en JSON, chiffré sous K
```

- **Clé protégée v2** (83 octets) : `0x02 ‖ m (u32 BE) ‖ t ‖ p ‖ sel (16) ‖ nonce (12) ‖
  AES-256-GCM(K) + tag`, l'en-tête de 35 octets en données associées ; la clé de chiffrement est
  `Argon2id(phrase, sel, m = 64 Mio, t = 3, p = 1)`, sur 32 octets. À l'import, les paramètres sont
  bornés comme dans brocolis-proto (m de 19 Mio à 1 Gio, 2 à 16 passes) ; les clés protégées v1
  (PBKDF2-HMAC-SHA256, 600 000 tours) se lisent aussi.
- **Jeton v1** : `nonce (12) ‖ AES-256-GCM(JSON) ‖ tag`.
- **Phrase** : 8 caractères au moins ; le bouton *Générer une phrase de passe* en propose une de
  6 mots (environ 63 bits) avec le générateur de l'app.
- **Argon2id** est écrit en Swift pur (`Core/Argon2.swift`, `Core/Blake2b.swift`, sans
  dépendance) et tourne hors du fil principal ; AES-GCM vient de CryptoKit. L'import ajoute les
  entrées absentes du coffre (même identifiant : ignorée) et n'écrit jamais par-dessus un coffre
  illisible.

Les apps Brocolis lisent ces deux formats, et `BrocolisTests` vérifie les vecteurs officiels de
brocolis-proto (`proto/vectors.json`) : jetons v2 aux paramètres minimum et par défaut, clé v1,
jeton v1 « Salut 🥦 », paramètres refusés.

## Tests

`KeyForgeTests` couvre la génération (longueurs, familles, caractères ambigus, mots, séparateurs,
PIN), l'entropie et les niveaux, l'analyseur (mots de passe courants, motifs), le temps de
craquage et les entrées du coffre ; `BrocolisTests` vérifie Argon2id et les formats Brocolis
contre les vecteurs de brocolis-proto, et l'aller-retour d'une sauvegarde. Dans Xcode : ⌘U.

La logique de `Core/` n'importe que Foundation : elle se compile et se teste aussi avec Swift sous
Linux, dans un paquet SwiftPM qui reprend ces fichiers et `KeyForgeTests.swift` (avec un AES-GCM
logiciel à la place de CryptoKit pour vérifier les formats Brocolis).

## Intégration continue

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) compile l'application pour le
simulateur et lance les tests sur un iPhone simulé (macOS 15, le Xcode le plus récent installé) à
chaque push qui touche `ios/`. En cas d'échec, le `.xcresult` est publié comme artefact.
