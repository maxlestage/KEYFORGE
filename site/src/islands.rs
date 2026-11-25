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
pub const ISLANDS: [(&str, paquets::active::IslandFn); 6] = [
    ("generator", generator),
    ("quantum", quantum),
    ("sealer", sealer),
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
                            move |item| {
                                span()
                                    .attr_dyn("class", move || {
                                        let (c, done) = item.get();
                                        format!(
                                            "{}{}",
                                            char_kind(c),
                                            if done { " is-set" } else { "" }
                                        )
                                    })
                                    .text_dyn(move || {
                                        let (c, done) = item.get();
                                        // Dans une phrase, la ligne ne se coupe qu'après un
                                        // séparateur, jamais au milieu d'un mot.
                                        let breaks = done
                                            && opts.with(|o| {
                                                o.mode == Mode::Passphrase
                                                    && o.separator == c
                                                    && c != ' '
                                            });
                                        if breaks {
                                            format!("{c}\u{200B}")
                                        } else {
                                            c.to_string()
                                        }
                                    })
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
                                        l.t("Copié\u{202f}!", "Copied!").into()
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
                            "Chaque chiffre est tiré sans biais. Un code PIN protège un appareil qui bloque les essais\u{a0}: pour un compte en ligne, préférez une phrase de passe.",
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
                        "Votre saisie reste dans cet onglet\u{a0}: elle n'est ni envoyée, ni enregistrée.",
                        "What you type stays in this tab: it is neither sent nor stored.",
                    )
                    .into();
            }
            result.with(|r| {
                if r.common {
                    l.t("Ce mot de passe figure parmi les plus utilisés au monde\u{a0}: changez-le partout, tout de suite.", "This is one of the most used passwords in the world: change it everywhere, right now.")
                } else if r.patterns {
                    l.t("Les suites et répétitions sont essayées en premier. Mélangez davantage.", "Runs and repeats are tried first. Mix it up more.")
                } else if r.length < 12 {
                    l.t("Allongez-le\u{a0}: chaque caractère multiplie le travail de l'attaquant.", "Make it longer: every character multiplies the attacker's work.")
                } else if r.level < Level::Strong {
                    l.t("Ajoutez des classes de caractères, ou passez à une phrase de passe de 6 mots.", "Add character classes, or switch to a 6-word passphrase.")
                } else {
                    l.t("Solide. Gardez-le unique\u{a0}: un mot de passe par compte, rangé dans un coffre.", "Solid. Keep it unique: one password per account, kept in a vault.")
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
                    "Sur iPhone\u{a0}: Partager → «\u{a0}Sur l'écran d'accueil\u{a0}».",
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

// ----- Scelleur Brocolis 🥦 --------------------------------------------------------------

/// Le message d'une erreur de brocolis-proto, pour un visiteur.
pub fn seal_error(lang: Lang, e: &brocolis_proto::Erreur) -> &'static str {
    use brocolis_proto::Erreur;
    match e {
        Erreur::PhraseTropCourte => lang.t(
            "La phrase doit faire au moins 8 caractères.",
            "The passphrase must be at least 8 characters long.",
        ),
        Erreur::Dechiffrement => lang.t(
            "Phrase incorrecte, ou secret abîmé.",
            "Wrong passphrase, or damaged secret.",
        ),
        Erreur::JetonAbsent | Erreur::Base64 => lang.t(
            "Aucun secret scellé trouvé dans ce texte.",
            "No sealed secret found in this text.",
        ),
        Erreur::Parametres => lang.t(
            "Paramètres Argon2id hors des bornes acceptées.",
            "Argon2id parameters out of the accepted bounds.",
        ),
        _ => lang.t(
            "Ce texte n'a pas pu être traité.",
            "This text could not be processed.",
        ),
    }
}

/// Chiffre un texte sous une phrase, au format Brocolis, dans le navigateur ; et ouvre un
/// secret scellé. Argon2id (64 Mio, 3 passes) puis AES-256-GCM, par brocolis-proto.
pub fn sealer(props: &str) -> Node {
    let l = lang(props);
    let opening = use_state(false);
    let text = use_state(String::new());
    let phrase = use_state(String::new());
    let visible = use_state(false);
    // Une phrase tirée par KeyForge : son entropie est connue (6 mots × 10 bits).
    let generated = use_state(false);
    let busy = use_state(false);
    let output = use_state(String::new());
    let error = use_state(String::new());
    let copied = use_state(false);

    let run = move || {
        if busy.get() {
            return;
        }
        error.set(String::new());
        output.set(String::new());
        busy.set(true);
        #[cfg(target_arch = "wasm32")]
        crate::client::seal_or_open(
            l,
            opening.get(),
            text.get(),
            phrase.get(),
            output,
            error,
            busy,
        );
    };

    let mode = move |open: bool, label: &'static str, ic: &'static str| {
        button()
            .class("gen__tab")
            .attr("type", "button")
            .attr("role", "tab")
            .attr_dyn("aria-selected", move || (opening.get() == open).to_string())
            .class_if("is-active", move || opening.get() == open)
            .on_click(move |_| {
                if opening.get() != open {
                    opening.set(open);
                    text.set(String::new());
                    output.set(String::new());
                    error.set(String::new());
                }
            })
            .child(icon(ic))
            .child(span().text(label))
    };

    div()
        .class("sealer")
        .class_if("is-busy", move || busy.get())
        .class_if("is-opening", move || opening.get())
        .child(
            div()
                .class("gen__tabs sealer__tabs")
                .attr("role", "tablist")
                .style_dyn("--tab", move || if opening.get() { "1".into() } else { "0".into() })
                .child(span().class("gen__tab-ink").attr("aria-hidden", "true"))
                .child(mode(false, l.t("Sceller", "Seal"), "lock"))
                .child(mode(true, l.t("Ouvrir", "Open"), "key")),
        )
        .child(
            label_el()
                .class("sealer__field")
                .child(span().class("sealer__label").text_dyn(move || {
                    if opening.get() {
                        l.t("Le secret scellé (les deux jetons)", "The sealed secret (both tokens)")
                    } else {
                        l.t("Ce que vous voulez protéger", "What you want to protect")
                    }
                    .into()
                }))
                .child(
                    textarea()
                        .attr("rows", "3")
                        .attr("spellcheck", "false")
                        .attr("autocomplete", "off")
                        .attr_dyn("placeholder", move || {
                            if opening.get() {
                                "[[BROCOLIS-CLE:v2:…]]\n[[BROCOLIS:v1:…]]".into()
                            } else {
                                l.t(
                                    "Un mot de passe, un code de récupération, une note…",
                                    "A password, a recovery code, a note…",
                                )
                                .into()
                            }
                        })
                        .attr_dyn("value", move || text.get())
                        .on_input(move |e| text.set(e.value())),
                ),
        )
        .child(
            div()
                .class("sealer__phrase")
                .child(
                    div()
                        .class("an__field")
                        .child(icon("words"))
                        .child(
                            input()
                                .attr_dyn("type", move || {
                                    if visible.get() { "text" } else { "password" }.into()
                                })
                                .attr("placeholder", l.t("Phrase secrète", "Passphrase"))
                                .attr("aria-label", l.t("Phrase secrète", "Passphrase"))
                                .attr("autocomplete", "off")
                                .attr("spellcheck", "false")
                                .attr_dyn("value", move || phrase.get())
                                .on_input(move |e| {
                                    generated.set(false);
                                    phrase.set(e.value());
                                })
                                .on("keydown", move |e| {
                                    if e.key() == "Enter" {
                                        e.prevent_default();
                                        run();
                                    }
                                }),
                        )
                        .child(
                            button()
                                .class("icon-btn")
                                .attr("type", "button")
                                .attr("aria-label", l.t("Afficher la phrase", "Show the passphrase"))
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
                .child(
                    button()
                        .class("btn btn--ghost btn--sm sealer__gen")
                        .attr("type", "button")
                        .bool_attr("hidden", move || opening.get())
                        .on_click(move |_| {
                            #[cfg(target_arch = "wasm32")]
                            {
                                phrase.set(crate::client::new_phrase());
                                generated.set(true);
                                visible.set(true);
                            }
                        })
                        .child(icon("dice"))
                        .child(span().text(l.t("Générer une phrase", "Generate a phrase"))),
                ),
        )
        .child(
            p().class("sealer__strength")
                .bool_attr("hidden", move || opening.get() || phrase.with(String::is_empty))
                .text_dyn(move || {
                    if generated.get() {
                        return l
                            .t(
                                "Phrase générée\u{a0}: 6 mots tirés parmi 1 024 · Correcte · 60 bits, renforcés par Argon2id",
                                "Generated phrase: 6 words drawn from 1,024 · Fair · 60 bits, hardened by Argon2id",
                            )
                            .into();
                    }
                    let a = forge::analyze(&phrase.get());
                    format!(
                        "{} {} · {} bits",
                        l.t("Phrase\u{a0}:", "Passphrase:"),
                        level_label(l, a.level),
                        number(l, a.bits, 0)
                    )
                }),
        )
        .child(
            button()
                .class("btn btn--primary btn--lg sealer__go")
                .attr("type", "button")
                .attr("data-magnetic", "")
                .bool_attr("disabled", move || busy.get())
                .on_click(move |_| run())
                .child(span().class("sealer__spinner").attr("aria-hidden", "true"))
                .child(span().text_dyn(move || {
                    match (busy.get(), opening.get()) {
                        (true, _) => l.t("Argon2id · 64 Mio · 3 passes…", "Argon2id · 64 MiB · 3 passes…"),
                        (false, false) => l.t("Sceller avec Brocolis 🥦", "Seal with Brocolis 🥦"),
                        (false, true) => l.t("Ouvrir avec Brocolis 🥦", "Open with Brocolis 🥦"),
                    }
                    .into()
                })),
        )
        .child(
            p().class("sealer__error")
                .attr("role", "alert")
                .bool_attr("hidden", move || error.with(String::is_empty))
                .text_dyn(move || error.get()),
        )
        .child(
            div()
                .class("sealer__out")
                .class_if("is-copied", move || copied.get())
                .bool_attr("hidden", move || output.with(String::is_empty))
                .child(
                    p().class("sealer__label").text_dyn(move || {
                        if opening.get() {
                            l.t("Le secret, ouvert dans ce navigateur", "The secret, opened in this browser")
                        } else {
                            l.t(
                                "Votre secret scellé\u{a0}: à garder où vous voulez, il ne s'ouvre qu'avec la phrase.",
                                "Your sealed secret: keep it anywhere, it only opens with the passphrase.",
                            )
                        }
                        .into()
                    }),
                )
                .child(pre().class("sealer__blob").attr("aria-live", "polite").text_dyn(move || output.get()))
                .child(
                    button()
                        .class("btn btn--ghost btn--sm")
                        .attr("type", "button")
                        .on_click(move |_| {
                            #[cfg(target_arch = "wasm32")]
                            crate::client::copy_text(&output.get(), copied);
                        })
                        .child(icon("copy"))
                        .child(span().text_dyn(move || {
                            if copied.get() { l.t("Copié\u{202f}!", "Copied!") } else { l.t("Copier", "Copy") }.into()
                        })),
                ),
        )
        .into()
}

// ----- Champs manquants ------------------------------------------------------------------

/// Ce qui manque avant de lancer une opération, dit simplement (`None` : tout est là).
pub enum Missing {
    /// Sceller : le texte, puis la phrase.
    Seal { text: bool, phrase: bool },
    /// Ouvrir un scellé : le secret scellé, puis la phrase.
    Open { sealed: bool, phrase: bool },
    /// Chiffrer pour quelqu'un : son paquet, puis le secret.
    Encrypt { bundle: bool, message: bool },
    /// Déchiffrer : le message reçu.
    Decrypt { message: bool },
}

pub fn missing(lang: Lang, what: Missing) -> Option<&'static str> {
    let t = |fr, en| Some(lang.t(fr, en));
    match what {
        Missing::Seal { text: false, .. } => t(
            "Écrivez d'abord ce que vous voulez protéger.",
            "First write what you want to protect.",
        ),
        Missing::Seal { phrase: false, .. }
        | Missing::Open {
            phrase: false,
            sealed: true,
        } => t(
            "Choisissez une phrase secrète de 8 caractères au moins, ou touchez «\u{a0}Générer une phrase\u{a0}».",
            "Choose a passphrase of at least 8 characters, or tap “Generate a phrase”.",
        ),
        Missing::Open { sealed: false, .. } => t(
            "Collez d'abord le secret scellé (les deux jetons [[BROCOLIS…]]).",
            "First paste the sealed secret (both [[BROCOLIS…]] tokens).",
        ),
        Missing::Encrypt { bundle: false, .. } => t(
            "Collez d'abord le paquet de clés du destinataire, ou touchez «\u{a0}M'écrire à moi-même\u{a0}» pour essayer.",
            "First paste the recipient's key bundle, or tap “Write to myself” to try it.",
        ),
        Missing::Encrypt { message: false, .. } => t(
            "Écrivez d'abord le secret à envoyer.",
            "First write the secret to send.",
        ),
        Missing::Decrypt { message: false } => t(
            "Collez d'abord le message reçu ([[BROCOLIS:v4:…]]).",
            "First paste the message you received ([[BROCOLIS:v4:…]]).",
        ),
        _ => None,
    }
}

/// Un paquet de clés illisible, quand on chiffre.
pub fn bad_bundle(lang: Lang) -> &'static str {
    lang.t(
        "Ce texte n'est pas un paquet de clés Brocolis\u{a0}: copiez-le en entier depuis «\u{a0}Mon identité\u{a0}».",
        "This text is not a Brocolis key bundle: copy it in full from “My identity”.",
    )
}

// ----- Échange post-quantique (Brocolis v4) ----------------------------------------------

/// Le message d'une erreur du protocole v4, pour un visiteur.
pub fn pq_error(lang: Lang, e: &brocolis_proto::Erreur) -> &'static str {
    use brocolis_proto::Erreur;
    match e {
        Erreur::PqIndisponible => lang.t(
            "Ce paquet ne propose pas ML-KEM-768\u{a0}: KeyForge refuse de chiffrer sans post-quantique.",
            "This bundle doesn't offer ML-KEM-768: KeyForge refuses to encrypt without post-quantum.",
        ),
        Erreur::Signature | Erreur::CleInvalide => lang.t(
            "Paquet de clés invalide\u{a0}: une signature Ed25519 ne correspond pas.",
            "Invalid key bundle: an Ed25519 signature doesn't match.",
        ),
        Erreur::Base64 | Erreur::TropGrand => lang.t(
            "Ce texte n'est pas un paquet de clés Brocolis.",
            "This text is not a Brocolis key bundle.",
        ),
        Erreur::CleInconnue => lang.t(
            "Ce message n'est pas adressé à cette identité.",
            "This message isn't addressed to this identity.",
        ),
        Erreur::Rejoue => lang.t(
            "Ce message a déjà été ouvert\u{a0}: un premier message ne s'ouvre qu'une fois.",
            "This message was already opened: a first message opens only once.",
        ),
        Erreur::JetonAbsent => lang.t(
            "Aucun message [[BROCOLIS:v4:…]] trouvé dans ce texte.",
            "No [[BROCOLIS:v4:…]] message found in this text.",
        ),
        Erreur::Format => lang.t(
            "Texte vide ou mal formé.",
            "Empty or malformed text.",
        ),
        _ => lang.t("Ce texte n'a pas pu être traité.", "This text could not be processed."),
    }
}

/// L'échange post-quantique : une identité X25519 + ML-KEM-768 dans le navigateur, chiffrer
/// pour le paquet de clés de quelqu'un, déchiffrer ce qu'on reçoit. Protocole v4 de
/// Brocolis 🥦, par brocolis-proto compilé en WebAssembly.
pub fn quantum(props: &str) -> Node {
    let l = lang(props);
    // 0 : identité, 1 : chiffrer, 2 : déchiffrer.
    let tab = use_state(0u8);
    let bundle = use_state(String::new());
    let print = use_state(String::new());
    let sender_print = use_state(String::new());
    let recipient = use_state(String::new());
    let message = use_state(String::new());
    let incoming = use_state(String::new());
    let output = use_state(String::new());
    let from = use_state(String::new());
    let error = use_state(String::new());
    let copied = use_state(false);
    let busy = use_state(false);

    effect(move || {
        #[cfg(target_arch = "wasm32")]
        crate::client::pq_identity(false, bundle, print, sender_print);
    });

    let tab_button = move |i: u8, label: &'static str, ic: &'static str| {
        button()
            .class("gen__tab")
            .attr("type", "button")
            .attr("role", "tab")
            .attr_dyn("aria-selected", move || (tab.get() == i).to_string())
            .class_if("is-active", move || tab.get() == i)
            .on_click(move |_| {
                tab.set(i);
                output.set(String::new());
                error.set(String::new());
                from.set(String::new());
            })
            .child(icon(ic))
            .child(span().text(label))
    };

    let copy_button = move |what: State<String>| {
        button()
            .class("btn btn--ghost btn--sm")
            .attr("type", "button")
            .on_click(move |_| {
                #[cfg(target_arch = "wasm32")]
                crate::client::copy_text(&what.get(), copied);
                let _ = what;
            })
            .child(icon("copy"))
            .child(span().text_dyn(move || {
                if copied.get() {
                    l.t("Copié\u{202f}!", "Copied!")
                } else {
                    l.t("Copier", "Copy")
                }
                .into()
            }))
    };

    let area = |state: State<String>, rows: &'static str, placeholder: &'static str| {
        textarea()
            .attr("rows", rows)
            .attr("spellcheck", "false")
            .attr("autocomplete", "off")
            .attr("placeholder", placeholder)
            .attr_dyn("value", move || state.get())
            .on_input(move |e| state.set(e.value()))
    };

    div()
        .class("sealer quantum")
        .class_if("is-busy", move || busy.get())
        .child(
            div()
                .class("gen__tabs")
                .attr("role", "tablist")
                .style_dyn("--tab", move || tab.get().to_string())
                .child(span().class("gen__tab-ink").attr("aria-hidden", "true"))
                .child(tab_button(0, l.t("Mon identité", "My identity"), "fingerprint"))
                .child(tab_button(1, l.t("Chiffrer", "Encrypt"), "lock"))
                .child(tab_button(2, l.t("Déchiffrer", "Decrypt"), "key")),
        )
        .child(
            div()
                .class("qbadges")
                .attr("aria-label", l.t("Algorithmes", "Algorithms"))
                .children(["ML-KEM-768", "X25519", "Ed25519", "AES-256-GCM", "HKDF-SHA256"].into_iter().enumerate().map(
                    |(i, name)| span().class("qbadge").style(format!("--i:{i}")).text(name),
                )),
        )
        // Mon identité.
        .child(
            div()
                .class("quantum__panel")
                .bool_attr("hidden", move || tab.get() != 0)
                .child(
                    div()
                        .class("qprint")
                        .child(span().class("sealer__label").text(l.t("Empreinte de mon identité", "My identity fingerprint")))
                        .child(strong().class("qprint__value").text_dyn(move || {
                            let p = print.get();
                            if p.is_empty() { "····-····-····-····".into() } else { p }
                        }))
                        .child(small().class("muted").text_dyn(move || {
                            format!("{} {}", l.t("Vue par vos correspondants\u{a0}:", "Seen by your correspondents:"), sender_print.get())
                        })),
                )
                .child(span().class("sealer__label").text(l.t(
                    "Mon paquet de clés publiques (à donner pour recevoir des secrets)",
                    "My public key bundle (give it out to receive secrets)",
                )))
                .child(pre().class("sealer__blob qbundle").text_dyn(move || bundle.get()))
                .child(
                    div()
                        .class("row")
                        .child(copy_button(bundle))
                        .child(
                            button()
                                .class("btn btn--ghost btn--sm")
                                .attr("type", "button")
                                .on_click(move |_| {
                                    #[cfg(target_arch = "wasm32")]
                                    crate::client::pq_identity(true, bundle, print, sender_print);
                                })
                                .child(icon("refresh"))
                                .child(span().text(l.t("Nouvelle identité", "New identity"))),
                        ),
                )
                .child(p().class("gen__hint").text(l.t(
                    "Votre identité est créée dans cet onglet et y reste (stockage de session)\u{a0}: les clés secrètes ne quittent jamais le navigateur. Pour une identité durable, utilisez l'app iOS.",
                    "Your identity is created in this tab and stays there (session storage): secret keys never leave the browser. For a lasting identity, use the iOS app.",
                ))),
        )
        // Chiffrer.
        .child(
            div()
                .class("quantum__panel")
                .bool_attr("hidden", move || tab.get() != 1)
                .child(
                    label_el()
                        .class("sealer__field")
                        .child(span().class("sealer__label").text(l.t("Le paquet de clés du destinataire", "The recipient's key bundle")))
                        .child(area(recipient, "3", l.t("Collez son paquet de clés (base64)…", "Paste their key bundle (base64)…"))),
                )
                .child(
                    button()
                        .class("btn btn--ghost btn--sm")
                        .attr("type", "button")
                        .on_click(move |_| recipient.set(bundle.get()))
                        .child(icon("fingerprint"))
                        .child(span().text(l.t("M'écrire à moi-même (pour essayer)", "Write to myself (to try it)"))),
                )
                .child(
                    label_el()
                        .class("sealer__field")
                        .child(span().class("sealer__label").text(l.t("Le secret à envoyer", "The secret to send")))
                        .child(area(message, "2", l.t("Un mot de passe, un code, une note…", "A password, a code, a note…"))),
                ),
        )
        // Déchiffrer.
        .child(
            div()
                .class("quantum__panel")
                .bool_attr("hidden", move || tab.get() != 2)
                .child(
                    label_el()
                        .class("sealer__field")
                        .child(span().class("sealer__label").text(l.t("Le message reçu", "The message you received")))
                        .child(area(incoming, "4", "[[BROCOLIS:v4:…]]")),
                ),
        )
        .child(
            button()
                .class("btn btn--primary btn--lg sealer__go")
                .attr("type", "button")
                .attr("data-magnetic", "")
                .bool_attr("hidden", move || tab.get() == 0)
                .bool_attr("disabled", move || busy.get())
                .on_click(move |_| {
                    error.set(String::new());
                    output.set(String::new());
                    from.set(String::new());
                    busy.set(true);
                    #[cfg(target_arch = "wasm32")]
                    crate::client::pq_run(l, tab.get() == 2, recipient.get(), message.get(), incoming.get(), output, from, error, busy);
                })
                .child(span().class("sealer__spinner").attr("aria-hidden", "true"))
                .child(span().text_dyn(move || {
                    if tab.get() == 2 {
                        l.t("Déchiffrer (ML-KEM-768 + X25519)", "Decrypt (ML-KEM-768 + X25519)")
                    } else {
                        l.t("Chiffrer en post-quantique", "Encrypt post-quantum")
                    }
                    .into()
                })),
        )
        .child(
            p().class("sealer__error")
                .attr("role", "alert")
                .bool_attr("hidden", move || error.with(String::is_empty))
                .text_dyn(move || error.get()),
        )
        .child(
            div()
                .class("sealer__out")
                .bool_attr("hidden", move || output.with(String::is_empty) || tab.get() == 0)
                .child(p().class("sealer__label").text_dyn(move || {
                    if tab.get() == 2 {
                        let f = from.get();
                        format!("{} {f}", l.t("Ouvert. Expéditeur\u{a0}:", "Opened. Sender:"))
                    } else {
                        l.t(
                            "Chiffré pour ce seul destinataire. Envoyez-le par n'importe quel canal\u{a0}: seul son appareil peut l'ouvrir, une seule fois.",
                            "Encrypted for this recipient only. Send it over any channel: only their device can open it, once.",
                        )
                        .into()
                    }
                }))
                .child(pre().class("sealer__blob").attr("aria-live", "polite").text_dyn(move || output.get()))
                .child(copy_button(output)),
        )
        .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_fields_are_named() {
        let l = Lang::Fr;
        assert!(
            missing(
                l,
                Missing::Encrypt {
                    bundle: false,
                    message: true
                }
            )
            .unwrap()
            .contains("paquet de clés")
        );
        assert!(
            missing(
                l,
                Missing::Encrypt {
                    bundle: true,
                    message: false
                }
            )
            .unwrap()
            .contains("secret à envoyer")
        );
        assert!(
            missing(
                l,
                Missing::Encrypt {
                    bundle: true,
                    message: true
                }
            )
            .is_none()
        );
        assert!(
            missing(
                l,
                Missing::Seal {
                    text: false,
                    phrase: false
                }
            )
            .unwrap()
            .contains("protéger")
        );
        assert!(
            missing(
                l,
                Missing::Seal {
                    text: true,
                    phrase: false
                }
            )
            .unwrap()
            .contains("phrase secrète")
        );
        assert!(
            missing(
                l,
                Missing::Open {
                    sealed: false,
                    phrase: true
                }
            )
            .unwrap()
            .contains("scellé")
        );
        assert!(
            missing(l, Missing::Decrypt { message: false })
                .unwrap()
                .contains("message reçu")
        );
        assert!(missing(l, Missing::Decrypt { message: true }).is_none());
    }
}
