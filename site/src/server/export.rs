//! `keyforge-site export <dossier>` : tout le site en fichiers statiques, pour GitHub Pages
//! ou n'importe quel hébergeur statique. Chaque page vient du serveur lui-même, par le
//! client de test de Paquets (`app.test()`) : les deux sont identiques.
//!
//! - `BASE_PATH` (`/KEYFORGE`) préfixe toutes les adresses absolues (liens, feuille de
//!   style, bundle WebAssembly, manifeste, service worker) ;
//! - `SITE_URL` (`https://maxlestage.github.io/KEYFORGE`) fait les URL absolues
//!   (canonique, Open Graph, plan du site).
//!
//! Ce qu'un hébergeur statique ne sait pas faire est remplacé : la racine sert l'accueil
//! en français (sa canonique pointe vers `/fr/`), et `404.html` la page « introuvable ».

use std::io;
use std::path::{Path, PathBuf};

use crate::i18n::Lang;
use crate::routes::Route;

/// `""`, ou `/quelque-chose` sans `/` final.
pub fn normalize_base(base: &str) -> String {
    let base = base.trim().trim_end_matches('/');
    if base.is_empty() {
        String::new()
    } else if base.starts_with('/') {
        base.to_owned()
    } else {
        format!("/{base}")
    }
}

/// Place derrière `base` chaque adresse absolue d'un texte : tout `"/x` (guillemet,
/// barre, puis autre chose qu'une barre). Les URL complètes (`https://…`), les
/// adresses relatives à un protocole (`//…`) et la fin d'une balise auto-fermante
/// (`href="…"/>` : le guillemet fermant, puis `/>`) ne changent pas.
pub fn with_base(text: &str, base: &str) -> String {
    if base.is_empty() {
        return text.to_owned();
    }
    let mut out = String::with_capacity(text.len() + 256);
    let mut rest = text;
    while let Some(i) = rest.find("\"/") {
        out.push_str(&rest[..=i]);
        let after = &rest[i + 1..];
        if !after.starts_with("//")
            && !after.starts_with("/>")
            && !after.starts_with(&format!("{base}/"))
        {
            out.push_str(base);
        }
        rest = after;
    }
    out.push_str(rest);
    out
}

