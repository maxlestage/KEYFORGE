//! Les animations que le CSS ne fait pas seul. Tout est en 2D (aucune 3D), tout se
//! dégrade en une page statique, et tout se calme quand le visiteur préfère moins de
//! mouvement.
//!
//! - introduction (la clé se forge, une fois par session) ;
//! - apparitions au défilement, en cascade, mots par mots ;
//! - barre de progression, navigation qui se cache, parallaxe, lignes qui se dessinent ;
//! - compteurs, machine à écrire, défilement de secrets « déchiffrés » ;
//! - braises dans un canvas 2D ;
//! - curseur, boutons magnétiques, halo qui suit le pointeur, ondulations au clic ;
//! - carrousel à faire glisser, copier, menus, retour en haut, sommaire actif.

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;
use web_sys::{
    Element, HtmlElement, IntersectionObserver, IntersectionObserverEntry, IntersectionObserverInit,
};

use super::{
    CryptoRng, GLYPHS, THEME_KEY, all, document, later, matches, noise, on, on_passive,
    reduced_motion, request_frame, root, set_style, window,
};
use crate::forge::{self, Mode, Options, Rng};
use crate::i18n::{Lang, number};

/// Le thème choisi la dernière fois, avant tout le reste.
pub fn apply_saved_theme() {
    if let Ok(Some(storage)) = window().local_storage()
        && let Ok(Some(theme)) = storage.get_item(THEME_KEY)
        && (theme == "dark" || theme == "light")
    {
        let _ = root().set_attribute("data-theme", &theme);
    }
}

pub fn init() {
    let html = root();
    intro(&html);
    reveals();
    // Seulement maintenant le CSS peut cacher ce qui n'est pas encore apparu : ce qui est
    // déjà à l'écran vient d'être marqué, rien ne clignote.
    let _ = html.class_list().add_1("hydrated");
    scroll_state();
    counters();
    typewriters();
    scramblers();
    embers();
    copy_buttons();
    menus(&html);
    drag_scroll();
    toc();
    ripples();
    if matches("(hover: hover) and (pointer: fine)") && !reduced_motion() {
        let _ = html.class_list().add_1("has-cursor");
        cursor();
        magnetic();
        spotlights();
        hero_mouse();
    }
}

fn observe(
    selector: &str,
    options: &IntersectionObserverInit,
    f: impl Fn(&IntersectionObserverEntry, &IntersectionObserver) + 'static,
) {
    let callback = Closure::<dyn Fn(js_sys::Array, IntersectionObserver)>::new(
        move |entries: js_sys::Array, io: IntersectionObserver| {
            for entry in entries.iter() {
                if let Ok(entry) = entry.dyn_into::<IntersectionObserverEntry>() {
                    f(&entry, &io);
                }
            }
        },
    );
    if let Ok(io) =
        IntersectionObserver::new_with_options(callback.as_ref().unchecked_ref(), options)
    {
        for el in all(selector) {
            io.observe(&el);
        }
    }
    callback.forget();
}

fn viewport() -> (f64, f64) {
    let w = window();
    (
        w.inner_width()
            .ok()
            .and_then(|v| v.as_f64())
            .unwrap_or(1200.0),
        w.inner_height()
            .ok()
            .and_then(|v| v.as_f64())
            .unwrap_or(800.0),
    )
}

fn page_lang() -> Lang {
    root()
        .get_attribute("lang")
        .and_then(|l| Lang::parse(&l))
        .unwrap_or(Lang::Fr)
}

/// L'introduction joue une fois par session ; un clic la passe.
fn intro(html: &HtmlElement) {
    let loaders = all(".loader");
    if loaders.is_empty() {
        return;
    }
    let storage = window().session_storage().ok().flatten();
    let seen = storage
        .as_ref()
        .and_then(|s| s.get_item("keyforge-intro").ok().flatten())
        .is_some();
    if seen || reduced_motion() {
        let _ = html.class_list().add_1("intro-seen");
        return;
    }
    if let Some(storage) = storage {
        let _ = storage.set_item("keyforge-intro", "1");
    }
    let _ = html.class_list().add_1("intro-playing");
    // Le pourcentage monte avec la barre.
    if let Some(percent) = all(".loader__percent").into_iter().next() {
        let mut start = None;
        request_frame(move |now| {
            let t0 = *start.get_or_insert(now);
            let p = ((now - t0) / 1500.0).min(1.0);
            let eased = 1.0 - (1.0 - p).powi(3);
            percent.set_text_content(Some(&format!("{:>3}%", (eased * 100.0).round())));
            p < 1.0
        });
    }
    let done = {
        let html = html.clone();
        move || {
            let _ = html.class_list().remove_1("intro-playing");
            let _ = html.class_list().add_1("intro-done");
        }
    };
    let done = Rc::new(RefCell::new(Some(done)));
    for loader in loaders {
        let done = done.clone();
        on(&loader, "click", move |_: web_sys::Event| {
            if let Some(f) = done.borrow_mut().take() {
                f();
            }
        });
    }
    later(2300, move || {
        if let Some(f) = done.borrow_mut().take() {
            f();
        }
    });
}

