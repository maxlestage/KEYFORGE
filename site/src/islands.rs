//! Les parties interactives du site. Chaque îlot est rendu par le serveur comme une vue
//! ordinaire puis, compilé en WebAssembly, repris par le navigateur à partir du même code.
//!
//! Règle des îlots : le rendu ne dépend que des props (la langue). Le hasard et tout ce
//! qui n'existe que dans le navigateur arrivent ensuite, par des effets.

use paquets::prelude::*;

use crate::forge::{self, Level, Mode, Options, SEPARATORS};
use crate::i18n::{Lang, duration, number};
use crate::icons::icon;

fn lang(props: &str) -> Lang {
    Lang::parse(props).unwrap_or(Lang::Fr)
}

/// Chaque îlot, enregistré sous le nom utilisé par `island(...)`.
pub const ISLANDS: [(&str, paquets::active::IslandFn); 4] = [
    ("generator", generator),
    ("analyzer", analyzer),
    ("theme", theme),
    ("pwa", pwa),
];

pub fn level_label(lang: Lang, level: Level) -> &'static str {
    match level {
        Level::VeryWeak => lang.t("Très faible", "Very weak"),
        Level::Weak => lang.t("Faible", "Weak"),
        Level::Fair => lang.t("Correcte", "Fair"),
        Level::Strong => lang.t("Forte", "Strong"),
        Level::Excellent => lang.t("Excellente", "Excellent"),
    }
}

/// Une jauge en cinq segments, avec une barre continue dessous.
fn meter(rank: impl Fn() -> u8 + Copy + 'static, fill: impl Fn() -> f64 + 'static) -> Element {
    div()
        .class("meter")
        .attr_dyn("data-level", move || rank().to_string())
        .child(div().class("meter__segs").children((1..=5u8).map(move |i| {
            span()
                .class("meter__seg")
                .style(format!("--i:{i}"))
                .class_if("on", move || rank() >= i)
        })))
        .child(div().class("meter__track").child(
            span().class("meter__bar").style_dyn("width", move || {
                format!("{:.1}%", fill().clamp(0.0, 1.0) * 100.0)
            }),
        ))
}

fn char_kind(c: char) -> &'static str {
    if c.is_ascii_digit() {
        "c c--d"
    } else if c.is_ascii_alphabetic() {
        "c c--l"
    } else if c == '•' {
        "c c--p"
    } else {
        "c c--s"
    }
}

// ----- Générateur ------------------------------------------------------------------------

