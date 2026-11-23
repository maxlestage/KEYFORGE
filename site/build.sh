#!/usr/bin/env bash
# Construit le site pour la production :
#   1. les îlots, compilés en WebAssembly puis liés par wasm-bindgen (pkg/) ;
#   2. le serveur Paquets, en release (target/release/keyforge-site).
#
#   ./build.sh            # les deux
#   ./build.sh --wasm     # seulement le bundle du navigateur (pour `cargo run`)
#
# Utilisé tel quel par le Dockerfile, la CI et le déploiement.
set -euo pipefail
cd "$(dirname "$0")"

# Les dépôts de Paquets peuvent être privés : Cargo les récupère alors avec git, qui
# demande ses identifiants à un helper lisant REPOS_TOKEN (un jeton GitHub en lecture).
# Le jeton ne figure dans aucune URL ; sans lui, rien ne change.
if [ -n "${REPOS_TOKEN:-}" ]; then
  export CARGO_NET_GIT_FETCH_WITH_CLI=true GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=credential.https://github.com.helper \
    GIT_CONFIG_VALUE_0='!f() { test "$1" = get && echo username=x-access-token && echo "password=$REPOS_TOKEN"; }; f'
fi

echo "-----> Îlots (WebAssembly)"
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true
cargo build --lib --target wasm32-unknown-unknown --profile wasm-release

# wasm-bindgen doit être exactement la version de Cargo.lock : un binaire précompilé,
# ou compilé s'il ne peut pas être téléchargé.
version=$(grep -A1 '^name = "wasm-bindgen"$' Cargo.lock | sed -n 's/^version = "\(.*\)"$/\1/p')
bin="${CARGO_HOME:-$HOME/.cargo}/bin"
if [ "$(wasm-bindgen --version 2>/dev/null | cut -d' ' -f2)" != "$version" ]; then
  mkdir -p "$bin"
  curl -sSfL "https://github.com/wasm-bindgen/wasm-bindgen/releases/download/${version}/wasm-bindgen-${version}-x86_64-unknown-linux-musl.tar.gz" \
    | tar -xz --strip-components=1 -C "$bin" \
    || cargo install wasm-bindgen-cli --version "$version" --locked
fi
PATH="$bin:$PATH" wasm-bindgen --target web --no-typescript \
  --remove-name-section --remove-producers-section \
  --out-dir pkg target/wasm32-unknown-unknown/wasm-release/keyforge_site.wasm
echo "       pkg/ : $(du -h pkg/keyforge_site_bg.wasm | cut -f1) de WebAssembly ($(gzip -9 -c pkg/keyforge_site_bg.wasm | wc -c) octets compressés)"

if [ "${1:-}" = "--wasm" ]; then
  exit 0
fi

echo "-----> Serveur"
cargo build --release --bin keyforge-site
echo "       target/release/keyforge-site prêt"
