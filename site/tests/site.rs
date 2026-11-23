//! Chaque page répond, dans chaque langue, avec ses balises ; la PWA, le plan du site et
//! la page « introuvable » sont en place. Sans réseau : le client de test de Paquets.

use keyforge_site::routes::{PageKind, Route};
use keyforge_site::server::app;

#[tokio::test]
async fn every_page_answers_in_both_languages() {
    let client = app().test().await;
    for route in Route::all() {
        let res = client.get(&route.path()).await;
        assert_eq!(res.status(), 200, "{}", route.path());
        let html = res.text();
        assert!(
            html.contains(&format!(r#"<html lang="{}""#, route.lang.code())),
            "{}",
            route.path()
        );
        assert!(html.contains("rel=\"canonical\""), "{}", route.path());
        assert!(html.contains("class=\"footer\""), "{}", route.path());
        // Chaque page charge le bundle (au moins un îlot : le thème, la PWA).
        assert!(html.contains("<active-island"), "{}", route.path());
    }
}

#[tokio::test]
async fn the_home_page_has_its_islands_and_sections() {
    let client = app().test().await;
    let html = client.get("/fr/").await.text();
    for needle in [
        r#"id="features""#,
        r#"id="generator""#,
        r#"id="analyzer""#,
        r#"id="security""#,
        r#"id="screens""#,
        r#"id="faq""#,
        r#"id="download""#,
        "SoftwareApplication",
        "KeyForge · Forgez des clés incassables",
    ] {
        assert!(html.contains(needle), "{needle}");
    }
    let en = client.get("/en/").await.text();
    assert!(en.contains("KeyForge · Forge unbreakable keys"));
}

#[tokio::test]
async fn root_redirects_by_language() {
    let client = app().test().await;
    let res = client
        .get("/")
        .header("accept-language", "en-GB,en;q=0.9")
        .await;
    assert_eq!(res.status(), 302);
    assert_eq!(res.header("location"), Some("/en/"));
    let res = client.get("/").await;
    assert_eq!(res.header("location"), Some("/fr/"));
    // Sans « / » final : redirection permanente.
    assert_eq!(client.get("/fr/securite").await.status(), 301);
}

#[tokio::test]
async fn unknown_pages_are_404_in_the_right_language() {
    let client = app().test().await;
    let res = client.get("/en/nowhere/").await;
    assert_eq!(res.status(), 404);
    assert!(
        res.text()
            .contains("<title>Page not found · KeyForge</title>")
    );
    let res = client.get("/nimporte/quoi").await;
    assert_eq!(res.status(), 404);
}

#[tokio::test]
async fn pwa_sitemap_robots_and_health() {
    let client = app().test().await;
    let manifest = client.get("/fr/manifest.webmanifest").await;
    assert_eq!(manifest.status(), 200);
    let json = manifest.text();
    assert!(json.contains("KeyForge") && json.contains("/fr/") && json.contains("maskable"));
    assert_eq!(client.get("/sw.js").await.status(), 200);
    let sitemap = client.get("/sitemap.xml").await.text();
    assert_eq!(sitemap.matches("<url>").count(), Route::all().count());
    assert!(sitemap.contains(&Route::new(keyforge_site::i18n::Lang::En, PageKind::Privacy).path()));
    assert!(client.get("/robots.txt").await.text().contains("Sitemap:"));
    assert_eq!(client.get("/health").await.status(), 200);
    for file in [
        "/site.css",
        "/assets/logo.svg",
        "/assets/og-image.png",
        "/icons/icon-512.png",
    ] {
        assert_eq!(client.get(file).await.status(), 200, "{file}");
    }
}