/// `[data-reveal]` apparaît en entrant dans l'écran.
fn reveals() {
    let (_, height) = viewport();
    for el in all("[data-reveal]") {
        let rect = el.get_bounding_client_rect();
        if rect.top() < height * 0.92 && rect.bottom() > 0.0 {
            let _ = el.class_list().add_1("in");
        }
    }
    let options = IntersectionObserverInit::new();
    options.set_threshold(&JsValue::from_f64(0.0));
    options.set_root_margin("0px 0px -8% 0px");
    observe("[data-reveal]:not(.in)", &options, |entry, io| {
        if entry.is_intersecting() {
            let target = entry.target();
            let _ = target.class_list().add_1("in");
            io.unobserve(&target);
        }
    });
    // Filet de sécurité pour Safari sur iOS pendant un défilement inertiel.
    let ticking = Rc::new(Cell::new(false));
    on_passive(&window(), "scroll", move |_: web_sys::Event| {
        if ticking.replace(true) {
            return;
        }
        let ticking = ticking.clone();
        request_frame(move |_| {
            ticking.set(false);
            let (_, height) = viewport();
            for el in all("[data-reveal]:not(.in)") {
                let rect = el.get_bounding_client_rect();
                if rect.top() < height && rect.bottom() > 0.0 {
                    let _ = el.class_list().add_1("in");
                }
            }
            false
        });
    });
}

/// Barre de progression, navigation, parallaxe, lignes qui se dessinent au défilement
/// (`[data-progress]` reçoit `--p` de 0 à 1) et anneau du bouton « haut de page ».
fn scroll_state() {
    let progress = all(".progress");
    let nav = all(".nav");
    let tracks = all("[data-progress]");
    let hero = all(".hero");
    let still = reduced_motion();
    let parallax: Vec<(HtmlElement, f64)> = if still {
        Vec::new()
    } else {
        all("[data-speed]")
            .into_iter()
            .map(|el| {
                let speed = el
                    .get_attribute("data-speed")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0.0);
                (el, speed)
            })
            .collect()
    };
    let last = Rc::new(Cell::new(0.0f64));
    let update = move || {
        let y = window().scroll_y().unwrap_or(0.0);
        let (_, height) = viewport();
        let html = root();
        let max = (f64::from(html.scroll_height()) - height).max(1.0);
        let ratio = (y / max).clamp(0.0, 1.0);
        set_style(&html, "--scroll", &format!("{ratio:.4}"));
        for bar in &progress {
            set_style(bar, "transform", &format!("scaleX({ratio:.4})"));
        }
        let menu_open = html.class_list().contains("menu-open");
        for nav in &nav {
            let list = nav.class_list();
            let _ = list.toggle_with_force("nav--scrolled", y > 24.0);
            if y > last.get() + 3.0 && y > 480.0 && !menu_open {
                let _ = list.add_1("nav--hidden");
            } else if y < last.get() - 3.0 {
                let _ = list.remove_1("nav--hidden");
            }
        }
        let _ = html
            .class_list()
            .toggle_with_force("past-hero", y > height * 0.8);
        last.set(y);
        for (el, speed) in &parallax {
            set_style(el, "translate", &format!("0 {:.1}px", y * speed));
        }
        for el in &tracks {
            let rect = el.get_bounding_client_rect();
            let p = ((height * 0.75 - rect.top()) / rect.height().max(1.0)).clamp(0.0, 1.0);
            set_style(el, "--p", &format!("{p:.4}"));
        }
        if !still {
            for el in &hero {
                set_style(el, "--out", &format!("{:.4}", (y / height).clamp(0.0, 1.0)));
            }
        }
    };
    update();
    let update = Rc::new(update);
    let ticking = Rc::new(Cell::new(false));
    for event in ["scroll", "resize"] {
        let (update, ticking) = (update.clone(), ticking.clone());
        on_passive(&window(), event, move |_: web_sys::Event| {
            if ticking.replace(true) {
                return;
            }
            let (update, ticking) = (update.clone(), ticking.clone());
            request_frame(move |_| {
                ticking.set(false);
                update();
                false
            });
        });
    }
}

