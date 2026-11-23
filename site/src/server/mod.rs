//! Le serveur : une `paquets::App` avec les pages en deux langues, le plan du site, la
//! PWA (manifeste et service worker) et une route de santé. Les fichiers statiques
//! viennent de `public/`, le bundle du navigateur de `pkg/` (Paquets les trouve dans le
//! dossier courant).

pub mod docs;
pub mod pages;

use std::path::{Path, PathBuf};

use paquets::prelude::*;

use crate::i18n::{Lang, pick_lang};
use crate::routes::{PageKind, Route};

/// L'adresse publique (`SITE_URL`), sinon celle de la requête.
pub fn origin(req: &Request) -> String {
    if let Ok(url) = std::env::var("SITE_URL")
        && !url.trim().is_empty()
    {
        return url.trim().trim_end_matches('/').to_owned();
    }
    let header = |name: &str| {
        req.header(name)
            .map(|v| v.split(',').next().unwrap_or("").trim().to_owned())
    };
    let host = header("x-forwarded-host")
        .or_else(|| header("host"))
        .unwrap_or_default();
    if host.is_empty()
        || !host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | ':'))
    {
        return "http://localhost:3000".into();
    }
    let proto = if header("x-forwarded-proto").as_deref() == Some("https") {
        "https"
    } else {
        "http"
    };
    format!("{proto}://{host}")
}

/// `/` : l'accueil dans la langue préférée du navigateur.
fn root(req: &Request) -> Response {
    let lang = pick_lang(req.header("accept-language").unwrap_or(""));
    Redirect::to(format!("/{}/", lang.code()))
        .into_response()
        .header("vary", "Accept-Language")
        .header("cache-control", "no-cache")
}

fn page(req: &Request) -> Response {
    let path = req.path();
    let Some(route) = Route::parse(path) else {
        return not_found(req);
    };
    if route.page == PageKind::NotFound {
        return not_found(req);
    }
    if !path.ends_with('/') {
        return Redirect::permanent(format!("{path}/")).into_response();
    }
    let ctx = pages::Ctx {
        route,
        origin: origin(req),
        intro: route.page == PageKind::Home,
    };
    pages::render(&ctx)
        .into_response()
        .header("cache-control", "no-cache")
}

fn not_found(req: &Request) -> Response {
    let lang = Route::parse(req.path()).map_or_else(
        || pick_lang(req.header("accept-language").unwrap_or("")),
        |r| r.lang,
    );
    let ctx = pages::Ctx {
        route: Route::new(lang, PageKind::NotFound),
        origin: origin(req),
        intro: false,
    };
    pages::render(&ctx).status(404).into_response()
}

fn sitemap(req: &Request) -> Response {
    let origin = origin(req);
    let mut xml = String::from(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\" xmlns:xhtml=\"http://www.w3.org/1999/xhtml\">\n",
    );
    for route in Route::all() {
        xml.push_str(&format!("<url><loc>{origin}{}</loc>", route.path()));
        for lang in Lang::ALL {
            xml.push_str(&format!(
                r#"<xhtml:link rel="alternate" hreflang="{}" href="{origin}{}"/>"#,
                lang.code(),
                route.with_lang(lang).path()
            ));
        }
        xml.push_str("</url>\n");
    }
    xml.push_str("</urlset>\n");
    Response::new()
        .header("content-type", "application/xml; charset=utf-8")
        .send(xml)
}

fn robots(req: &Request) -> Response {
    Response::new()
        .header("content-type", "text/plain; charset=utf-8")
        .send(format!(
            "User-agent: *\nAllow: /\n\nSitemap: {}/sitemap.xml\n",
            origin(req)
        ))
}

/// L'application, prête à tourner ou à être testée.
pub fn app() -> App {
    let mut app = App::new();
    app.get("/", |req: Request| async move { root(&req) });
    app.get("/sitemap.xml", |req: Request| async move { sitemap(&req) });
    app.get("/robots.txt", |req: Request| async move { robots(&req) });
    app.health("/health");
    for path in ["/:lang", "/:lang/:page"] {
        app.get(path, |req: Request| async move { page(&req) });
    }
    // Installable sur téléphone et ordinateur, lisible hors ligne.
    app.pwa(
        Pwa::new("KeyForge")
            .short_name("KeyForge")
            .description(
                "Forgez des clés incassables : mots de passe, phrases de passe et codes PIN.",
            )
            .start_url("/{lang}/")
            .theme_color("#0b0a12")
            .background_color("#0b0a12")
            .categories(["security", "utilities", "productivity"])
            .icon("/icons/icon-192.png", "192x192", "image/png")
            .icon("/icons/icon-512.png", "512x512", "image/png")
            .maskable_icon("/icons/icon-maskable-512.png", "512x512", "image/png"),
    );
    app.fallback(|req: Request| async move { not_found(&req) });
    app
}

/// Le dossier `site/` : le dossier courant s'il a `public/`, sinon celui de la crate.
fn site_dir() -> PathBuf {
    if Path::new("public").is_dir() {
        PathBuf::from(".")
    } else {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
    }
}

/// `cargo run` : le serveur, sur `PORT` (Heroku) ou 3000.
pub fn run() -> std::io::Result<()> {
    let dir = site_dir();
    if dir != Path::new(".") {
        std::env::set_current_dir(&dir)?;
    }
    app().run()
}
