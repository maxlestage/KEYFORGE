//! Le site de KeyForge, écrit avec Paquets : ce que le serveur et le navigateur
//! partagent (textes, routes, îlots, moteur du générateur), le serveur (natif) et le
//! bundle du navigateur (wasm32).

pub mod forge;
pub mod i18n;
pub mod icons;
pub mod islands;
pub mod pq;
pub mod routes;
pub mod seal;

#[cfg(not(target_arch = "wasm32"))]
pub mod server;

#[cfg(target_arch = "wasm32")]
mod client;