/// Les nombres comptent jusqu'à leur valeur (`data-count`, `data-decimals`,
/// `data-prefix`, `data-suffix`), au format de la langue.
fn counters() {
    let lang = page_lang();
    let options = IntersectionObserverInit::new();
    options.set_threshold(&JsValue::from_f64(0.4));
    observe("[data-count]", &options, move |entry, io| {
        if !entry.is_intersecting() {
            return;
        }
        let el: HtmlElement = entry.target().unchecked_into();
        io.unobserve(&el);
        let data = el.dataset();
        let target: f64 = data
            .get("count")
            .and_then(|v| v.parse().ok())
            .unwrap_or(0.0);
        let decimals: usize = data
            .get("decimals")
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        let prefix = data.get("prefix").unwrap_or_default();
        let suffix = data.get("suffix").unwrap_or_default();
        let render = move |v: f64| format!("{prefix}{}{suffix}", number(lang, v, decimals));
        if reduced_motion() {
            el.set_text_content(Some(&render(target)));
            return;
        }
        let mut start = None;
        request_frame(move |now| {
            let t0 = *start.get_or_insert(now);
            let p = ((now - t0) / 1800.0).min(1.0);
            let eased = if p >= 1.0 {
                1.0
            } else {
                1.0 - 2f64.powf(-10.0 * p)
            };
            el.set_text_content(Some(&render(target * eased)));
            p < 1.0
        });
    });
}

/// `[data-words="a|b|c"]` : les mots s'écrivent et s'effacent tour à tour.
fn typewriters() {
    for el in all("[data-words]") {
        let words: Vec<String> = el
            .get_attribute("data-words")
            .unwrap_or_default()
            .split('|')
            .map(str::to_owned)
            .filter(|w| !w.is_empty())
            .collect();
        if words.len() < 2 || reduced_motion() {
            continue;
        }
        let target = el
            .query_selector(".type__text")
            .ok()
            .flatten()
            .unwrap_or_else(|| el.clone().into());
        // État : mot courant, lettres visibles, en train d'effacer, pause.
        let state = Rc::new(Cell::new((0usize, words[0].chars().count(), false, 90u32)));
        let mut last = 0.0;
        request_frame(move |now| {
            let (word, shown, erasing, pause) = state.get();
            let delay = if erasing { 38.0 } else { 75.0 };
            if now - last < delay {
                return true;
            }
            last = now;
            let len = words[word].chars().count();
            let next = if pause > 0 {
                (word, shown, erasing, pause - 1)
            } else if erasing {
                if shown == 0 {
                    ((word + 1) % words.len(), 0, false, 4)
                } else {
                    (word, shown - 1, true, 0)
                }
            } else if shown < len {
                (word, shown + 1, false, 0)
            } else {
                (word, shown, true, 34)
            };
            state.set(next);
            let text: String = words[next.0].chars().take(next.1).collect();
            if target.text_content().as_deref() != Some(text.as_str()) {
                target.set_text_content(Some(&text));
            }
            true
        });
    }
}

