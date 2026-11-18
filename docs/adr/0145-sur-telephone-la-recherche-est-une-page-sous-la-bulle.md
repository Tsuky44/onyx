# ADR-0145 — Sur téléphone, la recherche est une page sous la bulle de la barre d'onglets

- **Statut :** accepté. Testé en widget (`phone_search_screen_test.dart`,
  `search_unavailable_shelf_test.dart`, `phone_tab_bar_test.dart`). **Pas encore regardé sur un vrai
  téléphone.**
- **Date :** 2026-11-18
- **Portée :** `app/lib/screens/search/phone/` (`PhoneSearchScreen`, `PhoneSearchRow`),
  `screens/shell/phone_search.dart` (`PhoneSearchSession`, qui ouvre la page), et ce que le
  téléphone partage désormais avec le bureau : `search_layout.dart` (`SearchFilter`,
  `SearchLayout`, `SearchHit`), `search_chips.dart`, `recent_searches.dart`. Remplace
  `SearchResultsScreen` (y compris son mode `docked` de l'ADR-0142) et `InlineCatalogSearch`,
  retirés ; `GlassCatalogSearch` ne sert plus qu'au téléviseur.
- **Complète** l'[ADR-0142](0142-la-barre-d-onglets-du-telephone-est-une-capsule-de-verre.md) :
  elle garde le dessin (le rond qui s'étire en bulle au-dessus du clavier), celle-ci décide de ce
  que montre la page derrière la bulle.

## Contexte

Retour d'usage : « la recherche sur téléphone est super mal gérée ». À côté du bureau (ADR-0139) et
du téléviseur (ADR-0126), le téléphone avait la recherche la plus pauvre :

- **Un champ coincé** dans la barre du haut, entre le logo, le bouton de téléchargement et le compte.
- **Deux champs.** Au premier caractère, la frappe passait au champ d'une autre page
  (`SearchResultsScreen`). Le passage était fragile : il fallait vider le premier champ et garder le
  clavier ouvert pendant que le focus changeait de page.
- **Vider le champ refermait la page.** Effacer sa recherche pour corriger une faute renvoyait en
  arrière.
- **Rien avant de taper**, alors que le bureau propose les recherches récentes et les derniers ajouts.
- **Pas de filtres**, alors que le bureau a les pastilles Tout, Films, Séries, Pas sur le serveur.
- **Une grille d'affiches sans titre**, à trois colonnes : deux « Dune » se distinguaient mal, et le
  clavier n'en laissait voir qu'une rangée, sans se baisser quand on faisait défiler.

## Décision

1. **Le rond de la barre d'onglets ouvre la page de recherche** (`PhoneSearchScreen`), derrière la
   bulle qui s'étire (ADR-0142). Le champ est celui de la bulle, le seul à l'écran ; la page lit sa
   frappe (`PhoneSearchSession.controller`). La croix de la bulle ou le geste retour referment la
   page ; vider le champ la garde ouverte.
2. **`PhoneSearchSession.open` est la seule porte d'entrée.** Une page déjà ouverte ne s'empile pas
   une seconde fois ; touché depuis une fiche ouverte des résultats, le rond y ramène. La loupe un
   temps posée dans la barre du haut est retirée : la barre du haut est celle de l'ADR-0144.
3. **Rien de tapé** : les recherches récentes (les mêmes que celles du bureau, par profil et par
   serveur), puis les derniers ajouts.
4. **Les résultats sont des lignes** (`PhoneSearchRow`) : une vignette d'affiche, le titre, l'année et
   le type, la progression d'un film en cours, la pastille « vu » ou « Indispo ». Une ligne se lit
   d'un coup d'œil, et cinq tiennent au-dessus du clavier. Toucher une ligne ouvre la fiche par
   l'envol de la vignette.
5. **Les pastilles sont celles du bureau**, sur une seule ligne qui défile. Une nouvelle frappe repart
   de « Tout ».
6. **Faire défiler baisse le clavier**, et « Rechercher » sur le clavier aussi.
7. **Le contenu reste rangé par `SearchShelves`** (ADR-0129) : la bibliothèque d'abord, puis les titres
   absents du serveur, voilés.

Le rangement par pastille, les pastilles elles-mêmes et l'historique quittent `screens/search/desktop/`
pour `screens/search/`, sous des noms sans « Desktop ». Le bureau n'y perd rien : ses pastilles
enveloppent `SearchFilterChips`, et sa sélection au clavier (`stepSelection`) reste à lui.
L'historique garde sa clé de préférences (`desktop_recent_searches/`), pour que celui déjà retenu sur
le bureau ne se perde pas.

## Conséquences

- La barre du haut du téléphone ne contient plus de champ ni de loupe (ADR-0144).
- La page s'ouvre en fondu sous la bulle, la transition de l'ADR-0142.
- Avant la frappe, la page reprend le titre « Rechercher » de l'ADR-0142, puis les recherches
  récentes et les derniers ajouts.
- Changer ce qu'affiche une recherche se fait à quatre endroits : `SearchShelves` pour le contenu, puis
  `TvSearchScreen`, `PhoneSearchScreen` et `DesktopSearchSheet` pour Flutter, et
  `tvos/Runner/SystemSearch*.swift` pour l'Apple TV.
- `SearchProvider` ne sert plus qu'au bureau.
- Pas encore fait : basculer en grille depuis la page, et appuyer longuement sur une ligne pour lancer
  un film. On les ajoutera si l'usage les réclame.
