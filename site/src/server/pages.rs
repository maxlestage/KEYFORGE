//! Les pages, rendues par le serveur : la mise en page commune (navigation, menu
//! mobile, footer, curseur, introduction), l'accueil et ses sections. Les autres pages
//! sont dans [`super::docs`].

use std::sync::OnceLock;

use paquets::prelude::*;

use crate::forge::{self, Mode, Options, Xorshift};
use crate::i18n::Lang;
use crate::icons::{icon, logo};
use crate::islands;
use crate::routes::{PageKind, Route};

/// L'auteur et le dépôt, repris dans le footer, les mentions et les données structurées.
pub const AUTHOR: &str = "Maxime Nathan Lestage";
pub const REPO: &str = "https://github.com/maxlestage/KEYFORGE";
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
pub const YEAR: &str = "2026";

pub struct Ctx {
    pub route: Route,
    /// L'adresse publique, pour les URL absolues (canonique, Open Graph).
    pub origin: String,
    /// L'introduction animée (accueil).
    pub intro: bool,
}

impl Ctx {
    pub fn lang(&self) -> Lang {
        self.route.lang
    }

    pub fn t(&self, fr: &'static str, en: &'static str) -> &'static str {
        self.route.lang.t(fr, en)
    }

    /// Le lien d'une page dans la langue courante.
    pub fn href(&self, page: PageKind) -> String {
        Route::new(self.lang(), page).path()
    }

    /// Une ancre de l'accueil.
    pub fn home(&self, anchor: &str) -> String {
        let home = self.href(PageKind::Home);
        if anchor.is_empty() {
            home
        } else {
            format!("{home}#{anchor}")
        }
    }
}

/// Le petit hash de `public/site.css`, pour `?v=` dans son lien.
fn css_version() -> &'static str {
    static VERSION: OnceLock<String> = OnceLock::new();
    VERSION.get_or_init(|| {
        let bytes = std::fs::read("public/site.css").unwrap_or_default();
        let h = bytes.iter().fold(0xcbf2_9ce4_8422_2325_u64, |h, b| {
            (h ^ u64::from(*b)).wrapping_mul(0x0100_0000_01b3)
        });
        format!("{h:016x}")[..10].to_owned()
    })
}

// ----- Briques ---------------------------------------------------------------------------

/// Un titre dont les mots montent un par un quand il apparaît.
pub fn split(tag: fn() -> Element, text: &str) -> Element {
    let mut nodes: Vec<Node> = Vec::new();
    for (i, word) in text.split(' ').enumerate() {
        if i > 0 {
            nodes.push(paquets::prelude::text(" "));
        }
        nodes.push(
            span()
                .class("w")
                .style(format!("--i:{i}"))
                .child(span().text(word.to_owned()))
                .into(),
        );
    }
    tag().class("split").attr("data-reveal", "").children(nodes)
}

/// Le petit libellé au-dessus d'un titre de section.
pub fn eyebrow(text: &'static str) -> Element {
    p().class("eyebrow")
        .attr("data-reveal", "")
        .child(span().class("eyebrow__dot"))
        .child(span().text(text))
}

pub fn section_head(kicker: &'static str, title: &'static str, lead: &'static str) -> Element {
    div()
        .class("section-head")
        .child(eyebrow(kicker))
        .child(split(h2, title))
        .child(
            p().class("lead")
                .attr("data-reveal", "")
                .style("--d:2")
                .text(lead),
        )
}

/// Un lien dont le texte roule au survol (chaque lettre décalée).
pub fn roll(text: &'static str) -> Element {
    span().class("roll").attr("aria-label", text).child(
        span()
            .class("roll__in")
            .attr("aria-hidden", "true")
            .children(text.chars().enumerate().map(|(i, c)| {
                span()
                    .style(format!("--i:{i}"))
                    .attr("data-c", c.to_string())
                    .text(if c == ' ' {
                        "\u{a0}".to_string()
                    } else {
                        c.to_string()
                    })
            })),
    )
}

/// Un secret d'exemple, toujours le même pour une graine (rendu par le serveur, puis
/// remplacé dans le navigateur par de vrais tirages).
fn sample(mode: Mode, length: u32, seed: u64) -> String {
    forge::generate(
        &Options {
            mode,
            length,
            ..Options::default()
        },
        &mut Xorshift(seed),
    )
}

fn button_link(class: &'static str, href: String, text: &'static str, ic: &'static str) -> Element {
    a().class(class)
        .href(href)
        .attr("data-magnetic", "")
        .child(span().class("btn__label").text(text))
        .child(icon(ic))
}

// ----- Mise en page ----------------------------------------------------------------------

/// La page autour de `content` : balises de tête, navigation, footer, curseur.
pub fn layout(ctx: &Ctx, title: &str, description: &str, content: Element) -> Page {
    let lang = ctx.lang();
    let route = ctx.route;
    let mut seo = Seo::new()
        .site_name("KeyForge")
        .base_url(ctx.origin.clone())
        .image("/assets/og-image.png")
        .meta_property("og:image:width", "1200")
        .meta_property("og:image:height", "630")
        .meta_property(
            "og:image:alt",
            ctx.t(
                "KeyForge : forgez des clés incassables.",
                "KeyForge: forge unbreakable keys.",
            ),
        )
        .og_type("website")
        .locale(lang.locale())
        .meta_name("author", AUTHOR);
    if route.page == PageKind::NotFound {
        seo = seo.noindex(true);
    } else {
        seo = seo.canonical(route.path());
        for l in Lang::ALL {
            seo = seo.alternate(l.code(), route.with_lang(l).path());
        }
        seo = seo.alternate("x-default", route.with_lang(Lang::Fr).path());
    }
    if route.page == PageKind::Home {
        seo = seo.json_ld(format!(
            r#"{{"@context":"https://schema.org","@type":"SoftwareApplication","name":"KeyForge","operatingSystem":"iOS 17+","applicationCategory":"SecurityApplication","description":"{}","author":{{"@type":"Person","name":"{AUTHOR}"}},"url":"{}{}"}}"#,
            description.replace('"', "'"),
            ctx.origin,
            route.path()
        ));
    }
    let head = r##"<meta name="color-scheme" content="dark light"/><link rel="icon" href="/assets/logo.svg" type="image/svg+xml"/><link rel="icon" href="/icons/favicon-32.png" sizes="32x32" type="image/png"/>"##;
    let mut site = div()
        .class("site")
        .child(
            a().class("skip")
                .href("#main")
                .text(ctx.t("Aller au contenu", "Skip to content")),
        )
        .child(div().class("progress").attr("aria-hidden", "true"));
    if ctx.intro {
        site = site.child(loader(ctx));
    }
    site = site
        .child(cursor())
        .child(navbar(ctx))
        .child(menu(ctx))
        .child(content.id("main"))
        .child(site_footer(ctx))
        .child(div().class("grain").attr("aria-hidden", "true"));
    Page::new(title.to_owned())
        .lang(lang.code())
        .description(description.to_owned())
        .seo(seo)
        .plain()
        .view_transitions()
        .prefetch(Prefetch::Hover)
        .stylesheet(format!("/site.css?v={}", css_version()))
        .head(head)
        .body(site)
}

/// L'introduction : la clé se dessine, l'étincelle jaillit, un rideau s'ouvre.
fn loader(ctx: &Ctx) -> Element {
    div()
        .class("loader")
        .attr("aria-hidden", "true")
        .child(
            div()
                .class("loader__inner")
                .child(div().class("loader__logo").child(logo()))
                .child(
                    div().class("loader__word").children(
                        "KEYFORGE"
                            .chars()
                            .enumerate()
                            .map(|(i, c)| span().style(format!("--i:{i}")).text(c.to_string())),
                    ),
                )
                .child(div().class("loader__bar").child(span()))
                .child(
                    p().class("loader__label")
                        .text(ctx.t("Chauffe de la forge", "Heating the forge")),
                ),
        )
        .child(div().class("loader__percent").text("  0%"))
        .child(div().class("loader__curtain"))
}