/// `[data-scramble]` : un nouveau secret toutes les ~3 s, « déchiffré » lettre à lettre.
/// Le mode vient de l'attribut (`password`, `passphrase`, `pin`). Avec `cycle` (la
/// maquette du téléphone), chaque secret passe au mode suivant : l'onglet actif, le
/// style du secret et la force affichée suivent, pour que l'écran reste cohérent.
fn scramblers() {
    const CYCLE: [Mode; 3] = [Mode::Password, Mode::Passphrase, Mode::Pin];
    let lang = page_lang();
    for el in all("[data-scramble]") {
        let cycle = el.get_attribute("data-scramble").as_deref() == Some("cycle");
        let mode = match el.get_attribute("data-scramble").as_deref() {
            Some("passphrase") => Mode::Passphrase,
            Some("pin") => Mode::Pin,
            _ => Mode::Password,
        };
        let password_length = el.get_attribute("data-length").and_then(|v| v.parse().ok());
        // Le premier secret du cycle reste un mot de passe (l'onglet affiché au départ).
        let mut step = CYCLE.len() - 1;
        let mut options = Options {
            mode,
            length: el
                .get_attribute("data-length")
                .and_then(|v| v.parse().ok())
                .unwrap_or(mode.range().2),
            separator: '-',
            ..Options::default()
        };
        let still = reduced_motion();
        let mut noise_rng = noise();
        let mut target: Vec<char> = el.text_content().unwrap_or_default().chars().collect();
        let mut t0 = None::<f64>;
        let mut last = 0.0;
        request_frame(move |now| {
            let start = *t0.get_or_insert(now - 2600.0);
            let age = now - start;
            if age > 3200.0 {
                if cycle {
                    step = (step + 1) % CYCLE.len();
                    options.mode = CYCLE[step];
                    options.length = match options.mode {
                        Mode::Password => password_length.unwrap_or(options.mode.range().2),
                        other => other.range().2,
                    };
                    show_cycle_step(&el, step, options.mode, options.entropy(), lang);
                }
                target = forge::generate(&options, &mut CryptoRng::new())
                    .chars()
                    .collect();
                t0 = Some(now);
                if still {
                    el.set_text_content(Some(&target.iter().collect::<String>()));
                }
                return true;
            }
            if still || now - last < 33.0 || age > 900.0 {
                return true;
            }
            last = now;
            let settled = (age / 700.0 * target.len() as f64) as usize;
            let text: String = target
                .iter()
                .enumerate()
                .map(|(i, &c)| {
                    if i < settled || c == '-' {
                        c
                    } else {
                        char::from(GLYPHS[noise_rng.below(GLYPHS.len() as u32) as usize])
                    }
                })
                .collect();
            el.set_text_content(Some(&text));
            true
        });
    }
}

/// L'écran de la maquette pour l'étape `step` : onglet actif, style du secret, force.
fn show_cycle_step(el: &web_sys::Element, step: usize, mode: Mode, bits: f64, lang: Lang) {
    let _ = el
        .class_list()
        .toggle_with_force("app-secret--phrase", mode == Mode::Passphrase);
    let Some(screen) = el.closest(".phone__screen").ok().flatten() else {
        return;
    };
    if let Some(seg) = screen.query_selector(".app-seg").ok().flatten() {
        let _ = seg.set_attribute("data-step", &step.to_string());
    }
    let level = forge::Level::of(bits);
    if let Some(label) = screen.query_selector(".app-level strong").ok().flatten() {
        label.set_text_content(Some(crate::islands::level_label(lang, level)));
    }
    if let Some(value) = screen.query_selector(".app-level span").ok().flatten() {
        value.set_text_content(Some(&format!(" · {bits:.0} bits")));
    }
    if let Some(meter) = screen.query_selector(".app-meter").ok().flatten() {
        let _ = meter
            .class_list()
            .toggle_with_force("app-meter--fair", level.rank() <= 3);
    }
}

