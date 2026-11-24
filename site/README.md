# Le site de KeyForge

Une application [Paquets 📦](https://github.com/maxlestage/Paquets) : le serveur et le
navigateur partagent la même crate Rust.

| Fichier | Rôle |
|---|---|
| `src/pq.rs` | le chiffrement post-quantique : identité, paquet de clés, protocole v4 de Brocolis (X25519 + ML-KEM-768) |
| `src/seal.rs` | le scelleur à phrase : clé protégée par Argon2id + message v4 (mode clé partagée) |
| `src/forge.rs` | le moteur du générateur et de l'analyseur, mêmes règles que l'app iOS |
| `src/islands.rs` | les îlots : générateur, analyseur, échange post-quantique, scelleur, thème, statut PWA |
| `src/server/pages.rs` | la mise en page (navigation, menu, footer), l'accueil et ses sections |
| `src/server/docs.rs` | les pages de contenu et la 404 |
| `src/server/export.rs` | l'export statique pour GitHub Pages (`keyforge-site export dist`, `BASE_PATH`, `SITE_URL`) |
| `src/server/mod.rs` | l'`App` Paquets : routes, PWA, sitemap, robots, santé |
| `src/client/` | le bundle du navigateur : hydratation, hasard (`crypto.getRandomValues`), animations |
| `src/i18n.rs`, `src/routes.rs` | les langues et les adresses (`/fr/securite/`, `/en/security/`…) |
| `public/` | la feuille de style, le logo, les icônes PWA, l'image Open Graph |
| `tests/site.rs` | chaque page dans chaque langue, redirections, 404, PWA, plan du site |

```sh
./build.sh --wasm && cargo run   # http://localhost:3000
./build.sh                       # production : pkg/ + target/release/keyforge-site
BASE_PATH=/KEYFORGE ./target/release/keyforge-site export dist   # GitHub Pages
```
