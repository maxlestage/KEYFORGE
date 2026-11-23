//! Les pages de contenu : sécurité, guide, aide, nouveautés, presse, pages légales et
//! « introuvable ». Chacune a un en-tête animé, un sommaire qui suit la lecture et des
//! sections qui apparaissent au défilement.

use paquets::prelude::*;

use super::pages::{Ctx, REPO, eyebrow, faq_list, layout, split};
use crate::i18n::Lang;
use crate::icons::{icon, logo};
use crate::routes::PageKind;

/// Un bloc de contenu.
enum Block {
    P(&'static str),
    List(Vec<&'static str>),
    Note(&'static str, &'static str),
    View(Element),
}

struct Section {
    id: &'static str,
    title: &'static str,
    blocks: Vec<Block>,
}

fn sec(id: &'static str, title: &'static str, blocks: Vec<Block>) -> Section {
    Section { id, title, blocks }
}

struct Doc {
    icon: &'static str,
    kicker: &'static str,
    title: &'static str,
    lead: &'static str,
    description: &'static str,
    sections: Vec<Section>,
}

const UPDATED_FR: &str = "Mis à jour le 23 novembre 2026";
const UPDATED_EN: &str = "Updated on November 23, 2026";

fn block(b: Block) -> Node {
    match b {
        Block::P(text) => p().text(text).into(),
        Block::List(items) => ul()
            .class("doc__list")
            .children(items.into_iter().enumerate().map(|(i, s)| {
                li().style(format!("--i:{i}"))
                    .child(icon("check"))
                    .child(span().text(s))
            }))
            .into(),
        Block::Note(ic, text) => div()
            .class("note")
            .child(span().class("note__icon").child(icon(ic)))
            .child(p().text(text))
            .into(),
        Block::View(el) => el.into(),
    }
}

fn related(ctx: &Ctx, current: PageKind) -> Element {
    let pages = [
        (PageKind::Security, "shield"),
        (PageKind::Guide, "book"),
        (PageKind::Help, "lifebuoy"),
        (PageKind::Changelog, "bolt"),
        (PageKind::Press, "news"),
        (PageKind::Privacy, "eyeoff"),
    ];
    section()
        .class("related wrap")
        .child(
            h2().class("related__title")
                .attr("data-reveal", "")
                .text(ctx.t("À lire aussi", "Read next")),
        )
        .child(
            div().class("related__grid").children(
                pages
                    .into_iter()
                    .filter(|(p, _)| *p != current)
                    .take(4)
                    .enumerate()
                    .map(|(i, (page, ic))| {
                        a().class("related__card")
                            .href(ctx.href(page))
                            .attr("data-reveal", "")
                            .attr("data-spot", "")
                            .style(format!("--d:{i}"))
                            .child(span().class("feature__icon").child(icon(ic)))
                            .child(strong().text(page.label(ctx.lang())))
                            .child(span().class("related__arrow").child(icon("arrow")))
                    }),
            ),
        )
}

fn doc_page(ctx: &Ctx, doc: Doc) -> Page {
    let lang = ctx.lang();
    let toc = nav()
        .class("toc")
        .attr("aria-label", ctx.t("Sur cette page", "On this page"))
        .child(
            p().class("toc__title")
                .text(ctx.t("Sur cette page", "On this page")),
        )
        .child(ol().children(doc.sections.iter().enumerate().map(|(i, s)| {
            li().child(
                a().href(format!("#{}", s.id))
                    .child(span().class("toc__n").text(format!("{:02}", i + 1)))
                    .child(span().text(s.title)),
            )
        })));
    let article = article()
        .class("doc")
        .children(doc.sections.into_iter().enumerate().map(|(i, s)| {
            section()
                .id(s.id)
                .class("doc__section")
                .attr("data-reveal", "")
                .child(
                    h2().child(span().class("doc__n").text(format!("{:02}", i + 1)))
                        .child(span().text(s.title)),
                )
                .children(s.blocks.into_iter().map(block))
        }));
    let content = html::main()
        .class("page")
        .child(
            header()
                .class("page-hero")
                .child(
                    div()
                        .class("page-hero__bg")
                        .attr("aria-hidden", "true")
                        .child(div().class("blob blob--a"))
                        .child(div().class("blob blob--b"))
                        .child(div().class("hero__grid")),
                )
                .child(
                    div()
                        .class("wrap page-hero__inner")
                        .child(
                            nav()
                                .class("crumbs")
                                .attr("aria-label", ctx.t("Fil d'Ariane", "Breadcrumb"))
                                .attr("data-reveal", "")
                                .child(
                                    a().href(ctx.href(PageKind::Home))
                                        .text(ctx.t("Accueil", "Home")),
                                )
                                .child(span().text("/"))
                                .child(
                                    span()
                                        .attr("aria-current", "page")
                                        .text(ctx.route.page.label(lang)),
                                ),
                        )
                        .child(
                            span()
                                .class("page-hero__icon")
                                .attr("data-reveal", "")
                                .child(icon(doc.icon)),
                        )
                        .child(eyebrow(doc.kicker))
                        .child(split(h1, doc.title))
                        .child(
                            p().class("lead")
                                .attr("data-reveal", "")
                                .style("--d:2")
                                .text(doc.lead),
                        )
                        .child(
                            p().class("page-hero__meta")
                                .attr("data-reveal", "")
                                .style("--d:3")
                                .child(icon("bolt"))
                                .child(span().text(lang.t(UPDATED_FR, UPDATED_EN))),
                        ),
                ),
        )
        .child(
            div()
                .class("wrap doc-layout")
                .child(aside().class("doc-side").child(toc))
                .child(article),
        )
        .child(related(ctx, ctx.route.page));
    layout(
        ctx,
        &format!("{} · KeyForge", ctx.route.page.label(lang)),
        doc.description,
        content,
    )
}

// ----- Contenus --------------------------------------------------------------------------

fn security(l: Lang) -> Doc {
    let t = |fr, en| l.t(fr, en);
    Doc {
        icon: "shield",
        kicker: t("Modèle de sécurité", "Security model"),
        title: t("Ce qui protège vos secrets.", "What protects your secrets."),
        lead: t(
            "KeyForge repose sur un principe simple : ce qui ne quitte jamais votre iPhone ne peut pas fuiter. Voici, sans jargon superflu, comment l'app génère, range et protège vos clés.",
            "KeyForge rests on a simple principle: what never leaves your iPhone cannot leak. Here is, without needless jargon, how the app generates, stores and protects your keys.",
        ),
        description: t(
            "Le modèle de sécurité de KeyForge : génération cryptographique, Trousseau iOS, Face ID, aucune connexion réseau.",
            "KeyForge's security model: cryptographic generation, iOS Keychain, Face ID, no network connection.",
        ),
        sections: vec![
            sec(
                "principles",
                t("Les principes", "Principles"),
                vec![Block::List(vec![
                    t(
                        "Aucun serveur : rien à pirater de notre côté, aucune base de données de vos secrets.",
                        "No server: nothing to breach on our side, no database of your secrets.",
                    ),
                    t(
                        "Aucun compte : pas d'adresse e-mail, pas de mot de passe maître à oublier ou à voler.",
                        "No account: no e-mail address, no master password to forget or steal.",
                    ),
                    t(
                        "Les briques de sécurité d'Apple plutôt qu'une cryptographie maison.",
                        "Apple's security building blocks rather than home-made cryptography.",
                    ),
                    t(
                        "Le moins de code possible entre vous et vos secrets.",
                        "As little code as possible between you and your secrets.",
                    ),
                ])],
            ),
            sec(
                "generation",
                t("La génération", "Generation"),
                vec![
                    Block::P(t(
                        "Chaque caractère, mot ou chiffre est tiré par le générateur aléatoire sécurisé du système (SystemRandomNumberGenerator, adossé au générateur cryptographique d'iOS), avec un tirage uniforme : aucun caractère n'est plus probable qu'un autre.",
                        "Every character, word or digit is drawn by the system's secure random generator (SystemRandomNumberGenerator, backed by iOS's cryptographic generator), uniformly: no character is more likely than another.",
                    )),
                    Block::P(t(
                        "Quand plusieurs classes de caractères sont choisies, l'app en place au moins une de chaque, puis mélange le tout (Fisher-Yates) pour que leur position ne révèle rien.",
                        "When several character classes are chosen, the app places at least one of each, then shuffles everything (Fisher-Yates) so their position reveals nothing.",
                    )),
                    Block::Note(
                        "dice",
                        t(
                            "L'entropie affichée est celle de la méthode de génération, pas une estimation : 20 caractères parmi 86 symboles valent 128 bits.",
                            "The entropy shown is that of the generation method, not a guess: 20 characters out of 86 symbols are worth 128 bits.",
                        ),
                    ),
                ],
            ),
            sec(
                "storage",
                t("Le stockage", "Storage"),
                vec![
                    Block::P(t(
                        "Le coffre est enregistré dans le Trousseau iOS, chiffré par l'iPhone avec des clés protégées par la Secure Enclave et votre code.",
                        "The vault is saved in the iOS Keychain, encrypted by the iPhone with keys protected by the Secure Enclave and your passcode.",
                    )),
                    Block::List(vec![
                        t(
                            "Accessible seulement quand l'iPhone est déverrouillé.",
                            "Readable only while the iPhone is unlocked.",
                        ),
                        t(
                            "Lié à cet appareil : ni synchronisé par iCloud, ni restauré sur un autre iPhone.",
                            "Tied to this device: neither synced through iCloud nor restored to another iPhone.",
                        ),
                        t(
                            "Effaçable entièrement depuis les réglages de l'app.",
                            "Fully erasable from the app's settings.",
                        ),
                    ]),
                ],
            ),
            sec(
                "unlock",
                t("Le déverrouillage", "Unlocking"),
                vec![
                    Block::P(t(
                        "Avec le verrouillage biométrique (activé par défaut), le coffre demande Face ID, Touch ID ou le code de l'appareil à chaque ouverture, via le framework LocalAuthentication d'Apple : KeyForge ne voit jamais votre visage ni votre empreinte.",
                        "With the biometric lock (on by default), the vault asks for Face ID, Touch ID or the device passcode every time it opens, through Apple's LocalAuthentication framework: KeyForge never sees your face or fingerprint.",
                    )),
                    Block::P(t(
                        "Dès que l'app passe en arrière-plan, le coffre se verrouille et l'écran est flouté dans le sélecteur d'apps.",
                        "As soon as the app goes to the background, the vault locks and the screen is blurred in the app switcher.",
                    )),
                ],
            ),
            sec(
                "clipboard",
                t("Le presse-papiers", "The clipboard"),
                vec![Block::P(t(
                    "Ce que vous copiez reçoit une date d'expiration (30 s, 1 min ou 2 min, au choix) et l'option « local uniquement » : il disparaît tout seul et n'est jamais envoyé à vos autres appareils par le presse-papiers universel.",
                    "What you copy gets an expiry date (30 s, 1 min or 2 min, your choice) and the “local only” option: it disappears on its own and is never sent to your other devices through Universal Clipboard.",
                ))],
            ),
            sec(
                "post-quantum",
                t("Le post-quantique", "Post-quantum"),
                vec![
                    Block::P(t(
                        "Un ordinateur quantique suffisamment puissant casserait X25519 et tous les échanges de clés classiques. Un attaquant patient peut déjà enregistrer des messages chiffrés aujourd'hui pour les lire ce jour-là (« récolter maintenant, déchiffrer plus tard »). KeyForge chiffre donc ses partages avec le protocole v4 de Brocolis 🥦, hybride : il faudrait casser à la fois X25519 et ML-KEM-768.",
                        "A powerful enough quantum computer would break X25519 and every classic key exchange. A patient attacker can already record encrypted messages today to read them on that day (“harvest now, decrypt later”). So KeyForge encrypts its shares with the Brocolis 🥦 v4 protocol, a hybrid: one would have to break both X25519 and ML-KEM-768.",
                    )),
                    Block::List(vec![
                        t(
                            "Une identité par appareil : IK X25519 et Ed25519, une clé pré-signée X25519 et une clé ML-KEM-768 (FIPS 203), signées par l'identité. Leur paquet public se partage librement.",
                            "One identity per device: X25519 and Ed25519 identity keys, an X25519 signed prekey and an ML-KEM-768 key (FIPS 203), signed by the identity. Their public bundle can be shared freely.",
                        ),
                        t(
                            "Chiffrer pour un paquet : trois échanges X25519 et une encapsulation ML-KEM-768, mélangés par HKDF-SHA256 dans la clé de session (façon PQXDH). Un paquet sans ML-KEM est refusé : pas de repli classique.",
                            "Encrypting to a bundle: three X25519 exchanges and one ML-KEM-768 encapsulation, mixed by HKDF-SHA256 into the session key (PQXDH-style). A bundle without ML-KEM is refused: no classic fallback.",
                        ),
                        t(
                            "L'identité de l'expéditeur voyage chiffrée dans un préambule, les en-têtes aussi : un observateur ne voit ni qui écrit, ni combien de messages.",
                            "The sender's identity travels encrypted in a preamble, and so do the headers: an observer sees neither who writes nor how many messages.",
                        ),
                        t(
                            "Les échanges suivants font tourner un triple cliquet : un nouvel échange X25519 et une nouvelle encapsulation ML-KEM-768 à chaque tour.",
                            "Later exchanges turn a triple ratchet: a new X25519 exchange and a new ML-KEM-768 encapsulation at every turn.",
                        ),
                        t(
                            "Un premier message ne s'ouvre qu'une fois : la clé éphémère déjà vue est refusée (rejeu).",
                            "A first message opens only once: an ephemeral key already seen is refused (replay).",
                        ),
                    ]),
                    Block::Note(
                        "shield",
                        t(
                            "Les parties symétriques (AES-256-GCM, HKDF-SHA256, Argon2id) ne craignent pas l'ordinateur quantique : l'algorithme de Grover ne fait que réduire 256 bits à 128.",
                            "The symmetric parts (AES-256-GCM, HKDF-SHA256, Argon2id) don't fear a quantum computer: Grover's algorithm only reduces 256 bits to 128.",
                        ),
                    ),
                ],
            ),
            sec(
                "brocolis",
                t("Le chiffrement Brocolis 🥦", "Brocolis encryption 🥦"),
                vec![
                    Block::P(t(
                        "Pour ses partages et sa sauvegarde chiffrée, KeyForge n'invente rien : il utilise les formats de Brocolis, un projet de chiffrement post-quantique doté d'une implémentation de référence en Rust (brocolis-proto) et de vecteurs de test publics. L'app iOS les retrouve octet pour octet, et ce site se sert directement de la crate, compilée en WebAssembly. Pour la sauvegarde à phrase :",
                        "For its shares and its encrypted backup, KeyForge invents nothing: it uses the formats of Brocolis, a post-quantum encryption project with a reference implementation in Rust (brocolis-proto) and public test vectors. The iOS app matches them byte for byte, and this website uses the crate directly, compiled to WebAssembly. For the passphrase backup:",
                    )),
                    Block::List(vec![
                        t(
                            "Une clé aléatoire de 32 octets, protégée par votre phrase : Argon2id (64 Mio, 3 passes), puis AES-256-GCM avec l'en-tête et les paramètres authentifiés — [[BROCOLIS-CLE:v2:…]].",
                            "A random 32-byte key, protected by your passphrase: Argon2id (64 MiB, 3 passes), then AES-256-GCM with the header and parameters authenticated — [[BROCOLIS-CLE:v2:…]].",
                        ),
                        t(
                            "Le contenu, premier message du protocole v4 en mode clé partagée sous cette clé : en-têtes chiffrés, AES-256-GCM — [[BROCOLIS:v4:…]]. Les anciennes sauvegardes [[BROCOLIS:v1:…]] s'ouvrent toujours.",
                            "The content, first message of the v4 protocol in shared-key mode under that key: encrypted headers, AES-256-GCM — [[BROCOLIS:v4:…]]. Older [[BROCOLIS:v1:…]] backups still open.",
                        ),
                        t(
                            "Une phrase de 8 caractères au moins ; KeyForge en propose une de six mots (60 bits).",
                            "A passphrase of at least 8 characters; KeyForge suggests a six-word one (60 bits).",
                        ),
                        t(
                            "À l'import, des paramètres Argon2id hors bornes sont refusés avant tout calcul.",
                            "On import, out-of-bounds Argon2id parameters are refused before any computation.",
                        ),
                    ]),
                    Block::View(
                        a().class("btn btn--ghost")
                            .href(super::pages::BROCOLIS)
                            .attr("target", "_blank")
                            .attr("rel", "noopener")
                            .child(icon("github"))
                            .child(
                                span()
                                    .text(t("Voir brocolis sur GitHub", "See brocolis on GitHub")),
                            ),
                    ),
                ],
            ),
            sec(
                "network",
                t("Le réseau", "The network"),
                vec![Block::P(t(
                    "L'application ne contient aucun code réseau : aucune requête, aucune analyse d'audience, aucun rapport de plantage envoyé par l'app. Son manifeste de confidentialité déclare qu'aucune donnée n'est collectée.",
                    "The app contains no networking code: no request, no analytics, no crash report sent by the app. Its privacy manifest declares that no data is collected.",
                ))],
            ),
            sec(
                "website",
                t("Ce site", "This website"),
                vec![
                    Block::P(t(
                        "Le site est une application Paquets écrite en Rust. Le générateur et le testeur tournent dans votre navigateur, en WebAssembly : ce que vous y tapez ou générez n'est jamais envoyé.",
                        "The website is a Paquets application written in Rust. The generator and the tester run in your browser, in WebAssembly: what you type or generate there is never sent.",
                    )),
                    Block::List(vec![
                        t(
                            "Une Content-Security-Policy stricte, calculée pour chaque page par Paquets.",
                            "A strict Content-Security-Policy, computed for every page by Paquets.",
                        ),
                        t(
                            "Aucun script tiers, aucune police externe, aucun cookie.",
                            "No third-party script, no external font, no cookie.",
                        ),
                        t(
                            "Un service worker qui garde le site disponible hors ligne.",
                            "A service worker that keeps the site available offline.",
                        ),
                    ]),
                ],
            ),
            sec(
                "limits",
                t("Les limites", "Limits"),
                vec![Block::P(t(
                    "Aucune app ne protège d'un appareil déjà compromis (jailbreak, logiciel espion) ni de quelqu'un qui connaît votre code. Et comme le coffre n'est pas synchronisé, perdre l'iPhone, c'est perdre le coffre : gardez une copie de secours de vos accès essentiels.",
                    "No app protects against an already compromised device (jailbreak, spyware) or someone who knows your passcode. And since the vault is not synced, losing the iPhone means losing the vault: keep a backup of your essential logins.",
                ))],
            ),
            sec(
                "report",
                t("Signaler une faille", "Report a vulnerability"),
                vec![
                    Block::P(t(
                        "Vous avez trouvé un problème de sécurité ? Merci de le signaler de façon privée via l'onglet « Security » du dépôt GitHub, plutôt que dans une issue publique.",
                        "Found a security issue? Please report it privately through the repository's GitHub “Security” tab rather than in a public issue.",
                    )),
                    Block::View(
                        a().class("btn btn--ghost")
                            .href(format!("{REPO}/security"))
                            .attr("target", "_blank")
                            .attr("rel", "noopener")
                            .child(icon("shield"))
                            .child(span().text(t("Signaler en privé", "Report privately"))),
                    ),
                ],
            ),
        ],
    }
}

fn entropy_table(l: Lang) -> Element {
    let t = |fr, en| l.t(fr, en);
    let rows = [
        (
            t("PIN de 6 chiffres", "6-digit PIN"),
            "20",
            t("Très faible", "Very weak"),
            1,
        ),
        (
            t("8 caractères, minuscules", "8 lowercase characters"),
            "38",
            t("Correcte", "Fair"),
            3,
        ),
        (
            t("Phrase de 5 mots", "5-word passphrase"),
            "50",
            t("Correcte", "Fair"),
            3,
        ),
        (
            t("Phrase de 7 mots", "7-word passphrase"),
            "70",
            t("Forte", "Strong"),
            4,
        ),
        (
            t("16 caractères, 4 classes", "16 characters, 4 classes"),
            "103",
            t("Forte", "Strong"),
            4,
        ),
        (
            t("20 caractères, 4 classes", "20 characters, 4 classes"),
            "128",
            t("Excellente", "Excellent"),
            5,
        ),
    ];
    div().class("table-wrap").child(
        table()
            .class("etable")
            .child(
                thead().child(
                    tr().child(th().text(t("Secret", "Secret")))
                        .child(th().text(t("Bits", "Bits")))
                        .child(th().text(t("Niveau", "Level"))),
                ),
            )
            .child(
                tbody().children(rows.into_iter().map(|(name, bits, level, rank)| {
                    tr().child(td().text(name))
                        .child(td().child(strong().text(bits)))
                        .child(td().child(span().class(format!("lvl lvl--{rank}")).text(level)))
                })),
            ),
    )
}

fn guide(l: Lang) -> Doc {
    let t = |fr, en| l.t(fr, en);
    Doc {
        icon: "book",
        kicker: t("Guide", "Guide"),
        title: t(
            "Les bons mots de passe, simplement.",
            "Good passwords, simply.",
        ),
        lead: t(
            "Cinq minutes pour comprendre ce qui rend un mot de passe solide, et les quelques habitudes qui vous protègent vraiment.",
            "Five minutes to understand what makes a password strong, and the few habits that really protect you.",
        ),
        description: t(
            "Le guide KeyForge des bons mots de passe : longueur, phrases de passe, unicité, double authentification et que faire après une fuite.",
            "The KeyForge guide to good passwords: length, passphrases, uniqueness, two-factor authentication and what to do after a leak.",
        ),
        sections: vec![
            sec(
                "why",
                t(
                    "Comment on casse un mot de passe",
                    "How passwords get cracked",
                ),
                vec![
                    Block::P(t(
                        "Les attaquants n'essaient pas au hasard : ils commencent par les mots de passe des fuites, les mots du dictionnaire, les prénoms, les dates et leurs variantes (« Soleil2024! »). Seul un secret vraiment aléatoire les oblige à tout essayer.",
                        "Attackers don't guess at random: they start with leaked passwords, dictionary words, names, dates and their variations (“Summer2024!”). Only a truly random secret forces them to try everything.",
                    )),
                    Block::P(t(
                        "Avec du matériel dédié, une attaque hors ligne teste des dizaines de milliards de combinaisons par seconde. C'est la base des temps de cassage affichés par KeyForge (10¹¹ essais par seconde).",
                        "With dedicated hardware, an offline attack tests tens of billions of combinations per second. That is the basis of the crack times KeyForge shows (10¹¹ guesses per second).",
                    )),
                ],
            ),
            sec(
                "length",
                t("La longueur avant tout", "Length first"),
                vec![
                    Block::P(t(
                        "Chaque caractère aléatoire multiplie le travail de l'attaquant. Ajouter des caractères rapporte plus que compliquer un mot court.",
                        "Every random character multiplies the attacker's work. Adding characters pays off more than complicating a short word.",
                    )),
                    Block::View(entropy_table(l)),
                ],
            ),
            sec(
                "passphrases",
                t("Les phrases de passe", "Passphrases"),
                vec![
                    Block::P(t(
                        "Pour ce que vous devez taper de mémoire (le code de votre ordinateur, votre identifiant Apple), une phrase de passe de 6 ou 7 mots tirés au hasard est idéale : facile à retenir, longue à deviner.",
                        "For what you must type from memory (your computer password, your Apple Account), a passphrase of 6 or 7 random words is ideal: easy to remember, slow to guess.",
                    )),
                    Block::Note(
                        "words",
                        t(
                            "Le hasard est essentiel : une phrase que vous inventez (« jaime-mon-chat ») est bien plus faible que des mots tirés par la machine.",
                            "Randomness is key: a phrase you make up (“i-love-my-cat”) is much weaker than words drawn by the machine.",
                        ),
                    ),
                ],
            ),
            sec(
                "unique",
                t("Un secret par compte", "One secret per account"),
                vec![Block::P(t(
                    "Quand un site se fait voler sa base, les mots de passe récupérés sont essayés partout ailleurs. Un mot de passe unique par compte contient les dégâts : c'est précisément ce que le coffre rend facile.",
                    "When a site's database is stolen, the recovered passwords are tried everywhere else. One unique password per account contains the damage: exactly what the vault makes easy.",
                ))],
            ),
            sec(
                "twofactor",
                t("La double authentification", "Two-factor authentication"),
                vec![Block::P(t(
                    "Activez-la partout où c'est possible, en priorité sur votre messagerie, votre banque et votre compte Apple. Préférez une application d'authentification ou une clé de sécurité aux SMS.",
                    "Turn it on wherever you can, first on your e-mail, your bank and your Apple Account. Prefer an authenticator app or a security key over text messages.",
                ))],
            ),
            sec(
                "traps",
                t("Les pièges classiques", "Classic traps"),
                vec![Block::List(vec![
                    t(
                        "Les substitutions évidentes (« P@ssw0rd ») : les outils d'attaque les connaissent toutes.",
                        "Obvious substitutions (“P@ssw0rd”): attack tools know them all.",
                    ),
                    t(
                        "Les informations personnelles : prénoms, dates, ville, animal.",
                        "Personal details: names, dates, city, pet.",
                    ),
                    t(
                        "Les suites de clavier : « azerty », « 123456 », « qwerty ».",
                        "Keyboard runs: “azerty”, “123456”, “qwerty”.",
                    ),
                    t(
                        "Un mot de passe « fort » réutilisé sur plusieurs sites.",
                        "A “strong” password reused on several sites.",
                    ),
                ])],
            ),
            sec(
                "leak",
                t("Après une fuite", "After a leak"),
                vec![Block::List(vec![
                    t(
                        "Changez le mot de passe du site concerné, puis de tous les comptes où vous l'aviez réutilisé.",
                        "Change the password of the affected site, then of every account where you reused it.",
                    ),
                    t(
                        "Activez la double authentification si ce n'est pas fait.",
                        "Turn on two-factor authentication if it isn't on yet.",
                    ),
                    t(
                        "Méfiez-vous des e-mails qui profitent de l'actualité de la fuite (hameçonnage).",
                        "Beware of e-mails taking advantage of the leak in the news (phishing).",
                    ),
                ])],
            ),
        ],
    }
}

fn help(l: Lang) -> Doc {
    let t = |fr, en| l.t(fr, en);
    Doc {
        icon: "lifebuoy",
        kicker: t("Assistance", "Support"),
        title: t("Comment pouvons-nous aider ?", "How can we help?"),
        lead: t(
            "Les premiers pas, les réponses aux questions fréquentes, les solutions aux petits soucis, et comment nous écrire.",
            "First steps, answers to common questions, fixes for small issues, and how to reach us.",
        ),
        description: t(
            "Le centre d'aide de KeyForge : premiers pas, questions fréquentes, dépannage et contact.",
            "KeyForge's help center: first steps, frequently asked questions, troubleshooting and contact.",
        ),
        sections: vec![
            sec(
                "start",
                t("Premiers pas", "Getting started"),
                vec![Block::List(vec![
                    t(
                        "Ouvrez KeyForge : l'onglet Générateur forge un premier secret.",
                        "Open KeyForge: the Generator tab forges a first secret.",
                    ),
                    t(
                        "Choisissez Mot de passe, Phrase de passe ou Code PIN, et ajustez la longueur.",
                        "Choose Password, Passphrase or PIN code, and adjust the length.",
                    ),
                    t(
                        "Touchez « Copier » pour le coller dans un site, ou « Ranger » pour l'enregistrer dans le coffre.",
                        "Tap “Copy” to paste it into a site, or “Save” to store it in the vault.",
                    ),
                    t(
                        "Dans l'onglet Analyse, testez vos anciens mots de passe.",
                        "In the Analysis tab, test your old passwords.",
                    ),
                ])],
            ),
            sec(
                "faq",
                t("Questions fréquentes", "Frequently asked questions"),
                vec![Block::View(faq_list(l))],
            ),
            sec(
                "trouble",
                t("Dépannage", "Troubleshooting"),
                vec![
                    Block::Note(
                        "faceid",
                        t(
                            "Face ID ne s'affiche pas : vérifiez dans Réglages → KeyForge que l'accès à Face ID est autorisé. Sinon, le code de l'appareil reste toujours proposé.",
                            "Face ID doesn't show: check in Settings → KeyForge that Face ID access is allowed. Otherwise, the device passcode is always offered.",
                        ),
                    ),
                    Block::Note(
                        "clipboard",
                        t(
                            "Le mot de passe copié a disparu : c'est l'effacement automatique. Allongez le délai ou désactivez-le dans les réglages de l'app.",
                            "The copied password vanished: that's the automatic clearing. Lengthen the delay or turn it off in the app's settings.",
                        ),
                    ),
                    Block::Note(
                        "vault",
                        t(
                            "Le coffre est vide sur un nouvel iPhone : il est lié à l'appareil et n'est ni synchronisé ni restauré ailleurs, par conception. Restaurez-le depuis une sauvegarde chiffrée Brocolis 🥦 (Réglages → Sauvegarde chiffrée).",
                            "The vault is empty on a new iPhone: it is tied to the device and neither synced nor restored elsewhere, by design. Restore it from a Brocolis 🥦 encrypted backup (Settings → Encrypted backup).",
                        ),
                    ),
                ],
            ),
            sec(
                "contact",
                t("Nous écrire", "Contact us"),
                vec![
                    Block::P(t(
                        "Une question, une idée, un bug ? Ouvrez une issue sur le dépôt GitHub : c'est le moyen le plus rapide d'obtenir une réponse, et la réponse profite à tout le monde.",
                        "A question, an idea, a bug? Open an issue on the GitHub repository: it's the fastest way to get an answer, and the answer helps everyone.",
                    )),
                    Block::View(
                        a().class("btn btn--primary")
                            .href(format!("{REPO}/issues/new"))
                            .attr("target", "_blank")
                            .attr("rel", "noopener")
                            .child(icon("mail"))
                            .child(span().text(t("Ouvrir une issue", "Open an issue"))),
                    ),
                ],
            ),
        ],
    }
}

fn changelog(l: Lang) -> Doc {
    let t = |fr, en| l.t(fr, en);
    let release =
        |version: &'static str, date: &'static str, tag: &'static str, items: Vec<&'static str>| {
            div()
                .class("release")
                .child(
                    div()
                        .class("release__head")
                        .child(strong().class("release__v grad").text(version))
                        .child(span().class("pill__tag").text(tag))
                        .child(time().class("muted").text(date)),
                )
                .child(
                    ul().class("doc__list")
                        .children(items.into_iter().enumerate().map(|(i, s)| {
                            li().style(format!("--i:{i}"))
                                .child(icon("spark"))
                                .child(span().text(s))
                        })),
                )
        };
    Doc {
        icon: "bolt",
        kicker: t("Nouveautés", "What's new"),
        title: t(
            "Ce qui change, version après version.",
            "What changes, version after version.",
        ),
        lead: t(
            "L'historique de l'application iOS et de ce site. Pour être prévenu des prochaines versions, abonnez-vous au flux RSS du dépôt.",
            "The history of the iOS app and of this website. To hear about the next versions, subscribe to the repository's RSS feed.",
        ),
        description: t(
            "Les nouveautés de KeyForge : l'historique des versions de l'application iOS et du site.",
            "What's new in KeyForge: the version history of the iOS app and the website.",
        ),
        sections: vec![
            sec(
                "app-1-0",
                t("Application iOS 1.0", "iOS app 1.0"),
                vec![Block::View(release(
                    "1.0",
                    t("À venir sur l'App Store", "Coming to the App Store"),
                    t("App", "App"),
                    vec![
                        t(
                            "Générateur de mots de passe (4 à 128 caractères), phrases de passe (3 à 12 mots) et codes PIN.",
                            "Password (4 to 128 characters), passphrase (3 to 12 words) and PIN generator.",
                        ),
                        t(
                            "Coffre dans le Trousseau iOS, verrouillé par Face ID, Touch ID ou le code.",
                            "Vault in the iOS Keychain, locked by Face ID, Touch ID or passcode.",
                        ),
                        t(
                            "Analyse de robustesse avec temps de cassage estimé.",
                            "Strength analysis with estimated time to crack.",
                        ),
                        t(
                            "Presse-papiers effacé automatiquement, écran flouté en arrière-plan.",
                            "Self-clearing clipboard, blurred screen in the background.",
                        ),
                        t(
                            "Partage post-quantique d'un secret (Brocolis 🥦 v4 : X25519 + ML-KEM-768) et réception, avec une identité gardée dans le Trousseau.",
                            "Post-quantum sharing of a secret (Brocolis 🥦 v4: X25519 + ML-KEM-768) and receiving, with an identity kept in the Keychain.",
                        ),
                        t(
                            "Sauvegarde chiffrée du coffre au format Brocolis 🥦 (Argon2id + message v4).",
                            "Encrypted vault backup in the Brocolis 🥦 format (Argon2id + v4 message).",
                        ),
                        t(
                            "Découverte animée en trois écrans, thème sombre « forge ».",
                            "Animated three-screen onboarding, dark “forge” theme.",
                        ),
                    ],
                ))],
            ),
            sec(
                "site-0-2",
                t("Site 0.2 · post-quantique", "Website 0.2 · post-quantum"),
                vec![Block::View(release(
                    "0.2.0",
                    t("Novembre 2026", "November 2026"),
                    t("Site", "Site"),
                    vec![
                        t(
                            "Échange post-quantique dans le navigateur : identité X25519 + ML-KEM-768, chiffrer pour un paquet de clés, déchiffrer (protocole v4 de Brocolis 🥦).",
                            "Post-quantum exchange in the browser: X25519 + ML-KEM-768 identity, encrypt to a key bundle, decrypt (Brocolis 🥦 v4 protocol).",
                        ),
                        t(
                            "Le scelleur à phrase produit des messages v4 ; les anciens scellés v1 s'ouvrent toujours.",
                            "The passphrase sealer produces v4 messages; older v1 sealed secrets still open.",
                        ),
                        t(
                            "Pages sécurité, confidentialité et FAQ mises à jour pour le post-quantique ; dépendances à jour.",
                            "Security, privacy and FAQ pages updated for post-quantum; dependencies up to date.",
                        ),
                    ],
                ))],
            ),
            sec(
                "site-0-1",
                t("Site 0.1", "Website 0.1"),
                vec![Block::View(release(
                    "0.1.0",
                    t("Novembre 2026", "November 2026"),
                    t("Site", "Site"),
                    vec![
                        t(
                            "Site écrit avec Paquets : pages rendues par le serveur, îlots WebAssembly.",
                            "Website built with Paquets: server-rendered pages, WebAssembly islands.",
                        ),
                        t(
                            "Générateur et testeur de robustesse en direct, dans le navigateur.",
                            "Live generator and strength tester, in the browser.",
                        ),
                        t(
                            "Installable (PWA) et disponible hors ligne.",
                            "Installable (PWA) and available offline.",
                        ),
                        t(
                            "Scelleur de secrets à phrase (Argon2id + message Brocolis v4), dans le navigateur.",
                            "Passphrase secret sealer (Argon2id + Brocolis v4 message), in the browser.",
                        ),
                        t(
                            "En français et en anglais, thème clair et sombre.",
                            "In French and English, light and dark themes.",
                        ),
                    ],
                ))],
            ),
        ],
    }
}

fn swatch(name: &'static str, hex: &'static str, l: Lang) -> Element {
    button()
        .class("swatch")
        .attr("type", "button")
        .attr("data-copy", hex)
        .attr("data-cursor", l.t("Copier", "Copy"))
        .attr("aria-label", format!("{name} {hex}"))
        .child(
            span()
                .class("swatch__chip")
                .style(format!("background:{hex}")),
        )
        .child(strong().text(name))
        .child(code().text(hex))
        .child(span().class("swatch__done").child(icon("check")))
}

fn copy_block(text: &'static str, l: Lang) -> Element {
    div().class("copyblock").child(p().text(text)).child(
        button()
            .class("btn btn--ghost btn--sm")
            .attr("type", "button")
            .attr("data-copy", text)
            .child(icon("copy"))
            .child(span().class("copy-label").text(l.t("Copier", "Copy")))
            .child(span().class("copied-label").text(l.t("Copié", "Copied"))),
    )
}

fn press(l: Lang) -> Doc {
    let t = |fr, en| l.t(fr, en);
    Doc {
        icon: "news",
        kicker: t("Kit presse", "Press kit"),
        title: t(
            "Tout pour parler de KeyForge.",
            "Everything to write about KeyForge.",
        ),
        lead: t(
            "Le nom, les descriptions, le logo et les couleurs, prêts à copier ou à télécharger.",
            "The name, descriptions, logo and colours, ready to copy or download.",
        ),
        description: t(
            "Le kit presse de KeyForge : descriptions, logo, icône et couleurs de la marque.",
            "KeyForge's press kit: descriptions, logo, icon and brand colours.",
        ),
        sections: vec![
            sec(
                "name",
                t("Le nom", "The name"),
                vec![Block::P(t(
                    "KeyForge s'écrit en un mot, avec un K et un F majuscules. En capitales, le mot-symbole s'écrit KEYFORGE.",
                    "KeyForge is one word, with a capital K and F. In capitals, the wordmark reads KEYFORGE.",
                ))],
            ),
            sec(
                "descriptions",
                t("Les descriptions", "Descriptions"),
                vec![
                    Block::View(copy_block(
                        t(
                            "KeyForge forge des mots de passe incassables et les garde derrière Face ID.",
                            "KeyForge forges unbreakable passwords and keeps them behind Face ID.",
                        ),
                        l,
                    )),
                    Block::View(copy_block(
                        t(
                            "KeyForge est une app iPhone qui génère des mots de passe, des phrases de passe et des codes PIN impossibles à deviner, les range dans le Trousseau iOS derrière Face ID et analyse la robustesse des anciens. Sans compte, sans réseau, sans publicité.",
                            "KeyForge is an iPhone app that generates passwords, passphrases and PIN codes nobody can guess, keeps them in the iOS Keychain behind Face ID and checks the strength of old ones. No account, no network, no ads.",
                        ),
                        l,
                    )),
                ],
            ),
            sec(
                "logo",
                t("Le logo et l'icône", "Logo and icon"),
                vec![
                    Block::View(
                        div()
                            .class("brand-assets")
                            .child(
                                div().class("brand-asset").child(logo()).child(
                                    a().class("btn btn--ghost btn--sm")
                                        .href("/assets/logo.svg")
                                        .attr("download", "keyforge-logo.svg")
                                        .child(icon("download"))
                                        .child(span().text("SVG")),
                                ),
                            )
                            .child(
                                div()
                                    .class("brand-asset")
                                    .child(
                                        img()
                                            .attr("src", "/icons/icon-512.png")
                                            .attr("alt", t("Icône de KeyForge", "KeyForge icon"))
                                            .attr("width", "120")
                                            .attr("height", "120"),
                                    )
                                    .child(
                                        a().class("btn btn--ghost btn--sm")
                                            .href("/icons/icon-512.png")
                                            .attr("download", "keyforge-icon-512.png")
                                            .child(icon("download"))
                                            .child(span().text("PNG 512")),
                                    ),
                            ),
                    ),
                    Block::Note(
                        "spark",
                        t(
                            "Gardez de l'espace autour du logo, ne le déformez pas et ne changez pas son dégradé.",
                            "Leave space around the logo, don't distort it and don't change its gradient.",
                        ),
                    ),
                ],
            ),
            sec(
                "colors",
                t("Les couleurs", "Colours"),
                vec![Block::View(
                    div()
                        .class("swatches")
                        .child(swatch(t("Encre", "Ink"), "#0B0A12", l))
                        .child(swatch(t("Braise", "Ember"), "#FF6B2C", l))
                        .child(swatch(t("Or", "Gold"), "#FFB547", l))
                        .child(swatch(t("Rose", "Pink"), "#FF2E7E", l))
                        .child(swatch(t("Violet", "Violet"), "#7C5CFF", l)),
                )],
            ),
            sec(
                "contact",
                t("Contact presse", "Press contact"),
                vec![Block::P(t(
                    "Pour une interview, une question ou un accès anticipé à l'app, écrivez-nous via une issue du dépôt GitHub en précisant « presse ».",
                    "For an interview, a question or early access to the app, write to us through an issue on the GitHub repository, mentioning “press”.",
                ))],
            ),
        ],
    }
}

fn privacy(l: Lang) -> Doc {
    let t = |fr, en| l.t(fr, en);
    Doc {
        icon: "eyeoff",
        kicker: t("Confidentialité", "Privacy"),
        title: t(
            "Vos données restent chez vous.",
            "Your data stays with you.",
        ),
        lead: t(
            "La politique de confidentialité de l'application KeyForge et de ce site, en clair.",
            "The privacy policy of the KeyForge app and of this website, in plain words.",
        ),
        description: t(
            "Politique de confidentialité de KeyForge : aucune donnée collectée par l'app, aucun cookie ni traqueur sur le site.",
            "KeyForge privacy policy: no data collected by the app, no cookies or trackers on the website.",
        ),
        sections: vec![
            sec(
                "summary",
                t("En résumé", "Summary"),
                vec![Block::List(vec![
                    t(
                        "L'application ne collecte aucune donnée et ne communique avec aucun serveur.",
                        "The app collects no data and talks to no server.",
                    ),
                    t(
                        "Le site n'utilise ni cookie, ni traqueur, ni outil de mesure d'audience.",
                        "The website uses no cookies, no trackers, no analytics.",
                    ),
                    t(
                        "Ce que vous tapez dans le générateur ou le testeur reste dans votre navigateur.",
                        "What you type in the generator or tester stays in your browser.",
                    ),
                ])],
            ),
            sec(
                "app",
                t("L'application", "The app"),
                vec![
                    Block::P(t(
                        "Une sauvegarde chiffrée n'est créée que si vous la demandez : c'est un texte chiffré par Brocolis 🥦 sous votre phrase, que vous gardez où vous voulez. Personne ne peut l'ouvrir sans cette phrase, pas même l'éditeur.",
                        "An encrypted backup is only created when you ask for it: a text encrypted by Brocolis 🥦 under your passphrase, kept wherever you choose. Nobody can open it without that passphrase, not even the publisher.",
                    )),
                    Block::P(t(
                        "Vos secrets, identifiants et notes sont enregistrés uniquement sur votre iPhone, dans le Trousseau iOS. Vos réglages sont gardés dans les préférences locales de l'app. Rien n'est transmis à l'éditeur ni à des tiers.",
                        "Your secrets, usernames and notes are stored only on your iPhone, in the iOS Keychain. Your settings are kept in the app's local preferences. Nothing is sent to the publisher or to third parties.",
                    )),
                    Block::P(t(
                        "Face ID et Touch ID sont gérés par iOS : l'app reçoit seulement la réponse « autorisé » ou « refusé ».",
                        "Face ID and Touch ID are handled by iOS: the app only receives “allowed” or “denied”.",
                    )),
                ],
            ),
            sec(
                "cookies",
                t("Cookies et stockage local", "Cookies and local storage"),
                vec![Block::P(t(
                    "Le site ne dépose aucun cookie. Il garde seulement, dans le stockage de votre navigateur, votre choix de thème (clair ou sombre), le fait d'avoir déjà vu l'animation d'introduction, et, le temps de la session de l'onglet, l'identité post-quantique que vous y créez (elle ne quitte jamais le navigateur et disparaît à sa fermeture). Le service worker met en cache les pages pour le mode hors ligne. Vous pouvez tout effacer depuis les réglages de votre navigateur.",
                    "The website sets no cookies. It only keeps, in your browser's storage, your theme choice (light or dark), whether you have already seen the intro animation, and, for the tab's session, the post-quantum identity you create there (it never leaves the browser and disappears when the tab closes). The service worker caches pages for offline use. You can clear all of it from your browser's settings.",
                ))],
            ),
            sec(
                "hosting",
                t("Hébergement et journaux", "Hosting and logs"),
                vec![Block::P(t(
                    "Le site est hébergé par Heroku (Salesforce). Comme tout hébergeur, celui-ci traite des journaux techniques (adresse IP, page demandée, date) nécessaires au fonctionnement et à la sécurité du service. L'éditeur ne les utilise pas pour mesurer l'audience ni pour vous profiler.",
                    "The website is hosted by Heroku (Salesforce). Like any host, it processes technical logs (IP address, requested page, date) needed to run and secure the service. The publisher doesn't use them to measure audience or profile you.",
                ))],
            ),
            sec(
                "rights",
                t("Vos droits", "Your rights"),
                vec![Block::P(t(
                    "Conformément au RGPD, vous disposez d'un droit d'accès, de rectification et d'effacement. Comme ni l'app ni le site ne conservent de données vous concernant, il n'y a en pratique rien à extraire ni à effacer de notre côté. Pour toute question, écrivez-nous via le dépôt GitHub ; vous pouvez aussi saisir la CNIL.",
                    "Under the GDPR, you have rights of access, rectification and erasure. Since neither the app nor the website keeps data about you, there is in practice nothing to extract or erase on our side. For any question, write to us through the GitHub repository; you can also contact the CNIL.",
                ))],
            ),
        ],
    }
}

fn terms(l: Lang) -> Doc {
    let t = |fr, en| l.t(fr, en);
    Doc {
        icon: "file",
        kicker: t("Conditions", "Terms"),
        title: t("Conditions d'utilisation.", "Terms of use."),
        lead: t(
            "Les règles du jeu, courtes et lisibles.",
            "The rules of the game, short and readable.",
        ),
        description: t(
            "Conditions d'utilisation de l'application KeyForge et de son site.",
            "Terms of use of the KeyForge app and its website.",
        ),
        sections: vec![
            sec(
                "purpose",
                t("Objet", "Purpose"),
                vec![Block::P(t(
                    "Ces conditions encadrent l'utilisation de l'application KeyForge et du site qui la présente. En les utilisant, vous les acceptez.",
                    "These terms govern the use of the KeyForge app and the website presenting it. By using them, you accept them.",
                ))],
            ),
            sec(
                "use",
                t("Utilisation", "Use"),
                vec![Block::P(t(
                    "KeyForge vous aide à créer et ranger des secrets. Vous restez responsable de l'usage que vous en faites, de la sécurité de votre appareil et de la conservation d'une copie de secours de vos accès importants.",
                    "KeyForge helps you create and store secrets. You remain responsible for how you use them, for your device's security and for keeping a backup of your important logins.",
                ))],
            ),
            sec(
                "recovery",
                t("Pas de récupération possible", "No recovery possible"),
                vec![Block::Note(
                    "lock",
                    t(
                        "Vos secrets ne sont stockés que sur votre appareil : l'éditeur n'y a pas accès et ne peut pas les récupérer en cas de perte, de vol ou d'effacement de l'iPhone.",
                        "Your secrets are stored only on your device: the publisher has no access to them and cannot recover them if the iPhone is lost, stolen or erased.",
                    ),
                )],
            ),
            sec(
                "ip",
                t("Propriété intellectuelle", "Intellectual property"),
                vec![Block::P(t(
                    "Le nom, le logo, l'application et le site sont la propriété de leur auteur. Le code source est consultable sur GitHub dans les conditions de la licence du dépôt.",
                    "The name, logo, app and website belong to their author. The source code can be read on GitHub under the terms of the repository's licence.",
                ))],
            ),
            sec(
                "liability",
                t("Responsabilité", "Liability"),
                vec![Block::P(t(
                    "L'application et le site sont fournis « en l'état ». L'éditeur s'efforce de les garder fiables et sûrs, sans pouvoir garantir l'absence totale d'erreur ou d'interruption.",
                    "The app and website are provided “as is”. The publisher strives to keep them reliable and safe, without being able to guarantee they are entirely free of errors or interruptions.",
                ))],
            ),
            sec(
                "law",
                t("Droit applicable", "Governing law"),
                vec![Block::P(t(
                    "Ces conditions sont régies par le droit français. Elles peuvent évoluer ; la date de mise à jour figure en haut de cette page.",
                    "These terms are governed by French law. They may change; the update date appears at the top of this page.",
                ))],
            ),
        ],
    }
}

fn legal(l: Lang) -> Doc {
    let t = |fr, en| l.t(fr, en);
    Doc {
        icon: "scale",
        kicker: t("Mentions légales", "Legal notice"),
        title: t("Qui fait KeyForge.", "Who makes KeyForge."),
        lead: t(
            "Les informations légales sur l'éditeur et l'hébergeur de ce site.",
            "Legal information about the publisher and host of this website.",
        ),
        description: t(
            "Mentions légales du site KeyForge : éditeur, hébergeur, propriété intellectuelle.",
            "KeyForge website legal notice: publisher, host, intellectual property.",
        ),
        sections: vec![
            sec(
                "publisher",
                t("Éditeur", "Publisher"),
                vec![
                    Block::P(t(
                        "Ce site est édité par Maxime Nathan Lestage, à titre personnel. Directeur de la publication : Maxime Nathan Lestage.",
                        "This website is published by Maxime Nathan Lestage, in a personal capacity. Publication director: Maxime Nathan Lestage.",
                    )),
                    Block::P(t(
                        "Contact : via les issues du dépôt GitHub du projet.",
                        "Contact: through the issues of the project's GitHub repository.",
                    )),
                ],
            ),
            sec(
                "host",
                t("Hébergeur", "Host"),
                vec![Block::P(t(
                    "Heroku, service de Salesforce, Inc., 415 Mission Street, Suite 300, San Francisco, CA 94105, États-Unis.",
                    "Heroku, a service of Salesforce, Inc., 415 Mission Street, Suite 300, San Francisco, CA 94105, United States.",
                ))],
            ),
            sec(
                "ip",
                t("Propriété intellectuelle", "Intellectual property"),
                vec![Block::P(t(
                    "Les textes, le logo, les illustrations et le code de ce site sont protégés. Toute reproduction non autorisée est interdite, sauf les éléments du kit presse, utilisables pour parler de KeyForge.",
                    "The texts, logo, illustrations and code of this website are protected. Any unauthorised reproduction is forbidden, except the press kit assets, which may be used to write about KeyForge.",
                ))],
            ),
            sec(
                "credits",
                t("Crédits", "Credits"),
                vec![Block::List(vec![
                    t(
                        "Site construit avec Paquets, en Rust et WebAssembly.",
                        "Website built with Paquets, in Rust and WebAssembly.",
                    ),
                    t(
                        "Chiffrement post-quantique fourni par Brocolis 🥦 (brocolis-proto : X25519 + ML-KEM-768).",
                        "Post-quantum encryption provided by Brocolis 🥦 (brocolis-proto: X25519 + ML-KEM-768).",
                    ),
                    t(
                        "Application iOS écrite en Swift et SwiftUI.",
                        "iOS app written in Swift and SwiftUI.",
                    ),
                    t(
                        "Icônes et illustrations dessinées pour KeyForge.",
                        "Icons and illustrations drawn for KeyForge.",
                    ),
                ])],
            ),
        ],
    }
}

fn accessibility(l: Lang) -> Doc {
    let t = |fr, en| l.t(fr, en);
    Doc {
        icon: "access",
        kicker: t("Accessibilité", "Accessibility"),
        title: t(
            "Un site et une app pour tout le monde.",
            "A website and an app for everyone.",
        ),
        lead: t(
            "Ce que nous faisons pour que KeyForge soit utilisable par chacun, et comment nous signaler un obstacle.",
            "What we do so that everyone can use KeyForge, and how to tell us about a barrier.",
        ),
        description: t(
            "Déclaration d'accessibilité de KeyForge : engagements, mesures prises et contact.",
            "KeyForge accessibility statement: commitments, measures taken and contact.",
        ),
        sections: vec![
            sec(
                "site",
                t("Sur ce site", "On this website"),
                vec![Block::List(vec![
                    t(
                        "Navigation complète au clavier, avec un lien d'évitement vers le contenu.",
                        "Full keyboard navigation, with a skip link to the content.",
                    ),
                    t(
                        "Les animations se calment quand votre système demande moins de mouvement.",
                        "Animations calm down when your system asks for reduced motion.",
                    ),
                    t(
                        "Le contenu est lisible sans JavaScript : les pages sont rendues par le serveur.",
                        "Content is readable without JavaScript: pages are rendered by the server.",
                    ),
                    t(
                        "Contrastes vérifiés en thème clair et sombre, textes redimensionnables.",
                        "Contrast checked in light and dark themes, resizable text.",
                    ),
                    t(
                        "Les résultats du générateur et du testeur sont annoncés aux lecteurs d'écran.",
                        "Generator and tester results are announced to screen readers.",
                    ),
                ])],
            ),
            sec(
                "app",
                t("Dans l'application", "In the app"),
                vec![Block::List(vec![
                    t(
                        "Dynamic Type : les textes suivent la taille choisie dans iOS.",
                        "Dynamic Type: text follows the size chosen in iOS.",
                    ),
                    t(
                        "VoiceOver : chaque bouton et chaque jauge a une description.",
                        "VoiceOver: every button and gauge has a description.",
                    ),
                    t(
                        "« Réduire les animations » est respecté.",
                        "“Reduce Motion” is respected.",
                    ),
                ])],
            ),
            sec(
                "feedback",
                t("Nous signaler un obstacle", "Report a barrier"),
                vec![Block::P(t(
                    "Si un élément vous bloque, dites-le-nous via une issue du dépôt GitHub : nous chercherons une solution et, en attendant, une autre façon d'accéder à l'information.",
                    "If something blocks you, tell us through an issue on the GitHub repository: we'll look for a fix and, meanwhile, another way to reach the information.",
                ))],
            ),
        ],
    }
}

fn not_found(ctx: &Ctx) -> Page {
    let t = |fr, en| ctx.t(fr, en);
    let content = html::main()
        .class("lost")
        .child(div().class("page-hero__bg").attr("aria-hidden", "true").child(div().class("blob blob--a")).child(div().class("blob blob--b")))
        .child(
            div()
                .class("wrap lost__inner")
                .child(
                    div()
                        .class("lost__art")
                        .attr("aria-hidden", "true")
                        .child(span().class("lost__digit").text("4"))
                        .child(span().class("lost__lock").child(icon("lock")))
                        .child(span().class("lost__digit").text("4"))
                        .child(span().class("lost__key").child(icon("key"))),
                )
                .child(split(h1, t("Cette clé n'ouvre aucune porte.", "This key opens no door.")))
                .child(p().class("lead").attr("data-reveal", "").text(t(
                    "La page demandée n'existe pas ou a changé d'adresse. Pas de panique : vos secrets, eux, n'ont pas bougé.",
                    "The page you asked for doesn't exist or has moved. Don't worry: your secrets haven't.",
                )))
                .child(
                    div()
                        .class("row center")
                        .attr("data-reveal", "")
                        .child(a().class("btn btn--primary").href(ctx.href(PageKind::Home)).attr("data-magnetic", "").child(span().text(t("Retour à l'accueil", "Back home"))).child(icon("arrow")))
                        .child(a().class("btn btn--ghost").href(ctx.href(PageKind::Help)).child(icon("lifebuoy")).child(span().text(t("Centre d'aide", "Help center")))),
                ),
        );
    layout(
        ctx,
        &format!("{} · KeyForge", PageKind::NotFound.label(ctx.lang())),
        t("Cette page n'existe pas.", "This page doesn't exist."),
        content,
    )
}

pub fn render(ctx: &Ctx) -> Page {
    let l = ctx.lang();
    let doc = match ctx.route.page {
        PageKind::Security => security(l),
        PageKind::Guide => guide(l),
        PageKind::Help => help(l),
        PageKind::Changelog => changelog(l),
        PageKind::Press => press(l),
        PageKind::Privacy => privacy(l),
        PageKind::Terms => terms(l),
        PageKind::Legal => legal(l),
        PageKind::Accessibility => accessibility(l),
        PageKind::Home | PageKind::NotFound => return not_found(ctx),
    };
    doc_page(ctx, doc)
}
