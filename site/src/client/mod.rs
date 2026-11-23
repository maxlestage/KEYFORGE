//! Le bundle du navigateur : reprend les îlots, puis lance les animations de la page.

pub mod motion;

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use paquets::prelude::State;
use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;

use crate::forge::{self, Options, Rng, Xorshift};

#[wasm_bindgen(start)]
pub fn start() {
    motion::apply_saved_theme();
    paquets::hydrate(&crate::islands::ISLANDS);
    motion::init();
}

pub fn window() -> web_sys::Window {
    web_sys::window().expect("window")
}

pub fn document() -> web_sys::Document {
    window().document().expect("document")
}

pub fn root() -> web_sys::HtmlElement {
    document()
        .document_element()
        .expect("html")
        .unchecked_into()
}

pub fn matches(query: &str) -> bool {
    window()
        .match_media(query)
        .ok()
        .flatten()
        .is_some_and(|m| m.matches())
}

pub fn reduced_motion() -> bool {
    matches("(prefers-reduced-motion: reduce)")
}

/// Ajoute un écouteur pour la durée de vie de la page.
pub fn on<E: JsCast + 'static>(
    target: &web_sys::EventTarget,
    event: &str,
    f: impl FnMut(E) + 'static,
) {
    let mut f = f;
    let closure =
        Closure::<dyn FnMut(web_sys::Event)>::new(move |e: web_sys::Event| f(e.unchecked_into()));
    let _ = target.add_event_listener_with_callback(event, closure.as_ref().unchecked_ref());
    closure.forget();
}

/// Comme [`on`], avec `{ passive: true }` (défilement, pointeur).
pub fn on_passive<E: JsCast + 'static>(
    target: &web_sys::EventTarget,
    event: &str,
    f: impl FnMut(E) + 'static,
) {
    let mut f = f;
    let closure =
        Closure::<dyn FnMut(web_sys::Event)>::new(move |e: web_sys::Event| f(e.unchecked_into()));
    let options = web_sys::AddEventListenerOptions::new();
    options.set_passive(true);
    let _ = target.add_event_listener_with_callback_and_add_event_listener_options(
        event,
        closure.as_ref().unchecked_ref(),
        &options,
    );
    closure.forget();
}

type FrameCallback = Closure<dyn FnMut(f64)>;

/// Appelle `f(horodatage)` à chaque image tant qu'il renvoie `true`.
pub fn request_frame(f: impl FnMut(f64) -> bool + 'static) {
    let f = Rc::new(RefCell::new(f));
    let slot: Rc<RefCell<Option<FrameCallback>>> = Rc::new(RefCell::new(None));
    let again = slot.clone();
    *slot.borrow_mut() = Some(Closure::new(move |now: f64| {
        if (f.borrow_mut())(now) {
            if let Some(cb) = again.borrow().as_ref() {
                let _ = window().request_animation_frame(cb.as_ref().unchecked_ref());
            }
        } else {
            again.borrow_mut().take();
        }
    }));
    if let Some(cb) = slot.borrow().as_ref() {
        let _ = window().request_animation_frame(cb.as_ref().unchecked_ref());
    }
}

/// Chaque élément qui correspond à `selector`.
pub fn all(selector: &str) -> Vec<web_sys::HtmlElement> {
    let Ok(list) = document().query_selector_all(selector) else {
        return Vec::new();
    };
    (0..list.length())
        .filter_map(|i| list.item(i)?.dyn_into().ok())
        .collect()
}

/// Appelle `f` une fois, après `ms` millisecondes.
pub fn later(ms: i32, f: impl FnOnce() + 'static) {
    let f = Closure::once_into_js(f);
    let _ = window().set_timeout_with_callback_and_timeout_and_arguments_0(f.unchecked_ref(), ms);
}

pub fn set_style(el: &web_sys::HtmlElement, name: &str, value: &str) {
    let _ = el.style().set_property(name, value);
}

// ----- Hasard ----------------------------------------------------------------------------

/// Le hasard du navigateur (`crypto.getRandomValues`), lu par blocs de 256 octets.
pub struct CryptoRng {
    buf: [u8; 256],
    pos: usize,
}

impl CryptoRng {
    pub fn new() -> CryptoRng {
        CryptoRng {
            buf: [0; 256],
            pos: 256,
        }
    }
}

impl Default for CryptoRng {
    fn default() -> Self {
        CryptoRng::new()
    }
}

impl Rng for CryptoRng {
    fn next_u32(&mut self) -> u32 {
        if self.pos + 4 > self.buf.len() {
            let crypto = window().crypto().expect("crypto.getRandomValues");
            crypto
                .get_random_values_with_u8_array(&mut self.buf)
                .expect("crypto.getRandomValues");
            self.pos = 0;
        }
        let bytes = [
            self.buf[self.pos],
            self.buf[self.pos + 1],
            self.buf[self.pos + 2],
            self.buf[self.pos + 3],
        ];
        self.pos += 4;
        u32::from_le_bytes(bytes)
    }
}

