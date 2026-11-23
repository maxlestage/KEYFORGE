//! `cargo run` : le site, sur http://localhost:3000 (`PORT` sur Heroku). À lancer depuis
//! `site/`, après avoir construit le bundle du navigateur (voir `README.md`).

#[cfg(not(target_arch = "wasm32"))]
fn main() -> std::io::Result<()> {
    keyforge_site::server::run()
}

#[cfg(target_arch = "wasm32")]
fn main() {}