/// Le générateur de KeyForge : mot de passe, phrase de passe ou code PIN, avec la même
/// logique que l'application, tiré par `crypto.getRandomValues`.
pub fn generator(props: &str) -> Node {
    let l = lang(props);
    let opts = use_state(Options::default());
    let value = use_state(String::new());
    // Ce qui est affiché : les caractères et s'ils sont arrivés (l'animation de
    // déchiffrement les fait défiler avant).
    let shown = use_state(vec![('•', false); 20]);
    let bits = use_state(Options::default().entropy());
    let copied = use_state(false);
    let spins = use_state(0u32);
    #[cfg(not(target_arch = "wasm32"))]
    let _ = value;

    // Chaque changement d'options forge un nouveau secret (dans le navigateur).
    effect(move || {
        let o = opts.get();
        untrack(move || {
            #[cfg(target_arch = "wasm32")]
            crate::client::forge_into(&o, value, shown, bits);
            let _ = &o;
        });
    });

    let regenerate = move || {
        spins.update(|n| *n += 1);
        opts.update(|_| {});
    };
    let mode = move || opts.with(|o| o.mode);
    let level = move || Level::of(opts.with(Options::entropy)).rank();

    let tab = move |m: Mode, label: &'static str, ic: &'static str| {
        button()
            .class("gen__tab")
            .attr("type", "button")
            .attr("role", "tab")
            .attr_dyn("aria-selected", move || (mode() == m).to_string())
            .class_if("is-active", move || mode() == m)
            .on_click(move |_| {
                if mode() != m {
                    opts.update(|o| {
                        o.mode = m;
                        o.length = m.range().2;
                    });
                }
            })
            .child(icon(ic))
            .child(span().text(label))
    };

    let switch = |label: &'static str, get: fn(&Options) -> bool, set: fn(&mut Options, bool)| {
        label_el()
            .class("switch")
            .child(
                input()
                    .attr("type", "checkbox")
                    .bool_attr("checked", move || opts.with(get))
                    .on("change", move |e| opts.update(|o| set(o, e.checked()))),
            )
            .child(
                span()
                    .class("switch__track")
                    .child(span().class("switch__thumb")),
            )
            .child(span().class("switch__label").text(label))
    };

    div()
        .class("gen")
        .attr("data-cursor", l.t("Forger", "Forge"))
        .child(
            div()
                .class("gen__tabs")
                .attr("role", "tablist")
                .attr("aria-label", l.t("Type de secret", "Kind of secret"))
                .style_dyn("--tab", move || {
                    Mode::ALL.iter().position(|m| *m == mode()).unwrap_or(0).to_string()
                })
                .child(span().class("gen__tab-ink").attr("aria-hidden", "true"))
                .child(tab(Mode::Password, l.t("Mot de passe", "Password"), "key"))
                .child(tab(Mode::Passphrase, l.t("Phrase de passe", "Passphrase"), "words"))
                .child(tab(Mode::Pin, l.t("Code PIN", "PIN code"), "hash")),
        )
        .child(
            div()
                .class("gen__screen")
                .class_if("is-copied", move || copied.get())
                .child(
                    output()
                        .class("gen__value")
                        .attr("aria-live", "polite")
                        .attr("aria-label", l.t("Secret généré", "Generated secret"))
                        .class_if("is-phrase", move || mode() == Mode::Passphrase)
                        .children_indexed(
                            move || shown.get(),
                            |item| {
                                span()
                                    .attr_dyn("class", move || {
                                        let (c, done) = item.get();
                                        format!(
                                            "{}{}",
                                            char_kind(c),
                                            if done { " is-set" } else { "" }
                                        )
                                    })
                                    .text_dyn(move || item.get().0.to_string())
                                    .into()
                            },
                        ),
                )
                .child(
                    div()
                        .class("gen__actions")
                        .child(
                            button()
                                .class("icon-btn gen__regen")
                                .attr("type", "button")
                                .attr("aria-label", l.t("Forger un autre secret", "Forge another one"))
                                .attr("data-cursor", l.t("Encore", "Again"))
                                .style_dyn("--spins", move || spins.get().to_string())
                                .on_click(move |_| regenerate())
                                .child(icon("refresh")),
                        )
                        .child(
                            button()
                                .class("btn btn--primary gen__copy")
                                .attr("type", "button")
                                .attr("data-magnetic", "")
                                .on_click(move |_| {
                                    #[cfg(target_arch = "wasm32")]
                                    crate::client::copy_text(&value.get(), copied);
                                })
                                .child(
                                    span()
                                        .class("gen__copy-icons")
                                        .child(icon("copy").class("i-copy"))
                                        .child(icon("check").class("i-done")),
                                )
                                .child(span().text_dyn(move || {
                                    if copied.get() {
                                        l.t("Copié !", "Copied!").into()
                                    } else {
                                        l.t("Copier", "Copy").into()
                                    }
                                }))
                                .child(
                                    span().class("burst").attr("aria-hidden", "true").children(
                                        (0..10).map(|i| i_el().style(format!("--k:{i}"))),
                                    ),
                                ),
                        ),
                ),
        )
        .child(
            div()
                .class("gen__strength")
                .child(meter(level, move || bits.get() / 128.0))
                .child(
                    p().class("gen__level")
                        .child(strong().text_dyn(move || {
                            level_label(l, Level::of(opts.with(Options::entropy))).into()
                        }))
                        .child(span().class("gen__bits").text_dyn(move || {
                            format!("{} bits", number(l, bits.get(), 0))
                        }))
                        .child(span().class("gen__time").text_dyn(move || {
                            let secs = forge::crack_seconds(opts.with(Options::entropy));
                            format!("{} {}", l.t("· cassé en", "· cracked in"), duration(l, secs))
                        })),
                ),
        )
        .child(
            div()
                .class("gen__controls")
                .child(
                    label_el()
                        .class("range")
                        .child(span().class("range__label").text_dyn(move || {
                            match mode() {
                                Mode::Password => l.t("Longueur", "Length"),
                                Mode::Passphrase => l.t("Nombre de mots", "Words"),
                                Mode::Pin => l.t("Chiffres", "Digits"),
                            }
                            .into()
                        }))
                        .child(
                            strong()
                                .class("range__value")
                                .text_dyn(move || opts.with(Options::clamped).to_string()),
                        )
                        .child(
                            input()
                                .attr("type", "range")
                                .attr_dyn("min", move || mode().range().0.to_string())
                                .attr_dyn("max", move || mode().range().1.to_string())
                                .attr_dyn("value", move || opts.with(Options::clamped).to_string())
                                .style_dyn("--fill", move || {
                                    let (min, max, _) = mode().range();
                                    let v = opts.with(Options::clamped);
                                    format!(
                                        "{:.1}%",
                                        f64::from(v - min) / f64::from(max - min) * 100.0
                                    )
                                })
                                .on_input(move |e| {
                                    if let Ok(n) = e.value().parse() {
                                        opts.update(|o| o.length = n);
                                    }
                                }),
                        ),
                )
                .child(
                    div()
                        .class("gen__group")
                        .bool_attr("hidden", move || mode() != Mode::Password)
                        .child(switch("A–Z", |o| o.upper, |o, v| o.upper = v))
                        .child(switch("a–z", |o| o.lower, |o, v| o.lower = v))
                        .child(switch("0–9", |o| o.digits, |o, v| o.digits = v))
                        .child(switch("!@#", |o| o.symbols, |o, v| o.symbols = v))
                        .child(switch(
                            l.t("Sans ambigus (0 O 1 l I)", "No look-alikes (0 O 1 l I)"),
                            |o| o.avoid_ambiguous,
                            |o, v| o.avoid_ambiguous = v,
                        )),
                )
                .child(
                    div()
                        .class("gen__group")
                        .bool_attr("hidden", move || mode() != Mode::Passphrase)
                        .child(
                            div()
                                .class("chips")
                                .attr("role", "group")
                                .attr("aria-label", l.t("Séparateur", "Separator"))
                                .child(span().class("chips__label").text(l.t("Séparateur", "Separator")))
                                .children(SEPARATORS.iter().map(move |&sep| {
                                    button()
                                        .class("chip")
                                        .attr("type", "button")
                                        .class_if("is-active", move || {
                                            opts.with(|o| o.separator == sep)
                                        })
                                        .on_click(move |_| opts.update(|o| o.separator = sep))
                                        .text(if sep == ' ' {
                                            "␣".to_string()
                                        } else {
                                            sep.to_string()
                                        })
                                })),
                        )
                        .child(switch(
                            l.t("Majuscules", "Capitalize"),
                            |o| o.capitalize,
                            |o, v| o.capitalize = v,
                        ))
                        .child(switch(
                            l.t("Ajouter un chiffre", "Add a digit"),
                            |o| o.add_number,
                            |o, v| o.add_number = v,
                        )),
                )
                .child(
                    p().class("gen__group gen__hint")
                        .bool_attr("hidden", move || mode() != Mode::Pin)
                        .text(l.t(
                            "Chaque chiffre est tiré sans biais. Un code PIN protège un appareil qui bloque les essais : pour un compte en ligne, préférez une phrase de passe.",
                            "Each digit is drawn without bias. A PIN protects a device that blocks retries: for an online account, prefer a passphrase.",
                        )),
                ),
        )
        .into()
}

