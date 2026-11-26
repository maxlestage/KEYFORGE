//! Le cœur de KeyForge, en Rust : les mêmes règles que l'application iOS.
//!
//! - mots de passe aléatoires (4 à 128 caractères, classes au choix, caractères ambigus
//!   exclus sur demande, au moins un caractère de chaque classe choisie) ;
//! - phrases de passe (3 à 20 mots tirés d'une liste de 1 024 mots : 10 bits par mot) ;
//! - codes PIN (4 à 12 chiffres) ;
//! - entropie, niveau de robustesse, et analyse d'un mot de passe saisi (motifs, mots de
//!   passe courants, temps de cassage estimé).
//!
//! Le hasard vient de [`Rng`] : `crypto.getRandomValues` dans le navigateur, un
//! générateur déterministe dans les tests. Rien n'est jamais envoyé à un serveur.

/// La liste de mots partagée avec l'application iOS (`shared/wordlist-fr.txt`).
pub const WORDLIST: &str = include_str!("../../shared/wordlist-fr.txt");

pub const LOWER: &str = "abcdefghijklmnopqrstuvwxyz";
pub const UPPER: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const DIGITS: &str = "0123456789";
pub const SYMBOLS: &str = "!@#$%^&*()-_=+[]{};:,.?/";
/// Retirés quand « exclure les caractères ambigus » est actif.
pub const AMBIGUOUS: &str = "0Oo1lI|";

/// Les mots de la liste, une fois découpés.
pub fn words() -> Vec<&'static str> {
    WORDLIST
        .lines()
        .map(str::trim)
        .filter(|w| !w.is_empty())
        .collect()
}

/// Une source de hasard uniforme.
pub trait Rng {
    /// Un entier uniforme sur 32 bits.
    fn next_u32(&mut self) -> u32;

    /// Un entier uniforme dans `0..n`, sans biais (rejet).
    fn below(&mut self, n: u32) -> u32 {
        assert!(n > 0, "below(0)");
        let range = 1u64 << 32;
        let limit = range - range % u64::from(n);
        loop {
            let x = u64::from(self.next_u32());
            if x < limit {
                return (x % u64::from(n)) as u32;
            }
        }
    }
}

/// Un générateur déterministe (xorshift64*), pour les tests et les démonstrations
/// rendues par le serveur. Jamais utilisé pour de vrais secrets.
pub struct Xorshift(pub u64);

impl Rng for Xorshift {
    fn next_u32(&mut self) -> u32 {
        let mut x = self.0.max(1);
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        (x.wrapping_mul(0x2545_f491_4f6c_dd1d) >> 32) as u32
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Password,
    Passphrase,
    Pin,
}

impl Mode {
    pub const ALL: [Mode; 3] = [Mode::Password, Mode::Passphrase, Mode::Pin];

    pub fn code(self) -> &'static str {
        match self {
            Mode::Password => "password",
            Mode::Passphrase => "passphrase",
            Mode::Pin => "pin",
        }
    }