/// Des braises qui montent dans un `<canvas class="embers">` (2D), seulement quand il
/// est visible.
fn embers() {
    if reduced_motion() {
        return;
    }
    for canvas in all("canvas.embers") {
        let Ok(canvas) = canvas.dyn_into::<web_sys::HtmlCanvasElement>() else {
            continue;
        };
        let Some(ctx) = canvas
            .get_context("2d")
            .ok()
            .flatten()
            .and_then(|c| c.dyn_into::<web_sys::CanvasRenderingContext2d>().ok())
        else {
            continue;
        };
        let visible = Rc::new(Cell::new(true));
        {
            let visible = visible.clone();
            let callback = Closure::<dyn Fn(js_sys::Array)>::new(move |entries: js_sys::Array| {
                for entry in entries.iter() {
                    if let Ok(entry) = entry.dyn_into::<IntersectionObserverEntry>() {
                        visible.set(entry.is_intersecting());
                    }
                }
            });
            if let Ok(io) = IntersectionObserver::new(callback.as_ref().unchecked_ref()) {
                io.observe(&canvas);
            }
            callback.forget();
        }
        let count: usize = canvas
            .get_attribute("data-count")
            .and_then(|v| v.parse().ok())
            .unwrap_or(70);
        let mut rng = noise();
        let mut rand = move || f64::from(rng.next_u32()) / f64::from(u32::MAX);
        // x, y, vitesse, rayon, phase, teinte
        let mut sparks: Vec<[f64; 6]> = (0..count)
            .map(|_| {
                [
                    rand(),
                    rand(),
                    0.2 + rand() * 0.8,
                    0.6 + rand() * 1.8,
                    rand() * 6.3,
                    rand(),
                ]
            })
            .collect();
        let mut last = None::<f64>;
        request_frame(move |now| {
            let dt = last.map_or(16.0, |l| (now - l).min(50.0));
            last = Some(now);
            if !visible.get() {
                return true;
            }
            let dpr = window().device_pixel_ratio().min(2.0);
            let (w, h) = (
                f64::from(canvas.client_width()) * dpr,
                f64::from(canvas.client_height()) * dpr,
            );
            if w < 1.0 || h < 1.0 {
                return true;
            }
            if f64::from(canvas.width()) != w || f64::from(canvas.height()) != h {
                canvas.set_width(w as u32);
                canvas.set_height(h as u32);
            }
            ctx.clear_rect(0.0, 0.0, w, h);
            let _ = ctx.set_global_composite_operation("lighter");
            for s in &mut sparks {
                s[1] -= s[2] * dt * 0.00008;
                s[4] += dt * 0.002;
                if s[1] < -0.05 {
                    s[1] = 1.05;
                    s[0] = rand();
                }
                let x = (s[0] + (s[4]).sin() * 0.015) * w;
                let y = s[1] * h;
                let life = s[1].clamp(0.0, 1.0);
                let alpha = (life * (1.0 - life) * 3.2).min(0.85);
                let (r, g, b) = if s[5] < 0.55 {
                    (255, 138, 61)
                } else if s[5] < 0.85 {
                    (255, 46, 126)
                } else {
                    (255, 200, 120)
                };
                ctx.set_fill_style_str(&format!("rgba({r},{g},{b},{alpha:.3})"));
                ctx.begin_path();
                let _ = ctx.arc(x, y, s[3] * dpr, 0.0, std::f64::consts::TAU);
                ctx.fill();
            }
            true
        });
    }
}

/// Boutons « copier » : le texte de `data-copy`.
fn copy_buttons() {
    on(&document(), "click", |e: web_sys::MouseEvent| {
        let Some(button) = e
            .target()
            .and_then(|t| t.dyn_into::<Element>().ok())
            .and_then(|t| t.closest("[data-copy]").ok().flatten())
        else {
            return;
        };
        let Some(text) = button.get_attribute("data-copy") else {
            return;
        };
        let promise = window().navigator().clipboard().write_text(&text);
        wasm_bindgen_futures::spawn_local(async move {
            if wasm_bindgen_futures::JsFuture::from(promise).await.is_err() {
                return;
            }
            let _ = button.class_list().add_1("is-copied");
            later(1400, move || {
                let _ = button.class_list().remove_1("is-copied");
            });
        });
    });
}

/// Le menu mobile, et le bouton « haut de page ».
/// Ouvre ou ferme le menu plein écran. La classe de la page et `aria-expanded` des
/// boutons changent toujours ensemble : un lecteur d'écran n'annonce jamais « développé »
/// pour un menu fermé (par un lien, Échap ou le bouton).
fn set_menu(html: &HtmlElement, open: bool) {
    let _ = html.class_list().toggle_with_force("menu-open", open);
    for button in all("[data-toggle-menu]") {
        let _ = button.set_attribute("aria-expanded", if open { "true" } else { "false" });
    }
}

fn menus(html: &HtmlElement) {
    for button in all("[data-toggle-menu]") {
        let html = html.clone();
        on(&button, "click", move |_: web_sys::Event| {
            let open = !html.class_list().contains("menu-open");
            set_menu(&html, open);
        });
    }
    for el in all(".menu a") {
        let html = html.clone();
        on(&el, "click", move |_: web_sys::Event| {
            set_menu(&html, false)
        });
    }
    let html_key = html.clone();
    on(&window(), "keydown", move |e: web_sys::KeyboardEvent| {
        if e.key() == "Escape" && html_key.class_list().contains("menu-open") {
            set_menu(&html_key, false);
            // Le focus revient au bouton qui a ouvert le menu.
            if let Some(button) = all("[data-toggle-menu]").into_iter().next()
                && let Ok(button) = button.dyn_into::<HtmlElement>()
            {
                let _ = button.focus();
            }
        }
    });
    for el in all("[data-top]") {
        on(&el, "click", |e: web_sys::Event| {
            e.prevent_default();
            let options = web_sys::ScrollToOptions::new();
            options.set_top(0.0);
            options.set_behavior(if reduced_motion() {
                web_sys::ScrollBehavior::Instant
            } else {
                web_sys::ScrollBehavior::Smooth
            });
            window().scroll_to_with_scroll_to_options(&options);
        });
    }
}

