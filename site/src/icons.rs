//! Les icônes du site : des SVG au trait (24 × 24), écrits dans la page par le serveur.

use paquets::prelude::*;

/// Le contenu SVG d'une icône.
pub fn svg(name: &str) -> &'static str {
    match name {
        "key" => {
            r#"<circle cx="7.5" cy="15.5" r="4.5"/><path d="M10.7 12.3 20 3"/><path d="m16 7 3 3"/><path d="m18 5 2 2"/>"#
        }
        "lock" => {
            r#"<rect x="4" y="11" width="16" height="10" rx="2.5"/><path class="shackle" d="M8 11V7.5a4 4 0 0 1 8 0V11"/><circle cx="12" cy="16" r="1.4"/>"#
        }
        "shield" => {
            r#"<path d="M12 3 4.5 6v5.5c0 4.6 3.1 8.4 7.5 9.5 4.4-1.1 7.5-4.9 7.5-9.5V6z"/><path class="tick" d="m8.8 12.2 2.3 2.3 4.3-4.6"/>"#
        }
        "faceid" => {
            r#"<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><path d="M9 9.5v1M15 9.5v1M12 9.5v3.5h-1"/><path d="M9.2 15.6a4 4 0 0 0 5.6 0"/>"#
        }
        "fingerprint" => {
            r#"<path d="M12 11v3a8 8 0 0 1-1.5 4.7"/><path d="M8.6 9.4A4 4 0 0 1 16 11.5v1.6c0 2-.4 3.9-1.2 5.6"/><path d="M5.3 7.8A8 8 0 0 1 20 11.5V13"/><path d="M4.5 12v1a12 12 0 0 0 .9 4.6"/><path d="M8 12.6a15 15 0 0 1-1 5.4"/>"#
        }
        "spark" => {
            r#"<path d="M12 3v4M12 17v4M3 12h4M17 12h4M5.6 5.6l2.8 2.8M15.6 15.6l2.8 2.8M5.6 18.4l2.8-2.8M15.6 8.4l2.8-2.8"/>"#
        }
        "sparkles" => {
            r#"<path d="M10 3.5 11.6 8 16 9.5l-4.4 1.6L10 15.5l-1.6-4.4L4 9.5 8.4 8z"/><path d="M18 14l.8 2.2L21 17l-2.2.8L18 20l-.8-2.2L15 17l2.2-.8z"/>"#
        }
        "dice" => {
            r#"<rect x="3.5" y="3.5" width="17" height="17" rx="3.5"/><circle cx="8.5" cy="8.5" r="1.2"/><circle cx="15.5" cy="15.5" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="15.5" cy="8.5" r="1.2"/><circle cx="8.5" cy="15.5" r="1.2"/>"#
        }
        "words" => r#"<path d="M4 7h7M4 12h10M4 17h6"/><path d="M15 7h5M17 17h3"/>"#,
        "hash" => r#"<path d="M5 9h15M4 15h15M10 3 8 21M16 3l-2 18"/>"#,
        "vault" => {
            r#"<rect x="3" y="4" width="18" height="15" rx="2.5"/><circle cx="12" cy="11.5" r="3.5"/><path d="M12 8v1M12 14v1M8.5 11.5h1M14.5 11.5h1M6 19v2M18 19v2"/>"#
        }
        "gauge" => {
            r#"<path d="M4.2 17a9 9 0 1 1 15.6 0"/><path class="needle" d="m12 13 4-5"/><circle cx="12" cy="13" r="1.3"/>"#
        }
        "clipboard" => {
            r#"<rect x="5" y="4" width="14" height="17" rx="2.5"/><path d="M9 4V3h6v1"/><path d="M9 11h6M9 15h4"/>"#
        }
        "copy" => {
            r#"<rect x="8" y="8" width="12" height="12" rx="2.5"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>"#
        }
        "check" => r#"<path class="tick" d="m5 12.5 4.5 4.5L19 7.5"/>"#,
        "x" => r#"<path d="M6 6l12 12M18 6 6 18"/>"#,
        "refresh" => {
            r#"<path d="M20 11a8 8 0 0 0-14.4-4.8L4 8"/><path d="M4 4v4h4"/><path d="M4 13a8 8 0 0 0 14.4 4.8L20 16"/><path d="M20 20v-4h-4"/>"#
        }
        "arrow" => r#"<path d="M5 12h14M13 6l6 6-6 6"/>"#,
        "up" => r#"<path d="M12 19V5M6 11l6-6 6 6"/>"#,
        "down" => r#"<path d="M12 5v14M6 13l6 6 6-6"/>"#,
        "eyeoff" => {
            r#"<path d="M3 3l18 18"/><path d="M10.6 5.1A9.7 9.7 0 0 1 12 5c5 0 8.5 4.2 9.5 7-.4 1.1-1.2 2.5-2.4 3.7M6.6 6.6C4.6 8 3.2 10 2.5 12c1 2.8 4.5 7 9.5 7 1.8 0 3.4-.5 4.8-1.3"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>"#
        }
        "eye" => {
            r#"<path d="M2.5 12C3.5 9.2 7 5 12 5s8.5 4.2 9.5 7c-1 2.8-4.5 7-9.5 7s-8.5-4.2-9.5-7z"/><circle cx="12" cy="12" r="3"/>"#
        }
        "offline" => {
            r#"<path d="M3 3l18 18"/><path d="M8.5 16.5a5 5 0 0 1 7 0M5 13a10 10 0 0 1 4-2.4M19 13a10 10 0 0 0-2.3-1.6M2 9a15 15 0 0 1 5-3M22 9a15 15 0 0 0-10.5-4"/><circle cx="12" cy="20" r=".8"/>"#
        }
        "phone" => {
            r#"<rect x="6.5" y="2.5" width="11" height="19" rx="2.8"/><path d="M10.5 5h3"/><path d="M11 18.5h2"/>"#
        }
        "github" => {
            r#"<path d="M9 19c-4.3 1.4-4.3-2.5-6-3m12 5v-3.5c0-1 .1-1.4-.5-2 2.8-.3 5.5-1.4 5.5-6a4.6 4.6 0 0 0-1.3-3.2 4.2 4.2 0 0 0-.1-3.2s-1.1-.3-3.5 1.3a12.3 12.3 0 0 0-6.2 0C6.5 2.8 5.4 3.1 5.4 3.1a4.2 4.2 0 0 0-.1 3.2A4.6 4.6 0 0 0 4 9.5c0 4.6 2.7 5.7 5.5 6-.6.6-.6 1.2-.5 2V21"/>"#
        }
        "rss" => {
            r#"<path d="M5 11a8 8 0 0 1 8 8M5 5a14 14 0 0 1 14 14"/><circle cx="6" cy="18" r="1.4"/>"#
        }
        "apple" => {
            r#"<path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5a4.3 4.3 0 0 0-3.4-1.8c-1.4-.2-2.8.8-3.5.8s-1.8-.8-3-.8a4.5 4.5 0 0 0-3.8 2.3c-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7c1.3 0 2.1-1.1 2.8-2.3a10 10 0 0 0 1.3-2.6 3.9 3.9 0 0 1-2.5-3.7z"/><path d="M14.2 5.6A3.9 3.9 0 0 0 15.1 2.8a4 4 0 0 0-2.6 1.4 3.7 3.7 0 0 0-.9 2.7 3.3 3.3 0 0 0 2.6-1.3z"/>"#
        }
        "download" => r#"<path d="M12 4v11M7 10l5 5 5-5"/><path d="M5 19h14"/>"#,
        "sun" => {
            r#"<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>"#
        }
        "moon" => r#"<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>"#,
        "globe" => {
            r#"<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>"#
        }
        "plus" => r#"<path d="M12 5v14M5 12h14"/>"#,
        "bolt" => r#"<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>"#,
        "heart" => {
            r#"<path d="M12 20s-7.5-4.6-7.5-10A4.3 4.3 0 0 1 12 7.4 4.3 4.3 0 0 1 19.5 10c0 5.4-7.5 10-7.5 10z"/>"#
        }
        "book" => {
            r#"<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5z"/><path d="M4 20.5A2.5 2.5 0 0 0 6.5 23H20v-5"/>"#
        }
        "help" => {
            r#"<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6V14"/><circle cx="12" cy="17" r=".8"/>"#
        }
        "file" => {
            r#"<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>"#
        }
        "scale" => {
            r#"<path d="M12 4v16M7 20h10M5 7h14"/><path d="m5 7-3 6a3 3 0 0 0 6 0zM19 7l-3 6a3 3 0 0 0 6 0z"/>"#
        }
        "access" => {
            r#"<circle cx="12" cy="4.5" r="1.8"/><path d="M5 8.5l7 1.5 7-1.5M12 10v4.5M8.5 21l3.5-6.5 3.5 6.5"/>"#
        }
        "news" => {
            r#"<rect x="3" y="4" width="15" height="16" rx="2"/><path d="M18 8h2a1 1 0 0 1 1 1v9a2 2 0 0 1-2 2H5"/><path d="M7 8h7M7 12h7M7 16h4"/>"#
        }
        "lifebuoy" => {
            r#"<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3.5"/><path d="m5.6 5.6 4 4M14.4 14.4l4 4M18.4 5.6l-4 4M9.6 14.4l-4 4"/>"#
        }
        "mail" => r#"<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="m4 7 8 6 8-6"/>"#,
        "layers" => r#"<path d="m12 3 9 5-9 5-9-5z"/><path d="m3 13 9 5 9-5"/>"#,
        "cookie" => {
            r#"<path d="M12 3a9 9 0 1 0 9 9 3 3 0 0 1-3.5-3A3 3 0 0 1 14 5.5 3 3 0 0 1 12 3z"/><circle cx="8.5" cy="10" r=".9"/><circle cx="10" cy="15.5" r=".9"/><circle cx="15" cy="14.5" r=".9"/>"#
        }
        "map" => {
            r#"<path d="m9 4-6 2.5v13.5l6-2.5 6 2.5 6-2.5V4l-6 2.5z"/><path d="M9 4v13.5M15 6.5V20"/>"#
        }
        "anvil" => {
            r#"<path d="M3 7h12c0 2.5 2 4 6 4v1c-3 0-5 1-6 3H9c-1-2-3-3-6-3z"/><path d="M8 15v3H5v2h14v-2h-3v-3"/>"#
        }
        "zap-off" => {
            r#"<path d="M3 3l18 18"/><path d="M12.4 6.6 13 2l-4.2 5.6M16.6 13.2 19 10h-5.4M10.6 14.4 10 22l4.4-5.9"/><path d="M4 14h5.6"/>"#
        }
        "infinity" => {
            r#"<path d="M7 16a4 4 0 1 1 0-8c4 0 6 8 10 8a4 4 0 1 0 0-8c-4 0-6 8-10 8z"/>"#
        }
        _ => r#"<circle cx="12" cy="12" r="8"/>"#,
    }
}

