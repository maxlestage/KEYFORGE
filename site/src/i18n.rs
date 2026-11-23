//! Les deux langues du site. Les textes sont écrits côte à côte, en français puis en
//! anglais, là où ils sont utilisés : `lang.t("Bonjour", "Hello")`.

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Lang {
    Fr,
    En,
}

impl Lang {
    pub const ALL: [Lang; 2] = [Lang::Fr, Lang::En];

    pub fn code(self) -> &'static str {
        match self {
            Lang::Fr => "fr",
            Lang::En => "en",
        }
    }

    pub fn parse(code: &str) -> Option<Lang> {
        match code {
            "fr" => Some(Lang::Fr),
            "en" => Some(Lang::En),
            _ => None,
        }
    }

    /// Le nom de la langue, dans cette langue.
    pub fn name(self) -> &'static str {
        match self {
            Lang::Fr => "Français",
            Lang::En => "English",
        }
    }

    pub fn locale(self) -> &'static str {
        match self {
            Lang::Fr => "fr_FR",
            Lang::En => "en_US",
        }
    }

    pub fn other(self) -> Lang {
        match self {
            Lang::Fr => Lang::En,
            Lang::En => Lang::Fr,
        }
    }

    /// Le texte de cette langue.
    pub fn t(self, fr: &'static str, en: &'static str) -> &'static str {
        match self {
            Lang::Fr => fr,
            Lang::En => en,
        }
    }
}

/// La langue préférée d'après `Accept-Language` (le français par défaut).
pub fn pick_lang(accept: &str) -> Lang {
    let mut best = (Lang::Fr, -1.0f32);
    for part in accept.split(',') {
        let mut it = part.trim().split(';');
        let tag = it.next().unwrap_or("").trim().to_ascii_lowercase();
        let q = it
            .find_map(|p| p.trim().strip_prefix("q=").and_then(|q| q.parse().ok()))
            .unwrap_or(1.0);
        let primary = tag.split('-').next().unwrap_or("");
        if let Some(lang) = Lang::parse(primary)
            && q > best.1
        {
            best = (lang, q);
        }
    }
    best.0
}

/// Un nombre avec les séparateurs de milliers de la langue.
pub fn number(lang: Lang, value: f64, decimals: usize) -> String {
    let s = format!("{value:.decimals$}");
    let (int, frac) = s
        .split_once('.')
        .map_or((s.as_str(), None), |(i, f)| (i, Some(f)));
    let (sign, digits) = int.strip_prefix('-').map_or(("", int), |d| ("-", d));
    let sep = lang.t("\u{202f}", ",");
    let mut grouped = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i) % 3 == 0 {
            grouped.push_str(sep);
        }
        grouped.push(c);
    }
    match frac {
        Some(f) => format!("{sign}{grouped}{}{f}", lang.t(",", ".")),
        None => format!("{sign}{grouped}"),
    }
}

/// Une durée lisible : « instantané », « 3 heures », « 12 siècles »…
pub fn duration(lang: Lang, seconds: f64) -> String {
    const MINUTE: f64 = 60.0;
    const HOUR: f64 = 3600.0;
    const DAY: f64 = 86_400.0;
    const YEAR: f64 = 31_557_600.0;
    let units: [(f64, &str, &str, &str, &str); 8] = [
        (1.0, "seconde", "secondes", "second", "seconds"),
        (MINUTE, "minute", "minutes", "minute", "minutes"),
        (HOUR, "heure", "heures", "hour", "hours"),
        (DAY, "jour", "jours", "day", "days"),
        (YEAR, "an", "ans", "year", "years"),
        (YEAR * 100.0, "siècle", "siècles", "century", "centuries"),
        (
            YEAR * 1e6,
            "million d'années",
            "millions d'années",
            "million years",
            "million years",
        ),
        (
            YEAR * 1e9,
            "milliard d'années",
            "milliards d'années",
            "billion years",
            "billion years",
        ),
    ];
    // L'âge de l'Univers : environ 13,8 milliards d'années.
    if !seconds.is_finite() || seconds > YEAR * 13.8e9 {
        return lang
            .t(
                "plus que l'âge de l'Univers",
                "longer than the age of the Universe",
            )
            .into();
    }
    if seconds < 1.0 {
        return lang.t("instantané", "instant").into();
    }
    let (unit, one, many, one_en, many_en) = units
        .iter()
        .rev()
        .find(|(u, ..)| seconds >= *u)
        .copied()
        .unwrap_or(units[0]);
    let n = (seconds / unit).floor();
    let word = match (lang, n < 2.0) {
        (Lang::Fr, true) => one,
        (Lang::Fr, false) => many,
        (Lang::En, true) => one_en,
        (Lang::En, false) => many_en,
    };
    format!("{} {word}", number(lang, n, 0))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn languages_from_the_browser() {
        assert_eq!(pick_lang("en-US,en;q=0.9"), Lang::En);
        assert_eq!(pick_lang("de-DE,fr;q=0.8,en;q=0.5"), Lang::Fr);
        assert_eq!(pick_lang(""), Lang::Fr);
    }

    #[test]
    fn numbers_and_durations() {
        assert_eq!(number(Lang::En, 1024.0, 0), "1,024");
        assert_eq!(number(Lang::Fr, 1234567.5, 1), "1\u{202f}234\u{202f}567,5");
        assert_eq!(duration(Lang::Fr, 0.2), "instantané");
        assert_eq!(duration(Lang::Fr, 7200.0), "2 heures");
        assert_eq!(duration(Lang::En, 90.0), "1 minute");
        assert_eq!(duration(Lang::Fr, 1e40), "plus que l'âge de l'Univers");
        assert_eq!(
            duration(Lang::Fr, 31_557_600.0 * 3e9),
            "3 milliards d'années"
        );
    }
}