/// Un générateur rapide pour le bruit visuel (jamais pour un secret), semé par la crypto.
pub fn noise() -> Xorshift {
    let mut seed = CryptoRng::new();
    Xorshift((u64::from(seed.next_u32()) << 32) | u64::from(seed.next_u32()))
}

pub const GLYPHS: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789#$%&*+=?@";

thread_local! {
    static FORGE_RUN: Cell<u32> = const { Cell::new(0) };
}

/// Forge un secret, puis l'affiche avec un effet de déchiffrement : les caractères
/// défilent et se fixent de gauche à droite. L'entropie affichée glisse vers sa valeur.
pub fn forge_into(
    options: &Options,
    value: State<String>,
    shown: State<Vec<(char, bool)>>,
    bits: State<f64>,
) {
    let secret = forge::generate(options, &mut CryptoRng::new());
    value.set(secret.clone());
    let target: Vec<char> = secret.chars().collect();
    let run = FORGE_RUN.with(|r| {
        r.set(r.get().wrapping_add(1));
        r.get()
    });

    let (from, to) = (bits.get(), options.entropy());
    if reduced_motion() {
        shown.set(target.iter().map(|&c| (c, true)).collect());
        bits.set(to);
        return;
    }
    let n = target.len().max(1);
    // Au plus ~650 ms quelle que soit la longueur.
    let step = (26.0 / n as f64).min(1.4);
    let mut rng = noise();
    let mut start = None;
    request_frame(move |now| {
        if FORGE_RUN.with(Cell::get) != run {
            return false;
        }
        let t0 = *start.get_or_insert(now);
        let frame = (now - t0) / 16.7;
        let p = ((now - t0) / 550.0).min(1.0);
        let eased = 1.0 - (1.0 - p).powi(3);
        bits.set(from + (to - from) * eased);
        let mut done = true;
        let next: Vec<(char, bool)> = target
            .iter()
            .enumerate()
            .map(|(i, &c)| {
                let settle = 4.0 + i as f64 * step;
                if frame >= settle || c == ' ' {
                    (c, true)
                } else {
                    done = false;
                    let g = GLYPHS[rng.below(GLYPHS.len() as u32) as usize];
                    (char::from(g), false)
                }
            })
            .collect();
        shown.set(next);
        !(done && p >= 1.0)
    });
}

/// Copie `text` et montre la confirmation pendant 1,6 s.
pub fn copy_text(text: &str, copied: State<bool>) {
    if text.is_empty() {
        return;
    }
    let promise = window().navigator().clipboard().write_text(text);
    wasm_bindgen_futures::spawn_local(async move {
        if wasm_bindgen_futures::JsFuture::from(promise).await.is_ok() {
            copied.set(false);
            later(20, move || copied.set(true));
            later(1600, move || copied.set(false));
        }
    });
}

// ----- Thème -----------------------------------------------------------------------------

pub const THEME_KEY: &str = "keyforge-theme";

fn current_theme() -> String {
    root().get_attribute("data-theme").unwrap_or_else(|| {
        if matches("(prefers-color-scheme: light)") {
            "light".into()
        } else {
            "dark".into()
        }
    })
}

/// Passe au thème opposé, en cercle depuis le point cliqué si le navigateur le permet.
pub fn toggle_theme(event: &paquets::active::Event) {
    let next = if current_theme() == "dark" {
        "light"
    } else {
        "dark"
    };
    let apply = move || {
        let _ = root().set_attribute("data-theme", next);
        if let Ok(Some(storage)) = window().local_storage() {
            let _ = storage.set_item(THEME_KEY, next);
        }
    };
    let html = root();
    if let Some(e) = event.raw().dyn_ref::<web_sys::MouseEvent>() {
        set_style(&html, "--vt-x", &format!("{}px", e.client_x()));
        set_style(&html, "--vt-y", &format!("{}px", e.client_y()));
    }
    let start = js_sys::Reflect::get(&document(), &JsValue::from_str("startViewTransition"))
        .ok()
        .and_then(|f| f.dyn_into::<js_sys::Function>().ok());
    match start {
        Some(start) if !reduced_motion() => {
            let _ = html.class_list().add_1("theme-switching");
            let callback = Closure::once_into_js(apply);
            let _ = start.call1(&document(), &callback);
            later(900, || {
                let _ = root().class_list().remove_1("theme-switching");
            });
        }
        _ => apply(),
    }
}

// ----- PWA -------------------------------------------------------------------------------

thread_local! {
    static INSTALL_EVENT: RefCell<Option<web_sys::Event>> = const { RefCell::new(None) };
}

/// Suit le réseau et la possibilité d'installer le site.
pub fn watch_pwa(online: State<bool>, installable: State<bool>, installed: State<bool>) {
    online.set(window().navigator().on_line());
    installed.set(matches("(display-mode: standalone)"));
    let w: web_sys::EventTarget = window().unchecked_into();
    on(&w, "online", move |_: web_sys::Event| online.set(true));
    on(&w, "offline", move |_: web_sys::Event| online.set(false));
    on(&w, "beforeinstallprompt", move |e: web_sys::Event| {
        e.prevent_default();
        INSTALL_EVENT.with(|slot| *slot.borrow_mut() = Some(e));
        installable.set(true);
    });
    on(&w, "appinstalled", move |_: web_sys::Event| {
        installed.set(true);
        installable.set(false);
    });
    if INSTALL_EVENT.with(|slot| slot.borrow().is_some()) {
        installable.set(true);
    }
}