/// `label`, dont le nom est pris par la fonction de l'îlot plus haut.
fn label_el() -> Element {
    paquets::prelude::html::label()
}

fn i_el() -> Element {
    paquets::prelude::html::i()
}

// ----- Analyseur -------------------------------------------------------------------------

/// Analyse la robustesse d'un mot de passe, sans jamais l'envoyer.
pub fn analyzer(props: &str) -> Node {
    let l = lang(props);
    let text = use_state(String::new());
    let visible = use_state(false);
    let result = memo(move || text.with(|t| forge::analyze(t)));
    let empty = move || text.with(String::is_empty);
    let rank = move || {
        if empty() {
            0
        } else {
            result.with(|r| r.level.rank())
        }
    };

    let check = move |label: &'static str, ok: fn(&forge::Analysis) -> bool| {
        li().class("check")
            .class_if("ok", move || !empty() && result.with(ok))
            .child(span().class("check__box").child(icon("check")))
            .child(span().text(label))
    };

    div()
        .class("an")
        .child(
            div()
                .class("an__field")
                .child(icon("key"))
                .child(
                    input()
                        .attr_dyn("type", move || {
                            if visible.get() { "text" } else { "password" }.into()
                        })
                        .attr("placeholder", l.t("Tapez un mot de passe à tester", "Type a password to test"))
                        .attr("aria-label", l.t("Mot de passe à analyser", "Password to analyse"))
                        .attr("autocomplete", "off")
                        .attr("autocapitalize", "off")
                        .attr("spellcheck", "false")
                        .attr("data-cursor", l.t("Tester", "Test"))
                        .on_input(move |e| text.set(e.value())),
                )
                .child(
                    button()
                        .class("icon-btn")
                        .attr("type", "button")
                        .attr_dyn("aria-label", move || {
                            if visible.get() {
                                l.t("Masquer", "Hide")
                            } else {
                                l.t("Afficher", "Show")
                            }
                            .into()
                        })
                        .on_click(move |_| visible.update(|v| *v = !*v))
                        .child(
                            span()
                                .class("eye")
                                .class_if("is-open", move || visible.get())
                                .child(icon("eye").class("i-open"))
                                .child(icon("eyeoff").class("i-closed")),
                        ),
                ),
        )
        .child(meter(rank, move || {
            if empty() { 0.0 } else { result.with(|r| r.bits / 128.0) }
        }))
        .child(
            div()
                .class("an__stats")
                .child(
                    div().class("stat").child(span().text(l.t("Niveau", "Level"))).child(
                        strong().text_dyn(move || {
                            if empty() {
                                "—".into()
                            } else {
                                level_label(l, result.with(|r| r.level)).into()
                            }
                        }),
                    ),
                )
                .child(
                    div().class("stat").child(span().text(l.t("Entropie estimée", "Estimated entropy"))).child(
                        strong().text_dyn(move || {
                            format!("{} bits", number(l, result.with(|r| r.bits), 0))
                        }),
                    ),
                )
                .child(
                    div().class("stat").child(span().text(l.t("Temps pour le casser", "Time to crack"))).child(
                        strong().text_dyn(move || {
                            if empty() {
                                "—".into()
                            } else {
                                duration(l, forge::crack_seconds(result.with(|r| r.bits)))
                            }
                        }),
                    ),
                ),
        )
        .child(
            ul().class("checks")
                .child(check(l.t("12 caractères ou plus", "12 characters or more"), |r| r.length >= 12))
                .child(check(l.t("Des minuscules", "Lowercase letters"), |r| r.has_lower))
                .child(check(l.t("Des majuscules", "Uppercase letters"), |r| r.has_upper))
                .child(check(l.t("Des chiffres", "Digits"), |r| r.has_digit))
                .child(check(l.t("Des symboles", "Symbols"), |r| r.has_symbol))
                .child(check(l.t("Ni suite ni répétition", "No runs or repeats"), |r| !r.patterns))
                .child(check(l.t("Absent des listes de fuites", "Not a leaked classic"), |r| !r.common)),
        )
        .child(p().class("an__tip").attr("aria-live", "polite").text_dyn(move || {
            if empty() {
                return l
                    .t(
                        "Votre saisie reste dans cet onglet : elle n'est ni envoyée, ni enregistrée.",
                        "What you type stays in this tab: it is neither sent nor stored.",
                    )
                    .into();
            }
            result.with(|r| {
                if r.common {
                    l.t("Ce mot de passe figure parmi les plus utilisés au monde : changez-le partout, tout de suite.", "This is one of the most used passwords in the world: change it everywhere, right now.")
                } else if r.patterns {
                    l.t("Les suites et répétitions sont essayées en premier. Mélangez davantage.", "Runs and repeats are tried first. Mix it up more.")
                } else if r.length < 12 {
                    l.t("Allongez-le : chaque caractère multiplie le travail de l'attaquant.", "Make it longer: every character multiplies the attacker's work.")
                } else if r.level < Level::Strong {
                    l.t("Ajoutez des classes de caractères, ou passez à une phrase de passe de 6 mots.", "Add character classes, or switch to a 6-word passphrase.")
                } else {
                    l.t("Solide. Gardez-le unique : un mot de passe par compte, rangé dans un coffre.", "Solid. Keep it unique: one password per account, kept in a vault.")
                }
                .into()
            })
        }))
        .into()
}

