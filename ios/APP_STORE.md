# KeyForge sur l'App Store : tout ce qu'il faut remplir

Textes prêts à copier dans App Store Connect. Les limites de caractères d'Apple sont
indiquées entre parenthèses.

## Informations de l'app

| Champ | Valeur |
|---|---|
| Nom (30) | `KeyForge` |
| Sous-titre (30) | `Mots de passe incassables` |
| Identifiant de bundle | `com.maxlestage.KeyForge` (extension : `com.maxlestage.KeyForge.AutoFill`) |
| Langue principale | Français |
| Catégorie principale | Utilitaires |
| Catégorie secondaire | Productivité |
| Copyright | `© 2026 Maxime Nathan Lestage` |
| URL d'assistance | `https://maxlestage.github.io/KEYFORGE/fr/aide/` |
| URL marketing | `https://maxlestage.github.io/KEYFORGE/fr/` |
| Politique de confidentialité | `https://maxlestage.github.io/KEYFORGE/fr/confidentialite/` |

**Mots-clés (100)**

```
mot de passe,générateur,coffre,phrase de passe,code PIN,Face ID,remplissage,chiffrement,sécurité
```

**Texte promotionnel (170)**

```
Nouveau : vos identifiants KeyForge proposés au-dessus du clavier dans Safari et vos apps, après Face ID. Et des phrases de passe jusqu'à 20 mots.
```

**Description (4 000)**

```
KeyForge forge des clés incassables : mots de passe, phrases de passe et codes PIN impossibles à deviner, rangés dans un coffre protégé par Face ID. Sans compte, sans serveur, sans publicité, sans traceur : rien ne quitte votre iPhone sans votre accord.

FORGEZ
• Mots de passe de 4 à 128 caractères : majuscules, minuscules, chiffres, symboles, sans caractères ambigus si vous le souhaitez.
• Phrases de passe de 3 à 20 mots, faciles à retenir et jusqu'à plus de 200 bits d'entropie.
• Codes PIN de 4 à 12 chiffres.
• Charabia : jusqu'à 128 caractères illisibles, symboles et Unicode compris (é, ß, λ, Ω, €, §…).
• Pour chaque secret : robustesse, entropie en bits et temps estimé pour le casser.
• Le hasard est celui de Brocolis 🥦 : le générateur cryptographique de l'iPhone.

PROTÉGEZ
• Un coffre pour vos identifiants (site, identifiant, mot de passe, notes, favoris), chiffré par Brocolis 🥦 (AES-256-GCM, clé de 256 bits propre au coffre) et jamais synchronisé ailleurs.
• La clé du coffre est gardée par la Secure Enclave, la puce de sécurité de l'iPhone : elle n'est libérée qu'après Face ID, Touch ID ou le code.
• Déverrouillé par Face ID, Touch ID ou le code, verrouillé dès que l'app passe en arrière-plan.
• Presse-papiers effacé automatiquement, aperçu masqué dans le sélecteur d'apps.

REMPLISSEZ
• Activez KeyForge dans Réglages → Général → Remplissage automatique et mots de passe : vos identifiants sont proposés au-dessus du clavier dans Safari et vos apps.
• Chaque mot de passe n'est rempli qu'après Face ID.
• Codes de validation (2FA) : scannez le QR code du site, KeyForge calcule le code à 6 chiffres et le propose au-dessus du clavier (iOS 18 et plus récent).
• Sur iOS 18 et plus récent, insérez un secret tout juste forgé dans n'importe quel champ.
• Sur iOS 26.2 et plus récent, iOS propose d'enregistrer vos nouveaux identifiants directement dans KeyForge.
• Sur iOS 26, transférez votre coffre vers l'app Mots de passe d'Apple en un geste.

PARTAGEZ EN TOUTE CONFIANCE
• Envoyez un secret chiffré en post-quantique (protocole Brocolis v4 : X25519 + ML-KEM-768) : il reste protégé même face à un futur ordinateur quantique.
• Sauvegardez votre coffre dans un fichier chiffré par une phrase que vous seul connaissez.

VÉRIFIEZ
• Analysez vos anciens mots de passe : longueur, familles de caractères, suites, rangées du clavier, mots de passe trop courants.

KeyForge ne contient aucun code réseau et ne collecte aucune donnée. Son code est public.
```