/// Ouvre la fenêtre d'installation du navigateur.
pub fn prompt_install(installable: State<bool>) {
    let Some(event) = INSTALL_EVENT.with(|slot| slot.borrow_mut().take()) else {
        return;
    };
    if let Ok(prompt) = js_sys::Reflect::get(&event, &JsValue::from_str("prompt"))
        && let Ok(prompt) = prompt.dyn_into::<js_sys::Function>()
    {
        let _ = prompt.call0(&event);
    }
    installable.set(false);
}

// ----- Brocolis 🥦 -----------------------------------------------------------------------

/// Une phrase secrète neuve : six mots de la liste (60 bits), séparés par des tirets.
pub fn new_phrase() -> String {
    let options = Options {
        mode: forge::Mode::Passphrase,
        length: 6,
        capitalize: false,
        add_number: false,
        separator: '-',
        ..Options::default()
    };
    forge::generate(&options, &mut CryptoRng::new())
}

/// Scelle ou ouvre, après avoir laissé le navigateur afficher l'attente : Argon2id
/// (64 Mio) prend une à quelques secondes et occupe le fil principal.
pub fn seal_or_open(
    lang: crate::i18n::Lang,
    opening: bool,
    text: String,
    phrase: String,
    output: State<String>,
    error: State<String>,
    busy: State<bool>,
) {
    later(120, move || {
        let result = if opening {
            crate::seal::open(&text, &phrase, now(), &mut brocolis_proto::hasard::system())
        } else {
            crate::seal::seal(
                &text,
                &phrase,
                crate::seal::PARAMS,
                &mut brocolis_proto::hasard::system(),
            )
        };
        match result {
            Ok(out) => output.set(out),
            Err(e) => error.set(crate::islands::seal_error(lang, &e).to_owned()),
        }
        busy.set(false);
    });
}

/// L'heure, en secondes Unix (brocolis-proto la demande à l'appelant).
pub fn now() -> u64 {
    (js_sys::Date::now() / 1000.0) as u64
}

// ----- Post-quantique (Brocolis v4) ------------------------------------------------------

const PQ_KEY: &str = "keyforge-pq-identity";

thread_local! {
    static PQ_DEVICE: RefCell<Option<brocolis_proto::Device>> = const { RefCell::new(None) };
}

fn pq_save(device: &brocolis_proto::Device) {
    if let Ok(Some(storage)) = window().session_storage() {
        let _ = storage.set_item(PQ_KEY, &device.to_json());
    }
}

/// L'identité de cet onglet : relue du stockage de session, sinon créée (ou recréée avec
/// `fresh`). Met à jour le paquet et les empreintes affichés.
pub fn pq_identity(
    fresh: bool,
    bundle: State<String>,
    print: State<String>,
    sender: State<String>,
) {
    let device = PQ_DEVICE.with(|slot| {
        let mut slot = slot.borrow_mut();
        if fresh || slot.is_none() {
            let stored = (!fresh)
                .then(|| window().session_storage().ok().flatten())
                .flatten()
                .and_then(|s| s.get_item(PQ_KEY).ok().flatten())
                .and_then(|json| brocolis_proto::Device::from_json(&json).ok());
            let device = stored.unwrap_or_else(|| {
                crate::pq::new_identity(&mut brocolis_proto::hasard::system(), now())
            });
            pq_save(&device);
            *slot = Some(device);
        }
        slot.clone()
    });
    if let Some(device) = device {
        bundle.set(crate::pq::bundle(&device).unwrap_or_default());
        print.set(crate::pq::identity_fingerprint(&device));
        sender.set(crate::pq::sender_fingerprint(&device));
    }
}

/// Chiffre pour un paquet, ou déchiffre un message reçu, après avoir laissé le navigateur
/// afficher l'attente.
#[allow(clippy::too_many_arguments)]
pub fn pq_run(
    lang: crate::i18n::Lang,
    decrypting: bool,
    recipient: String,
    message: String,
    incoming: String,
    output: State<String>,
    from: State<String>,
    error: State<String>,
    busy: State<bool>,
) {
    later(60, move || {
        let mut rng = brocolis_proto::hasard::system();
        let result = PQ_DEVICE.with(|slot| {
            let mut slot = slot.borrow_mut();
            let device = slot.as_mut().ok_or(brocolis_proto::Erreur::Etat)?;
            if decrypting {
                let got = crate::pq::decrypt(device, &incoming, now(), &mut rng)?;
                // La mémoire des premiers messages a changé : rejeu refusé après rechargement.
                pq_save(device);
                from.set(got.from);
                Ok(got.text)
            } else {
                crate::pq::encrypt_for(device, &recipient, &message, &mut rng)
            }
        });
        match result {
            Ok(out) => output.set(out),
            Err(e) => error.set(crate::islands::pq_error(lang, &e).to_owned()),
        }
        busy.set(false);
    });
}
