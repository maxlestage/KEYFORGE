# syntax=docker/dockerfile:1
#
# L'image de production du site (Heroku, et telle quelle sur Fly.io, Render, Cloud Run…).
# Le contexte de construction est la racine du dépôt (le site lit shared/wordlist-fr.txt) :
#
#   docker build -f site/Dockerfile -t keyforge-site . && docker run --rm -p 8080:8080 keyforge-site
#
# Si les dépendances git sont privées : --secret id=repos_token,env=REPOS_TOKEN

FROM rust:1-slim-bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY shared ./shared
COPY site ./site
RUN --mount=type=secret,id=repos_token,env=REPOS_TOKEN ./site/build.sh

# Une petite image : le programme, ses fichiers statiques et le bundle WebAssembly.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* && useradd --system --uid 10001 keyforge
WORKDIR /app
COPY --from=build /src/site/target/release/keyforge-site /usr/local/bin/server
COPY --from=build /src/site/public ./public
COPY --from=build /src/site/pkg ./pkg
USER keyforge
# Heroku fixe PORT au démarrage ; 8080 ailleurs.
ENV PORT=8080
EXPOSE 8080
CMD ["server"]