/// `[data-drag]` : faire glisser un carrousel horizontal à la souris.
fn drag_scroll() {
    for el in all("[data-drag]") {
        let start = Rc::new(Cell::new(None::<(f64, f64)>));
        {
            let (start, target) = (start.clone(), el.clone());
            on(&el, "pointerdown", move |e: web_sys::PointerEvent| {
                if e.pointer_type() != "mouse" {
                    return;
                }
                start.set(Some((
                    f64::from(e.client_x()),
                    f64::from(target.scroll_left()),
                )));
                let _ = target.class_list().add_1("is-dragging");
            });
        }
        {
            let (start, target) = (start.clone(), el.clone());
            on(&el, "pointermove", move |e: web_sys::PointerEvent| {
                if let Some((x0, left)) = start.get() {
                    target.set_scroll_left((left - (f64::from(e.client_x()) - x0)) as i32);
                }
            });
        }
        for event in ["pointerup", "pointerleave"] {
            let (start, target) = (start.clone(), el.clone());
            on(&el, event, move |_: web_sys::Event| {
                start.set(None);
                let _ = target.class_list().remove_1("is-dragging");
            });
        }
    }
}

/// « Sur cette page » : la section en cours de lecture est mise en avant.
fn toc() {
    let links = all(".toc a");
    if links.is_empty() {
        return;
    }
    let options = IntersectionObserverInit::new();
    options.set_root_margin("-20% 0px -65% 0px");
    observe(".doc section[id]", &options, move |entry, _| {
        if !entry.is_intersecting() {
            return;
        }
        let id = entry.target().id();
        for link in &links {
            let active = link.get_attribute("href").as_deref() == Some(&format!("#{id}"));
            let _ = link.class_list().toggle_with_force("is-active", active);
        }
    });
}

/// Une onde part du point de clic sur les boutons.
fn ripples() {
    if reduced_motion() {
        return;
    }
    on(&document(), "pointerdown", |e: web_sys::PointerEvent| {
        let Some(button) = e
            .target()
            .and_then(|t| t.dyn_into::<Element>().ok())
            .and_then(|t| t.closest(".btn, .chip, .gen__tab").ok().flatten())
        else {
            return;
        };
        let rect = button.get_bounding_client_rect();
        let Ok(wave) = document().create_element("span") else {
            return;
        };
        let wave: HtmlElement = wave.unchecked_into();
        wave.set_class_name("ripple");
        let size = rect.width().max(rect.height()) * 2.2;
        set_style(&wave, "width", &format!("{size}px"));
        set_style(&wave, "height", &format!("{size}px"));
        set_style(
            &wave,
            "left",
            &format!("{}px", f64::from(e.client_x()) - rect.left() - size / 2.0),
        );
        set_style(
            &wave,
            "top",
            &format!("{}px", f64::from(e.client_y()) - rect.top() - size / 2.0),
        );
        let _ = button.append_child(&wave);
        later(700, move || wave.remove());
    });
}