/// Écrit le site dans `out`. Renvoie le nombre de fichiers écrits.
pub async fn export(out: &Path, base: &str) -> io::Result<usize> {
    let base = normalize_base(base);
    let out = std::path::absolute(out)?;
    // Paquets trouve `public/` et `pkg/` dans le dossier courant.
    let dir = std::path::absolute(super::site_dir())?;
    std::env::set_current_dir(&dir)?;
    if !dir.join("pkg").is_dir() {
        eprintln!(
            "attention : pkg/ manque, les pages ne seront pas interactives (./build.sh --wasm)"
        );
    }
    let mut app = super::app();
    // Des fichiers statiques n'ont pas de serveur à protéger, et l'export demande toutes
    // les pages d'un coup (la limite de débit l'arrêterait).
    app.security(None);
    let client = app.test().await;

    let mut written = 0;
    let mut write = |path: &str, bytes: &[u8]| -> io::Result<()> {
        let file = out.join(path.trim_start_matches('/'));
        if let Some(parent) = file.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(file, bytes)?;
        written += 1;
        Ok(())
    };
    let get = |path: String, expected: u16| {
        let client = &client;
        async move {
            let res = client.get(&path).await;
            if res.status().as_u16() != expected {
                return Err(io::Error::other(format!(
                    "GET {path} : {} au lieu de {expected}",
                    res.status()
                )));
            }
            Ok(res.text())
        }
    };

    for route in Route::all() {
        let html = get(route.path(), 200).await?;
        write(
            &format!("{}index.html", route.path()),
            with_base(&html, &base).as_bytes(),
        )?;
    }
    // La racine : l'accueil en français (canonique vers /fr/, sélecteur de langue en haut).
    let home = get("/fr/".into(), 200).await?;
    write("index.html", with_base(&home, &base).as_bytes())?;
    // « Introuvable » : GitHub Pages sert 404.html pour toute adresse inconnue.
    let missing = get("/fr/introuvable/".into(), 404).await?;
    write("404.html", with_base(&missing, &base).as_bytes())?;
    for lang in Lang::ALL {
        let missing = get(format!("/{}/404/", lang.code()), 404).await?;
        write(
            &format!("/{}/404/index.html", lang.code()),
            with_base(&missing, &base).as_bytes(),
        )?;
    }
    // La PWA : le manifeste et le service worker listent des adresses absolues.
    let mut pwa = vec!["/manifest.webmanifest".to_owned(), "/sw.js".to_owned()];
    pwa.extend(
        Lang::ALL
            .iter()
            .map(|l| format!("/{}/manifest.webmanifest", l.code())),
    );
    for file in pwa {
        let body = get(file.clone(), 200).await?;
        write(&file, with_base(&body, &base).as_bytes())?;
    }
    for file in ["/sitemap.xml", "/robots.txt"] {
        let body = get(file.to_owned(), 200).await?;
        write(file, body.as_bytes())?;
    }
    for folder in ["public", "pkg"] {
        let root = dir.join(folder);
        let prefix = if folder == "pkg" { "pkg/" } else { "" };
        for file in files(&root) {
            let relative = file.strip_prefix(&root).map_err(io::Error::other)?;
            let url = format!("{prefix}{}", relative.to_string_lossy().replace('\\', "/"));
            // Les fichiers annexes de wasm-bindgen, inutiles pour lancer le bundle.
            if url.ends_with(".gitignore") || url.ends_with("package.json") {
                continue;
            }
            write(&url, &std::fs::read(&file)?)?;
        }
    }
    // Les fichiers sont servis tels quels : pas de traitement Jekyll sur GitHub Pages.
    write(".nojekyll", b"")?;
    Ok(written)
}

/// Chaque fichier sous `dir`, récursivement.
fn files(dir: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();
    let Ok(entries) = std::fs::read_dir(dir) else {
        return found;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            found.extend(files(&path));
        } else {
            found.push(path);
        }
    }
    found.sort();
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn absolute_addresses_get_the_base() {
        let html = r##"<a href="/fr/">x</a><link href="/site.css?v=1"/><script type="module">import init from "/pkg/a.js";init({module_or_path:"/pkg/a_bg.wasm"});</script><a href="https://github.com/x">g</a><a href="//cdn">c</a><a href="#main">m</a>"##;
        let out = with_base(html, "/KEYFORGE");
        assert!(out.contains(r#"href="/KEYFORGE/fr/""#));
        assert!(out.contains(r#"href="/KEYFORGE/site.css?v=1""#));
        assert_eq!(out.matches("\"/KEYFORGE/pkg/").count(), 2);
        assert!(out.contains(r#"href="https://github.com/x""#));
        assert!(out.contains(r#"href="//cdn""#));
        assert!(out.contains(r##"href="#main""##));
        // Idempotent, et sans base rien ne change.
        assert_eq!(with_base(&out, "/KEYFORGE"), out);
        assert_eq!(with_base(html, ""), html);
        assert_eq!(normalize_base("KEYFORGE/"), "/KEYFORGE");
        // La fin d'une balise auto-fermante n'est pas une adresse.
        let tags = r#"<link rel="canonical" href="https://x/fr/"/><meta name="a" content="b"/><path d="M1 2"/><a href="/">r</a>"#;
        let out = with_base(tags, "/KEYFORGE");
        assert!(!out.contains("\"/KEYFORGE/>"), "{out}");
        assert!(out.contains(r#"<path d="M1 2"/>"#));
        assert!(out.contains(r#"href="/KEYFORGE/""#));
        assert_eq!(normalize_base("/"), "");
    }
}
