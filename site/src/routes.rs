//! Les pages du site et leurs adresses, dans chaque langue : `/fr/`, `/fr/securite/`,
//! `/en/security/`…

use crate::i18n::Lang;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum PageKind {
    Home,
    Security,
    Guide,
    Help,
    Changelog,
    Press,
    Privacy,
    Terms,
    Legal,
    Accessibility,
    NotFound,
}

impl PageKind {
    /// Toutes les pages, sauf « introuvable ».
    pub const ALL: [PageKind; 10] = [
        PageKind::Home,
        PageKind::Security,
        PageKind::Guide,
        PageKind::Help,
        PageKind::Changelog,
        PageKind::Press,
        PageKind::Privacy,
        PageKind::Terms,
        PageKind::Legal,
        PageKind::Accessibility,
    ];

    pub fn slug(self, lang: Lang) -> &'static str {
        use PageKind::*;
        match (self, lang) {
            (Home | NotFound, _) => "",
            (Security, Lang::Fr) => "securite",
            (Security, Lang::En) => "security",
            (Guide, _) => "guide",
            (Help, Lang::Fr) => "aide",
            (Help, Lang::En) => "help",
            (Changelog, Lang::Fr) => "nouveautes",
            (Changelog, Lang::En) => "changelog",
            (Press, Lang::Fr) => "presse",
            (Press, Lang::En) => "press",
            (Privacy, Lang::Fr) => "confidentialite",
            (Privacy, Lang::En) => "privacy",
            (Terms, Lang::Fr) => "conditions",
            (Terms, Lang::En) => "terms",
            (Legal, Lang::Fr) => "mentions-legales",
            (Legal, Lang::En) => "legal",
            (Accessibility, Lang::Fr) => "accessibilite",
            (Accessibility, Lang::En) => "accessibility",
        }
    }

    /// Le nom de la page, pour les liens et les titres.
    pub fn label(self, lang: Lang) -> &'static str {
        use PageKind::*;
        match self {
            Home => lang.t("Accueil", "Home"),
            Security => lang.t("Sécurité", "Security"),
            Guide => lang.t("Guide des bons mots de passe", "Password guide"),
            Help => lang.t("Centre d'aide", "Help center"),
            Changelog => lang.t("Nouveautés", "What's new"),
            Press => lang.t("Kit presse", "Press kit"),
            Privacy => lang.t("Confidentialité", "Privacy"),
            Terms => lang.t("Conditions d'utilisation", "Terms of use"),
            Legal => lang.t("Mentions légales", "Legal notice"),
            Accessibility => lang.t("Accessibilité", "Accessibility"),
            NotFound => lang.t("Page introuvable", "Page not found"),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Route {
    pub lang: Lang,
    pub page: PageKind,
}

impl Route {
    pub fn new(lang: Lang, page: PageKind) -> Route {
        Route { lang, page }
    }

    /// `/fr/`, `/fr/securite/`.
    pub fn path(self) -> String {
        match self.page.slug(self.lang) {
            "" => format!("/{}/", self.lang.code()),
            slug => format!("/{}/{slug}/", self.lang.code()),
        }
    }

    /// La même page dans une autre langue.
    pub fn with_lang(self, lang: Lang) -> Route {
        Route { lang, ..self }
    }

    /// Lit une adresse (avec ou sans `/` final).
    pub fn parse(path: &str) -> Option<Route> {
        let mut parts = path.trim_matches('/').split('/');
        let lang = Lang::parse(parts.next()?)?;
        let slug = parts.next().unwrap_or("");
        if parts.next().is_some() {
            return Some(Route::new(lang, PageKind::NotFound));
        }
        let page = PageKind::ALL
            .into_iter()
            .find(|p| p.slug(lang) == slug)
            .unwrap_or(PageKind::NotFound);
        Some(Route::new(lang, page))
    }

    /// Toutes les pages, dans toutes les langues.
    pub fn all() -> impl Iterator<Item = Route> {
        Lang::ALL
            .into_iter()
            .flat_map(|l| PageKind::ALL.into_iter().map(move |p| Route::new(l, p)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_route_parses_back() {
        for route in Route::all() {
            assert_eq!(Route::parse(&route.path()), Some(route), "{}", route.path());
        }
        assert_eq!(Route::parse("/de/"), None);
        assert_eq!(
            Route::parse("/fr/nope/").map(|r| r.page),
            Some(PageKind::NotFound)
        );
        assert_eq!(
            Route::new(Lang::Fr, PageKind::Security)
                .with_lang(Lang::En)
                .path(),
            "/en/security/"
        );
    }
}