/// Un point suit le pointeur, un anneau le rattrape ; l'anneau grossit sur les liens et
/// affiche l'étiquette `data-cursor` de ce qu'il survole.
fn cursor() {
    let (Some(dot), Some(ring)) = (
        all(".cursor__dot").into_iter().next(),
        all(".cursor__ring").into_iter().next(),
    ) else {
        return;
    };
    let target = Rc::new(Cell::new((-100.0f64, -100.0f64)));
    {
        let (target, dot, ring) = (target.clone(), dot.clone(), ring.clone());
        on_passive(&window(), "pointermove", move |e: web_sys::PointerEvent| {
            let (x, y) = (f64::from(e.client_x()), f64::from(e.client_y()));
            target.set((x, y));
            set_style(&dot, "translate", &format!("{x}px {y}px"));
            let hovered = e
                .target()
                .and_then(|t| t.dyn_into::<Element>().ok())
                .and_then(|t| {
                    t.closest("a, button, input, label, summary, [data-cursor]")
                        .ok()
                        .flatten()
                });
            let label = hovered
                .as_ref()
                .and_then(|el| el.get_attribute("data-cursor"))
                .unwrap_or_default();
            let list = ring.class_list();
            let _ = list.toggle_with_force("is-hover", hovered.is_some());
            let _ = list.toggle_with_force("has-label", !label.is_empty());
            if let Some(span) = ring.query_selector("span").ok().flatten()
                && span.text_content().unwrap_or_default() != label
            {
                span.set_text_content(Some(&label));
            }
        });
    }
    for (event, down) in [("pointerdown", true), ("pointerup", false)] {
        let ring = ring.clone();
        on(&window(), event, move |_: web_sys::Event| {
            let _ = ring.class_list().toggle_with_force("is-down", down);
        });
    }
    let mut pos = (-100.0f64, -100.0f64);
    request_frame(move |_| {
        let (tx, ty) = target.get();
        if (tx - pos.0).abs() > 0.1 || (ty - pos.1).abs() > 0.1 {
            pos.0 += (tx - pos.0) * 0.18;
            pos.1 += (ty - pos.1) * 0.18;
            set_style(
                &ring,
                "translate",
                &format!("{:.1}px {:.1}px", pos.0, pos.1),
            );
        }
        true
    });
}

/// Les boutons se penchent vers le pointeur (`data-magnetic`).
fn magnetic() {
    for el in all("[data-magnetic]") {
        let target = el.clone();
        on(&el, "pointermove", move |e: web_sys::PointerEvent| {
            let r = target.get_bounding_client_rect();
            let x = f64::from(e.client_x()) - r.left() - r.width() / 2.0;
            let y = f64::from(e.client_y()) - r.top() - r.height() / 2.0;
            set_style(&target, "--mx", &format!("{:.1}px", x * 0.28));
            set_style(&target, "--my", &format!("{:.1}px", y * 0.35));
        });
        let target = el.clone();
        on(&el, "pointerleave", move |_: web_sys::Event| {
            set_style(&target, "--mx", "0px");
            set_style(&target, "--my", "0px");
        });
    }
}

/// Un halo suit le pointeur dans les cartes (`data-spot`).
fn spotlights() {
    on_passive(&document(), "pointermove", |e: web_sys::PointerEvent| {
        let Some(card) = e
            .target()
            .and_then(|t| t.dyn_into::<Element>().ok())
            .and_then(|t| t.closest("[data-spot]").ok().flatten())
            .and_then(|t| t.dyn_into::<HtmlElement>().ok())
        else {
            return;
        };
        let r = card.get_bounding_client_rect();
        set_style(
            &card,
            "--x",
            &format!("{:.0}px", f64::from(e.client_x()) - r.left()),
        );
        set_style(
            &card,
            "--y",
            &format!("{:.0}px", f64::from(e.client_y()) - r.top()),
        );
    });
}

/// Le décor du héros suit la souris, avec de l'inertie (translations 2D seulement).
fn hero_mouse() {
    let Some(hero) = all(".hero").into_iter().next() else {
        return;
    };
    let mouse = Rc::new(Cell::new((0.0f64, 0.0f64)));
    let running = Rc::new(Cell::new(false));
    let eased = Rc::new(Cell::new((0.0f64, 0.0f64)));
    on_passive(&window(), "pointermove", move |e: web_sys::PointerEvent| {
        let (w, h) = viewport();
        mouse.set((
            f64::from(e.client_x()) / w.max(1.0) - 0.5,
            f64::from(e.client_y()) / h.max(1.0) - 0.5,
        ));
        if running.replace(true) {
            return;
        }
        let (hero, mouse, running, eased) =
            (hero.clone(), mouse.clone(), running.clone(), eased.clone());
        request_frame(move |_| {
            let (mx, my) = mouse.get();
            let (ex, ey) = eased.get();
            let next = (ex + (mx - ex) * 0.07, ey + (my - ey) * 0.07);
            eased.set(next);
            set_style(&hero, "--hx", &format!("{:.4}", next.0));
            set_style(&hero, "--hy", &format!("{:.4}", next.1));
            let moving = (mx - next.0).abs() > 0.001 || (my - next.1).abs() > 0.001;
            running.set(moving);
            moving
        });
    });
}