fn cursor() -> Element {
    div()
        .class("cursor")
        .attr("aria-hidden", "true")
        .child(div().class("cursor__dot"))
        .child(div().class("cursor__ring").child(span()))
}

/// Les liens principaux : (ancre de l'accueil ou page, texte).
fn nav_links(ctx: &Ctx) -> Vec<(String, &'static str)> {
    vec![
        (ctx.home("features"), ctx.t("Fonctionnalités", "Features")),
        (ctx.home("generator"), ctx.t("Générateur", "Generator")),
        (ctx.href(PageKind::Security), ctx.t("Sécurité", "Security")),
        (ctx.href(PageKind::Guide), ctx.t("Guide", "Guide")),
        (ctx.href(PageKind::Help), ctx.t("Aide", "Help")),
    ]
}

fn lang_switch(ctx: &Ctx) -> Element {
    let other = ctx.lang().other();
    a().class("lang-switch")
        .href(ctx.route.with_lang(other).path())
        .attr("hreflang", other.code())
        .attr("lang", other.code())
        .attr("aria-label", other.name())
        .attr("data-cursor", other.name())
        .child(icon("globe"))
        .child(span().text(other.code().to_uppercase()))
}

fn navbar(ctx: &Ctx) -> Element {
    header()
        .class("nav")
        .child(
            a().class("nav__brand")
                .href(ctx.home(""))
                .attr("aria-label", ctx.t("KeyForge, accueil", "KeyForge, home"))
                .child(logo())
                .child(span().class("nav__name").text("KeyForge")),
        )
        .child(
            nav()
                .class("nav__links")
                .attr(
                    "aria-label",
                    ctx.t("Navigation principale", "Main navigation"),
                )
                .children(
                    nav_links(ctx)
                        .into_iter()
                        .map(|(href, text)| a().class("nav__link").href(href).child(roll(text))),
                ),
        )
        .child(
            div()
                .class("nav__tools")
                .child(lang_switch(ctx))
                .child(island("theme", ctx.lang().code(), islands::theme))
                .child(
                    a().class("btn btn--primary btn--sm nav__cta")
                        .href(ctx.home("download"))
                        .attr("data-magnetic", "")
                        .child(icon("apple"))
                        .child(span().text(ctx.t("Télécharger", "Download"))),
                )
                .child(
                    button()
                        .class("nav__burger")
                        .attr("type", "button")
                        .attr("data-toggle-menu", "")
                        .attr("aria-label", ctx.t("Menu", "Menu"))
                        .attr("aria-expanded", "false")
                        .child(span())
                        .child(span())
                        .child(span()),
                ),
        )
}

/// Le menu plein écran des petits écrans.
fn menu(ctx: &Ctx) -> Element {
    div()
        .class("menu")
        .attr("aria-label", ctx.t("Menu", "Menu"))
        .child(div().class("menu__bg"))
        .child(
            nav().class("menu__links").children(
                nav_links(ctx)
                    .into_iter()
                    .chain([(ctx.home("download"), ctx.t("Télécharger", "Download"))])
                    .enumerate()
                    .map(|(i, (href, text))| {
                        a().href(href)
                            .style(format!("--i:{i}"))
                            .child(span().class("menu__num").text(format!("0{}", i + 1)))
                            .child(span().text(text))
                    }),
            ),
        )
        .child(
            div().class("menu__foot").child(lang_switch(ctx)).child(
                p().class("muted")
                    .text(ctx.t("Forgez des clés incassables.", "Forge unbreakable keys.")),
            ),
        )
}

// ----- Footer ----------------------------------------------------------------------------

fn footer_col(title: &'static str, links: Vec<(String, &'static str, &'static str)>) -> Element {
    div()
        .class("fcol")
        .attr("data-reveal", "")
        .child(h3().class("fcol__title").text(title))
        .child(ul().children(links.into_iter().map(|(href, text, ic)| {
            let external = href.starts_with("http");
            let link = a()
                .class("flink")
                .href(href)
                .child(icon(ic))
                .child(span().text(text))
                .child(
                    span()
                        .class("flink__arrow")
                        .text(if external { "↗" } else { "→" }),
                );
            li().child(if external {
                link.attr("target", "_blank").attr("rel", "noopener")
            } else {
                link
            })
        })))
}

