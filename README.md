<div align="center">

<img src="site/public/icons/icon-192.png" width="96" alt="KeyForge"/>

# KeyForge

**Forgez des clés incassables.**

Mots de passe, phrases de passe et codes PIN impossibles à deviner, rangés derrière Face ID.
Sans compte, sans réseau, sans publicité.

[![Site](https://github.com/maxlestage/KEYFORGE/actions/workflows/site.yml/badge.svg)](https://github.com/maxlestage/KEYFORGE/actions/workflows/site.yml)
[![iOS](https://github.com/maxlestage/KEYFORGE/actions/workflows/ios.yml/badge.svg)](https://github.com/maxlestage/KEYFORGE/actions/workflows/ios.yml)
[![GitHub Pages](https://github.com/maxlestage/KEYFORGE/actions/workflows/pages.yml/badge.svg)](https://maxlestage.github.io/KEYFORGE/)
[![Heroku](https://github.com/maxlestage/KEYFORGE/actions/workflows/deploy.yml/badge.svg)](https://github.com/maxlestage/KEYFORGE/actions/workflows/deploy.yml)

**[maxlestage.github.io/KEYFORGE](https://maxlestage.github.io/KEYFORGE/)**

</div>

---

Ce dépôt contient deux choses :

| Dossier | Contenu |
|---|---|
| [`site/`](site) | le site de présentation, en **Rust et WebAssembly uniquement**, écrit avec [Paquets 📦](https://github.com/maxlestage/Paquets) : pages rendues par le serveur, îlots WebAssembly, PWA installable et hors ligne |
| [`ios/`](ios) | l'application **iOS** en Swift et SwiftUI (iOS 17+) |
| [`shared/`](shared) | la liste de 1 024 mots des phrases de passe, commune au site et à l'app |
| [brocolis 🥦](https://github.com/maxlestage/brocolis) | **le chiffrement post-quantique** (protocole v4 : X25519 + ML-KEM-768) : le site utilise sa crate `brocolis-proto` (dépendance git), l'app iOS reproduit ses formats octet pour octet |
| [`.github/workflows/`](.github/workflows) | la CI du site, la CI iOS et le déploiement du site |

## Le site

Une application Paquets : le serveur rend chaque page en HTML fini (SEO, Open Graph, JSON-LD,
Content-Security-Policy stricte), et les parties interactives sont des îlots Rust compilés en
WebAssembly. Aucune ligne de JavaScript n'est écrite à la main.

- **Pages** : accueil, sécurité, guide des mots de passe, centre d'aide, nouveautés, kit presse,
  confidentialité, conditions, mentions légales, accessibilité et 404, **en français et en
  anglais**, thèmes **sombre et clair**.
- **Chiffrement post-quantique, par Brocolis 🥦** : [`brocolis-proto`](https://github.com/maxlestage/brocolis),
  compilé en WebAssembly, fait tout le travail dans le navigateur.
  - *Échange* : une identité X25519 + Ed25519 + **ML-KEM-768** (FIPS 203) par onglet, son
    paquet de clés à partager, et le chiffrement pour le paquet de quelqu'un avec le
    **protocole v4** (établissement hybride façon PQXDH, identité de l'expéditeur cachée,
    en-têtes chiffrés, triple cliquet) : `[[BROCOLIS:v4:…]]`. Il faudrait casser X25519
    **et** ML-KEM-768. Un paquet sans ML-KEM est refusé, un rejeu aussi.
  - *Scelleur à phrase* : une clé de 256 bits protégée par Argon2id (`[[BROCOLIS-CLE:v2:…]]`)
    et le texte en message v4 (mode clé partagée). C'est le format de la sauvegarde chiffrée
    de l'app iOS ; les anciens scellés v1 s'ouvrent toujours.
- **Îlots** : le générateur (le même moteur que l'app, avec `crypto.getRandomValues`), le testeur
  de robustesse, la bascule de thème (en cercle, View Transitions) et le statut PWA (en ligne /
  hors ligne, bouton « Installer »).
- **PWA** : manifeste par langue, service worker hors ligne, icônes, Apple touch icon.
- **Footer très complet** : bandeau défilant, appel « restez informé » (flux RSS des versions),
  marque et badge App Store, statut réseau en direct, réseaux, quatre colonnes de liens
  (produit, ressources, assistance, légal), garanties, mot-symbole géant animé, langue,
  retour en haut avec anneau de progression.
- **Animations (beaucoup, et aucune 3D)** : introduction (la clé se dessine, rideau), titres mot
  par mot, apparitions en cascade, machine à écrire, secrets « déchiffrés » en direct, braises
  en canvas 2D, blobs qui se déforment, grille qui défile, rayons, téléphone animé (onglets,
  curseur, interrupteurs, toast, Dynamic Island), badges flottants, orbites, bandeaux
  défilants, compteurs, halo qui suit le pointeur, curseur personnalisé, boutons magnétiques,
  ondes au clic, reflets, bordures en dégradé qui tournent, ligne qui se dessine au défilement,
  bouclier radar, FAQ en accordéon, galerie à faire glisser, barre de lecture, navigation qui
  se cache, menu mobile en cercle… Tout se calme avec « réduire les animations ».

### Développer

```sh
cd site
./build.sh --wasm      # les îlots en WebAssembly (pkg/)
cargo run              # http://localhost:3000
cargo test             # chaque page dans chaque langue, la PWA, le moteur du générateur
```

`./build.sh` sans argument construit aussi le serveur en release. Il faut Rust stable et la cible
`wasm32-unknown-unknown` ; le script installe la bonne version de `wasm-bindgen`.

### GitHub Pages (statique)

[`pages.yml`](.github/workflows/pages.yml) publie le site sur
**[maxlestage.github.io/KEYFORGE](https://maxlestage.github.io/KEYFORGE/)** après chaque CI
verte de `master`. `keyforge-site export dist` rend tout le site en fichiers statiques depuis le
serveur Paquets lui-même : chaque page dans chaque langue, le bundle WebAssembly, la PWA (hors
ligne comprise), le plan du site, avec chaque adresse derrière `/KEYFORGE` (`BASE_PATH`). Le
générateur, le testeur et le chiffrement post-quantique tournent dans le navigateur : rien ne
manque sans serveur.

```sh
cd site && ./build.sh && BASE_PATH=/KEYFORGE ./target/release/keyforge-site export dist
```

Réglage unique : *Settings → Pages → Build and deployment → Source* : **GitHub Actions**.

### Déployer (GitHub Actions → Heroku)

[`deploy.yml`](.github/workflows/deploy.yml) déploie le site après chaque CI verte de `master`
(ou à la main : *Actions → Déployer le site → Run workflow*). L'image Docker
([`site/Dockerfile`](site/Dockerfile)) est construite dans GitHub Actions, poussée dans le
registre de Heroku, puis publiée par l'API Platform ; le workflow attend que `/health` réponde.

Dans *Settings → Secrets and variables → Actions* :

| Nom | Type | Valeur |
|---|---|---|
| `HEROKU_API_KEY` | secret | Heroku → *Account settings* → *API Key* |
| `HEROKU_APP_NAME` | variable | le nom de l'application (créée si elle n'existe pas, pile `container`) |
| `HEROKU_REGION` | variable, facultative | `us` (défaut) ou `eu` |
| `REPOS_TOKEN` | secret, facultatif | un jeton GitHub qui peut lire les dépôts de Paquets s'ils sont privés |

Sans `HEROKU_API_KEY` ni `HEROKU_APP_NAME`, le déploiement est simplement sauté. L'image tourne
aussi telle quelle ailleurs : `docker build -f site/Dockerfile -t keyforge-site .`

## L'application iOS

SwiftUI, iOS 17+, aucune dépendance : générateur (mot de passe, phrase de passe, PIN), coffre dans
le Trousseau derrière Face ID / Touch ID, analyse de robustesse, presse-papiers qui s'efface
seul, découverte animée, **partage post-quantique** (protocole v4 de Brocolis 🥦 : ML-KEM-768
écrit en Swift, X25519 par CryptoKit) et **sauvegarde chiffrée** au même format, vérifiés contre
les vecteurs de brocolis. Détails, architecture et modèle de sécurité :
[`ios/README.md`](ios/README.md).

```sh
open ios/KeyForge.xcodeproj   # Xcode 16 ou plus récent
```

La CI [`ios.yml`](.github/workflows/ios.yml) compile l'app et lance ses tests sur un simulateur
iPhone à chaque changement de `ios/`.

## Licence

© 2026 Maxime Nathan Lestage. Tous droits réservés.