// ----- Thème -----------------------------------------------------------------------------

/// Bascule clair / sombre. Le choix est gardé dans le navigateur ; la transition part
/// du bouton en cercle (View Transitions, là où le navigateur le permet).
pub fn theme(props: &str) -> Node {
    let l = lang(props);
    button()
        .class("icon-btn theme-btn")
        .attr("type", "button")
        .attr("aria-label", l.t("Changer de thème", "Switch theme"))
        .attr("data-cursor", l.t("Thème", "Theme"))
        .on_click(|_e| {
            #[cfg(target_arch = "wasm32")]
            crate::client::toggle_theme(&_e);
        })
        .child(icon("sun").class("i-sun"))
        .child(icon("moon").class("i-moon"))
        .into()
}

// ----- PWA : installation et réseau ------------------------------------------------------

/// Le statut du réseau en direct, et le bouton « Installer » quand le navigateur le
/// propose (Chrome, Edge, Android). Sur iPhone : Partager → Sur l'écran d'accueil.
pub fn pwa(props: &str) -> Node {
    let l = lang(props);
    let online = use_state(true);
    let installable = use_state(false);
    let installed = use_state(false);
    effect(move || {
        #[cfg(target_arch = "wasm32")]
        crate::client::watch_pwa(online, installable, installed);
    });
    div()
        .class("pwa")
        .child(
            p().class("pwa__status")
                .class_if("is-offline", move || !online.get())
                .attr("aria-live", "polite")
                .child(span().class("pulse").attr("aria-hidden", "true"))
                .child(span().text_dyn(move || {
                    if online.get() {
                        l.t(
                            "En ligne · disponible aussi hors ligne",
                            "Online · also works offline",
                        )
                    } else {
                        l.t(
                            "Hors ligne · le site reste consultable",
                            "Offline · the site still works",
                        )
                    }
                    .into()
                })),
        )
        .child(
            button()
                .class("btn btn--ghost btn--sm pwa__install")
                .attr("type", "button")
                .bool_attr("hidden", move || !installable.get() || installed.get())
                .on_click(move |_| {
                    #[cfg(target_arch = "wasm32")]
                    crate::client::prompt_install(installable);
                })
                .child(icon("download"))
                .child(span().text(l.t("Installer l'app web", "Install the web app"))),
        )
        .child(
            p().class("pwa__hint")
                .bool_attr("hidden", move || installable.get() || installed.get())
                .text(l.t(
                    "Sur iPhone : Partager → « Sur l'écran d'accueil ».",
                    "On iPhone: Share → “Add to Home Screen”.",
                )),
        )
        .child(
            p().class("pwa__hint")
                .bool_attr("hidden", move || !installed.get())
                .text(l.t("Installée sur cet appareil ✓", "Installed on this device ✓")),
        )
        .into()
}