**Nouveautés de cette version (4 000)**

```
Première version de KeyForge : générateur, coffre protégé par Face ID, remplissage automatique dans Safari et vos apps, transfert vers l'app Mots de passe (iOS 26), partage chiffré en post-quantique et sauvegarde chiffrée.
```

## Confidentialité de l'app (étiquette « Confidentialité »)

- *Collectez-vous des données à partir de cette app ?* → **Non, nous ne collectons pas de
  données à partir de cette app.**
- Résultat affiché : **Données non collectées**.

Le manifeste de confidentialité (`PrivacyInfo.xcprivacy`, app et extension) le déclare
aussi : aucun suivi, aucun domaine de suivi, aucune donnée collectée.

## Classification par âge

Répondez **Aucun** / **Non** à toutes les questions (violence, contenu pour adultes, jeux
d'argent, accès web non restreint, contenus générés par les utilisateurs, etc.).
Classification obtenue : **4+**.

## Conformité au chiffrement (Export Compliance)

Faits techniques (ce n'est pas un avis juridique ; vérifiez auprès d'Apple et, pour la
France, de l'ANSSI) :

- KeyForge utilise du chiffrement : **oui**.
- Algorithmes **standard** uniquement : AES-256-GCM, X25519, Ed25519 (CryptoKit d'Apple),
  ML-KEM-768 (FIPS 203), Argon2id (RFC 9106), SHA-256, SHA-3, HKDF.
- Certains sont implémentés dans l'app (ML-KEM, Argon2id, SHA-3), en plus de ceux du système.
- Usage : protéger les secrets de l'utilisateur (coffre, sauvegarde, partage chiffré
  choisi par l'utilisateur). Pas de service de communication, aucun code réseau.

## Vérification par Apple (App Review)

- **Connexion requise** : non (aucun compte).
- **Notes**

```
No account or sign-in: KeyForge works entirely offline on the device.

- The vault is stored in the iOS Keychain (ThisDeviceOnly) and unlocked with Face ID / Touch ID / passcode. On a device without a passcode, it opens directly.
- AutoFill: enable KeyForge in Settings > General > AutoFill & Passwords. Saved logins are then suggested in Safari; Face ID is required before any password is filled.
- "Transfer to Passwords" (iOS 26 only) uses the system Credential Exchange sheet, only on user request.
- The app makes no network requests; post-quantum encryption (X25519 + ML-KEM-768) is used only to protect secrets the user chooses to share or back up.
```

## TestFlight

- **Description de l'app bêta** : reprendre les paragraphes « Forgez » à « Vérifiez »
  ci-dessus.
- **Quoi tester**

```
Merci de tester KeyForge ! Points à vérifier en priorité :

1. Générateur : changez de mode, de longueur et d'options. Une phrase de 13 mots ou plus doit atteindre « Excellente ».
2. Coffre : enregistrez un identifiant avec un site web (ex. github.com), passez l'app en arrière-plan puis rouvrez-la avec Face ID.
3. Remplissage automatique : Réglages → Général → Remplissage automatique et mots de passe → activez KeyForge. Dans Safari, sur la page de connexion du site enregistré, l'identifiant est proposé au-dessus du clavier ; Face ID est demandé avant de remplir. Sur iOS 18+ : Remplissage automatique → Mots de passe → KeyForge → « Insérer ».
4. iOS 26 : KeyForge → Réglages → iPhone et Mots de passe → « Transférer vers l'app Mots de passe ».
5. Sauvegarde chiffrée : exportez puis réimportez le coffre avec une phrase.

Signalez tout plantage ou écran incohérent avec une capture (bouton Commentaires de TestFlight). N'utilisez pas vos vrais mots de passe pendant la bêta.
```

## Captures d'écran

App Store Connect exige au moins les captures **iPhone 6,9 pouces** (1320 × 2868 ou
1290 × 2796) et, l'app étant aussi pour iPad, **iPad 13 pouces** (2064 × 2752). Écrans
conseillés : générateur, coffre, remplissage automatique dans Safari, analyse, partage
chiffré.