    /// Longueur (ou nombre de mots) : minimum, maximum, valeur par défaut.
    pub fn range(self) -> (u32, u32, u32) {
        match self {
            Mode::Password => (4, 128, 20),
            Mode::Passphrase => (3, 20, 5),
            Mode::Pin => (4, 12, 6),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Options {
    pub mode: Mode,
    /// Caractères, mots ou chiffres.
    pub length: u32,
    pub upper: bool,
    pub lower: bool,
    pub digits: bool,
    pub symbols: bool,
    pub avoid_ambiguous: bool,
    /// Phrase de passe : séparateur, majuscule initiale, chiffre ajouté.
    pub separator: char,
    pub capitalize: bool,
    pub add_number: bool,
}

impl Default for Options {
    fn default() -> Self {
        Options {
            mode: Mode::Password,
            length: 20,
            upper: true,
            lower: true,
            digits: true,
            symbols: true,
            avoid_ambiguous: false,
            separator: '-',
            capitalize: true,
            add_number: true,
        }
    }
}

pub const SEPARATORS: [char; 5] = ['-', '.', '_', ' ', '/'];

impl Options {
    /// Les classes de caractères choisies (au moins les minuscules si aucune ne l'est).
    pub fn classes(&self) -> Vec<Vec<char>> {
        let keep = |set: &str| -> Vec<char> {
            set.chars()
                .filter(|c| !self.avoid_ambiguous || !AMBIGUOUS.contains(*c))
                .collect()
        };
        let mut classes = Vec::new();
        if self.lower {
            classes.push(keep(LOWER));
        }
        if self.upper {
            classes.push(keep(UPPER));
        }
        if self.digits {
            classes.push(keep(DIGITS));
        }
        if self.symbols {
            classes.push(keep(SYMBOLS));
        }
        if classes.is_empty() {
            classes.push(keep(LOWER));
        }
        classes
    }

    /// La longueur, ramenée dans les bornes du mode.
    pub fn clamped(&self) -> u32 {
        let (min, max, _) = self.mode.range();
        self.length.clamp(min, max)
    }

    /// L'entropie, en bits, de ce que ces options produisent.
    pub fn entropy(&self) -> f64 {
        let n = f64::from(self.clamped());
        match self.mode {
            Mode::Password => {
                let pool: usize = self.classes().iter().map(Vec::len).sum();
                n * (pool as f64).log2()
            }
            Mode::Passphrase => {
                let per_word = (words().len() as f64).log2();
                n * per_word + if self.add_number { 10f64.log2() } else { 0.0 }
            }
            Mode::Pin => n * 10f64.log2(),
        }
    }
}

/// Génère un secret selon `options`.
pub fn generate(options: &Options, rng: &mut impl Rng) -> String {
    match options.mode {
        Mode::Password => password(options, rng),
        Mode::Passphrase => passphrase(options, rng),
        Mode::Pin => (0..options.clamped())
            .map(|_| char::from(b'0' + rng.below(10) as u8))
            .collect(),
    }
}

fn pick<T: Copy>(items: &[T], rng: &mut impl Rng) -> T {
    items[rng.below(items.len() as u32) as usize]
}

fn password(options: &Options, rng: &mut impl Rng) -> String {
    let classes = options.classes();
    let pool: Vec<char> = classes.iter().flatten().copied().collect();
    let n = options.clamped() as usize;
    // Un caractère de chaque classe d'abord (si la longueur le permet), puis le reste
    // dans l'ensemble, et un mélange de Fisher-Yates pour que leur place ne dise rien.
    let mut out: Vec<char> = classes
        .iter()
        .take(n)
        .map(|class| pick(class, rng))
        .collect();
    while out.len() < n {
        out.push(pick(&pool, rng));
    }
    for i in (1..out.len()).rev() {
        let j = rng.below(i as u32 + 1) as usize;
        out.swap(i, j);
    }
    out.into_iter().collect()
}

fn passphrase(options: &Options, rng: &mut impl Rng) -> String {
    let list = words();
    let n = options.clamped() as usize;
    let mut parts: Vec<String> = (0..n)
        .map(|_| {
            let word = pick(&list, rng);
            if options.capitalize {
                let mut chars = word.chars();
                chars
                    .next()
                    .map(|c| c.to_uppercase().chain(chars).collect())
                    .unwrap_or_default()
            } else {
                word.to_owned()
            }
        })
        .collect();
    if options.add_number {
        let i = rng.below(n as u32) as usize;
        parts[i].push(char::from(b'0' + rng.below(10) as u8));
    }
    parts.join(&options.separator.to_string())
}

// ----- Robustesse ---------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    VeryWeak,
    Weak,
    Fair,
    Strong,
    Excellent,
}

impl Level {
    /// Les seuils, en bits, communs au site et à l'application.
    pub fn of(bits: f64) -> Level {
        match bits {
            b if b < 28.0 => Level::VeryWeak,
            b if b < 36.0 => Level::Weak,
            b if b < 60.0 => Level::Fair,
            b if b < 128.0 => Level::Strong,
            _ => Level::Excellent,
        }
    }

    /// 1 à 5, pour les barres et les classes CSS.
    pub fn rank(self) -> u8 {
        self as u8 + 1
    }
}

/// Le résultat de l'analyse d'un mot de passe saisi.
#[derive(Clone, Debug, PartialEq)]
pub struct Analysis {
    pub bits: f64,
    pub level: Level,
    pub length: usize,
    pub has_lower: bool,
    pub has_upper: bool,
    pub has_digit: bool,
    pub has_symbol: bool,
    /// Un mot de passe de la liste des plus courants.
    pub common: bool,
    /// Des suites (`abc`, `123`, `azerty`…) ou des répétitions (`aaa`).
    pub patterns: bool,
}

/// Les mots de passe les plus utilisés : trouvés en premier par tout attaquant.
pub const COMMON: [&str; 50] = [
    "123456",
    "123456789",
    "12345678",
    "password",
    "qwerty",
    "azerty",
    "123123",
    "111111",
    "1234567",
    "12345",
    "1234567890",
    "000000",
    "abc123",
    "password1",
    "iloveyou",
    "admin",
    "welcome",
    "monkey",
    "dragon",
    "football",
    "letmein",
    "sunshine",
    "princess",
    "master",
    "soleil",
    "doudou",
    "chouchou",
    "loulou",
    "marseille",
    "motdepasse",
    "bonjour",
    "jetaime",
    "nicolas",
    "camille",
    "qwertyuiop",
    "azertyuiop",
    "654321",
    "666666",
    "121212",
    "7777777",
    "987654321",
    "superman",
    "batman",
    "trustno1",
    "starwars",
    "passw0rd",
    "hello123",
    "freedom",
    "whatever",
    "shadow",
];

const SEQUENCES: [&str; 6] = [
    "abcdefghijklmnopqrstuvwxyz",
    "0123456789",
    "qwertyuiop",
    "azertyuiop",
    "asdfghjkl",
    "zxcvbnm",
];

/// Analyse un mot de passe, entièrement dans le navigateur.
pub fn analyze(password: &str) -> Analysis {
    let chars: Vec<char> = password.chars().collect();
    let length = chars.len();
    let has_lower = chars.iter().any(char::is_ascii_lowercase);
    let has_upper = chars.iter().any(char::is_ascii_uppercase);
    let has_digit = chars.iter().any(char::is_ascii_digit);
    let has_symbol = chars.iter().any(|c| !c.is_ascii_alphanumeric());
    let lowered = password.to_lowercase();
    let common = COMMON.contains(&lowered.as_str());

    let mut pool = 0u32;
    if has_lower {
        pool += 26;
    }
    if has_upper {
        pool += 26;
    }
    if has_digit {
        pool += 10;
    }
    if has_symbol {
        pool += 33;
    }

    // Chaque caractère qui prolonge une répétition ou une suite ne compte que pour un
    // quart : `aaaa` ou `1234` ne valent guère plus que leur premier caractère.
    let mut weak = 0usize;
    let lower: Vec<char> = lowered.chars().collect();
    for i in 1..lower.len() {
        let repeated = lower[i] == lower[i - 1];
        let sequence = SEQUENCES.iter().any(|s| {
            let pair: String = [lower[i - 1], lower[i]].iter().collect();
            let rev: String = [lower[i], lower[i - 1]].iter().collect();
            s.contains(&pair) || s.contains(&rev)
        });
        if repeated || sequence {
            weak += 1;
        }
    }
    let patterns = length >= 3 && weak * 2 >= length;
    let effective = (length - weak) as f64 + weak as f64 * 0.25;
    let mut bits = if pool == 0 {
        0.0
    } else {
        effective * f64::from(pool).log2()
    };
    if common {
        bits = bits.min(4.0);
    }
    Analysis {
        bits,
        level: Level::of(bits),
        length,
        has_lower,
        has_upper,
        has_digit,
        has_symbol,
        common,
        patterns,
    }
}

/// Le temps moyen pour trouver un secret de `bits` bits à 10¹¹ essais par seconde
/// (une attaque hors ligne avec du matériel dédié), en secondes.
pub fn crack_seconds(bits: f64) -> f64 {
    2f64.powf(bits - 1.0) / 1e11
}

#[cfg(test)]
mod tests {
    use super::*;

    fn opts(mode: Mode, length: u32) -> Options {
        Options {
            mode,
            length,
            ..Options::default()
        }
    }

    #[test]
    fn the_word_list_has_1024_unique_words() {
        let list = words();
        assert_eq!(list.len(), 1024);
        let mut sorted = list.clone();
        sorted.sort_unstable();
        sorted.dedup();
        assert_eq!(sorted.len(), 1024);
        assert!(
            list.iter()
                .all(|w| w.chars().all(|c| c.is_ascii_lowercase()))
        );
    }

    #[test]
    fn passwords_have_the_length_and_every_class() {
        let mut rng = Xorshift(42);
        for length in [4, 12, 20, 64, 128] {
            for _ in 0..50 {
                let p = generate(&opts(Mode::Password, length), &mut rng);
                assert_eq!(p.chars().count(), length as usize);
                assert!(p.chars().any(|c| c.is_ascii_lowercase()));
                assert!(p.chars().any(|c| c.is_ascii_uppercase()));
                assert!(p.chars().any(|c| c.is_ascii_digit()));
                assert!(p.chars().any(|c| SYMBOLS.contains(c)));
            }
        }
    }

    #[test]
    fn ambiguous_characters_can_be_excluded() {
        let mut rng = Xorshift(7);
        let o = Options {
            avoid_ambiguous: true,
            length: 128,
            ..Options::default()
        };
        for _ in 0..50 {
            assert!(
                !generate(&o, &mut rng)
                    .chars()
                    .any(|c| AMBIGUOUS.contains(c))
            );
        }
    }

    #[test]
    fn lengths_are_clamped() {
        let mut rng = Xorshift(1);
        assert_eq!(generate(&opts(Mode::Password, 1), &mut rng).len(), 4);
        assert_eq!(generate(&opts(Mode::Password, 999), &mut rng).len(), 128);
        assert_eq!(generate(&opts(Mode::Pin, 2), &mut rng).len(), 4);
    }

    #[test]
    fn long_passphrases_reach_excellent() {
        // 20 mots au plus : assez pour « Excellente » (128 bits et plus) ; au-delà, borné.
        let mut o = opts(Mode::Passphrase, 20);
        assert_eq!(o.clamped(), 20);
        assert!(o.entropy() >= 128.0, "{}", o.entropy());
        assert_eq!(Level::of(o.entropy()), Level::Excellent);
        let phrase = generate(&o, &mut Xorshift(7));
        assert_eq!(phrase.split(o.separator).count(), 20);
        o.length = 99;
        assert_eq!(o.clamped(), 20);
    }

    #[test]
    fn passphrases_and_pins() {
        let mut rng = Xorshift(99);
        let o = Options {
            mode: Mode::Passphrase,
            length: 6,
            separator: '.',
            ..Options::default()
        };
        let phrase = generate(&o, &mut rng);
        let parts: Vec<&str> = phrase.split('.').collect();
        assert_eq!(parts.len(), 6);
        assert!(
            parts
                .iter()
                .all(|w| w.chars().next().unwrap().is_uppercase())
        );
        assert_eq!(phrase.chars().filter(char::is_ascii_digit).count(), 1);
        let pin = generate(&opts(Mode::Pin, 8), &mut rng);
        assert_eq!(pin.len(), 8);
        assert!(pin.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn entropy_and_levels() {
        let pw = opts(Mode::Password, 20);
        // 26 + 26 + 10 + 24 = 86 symboles, 20 caractères.
        assert!((pw.entropy() - 20.0 * 86f64.log2()).abs() < 1e-9);
        assert_eq!(Level::of(pw.entropy()), Level::Excellent);
        let phrase = Options {
            mode: Mode::Passphrase,
            length: 5,
            add_number: false,
            ..Options::default()
        };
        assert!((phrase.entropy() - 50.0).abs() < 1e-9);
        assert_eq!(Level::of(phrase.entropy()), Level::Fair);
        assert_eq!(Level::of(opts(Mode::Pin, 6).entropy()), Level::VeryWeak);
        assert_eq!(Level::of(27.9), Level::VeryWeak);
        assert_eq!(Level::of(35.0), Level::Weak);
        assert_eq!(Level::of(100.0), Level::Strong);
    }

    #[test]
    fn analysis_spots_weak_passwords() {
        let common = analyze("Azerty");
        assert!(common.common);
        assert_eq!(common.level, Level::VeryWeak);
        assert!(analyze("aaaaaaaa").patterns);
        assert!(analyze("abcd1234").patterns);
        let strong = analyze("Tg7#qP!m2Lz@Wv9$");
        assert!(!strong.patterns && !strong.common);
        assert!(strong.level >= Level::Strong);
        assert_eq!(analyze("").bits, 0.0);
    }

    #[test]
    fn the_random_draw_is_unbiased_enough() {
        let mut rng = Xorshift(5);
        let mut counts = [0u32; 10];
        for _ in 0..100_000 {
            counts[rng.below(10) as usize] += 1;
        }
        assert!(counts.iter().all(|&c| (9_000..11_000).contains(&c)));
    }

    #[test]
    fn crack_time_grows_with_the_bits() {
        assert!(crack_seconds(40.0) < 10.0);
        assert!(crack_seconds(128.0) > 1e20);
    }
}
