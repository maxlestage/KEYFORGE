<div align="center">

<img src="site/public/icons/icon-192.png" width="96" alt="KeyForge"/>

# KeyForge

**Forgez des clés incassables.**

Mots de passe, phrases de passe et codes PIN impossibles à deviner, rangés derrière Face ID.
Sans compte, sans réseau, sans publicité.

[![Site](https://github.com/maxlestage/KEYFORGE/actions/workflows/site.yml/badge.svg)](https://github.com/maxlestage/KEYFORGE/actions/workflows/site.yml)
[![iOS](https://github.com/maxlestage/KEYFORGE/actions/workflows/ios.yml/badge.svg)](https://github.com/maxlestage/KEYFORGE/actions/workflows/ios.yml)
[![Déploiement](https://github.com/maxlestage/KEYFORGE/actions/workflows/deploy.yml/badge.svg)](https://github.com/maxlestage/KEYFORGE/actions/workflows/deploy.yml)

</div>

---

Ce dépôt contient deux choses :

| Dossier | Contenu |
|---|---|
| [`site/`](site) | le site de présentation, en **Rust et WebAssembly uniquement**, écrit avec [Paquets 📦](https://github.com/maxlestage/Paquets) : pages rendues par le serveur, îlots WebAssembly, PWA installable et hors ligne |
| [`ios/`](ios) | l'application **iOS** en Swift et SwiftUI (iOS 17+) |
| [`shared/`](shared) | la liste de 1 024 mots des phrases de passe, commune au site et à l'app |
| [`.github/workflows/`](.github/workflows) | la CI du site, la CI iOS et le déploiement du site |

## Le site

Une application Paquets : le serveur rend chaque page en HTML fini (SEO, Open Graph, JSON-LD,
Content-Security-Policy stricte), et les parties interactives sont des îlots Rust compilés en
WebAssembly. Aucune ligne de JavaScript n'est écrite à la main.

- **Pages** : accueil, sécurité, guide des mots de passe, centre d'aide, nouveautés, kit presse,
  confidentialité, conditions, mentions légales, accessibilité et 404, **en français et en
  anglais**, thèmes **sombre et clair**.
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
seul, découverte animée. Détails, architecture et modèle de sécurité :
[`ios/README.md`](ios/README.md).

```sh
open ios/KeyForge.xcodeproj   # Xcode 16 ou plus récent
```

La CI [`ios.yml`](.github/workflows/ios.yml) compile l'app et lance ses tests sur un simulateur
iPhone à chaque changement de `ios/`.

## Licence

© 2026 Maxime Nathan Lestage. Tous droits réservés.