/// Une icône décorative.
pub fn icon(name: &str) -> Element {
    span().class("icon").attr("aria-hidden", "true").html(format!(
        r#"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{}</svg>"#,
        svg(name)
    ))
}

/// Le logo de KeyForge : une clé forgée dans une étincelle.
///
/// `id` distingue le dégradé de chaque logo d'une page : un seul identifiant partagé
/// ferait dépendre tous les logos du premier, celui de l'introduction, que
/// `prefers-reduced-motion` masque (`display: none`) ; Firefox et Safari ne peignent pas
/// un dégradé défini dans un élément masqué, et le fond des logos disparaîtrait.
pub fn logo(id: &str) -> Element {
    span().class("logo").html(format!(
        r##"<svg viewBox="0 0 64 64" fill="none" aria-hidden="true"><defs><linearGradient id="kf-g-{id}" x1="6" y1="58" x2="58" y2="6" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#7c5cff"/><stop offset=".5" stop-color="#ff2e7e"/><stop offset="1" stop-color="#ff8a3d"/></linearGradient></defs><rect class="logo__bg" x="2" y="2" width="60" height="60" rx="16" fill="url(#kf-g-{id})"/><g class="logo__key" stroke="#fff" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="23" cy="40" r="9"/><path d="M29.5 33.5 46 17"/><path d="m40 23 5 5"/><path d="m44.5 18.5 4 4"/></g><g class="logo__spark" fill="#fff"><path d="M48 38.5l1.6 4 4 1.6-4 1.6-1.6 4-1.6-4-4-1.6 4-1.6z"/></g></svg>"##
    ))
}