fn site_footer(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    let words = [
        t("Mots de passe", "Passwords"),
        t("Phrases de passe", "Passphrases"),
        t("Codes PIN", "PIN codes"),
        "Face ID",
        t("Trousseau iOS", "iOS Keychain"),
        t("Hors ligne", "Offline"),
        t("Sans compte", "No account"),
        t("Sans traqueur", "No trackers"),
    ];
    footer()
        .class("footer")
        // Le bandeau qui défile.
        .child(
            div().class("footer__marquee").attr("aria-hidden", "true").child(
                div().class("marquee marquee--slow").child(
                    div().class("marquee__track").children((0..2).map(move |_| {
                        div().class("marquee__group").children(words.iter().map(|w| {
                            span().class("marquee__item").child(icon("spark")).child(span().text(*w))
                        }))
                    })),
                ),
            ),
        )
        // L'appel à rester informé.
        .child(
            div()
                .class("footer__cta wrap")
                .attr("data-reveal", "")
                .child(
                    div()
                        .child(h2().class("footer__cta-title").text(t(
                            "Restez au courant des nouvelles versions.",
                            "Hear about new versions first.",
                        )))
                        .child(p().class("muted").text(t(
                            "Pas de newsletter, pas d'e-mail à donner : abonnez-vous au flux des versions avec votre lecteur RSS, ou suivez le dépôt.",
                            "No newsletter, no e-mail to give away: subscribe to the releases feed in your RSS reader, or watch the repository.",
                        ))),
                )
                .child(
                    div()
                        .class("row")
                        .child(button_link(
                            "btn btn--primary",
                            format!("{REPO}/releases.atom"),
                            t("Flux RSS des versions", "Releases RSS feed"),
                            "rss",
                        ))
                        .child(button_link(
                            "btn btn--ghost",
                            ctx.href(PageKind::Changelog),
                            t("Voir les nouveautés", "See what's new"),
                            "arrow",
                        )),
                ),
        )
        .child(
            div()
                .class("footer__grid wrap")
                // La marque.
                .child(
                    div()
                        .class("fbrand")
                        .attr("data-reveal", "")
                        .child(
                            a().class("fbrand__logo")
                                .href(ctx.home(""))
                                .child(logo())
                                .child(span().text("KeyForge")),
                        )
                        .child(p().class("muted").text(t(
                            "Le générateur et coffre de mots de passe pour iPhone : des secrets impossibles à deviner, rangés derrière Face ID, sans compte ni réseau.",
                            "The password generator and vault for iPhone: secrets nobody can guess, kept behind Face ID, with no account and no network.",
                        )))
                        .child(
                            a().class("store")
                                .href(ctx.home("download"))
                                .attr("data-magnetic", "")
                                .child(icon("apple"))
                                .child(
                                    span()
                                        .child(small().text(t("Bientôt sur", "Coming soon to the")))
                                        .child(strong().text("App Store")),
                                ),
                        )
                        .child(island("pwa", ctx.lang().code(), islands::pwa))
                        .child(
                            div()
                                .class("socials")
                                .child(
                                    a().class("social")
                                        .href(REPO)
                                        .attr("target", "_blank")
                                        .attr("rel", "noopener")
                                        .attr("aria-label", "GitHub")
                                        .attr("data-cursor", "GitHub")
                                        .child(icon("github")),
                                )
                                .child(
                                    a().class("social")
                                        .href(format!("{REPO}/releases.atom"))
                                        .attr("aria-label", "RSS")
                                        .attr("data-cursor", "RSS")
                                        .child(icon("rss")),
                                )
                                .child(
                                    a().class("social")
                                        .href(format!("{REPO}/issues"))
                                        .attr("target", "_blank")
                                        .attr("rel", "noopener")
                                        .attr("aria-label", t("Signaler un problème", "Report an issue"))
                                        .attr("data-cursor", t("Écrire", "Write"))
                                        .child(icon("mail")),
                                ),
                        ),
                )
                .child(footer_col(
                    t("Produit", "Product"),
                    vec![
                        (ctx.home("features"), t("Fonctionnalités", "Features"), "sparkles"),
                        (ctx.home("generator"), t("Générateur en ligne", "Online generator"), "dice"),
                        (ctx.home("analyzer"), t("Testeur de robustesse", "Strength tester"), "gauge"),
                        (ctx.home("brocolis"), t("Scelleur Brocolis 🥦", "Brocolis sealer 🥦"), "lock"),
                        (ctx.home("screens"), t("Captures d'écran", "Screenshots"), "phone"),
                        (ctx.home("download"), t("Télécharger", "Download"), "download"),
                        (ctx.href(PageKind::Changelog), t("Nouveautés", "What's new"), "bolt"),
                    ],
                ))
                .child(footer_col(
                    t("Ressources", "Resources"),
                    vec![
                        (ctx.href(PageKind::Security), t("Modèle de sécurité", "Security model"), "shield"),
                        (ctx.href(PageKind::Guide), t("Guide des mots de passe", "Password guide"), "book"),
                        (ctx.home("faq"), t("Questions fréquentes", "FAQ"), "help"),
                        (ctx.href(PageKind::Press), t("Kit presse", "Press kit"), "news"),
                        ("/sitemap.xml".into(), t("Plan du site", "Sitemap"), "map"),
                    ],
                ))
                .child(footer_col(
                    t("Assistance", "Support"),
                    vec![
                        (ctx.href(PageKind::Help), t("Centre d'aide", "Help center"), "lifebuoy"),
                        (format!("{REPO}/issues/new"), t("Signaler un problème", "Report a bug"), "mail"),
                        (format!("{REPO}/security"), t("Signaler une faille", "Report a vulnerability"), "shield"),
                        (REPO.into(), t("Code source", "Source code"), "github"),
                        (BROCOLIS.into(), t("Chiffrement : brocolis", "Encryption: brocolis"), "shield"),
                        (format!("{REPO}/releases"), t("Versions", "Releases"), "layers"),
                    ],
                ))
                .child(footer_col(
                    t("Légal", "Legal"),
                    vec![
                        (ctx.href(PageKind::Privacy), t("Confidentialité", "Privacy"), "eyeoff"),
                        (ctx.href(PageKind::Terms), t("Conditions d'utilisation", "Terms of use"), "file"),
                        (ctx.href(PageKind::Legal), t("Mentions légales", "Legal notice"), "scale"),
                        (ctx.href(PageKind::Privacy) + "#cookies", t("Cookies : aucun", "Cookies: none"), "cookie"),
                        (ctx.href(PageKind::Accessibility), t("Accessibilité", "Accessibility"), "access"),
                    ],
                )),
        )
        // Les garanties, en une ligne.
        .child(
            ul().class("footer__badges wrap").attr("data-reveal", "").children(
                [
                    ("offline", t("100 % hors ligne", "100% offline")),
                    ("eyeoff", t("Zéro traqueur", "Zero trackers")),
                    ("cookie", t("Zéro cookie", "Zero cookies")),
                    ("faceid", "Face ID & Touch ID"),
                    ("lock", t("Trousseau iOS chiffré", "Encrypted iOS Keychain")),
                    ("shield", t("Chiffré par Brocolis 🥦", "Encrypted by Brocolis 🥦")),
                    ("bolt", t("Rust · WebAssembly", "Rust · WebAssembly")),
                ]
                .into_iter()
                .enumerate()
                .map(|(i, (ic, text))| {
                    li().style(format!("--i:{i}")).child(icon(ic)).child(span().text(text))
                }),
            ),
        )
        // Le grand mot-symbole.
        .child(
            div()
                .class("footer__word")
                .attr("aria-hidden", "true")
                .attr("data-reveal", "")
                .children("KEYFORGE".chars().enumerate().map(|(i, c)| {
                    span().style(format!("--i:{i}")).text(c.to_string())
                })),
        )
        // La dernière ligne.
        .child(
            div()
                .class("footer__bottom wrap")
                .child(
                    p().child(span().text(format!("© {YEAR} {AUTHOR}. ")))
                        .child(span().text(t("Tous droits réservés.", "All rights reserved."))),
                )
                .child(
                    p().class("made")
                        .child(span().text(t("Fait avec ", "Made with ")))
                        .child(
                            a().href("https://github.com/maxlestage/Paquets")
                                .attr("target", "_blank")
                                .attr("rel", "noopener")
                                .text("Paquets 📦"),
                        )
                        .child(span().text(t(", chiffré par ", ", encrypted by ")))
                        .child(
                            a().href(BROCOLIS)
                                .attr("target", "_blank")
                                .attr("rel", "noopener")
                                .text("Brocolis 🥦"),
                        )
                        .child(span().text(t(", en Rust et WebAssembly · site v", ", in Rust and WebAssembly · site v")))
                        .child(span().text(VERSION)),
                )
                .child(
                    div()
                        .class("footer__end")
                        .child(lang_switch(ctx))
                        .child(
                            a().class("totop")
                                .href("#main")
                                .attr("data-top", "")
                                .attr("aria-label", t("Haut de page", "Back to top"))
                                .attr("data-cursor", t("Haut", "Top"))
                                .child(span().class("totop__ring").html(r#"<svg viewBox="0 0 48 48" aria-hidden="true"><circle cx="24" cy="24" r="21" pathLength="1"/></svg>"#))
                                .child(icon("up")),
                        ),
                ),
        )
}

// ----- Accueil ---------------------------------------------------------------------------

fn hero(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    let words = t(
        "incassables.|uniques.|mémorables.|à votre image.",
        "unbreakable.|unique.|memorable.|truly yours.",
    );
    let first = words.split('|').next().unwrap_or_default();
    section()
        .class("hero")
        .child(
            div()
                .class("hero__bg")
                .attr("aria-hidden", "true")
                .child(div().class("hero__grid"))
                .child(div().class("blob blob--a").attr("data-speed", "0.12"))
                .child(div().class("blob blob--b").attr("data-speed", "-0.08"))
                .child(div().class("blob blob--c").attr("data-speed", "0.05"))
                .child(canvas().class("embers").attr("data-count", "80"))
                .child(div().class("hero__rays")),
        )
        .child(
            div()
                .class("hero__inner wrap")
                .child(
                    div()
                        .class("hero__copy")
                        .child(
                            a().class("pill")
                                .href(ctx.href(PageKind::Changelog))
                                .attr("data-reveal", "")
                                .child(span().class("pill__tag").text(t("Nouveau", "New")))
                                .child(span().text(t("L'app iOS arrive · v1.0", "The iOS app is coming · v1.0")))
                                .child(icon("arrow")),
                        )
                        .child(
                            h1().class("hero__title")
                                .child(split(span, t("Forgez des clés", "Forge keys")).class("hero__line"))
                                .child(
                                    span()
                                        .class("hero__line type")
                                        .attr("data-words", words)
                                        .child(span().class("type__text grad").text(first))
                                        .child(span().class("type__caret").attr("aria-hidden", "true")),
                                ),
                        )
                        .child(p().class("hero__lead").attr("data-reveal", "").style("--d:3").text(t(
                            "KeyForge génère des mots de passe, des phrases de passe et des codes PIN impossibles à deviner, les range dans le Trousseau de votre iPhone derrière Face ID, et vérifie la robustesse de ceux que vous utilisez déjà. Sans compte, sans réseau, sans publicité.",
                            "KeyForge generates passwords, passphrases and PIN codes nobody can guess, keeps them in your iPhone's Keychain behind Face ID, and checks the strength of the ones you already use. No account, no network, no ads.",
                        )))
                        .child(
                            div()
                                .class("hero__actions")
                                .attr("data-reveal", "")
                                .style("--d:4")
                                .child(button_link(
                                    "btn btn--primary btn--lg",
                                    ctx.home("download"),
                                    t("Bientôt sur l'App Store", "Coming to the App Store"),
                                    "apple",
                                ))
                                .child(button_link(
                                    "btn btn--ghost btn--lg",
                                    ctx.home("generator"),
                                    t("Essayer le générateur", "Try the generator"),
                                    "arrow",
                                )),
                        )
                        .child(
                            div()
                                .class("ticker")
                                .attr("data-reveal", "")
                                .style("--d:5")
                                .child(span().class("ticker__label").child(span().class("pulse")).child(span().text(t(
                                    "Forgé à l'instant, dans votre navigateur",
                                    "Forged just now, in your browser",
                                ))))
                                .child(
                                    code()
                                        .class("ticker__value")
                                        .attr("data-scramble", "password")
                                        .attr("data-length", "22")
                                        .text(sample(Mode::Password, 22, 2026)),
                                ),
                        )
                        .child(
                            ul().class("hero__pills").attr("data-reveal", "").style("--d:6").children(
                                [
                                    ("offline", t("100 % hors ligne", "100% offline")),
                                    ("faceid", "Face ID"),
                                    ("lock", t("Trousseau iOS", "iOS Keychain")),
                                    ("eyeoff", t("Zéro traqueur", "Zero trackers")),
                                ]
                                .into_iter()
                                .map(|(ic, text)| li().child(icon(ic)).child(span().text(text))),
                            ),
                        ),
                )
                .child(div().class("hero__visual").attr("data-reveal", "").style("--d:2").child(phone(ctx))),
        )
        .child(
            a().class("scroll-hint")
                .href("#features")
                .attr("aria-label", t("Découvrir", "Discover"))
                .child(span().class("scroll-hint__mouse").child(span()))
                .child(span().text(t("Défiler", "Scroll"))),
        )
}

/// Le téléphone du héros (2D) : l'écran du générateur joue tout seul.
fn phone(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    div()
        .class("phone-wrap")
        .child(
            div()
                .class("phone")
                .child(div().class("phone__island"))
                .child(
                    div()
                        .class("phone__screen")
                        .child(
                            div()
                                .class("app-bar")
                                .child(strong().text(t("Générateur", "Generator")))
                                .child(span().class("app-bar__lock").child(icon("lock"))),
                        )
                        .child(
                            div()
                                .class("app-seg")
                                .child(span().class("app-seg__ink"))
                                .child(span().text(t("Mot de passe", "Password")))
                                .child(span().text(t("Phrase", "Phrase")))
                                .child(span().text("PIN")),
                        )
                        .child(
                            div()
                                .class("app-card")
                                .child(
                                    p().class("app-secret")
                                        .attr("data-scramble", "password")
                                        .attr("data-length", "16")
                                        .text(sample(Mode::Password, 16, 7)),
                                )
                                .child(
                                    div()
                                        .class("app-meter")
                                        .children((0..5).map(|i| span().style(format!("--i:{i}")))),
                                )
                                .child(
                                    p().class("app-level")
                                        .child(strong().text(t("Excellente", "Excellent")))
                                        .child(span().text(" · 104 bits")),
                                ),
                        )
                        .child(
                            div()
                                .class("app-row")
                                .child(span().text(t("Longueur", "Length")))
                                .child(div().class("app-slider").child(span())),
                        )
                        .child(
                            div().class("app-toggles").children(
                                ["A–Z", "a–z", "0–9", "!@#"].into_iter().enumerate().map(
                                    |(i, s)| {
                                        div()
                                            .class("app-toggle")
                                            .style(format!("--i:{i}"))
                                            .child(span().text(s))
                                            .child(span().class("app-switch"))
                                    },
                                ),
                            ),
                        )
                        .child(
                            div()
                                .class("app-history")
                                .child(small().text(t("Récents", "Recent")))
                                .children(
                                    [
                                        (sample(Mode::Passphrase, 3, 5), "50"),
                                        (sample(Mode::Pin, 6, 9), "20"),
                                    ]
                                    .into_iter()
                                    .enumerate()
                                    .map(
                                        |(i, (secret, bits))| {
                                            div()
                                                .class("app-history__row")
                                                .style(format!("--i:{i}"))
                                                .child(code().text(secret))
                                                .child(span().text(format!("{bits} bits")))
                                        },
                                    ),
                                ),
                        )
                        .child(
                            div()
                                .class("app-buttons")
                                .child(
                                    span()
                                        .class("app-btn app-btn--main")
                                        .child(icon("copy"))
                                        .child(span().text(t("Copier", "Copy"))),
                                )
                                .child(
                                    span()
                                        .class("app-btn")
                                        .child(icon("vault"))
                                        .child(span().text(t("Ranger", "Save"))),
                                ),
                        )
                        .child(div().class("app-toast").child(icon("check")).child(
                            span().text(t("Copié · effacé dans 30 s", "Copied · cleared in 30 s")),
                        ))
                        .child(
                            div().class("app-tabs").children(
                                ["dice", "vault", "gauge", "spark"]
                                    .into_iter()
                                    .enumerate()
                                    .map(|(i, ic)| {
                                        span()
                                            .class("app-tab")
                                            .class(if i == 0 { "is-on" } else { "" })
                                            .child(icon(ic))
                                    }),
                            ),
                        ),
                ),
        )
        .child(
            div()
                .class("float float--a")
                .child(span().class("float__icon").child(icon("faceid")))
                .child(
                    span()
                        .child(strong().text("Face ID"))
                        .child(small().text(t("Coffre déverrouillé", "Vault unlocked"))),
                ),
        )
        .child(
            div()
                .class("float float--b")
                .child(
                    span()
                        .class("float__icon float__icon--gold")
                        .child(icon("shield")),
                )
                .child(
                    span()
                        .child(strong().text("128 bits"))
                        .child(small().text(t("Excellente", "Excellent"))),
                ),
        )
        .child(
            div()
                .class("float float--c")
                .child(
                    span()
                        .class("float__icon float__icon--violet")
                        .child(icon("offline")),
                )
                .child(
                    span()
                        .child(strong().text(t("Hors ligne", "Offline")))
                        .child(small().text(t("0 octet envoyé", "0 bytes sent"))),
                ),
        )
        .child(
            div()
                .class("phone-wrap__orbit")
                .attr("aria-hidden", "true")
                .children(
                    ["key", "lock", "spark", "shield"]
                        .into_iter()
                        .enumerate()
                        .map(|(i, ic)| {
                            span()
                                .class("orbit__dot")
                                .style(format!("--i:{i}"))
                                .child(icon(ic))
                        }),
                ),
        )
}

fn marquee(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    let row = |items: Vec<(&'static str, &'static str)>, reverse: bool| {
        div()
            .class(if reverse {
                "marquee marquee--reverse"
            } else {
                "marquee"
            })
            .child(div().class("marquee__track").children((0..2).map(move |_| {
                div()
                    .class("marquee__group")
                    .children(items.clone().into_iter().map(|(ic, text)| {
                        span()
                            .class("marquee__item")
                            .child(icon(ic))
                            .child(span().text(text))
                    }))
            })))
    };
    section()
        .class("band")
        .attr("aria-label", t("En bref", "At a glance"))
        .child(row(
            vec![
                ("key", t("Mots de passe sur mesure", "Custom passwords")),
                ("words", t("Phrases de passe", "Passphrases")),
                ("hash", t("Codes PIN", "PIN codes")),
                ("vault", t("Coffre chiffré", "Encrypted vault")),
                ("faceid", "Face ID · Touch ID"),
                ("gauge", t("Analyse de robustesse", "Strength analysis")),
            ],
            false,
        ))
        .child(row(
            vec![
                (
                    "clipboard",
                    t("Presse-papiers éphémère", "Self-clearing clipboard"),
                ),
                ("offline", t("Aucune connexion", "No connection")),
                ("eyeoff", t("Aucun traqueur", "No trackers")),
                ("lock", t("Verrouillage automatique", "Auto-lock")),
                ("sparkles", t("Animations soignées", "Crafted animations")),
                (
                    "shield",
                    t("Chiffrement Brocolis 🥦", "Brocolis encryption 🥦"),
                ),
                ("heart", t("Sans publicité", "No ads")),
            ],
            true,
        ))
}

fn stats(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    let stat = |count: &'static str, suffix: &'static str, label: &'static str, i: usize| {
        div()
            .class("stat-card")
            .attr("data-reveal", "")
            .attr("data-spot", "")
            .style(format!("--d:{i}"))
            .child(
                strong()
                    .class("stat-card__num grad")
                    .attr("data-count", count)
                    .attr("data-suffix", suffix)
                    .text(format!("{count}{suffix}")),
            )
            .child(p().text(label))
    };
    section().class("stats wrap").child(
        div()
            .class("stats__grid")
            .child(stat(
                "1024",
                "",
                t(
                    "mots dans la liste des phrases de passe : 10 bits par mot",
                    "words in the passphrase list: 10 bits per word",
                ),
                0,
            ))
            .child(stat(
                "128",
                "",
                t(
                    "caractères au plus pour un mot de passe",
                    "characters at most for a password",
                ),
                1,
            ))
            .child(stat(
                "0",
                t(" octet", " bytes"),
                t(
                    "envoyé sur Internet par l'application",
                    "sent over the Internet by the app",
                ),
                2,
            ))
            .child(stat(
                "5",
                "",
                t(
                    "niveaux de robustesse, de « très faible » à « excellente »",
                    "strength levels, from “very weak” to “excellent”",
                ),
                3,
            )),
    )
}

fn features(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    let list: [(&str, &str, &str, &str); 8] = [
        (
            "key",
            t("Mots de passe sur mesure", "Passwords, your way"),
            t(
                "De 4 à 128 caractères, majuscules, minuscules, chiffres et symboles au choix, sans caractères ambigus si vous le voulez. Au moins un caractère de chaque classe, toujours.",
                "From 4 to 128 characters, with the classes you choose, without look-alike characters if you want. At least one character of each class, always.",
            ),
            "ember",
        ),
        (
            "words",
            t("Phrases de passe mémorables", "Memorable passphrases"),
            t(
                "De 3 à 12 mots tirés parmi 1 024, séparateur au choix, majuscules et chiffre en option. « Galet-Phare7-Sorbet-Lynx-Opale » se retient, et résiste.",
                "3 to 12 words drawn from 1,024, your choice of separator, optional capitals and digit. “Galet-Phare7-Sorbet-Lynx-Opale” sticks in your head, and holds.",
            ),
            "pink",
        ),
        (
            "hash",
            t("Codes PIN sans biais", "Unbiased PIN codes"),
            t(
                "De 4 à 12 chiffres, chacun tiré uniformément par le générateur cryptographique du système. Fini les 1234 et les dates de naissance.",
                "4 to 12 digits, each drawn uniformly by the system's cryptographic generator. No more 1234 or birthdays.",
            ),
            "violet",
        ),
        (
            "vault",
            t("Un coffre dans le Trousseau", "A vault in the Keychain"),
            t(
                "Vos clés sont rangées dans le Trousseau iOS, chiffré par l'iPhone, accessibles seulement quand il est déverrouillé, et jamais synchronisées ailleurs.",
                "Your keys live in the iOS Keychain, encrypted by the iPhone, readable only while it is unlocked, and never synced anywhere else.",
            ),
            "gold",
        ),
        (
            "faceid",
            t("Face ID et Touch ID", "Face ID and Touch ID"),
            t(
                "Le coffre s'ouvre avec votre visage, votre doigt ou le code de l'appareil, et se referme dès que l'app passe en arrière-plan.",
                "The vault opens with your face, your finger or the device passcode, and locks again as soon as the app goes to the background.",
            ),
            "ember",
        ),
        (
            "gauge",
            t("Analyse de robustesse", "Strength analysis"),
            t(
                "Entropie, suites, répétitions, mots de passe les plus courants et temps de cassage estimé : sachez ce que valent vos anciens mots de passe.",
                "Entropy, runs, repeats, the most common passwords and an estimated time to crack: know what your old passwords are worth.",
            ),
            "pink",
        ),
        (
            "clipboard",
            t("Presse-papiers éphémère", "Self-clearing clipboard"),
            t(
                "Ce que vous copiez s'efface tout seul après 30 s, 1 min ou 2 min, et n'est jamais partagé avec vos autres appareils.",
                "What you copy clears itself after 30 s, 1 min or 2 min, and is never shared with your other devices.",
            ),
            "violet",
        ),
        (
            "eyeoff",
            t("Confidentialité totale", "Total privacy"),
            t(
                "Aucune requête réseau, aucun compte, aucune donnée collectée, et un écran flouté dans le sélecteur d'apps.",
                "No network request, no account, no data collected, and a blurred screen in the app switcher.",
            ),
            "gold",
        ),
    ];
    section()
        .class("section wrap")
        .id("features")
        .child(section_head(
            t("Fonctionnalités", "Features"),
            t("Tout ce qu'il faut pour des secrets solides.", "Everything you need for solid secrets."),
            t(
                "Un générateur, un coffre et un analyseur, réunis dans une app rapide, sobre et entièrement hors ligne.",
                "A generator, a vault and an analyser, together in a fast, quiet, fully offline app.",
            ),
        ))
        .child(div().class("features").children(list.into_iter().enumerate().map(
            |(i, (ic, title, body, tone))| {
                article()
                    .class(format!("feature feature--{tone}"))
                    .attr("data-reveal", "")
                    .attr("data-spot", "")
                    .style(format!("--d:{}", i % 4))
                    .child(span().class("feature__icon").child(icon(ic)))
                    .child(h3().text(title))
                    .child(p().text(body))
                    .child(span().class("feature__num").text(format!("0{}", i + 1)))
            },
        )))
}

fn steps(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    let list = [
        (
            "dice",
            t("Réglez", "Tune"),
            t(
                "Choisissez le type de secret, la longueur et les caractères. L'entropie et le niveau se mettent à jour à chaque geste.",
                "Pick the kind of secret, its length and characters. Entropy and level update with every move.",
            ),
        ),
        (
            "anvil",
            t("Forgez", "Forge"),
            t(
                "Un tap, et le générateur cryptographique de l'iPhone forge un secret neuf, que vous copiez ou forgez encore.",
                "One tap, and the iPhone's cryptographic generator forges a fresh secret, to copy or forge again.",
            ),
        ),
        (
            "vault",
            t("Rangez", "Store"),
            t(
                "Enregistrez-le dans le coffre avec le site et l'identifiant : il ne ressortira qu'avec Face ID.",
                "Save it in the vault with the site and username: it only comes out again with Face ID.",
            ),
        ),
    ];
    section()
        .class("section wrap")
        .id("how")
        .child(section_head(
            t("Comment ça marche", "How it works"),
            t("Trois gestes, aucun compte.", "Three moves, no account."),
            t("Pas d'inscription, pas de mot de passe maître à inventer : votre iPhone est déjà la clé.", "No sign-up, no master password to invent: your iPhone already is the key."),
        ))
        .child(
            div()
                .class("steps")
                .attr("data-progress", "")
                .child(div().class("steps__track").attr("aria-hidden", "true").html(r#"<svg class="steps__line" viewBox="0 0 1000 40" preserveAspectRatio="none" aria-hidden="true"><path class="steps__path-bg" d="M20 20 C 260 -10, 420 50, 500 20 S 760 -10, 980 20" pathLength="1"/><path class="steps__path" d="M20 20 C 260 -10, 420 50, 500 20 S 760 -10, 980 20" pathLength="1"/></svg>"#))
                .children(list.into_iter().enumerate().map(|(i, (ic, title, body))| {
                    div()
                        .class("step")
                        .attr("data-reveal", "")
                        .style(format!("--d:{i}"))
                        .child(div().class("step__badge").child(icon(ic)).child(span().class("step__n").text(format!("{}", i + 1))))
                        .child(h3().text(title))
                        .child(p().text(body))
                })),
        )
}

fn generator_section(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    section()
        .class("section section--glow")
        .id("generator")
        .child(
            div()
                .class("wrap")
                .child(section_head(
                    t("Essayez-le ici", "Try it here"),
                    t("Le moteur de KeyForge, dans votre navigateur.", "KeyForge's engine, in your browser."),
                    t(
                        "Les mêmes règles que l'app, écrites en Rust et compilées en WebAssembly. Le hasard vient de crypto.getRandomValues : rien ne quitte cet onglet.",
                        "The same rules as the app, written in Rust and compiled to WebAssembly. Randomness comes from crypto.getRandomValues: nothing leaves this tab.",
                    ),
                ))
                .child(
                    div()
                        .class("panel")
                        .attr("data-reveal", "")
                        .child(island("generator", ctx.lang().code(), islands::generator)),
                ),
        )
}

fn analyzer_section(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    section()
        .class("section wrap split-section")
        .id("analyzer")
        .child(
            div()
                .class("split-section__copy")
                .child(eyebrow(t("Testeur de robustesse", "Strength tester")))
                .child(split(h2, t("Votre mot de passe tient-il la route ?", "Does your password hold up?")))
                .child(p().class("lead").attr("data-reveal", "").text(t(
                    "Tapez-le : l'analyse se fait ici, dans votre navigateur, comme dans l'onglet « Analyse » de l'app. Suites, répétitions, mots de passe des fuites célèbres : tout ce qu'un attaquant essaie en premier.",
                    "Type it: the analysis runs here, in your browser, like the app's “Analysis” tab. Runs, repeats, passwords from famous leaks: everything an attacker tries first.",
                )))
                .child(
                    ul().class("ticks").attr("data-reveal", "").children(
                        [
                            t("Rien n'est envoyé, rien n'est enregistré", "Nothing is sent, nothing is stored"),
                            t("Temps de cassage à 100 milliards d'essais par seconde", "Time to crack at 100 billion guesses per second"),
                            t("Des conseils concrets pour faire mieux", "Concrete tips to do better"),
                        ]
                        .into_iter()
                        .map(|s| li().child(icon("check")).child(span().text(s))),
                    ),
                ),
        )
        .child(
            div()
                .class("panel panel--tight")
                .attr("data-reveal", "")
                .style("--d:2")
                .child(island("analyzer", ctx.lang().code(), islands::analyzer)),
        )
}

pub const BROCOLIS: &str = "https://github.com/maxlestage/brocolis";

fn brocolis_section(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    let steps = [
        (
            "words",
            t("Une phrase", "A passphrase"),
            t(
                "Argon2id, 64 Mio, 3 passes : chaque essai coûte cher à l'attaquant.",
                "Argon2id, 64 MiB, 3 passes: every guess is expensive for an attacker.",
            ),
        ),
        (
            "key",
            t("Une clé neuve", "A fresh key"),
            t(
                "32 octets tirés au hasard, protégés par la phrase : [[BROCOLIS-CLE:v2:…]].",
                "32 random bytes, protected by the passphrase: [[BROCOLIS-CLE:v2:…]].",
            ),
        ),
        (
            "lock",
            t("Un jeton scellé", "A sealed token"),
            t(
                "Le texte chiffré en AES-256-GCM sous cette clé : [[BROCOLIS:v1:…]].",
                "The text encrypted with AES-256-GCM under that key: [[BROCOLIS:v1:…]].",
            ),
        ),
    ];
    section()
        .class("section section--glow brocolis")
        .id("brocolis")
        .child(
            div()
                .class("wrap split-section split-section--flip")
                .child(
                    div()
                        .class("split-section__copy")
                        .child(eyebrow(t("Chiffrement Brocolis 🥦", "Brocolis encryption 🥦")))
                        .child(split(h2, t("Scellez un secret, ouvrez-le n'importe où.", "Seal a secret, open it anywhere.")))
                        .child(p().class("lead").attr("data-reveal", "").text(t(
                            "KeyForge confie son chiffrement à Brocolis 🥦 : ses formats, ses vecteurs de test, sa crate Rust. Ici, dans votre navigateur, comme dans la sauvegarde chiffrée de l'app iOS, octet pour octet.",
                            "KeyForge hands its encryption to Brocolis 🥦: its formats, its test vectors, its Rust crate. Here, in your browser, as in the iOS app's encrypted backup, byte for byte.",
                        )))
                        .child(div().class("chain").children(steps.into_iter().enumerate().map(|(i, (ic, title, body))| {
                            div()
                                .class("chain__step")
                                .attr("data-reveal", "")
                                .style(format!("--d:{i}"))
                                .child(span().class("point__icon").child(icon(ic)))
                                .child(div().child(h3().text(title)).child(p().text(body)))
                        })))
                        .child(
                            a().class("btn btn--ghost")
                                .href(BROCOLIS)
                                .attr("target", "_blank")
                                .attr("rel", "noopener")
                                .attr("data-magnetic", "")
                                .child(icon("github"))
                                .child(span().text(t("Le dépôt brocolis", "The brocolis repository"))),
                        ),
                )
                .child(
                    div()
                        .class("panel panel--tight")
                        .attr("data-reveal", "")
                        .style("--d:2")
                        .child(island("sealer", ctx.lang().code(), islands::sealer)),
                ),
        )
}

fn security(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    let points = [
        (
            "offline",
            t("Aucune connexion réseau", "No network connection"),
            t(
                "L'app ne contient aucun code réseau : vos secrets ne peuvent pas partir.",
                "The app contains no networking code: your secrets cannot leave.",
            ),
        ),
        (
            "lock",
            t("Chiffré par l'iPhone", "Encrypted by the iPhone"),
            t(
                "Le coffre vit dans le Trousseau, protégé par la Secure Enclave et votre code.",
                "The vault lives in the Keychain, protected by the Secure Enclave and your passcode.",
            ),
        ),
        (
            "faceid",
            t("Biométrie native", "Native biometrics"),
            t(
                "Face ID et Touch ID passent par LocalAuthentication : KeyForge ne voit jamais votre visage.",
                "Face ID and Touch ID go through LocalAuthentication: KeyForge never sees your face.",
            ),
        ),
        (
            "dice",
            t("Hasard cryptographique", "Cryptographic randomness"),
            t(
                "Chaque caractère est tiré sans biais par le générateur sécurisé du système.",
                "Each character is drawn without bias by the system's secure generator.",
            ),
        ),
    ];
    section().class("section security").id("security").child(
        div()
            .class("wrap security__inner")
            .child(
                div()
                    .class("shield")
                    .attr("aria-hidden", "true")
                    .attr("data-reveal", "")
                    .child(div().class("shield__ring shield__ring--1"))
                    .child(div().class("shield__ring shield__ring--2"))
                    .child(div().class("shield__ring shield__ring--3"))
                    .child(div().class("shield__radar"))
                    .child(div().class("shield__core").child(icon("shield")))
                    .children(
                        ["key", "lock", "faceid", "eyeoff", "dice", "vault"]
                            .into_iter()
                            .enumerate()
                            .map(|(i, ic)| {
                                span()
                                    .class("shield__sat")
                                    .style(format!("--i:{i}"))
                                    .child(icon(ic))
                            }),
                    ),
            )
            .child(
                div()
                    .class("security__copy")
                    .child(eyebrow(t("Sécurité", "Security")))
                    .child(split(
                        h2,
                        t(
                            "Vos secrets ne quittent jamais votre iPhone.",
                            "Your secrets never leave your iPhone.",
                        ),
                    ))
                    .child(
                        div().class("security__points").children(
                            points
                                .into_iter()
                                .enumerate()
                                .map(|(i, (ic, title, body))| {
                                    div()
                                        .class("point")
                                        .attr("data-reveal", "")
                                        .style(format!("--d:{i}"))
                                        .child(span().class("point__icon").child(icon(ic)))
                                        .child(div().child(h3().text(title)).child(p().text(body)))
                                }),
                        ),
                    )
                    .child(button_link(
                        "btn btn--ghost",
                        ctx.href(PageKind::Security),
                        t("Lire le modèle de sécurité", "Read the security model"),
                        "arrow",
                    )),
            ),
    )
}

/// Un écran d'app miniature pour la galerie.
fn screen(title: &'static str, caption: &'static str, body: Element, i: usize) -> Element {
    figure()
        .class("shot")
        .attr("data-reveal", "")
        .style(format!("--d:{i}"))
        .child(
            div()
                .class("phone phone--mini")
                .child(div().class("phone__island"))
                .child(
                    div()
                        .class("phone__screen")
                        .child(div().class("app-bar").child(strong().text(title)))
                        .child(body),
                ),
        )
        .child(figcaption().text(caption))
}

fn screens(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    let vault = div().class("mini-list").children(
        [
            ("G", "GitHub", "max@…", true),
            ("B", t("Banque", "Bank"), "•••• 4821", true),
            ("M", t("Messagerie", "Mail"), "max@…", false),
            ("W", t("Wi-Fi maison", "Home Wi-Fi"), "Box-7F2A", false),
            ("N", "Netflix", "famille@…", false),
        ]
        .into_iter()
        .enumerate()
        .map(|(i, (letter, name, sub, fav))| {
            div()
                .class("mini-item")
                .style(format!("--i:{i}"))
                .child(span().class("mini-item__avatar").text(letter))
                .child(
                    span()
                        .class("mini-item__text")
                        .child(strong().text(name))
                        .child(small().text(sub)),
                )
                .child(fav.then(|| span().class("mini-item__star").text("★")))
        }),
    );
    let analysis = div()
        .class("mini-gauge")
        .child(span().class("mini-gauge__arc").html(r#"<svg viewBox="0 0 120 70" aria-hidden="true"><path class="mini-gauge__bg" d="M10 62a50 50 0 0 1 100 0" pathLength="1"/><path class="mini-gauge__fg" d="M10 62a50 50 0 0 1 100 0" pathLength="1"/></svg>"#))
        .child(strong().class("mini-gauge__value").text(t("Forte", "Strong")))
        .child(div().class("mini-checks").children(
            [t("12 caractères ou plus", "12+ characters"), t("Symboles", "Symbols"), t("Aucune suite", "No runs"), t("Absent des fuites", "Not leaked")]
                .into_iter()
                .enumerate()
                .map(|(i, s)| span().style(format!("--i:{i}")).child(icon("check")).child(span().text(s))),
        ));
    let settings = div().class("mini-settings").children(
        [
            (t("Verrouillage biométrique", "Biometric lock"), true),
            (t("Effacer le presse-papiers", "Clear clipboard"), true),
            (t("Retours haptiques", "Haptics"), true),
            (t("Phrase par défaut", "Passphrase by default"), false),
        ]
        .into_iter()
        .enumerate()
        .map(|(i, (label, on))| {
            div()
                .class("mini-setting")
                .style(format!("--i:{i}"))
                .child(span().text(label))
                .child(span().class(if on { "app-switch is-on" } else { "app-switch" }))
        }),
    );
    let phrase = div()
        .class("mini-phrase")
        .child(
            p().class("app-secret app-secret--phrase")
                .attr("data-scramble", "passphrase")
                .attr("data-length", "4")
                .text(sample(Mode::Passphrase, 4, 11)),
        )
        .child(
            div()
                .class("app-meter app-meter--fair")
                .children((0..5).map(|i| span().style(format!("--i:{i}")))),
        )
        .child(
            p().class("app-level")
                .child(strong().text(t("Correcte", "Fair")))
                .child(span().text(" · 40 bits")),
        );
    section()
        .class("section")
        .id("screens")
        .child(div().class("wrap").child(section_head(
            t("Aperçu", "Preview"),
            t("Une app sobre, vivante, et à vous.", "A quiet, lively app that is yours."),
            t("Thème sombre « forge », animations fluides, retours haptiques, Dynamic Type et VoiceOver.", "A dark “forge” theme, fluid animations, haptics, Dynamic Type and VoiceOver."),
        )))
        .child(
            div()
                .class("shots")
                .attr("data-drag", "")
                .attr("data-cursor", t("Glisser", "Drag"))
                .child(screen(t("Phrase de passe", "Passphrase"), t("Des phrases faciles à retenir", "Phrases that are easy to remember"), phrase, 0))
                .child(screen(t("Coffre", "Vault"), t("Le coffre, derrière Face ID", "The vault, behind Face ID"), vault, 1))
                .child(screen(t("Analyse", "Analysis"), t("L'analyse de vos anciens mots de passe", "Checking your old passwords"), analysis, 2))
                .child(screen(t("Réglages", "Settings"), t("Des réglages simples", "Simple settings"), settings, 3)),
        )
}

fn compare(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    let rows = [
        (
            t(
                "Le même mot de passe partout",
                "The same password everywhere",
            ),
            t("Un secret unique par compte", "A unique secret per account"),
        ),
        (
            t(
                "« Soleil2024! », deviné en secondes",
                "“Summer2024!”, guessed in seconds",
            ),
            t("128 bits, hors de portée", "128 bits, out of reach"),
        ),
        (
            t(
                "Un carnet ou une note en clair",
                "A notebook or a plain note",
            ),
            t(
                "Un coffre chiffré derrière Face ID",
                "An encrypted vault behind Face ID",
            ),
        ),
        (
            t(
                "Un mot de passe copié qui traîne",
                "A copied password lying around",
            ),
            t(
                "Un presse-papiers qui s'efface seul",
                "A clipboard that clears itself",
            ),
        ),
        (
            t("Un compte de plus à créer", "Yet another account to create"),
            t("Aucune inscription, aucun serveur", "No sign-up, no server"),
        ),
    ];
    section()
        .class("section wrap")
        .id("compare")
        .child(section_head(
            t("Avant, après", "Before, after"),
            t("Finies les mauvaises habitudes.", "Goodbye, bad habits."),
            t(
                "Ce que KeyForge change au quotidien.",
                "What KeyForge changes every day.",
            ),
        ))
        .child(
            div()
                .class("compare")
                .child(
                    div()
                        .class("compare__head")
                        .child(span().text(t("Sans KeyForge", "Without KeyForge")))
                        .child(
                            span()
                                .class("grad")
                                .text(t("Avec KeyForge", "With KeyForge")),
                        ),
                )
                .children(rows.into_iter().enumerate().map(|(i, (before, after))| {
                    div()
                        .class("compare__row")
                        .attr("data-reveal", "")
                        .style(format!("--d:{i}"))
                        .child(
                            p().class("compare__before")
                                .child(icon("x"))
                                .child(span().text(before)),
                        )
                        .child(span().class("compare__arrow").child(icon("arrow")))
                        .child(
                            p().class("compare__after")
                                .child(icon("check"))
                                .child(span().text(after)),
                        )
                })),
        )
}

/// Les questions fréquentes, partagées avec le centre d'aide.
pub fn faq_items(lang: Lang) -> Vec<(&'static str, &'static str)> {
    let t = |fr, en| lang.t(fr, en);
    vec![
        (
            t("KeyForge est-il gratuit ?", "Is KeyForge free?"),
            t(
                "Le prix sera annoncé à la sortie sur l'App Store. Dans tous les cas, l'app ne contient ni publicité, ni traqueur, ni compte à créer.",
                "The price will be announced at launch on the App Store. Either way, the app has no ads, no trackers and no account to create.",
            ),
        ),
        (
            t(
                "Mes mots de passe sont-ils envoyés quelque part ?",
                "Are my passwords sent anywhere?",
            ),
            t(
                "Non. L'app ne fait aucune requête réseau. Le coffre est stocké dans le Trousseau de votre iPhone, avec l'option « cet appareil uniquement » : il n'est pas non plus synchronisé par iCloud.",
                "No. The app makes no network request. The vault is stored in your iPhone's Keychain with the “this device only” option: it is not synced through iCloud either.",
            ),
        ),
        (
            t(
                "Que se passe-t-il si je perds mon iPhone ?",
                "What happens if I lose my iPhone?",
            ),
            t(
                "Le coffre reste chiffré et inaccessible sans votre visage, votre doigt ou votre code. Comme il n'est pas synchronisé, pensez à garder une copie de vos accès les plus importants ailleurs, en lieu sûr.",
                "The vault stays encrypted and out of reach without your face, finger or passcode. Since it is not synced, keep a copy of your most important logins somewhere safe.",
            ),
        ),
        (
            t("Qu'est-ce que l'entropie ?", "What is entropy?"),
            t(
                "C'est la mesure, en bits, du nombre d'essais qu'il faudrait pour deviner un secret : chaque bit double le travail. Au-delà de 60 bits un secret est fort, au-delà de 128 il est hors de portée de toute attaque connue.",
                "It measures, in bits, how many guesses it would take to find a secret: every bit doubles the work. Above 60 bits a secret is strong, above 128 it is out of reach of any known attack.",
            ),
        ),
        (
            t(
                "Mot de passe ou phrase de passe ?",
                "Password or passphrase?",
            ),
            t(
                "Un mot de passe aléatoire est le plus compact ; une phrase de passe est bien plus facile à retenir et à taper. Six mots de la liste valent 60 bits : parfait pour un mot de passe que vous devez taper de mémoire.",
                "A random password is the most compact; a passphrase is much easier to remember and type. Six words from the list are worth 60 bits: perfect for a password you must type from memory.",
            ),
        ),
        (
            t(
                "Quels appareils sont pris en charge ?",
                "Which devices are supported?",
            ),
            t(
                "Les iPhone et iPad sous iOS 17 ou plus récent. Ce site, lui, s'installe comme une app web sur n'importe quel appareil et fonctionne hors ligne.",
                "iPhone and iPad running iOS 17 or later. This website installs as a web app on any device and works offline.",
            ),
        ),
        (
            t(
                "Le générateur de ce site est-il sûr ?",
                "Is this website's generator safe?",
            ),
            t(
                "Il tourne entièrement dans votre navigateur, en WebAssembly, avec crypto.getRandomValues. Aucune valeur n'est envoyée au serveur : vous pouvez même couper le réseau avant de l'utiliser.",
                "It runs entirely in your browser, in WebAssembly, with crypto.getRandomValues. No value is sent to the server: you can even go offline before using it.",
            ),
        ),
        (
            t("Qu'est-ce que Brocolis 🥦 ?", "What is Brocolis 🥦?"),
            t(
                "Le projet de chiffrement auquel KeyForge confie ses formats : clés protégées par une phrase (Argon2id) et jetons AES-256-GCM, avec une implémentation de référence en Rust et des vecteurs de test. La sauvegarde chiffrée de l'app et le scelleur de ce site produisent exactement ses octets, lisibles par les apps Brocolis.",
                "The encryption project KeyForge hands its formats to: passphrase-protected keys (Argon2id) and AES-256-GCM tokens, with a reference implementation in Rust and test vectors. The app's encrypted backup and this site's sealer produce exactly its bytes, readable by the Brocolis apps.",
            ),
        ),
        (
            t("Le code est-il public ?", "Is the code public?"),
            t(
                "Le site et l'application sont développés dans le dépôt GitHub du projet : vous pouvez y lire le code, suivre les versions et signaler un problème.",
                "The website and the app are developed in the project's GitHub repository: read the code, follow releases and report issues there.",
            ),
        ),
    ]
}

pub fn faq_list(lang: Lang) -> Element {
    div()
        .class("faq")
        .children(faq_items(lang).into_iter().enumerate().map(|(i, (q, a))| {
            details()
                .class("faq__item")
                .attr("data-reveal", "")
                .style(format!("--d:{}", i % 4))
                .child(
                    summary()
                        .child(span().class("faq__q").text(q))
                        .child(span().class("faq__plus").attr("aria-hidden", "true")),
                )
                .child(div().class("faq__a").child(div().child(p().text(a))))
        }))
}

fn faq(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    section()
        .class("section wrap")
        .id("faq")
        .child(section_head(
            "FAQ",
            t("Vos questions, nos réponses.", "Your questions, answered."),
            t(
                "Et si la vôtre n'y est pas, le centre d'aide va plus loin.",
                "And if yours is missing, the help center goes further.",
            ),
        ))
        .child(faq_list(ctx.lang()))
        .child(
            div()
                .class("center")
                .attr("data-reveal", "")
                .child(button_link(
                    "btn btn--ghost",
                    ctx.href(PageKind::Help),
                    t("Ouvrir le centre d'aide", "Open the help center"),
                    "lifebuoy",
                )),
        )
}

fn download(ctx: &Ctx) -> Element {
    let t = |fr, en| ctx.t(fr, en);
    section()
        .class("download")
        .id("download")
        .child(div().class("download__bg").attr("aria-hidden", "true").child(canvas().class("embers").attr("data-count", "50")))
        .child(
            div()
                .class("wrap download__inner")
                .child(div().class("download__logo").attr("data-reveal", "").child(logo()))
                .child(split(h2, t("Prêt à forger vos clés ?", "Ready to forge your keys?")))
                .child(p().class("lead").attr("data-reveal", "").text(t(
                    "KeyForge arrive sur l'App Store pour iPhone et iPad (iOS 17 ou plus récent). En attendant, installez ce site : il fonctionne hors ligne, avec le générateur et le testeur.",
                    "KeyForge is coming to the App Store for iPhone and iPad (iOS 17 or later). Meanwhile, install this website: it works offline, with the generator and the tester.",
                )))
                .child(
                    div()
                        .class("download__actions")
                        .attr("data-reveal", "")
                        .child(
                            a().class("store store--lg")
                                .href(format!("{REPO}/releases"))
                                .attr("data-magnetic", "")
                                .child(icon("apple"))
                                .child(span().child(small().text(t("Bientôt sur", "Coming soon to the"))).child(strong().text("App Store"))),
                        )
                        .child(button_link("btn btn--ghost btn--lg", REPO.into(), t("Voir le code source", "View the source"), "github")),
                )
                .child(p().class("download__note muted").attr("data-reveal", "").text(t(
                    "Pour être prévenu de la sortie : abonnez-vous au flux RSS des versions, en bas de page.",
                    "To hear about the launch: subscribe to the releases RSS feed, at the bottom of the page.",
                ))),
        )
}

fn home(ctx: &Ctx) -> Page {
    let content = html::main()
        .class("home")
        .child(hero(ctx))
        .child(marquee(ctx))
        .child(stats(ctx))
        .child(features(ctx))
        .child(steps(ctx))
        .child(generator_section(ctx))
        .child(analyzer_section(ctx))
        .child(brocolis_section(ctx))
        .child(security(ctx))
        .child(screens(ctx))
        .child(compare(ctx))
        .child(faq(ctx))
        .child(download(ctx));
    layout(
        ctx,
        ctx.t("KeyForge · Forgez des clés incassables", "KeyForge · Forge unbreakable keys"),
        ctx.t(
            "KeyForge, l'app iPhone qui génère des mots de passe, phrases de passe et codes PIN incassables, les range derrière Face ID et analyse leur robustesse. Hors ligne, sans compte.",
            "KeyForge, the iPhone app that generates unbreakable passwords, passphrases and PIN codes, keeps them behind Face ID and checks their strength. Offline, no account.",
        ),
        content,
    )
}

/// La page d'une route.
pub fn render(ctx: &Ctx) -> Page {
    match ctx.route.page {
        PageKind::Home => home(ctx),
        _ => super::docs::render(ctx),
    }
}
