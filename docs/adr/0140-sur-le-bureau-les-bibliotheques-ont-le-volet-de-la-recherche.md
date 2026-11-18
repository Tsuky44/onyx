# ADR-0140 — Sur le bureau, les bibliothèques ont le volet de la recherche

- **Statut :** accepté. Testé en widget (`library_desktop_spotlight_test.dart`). **Pas encore
  regardé dans l'app lancée sous Windows.**
- **Date :** 2026-11-18
- **Portée :** les onglets de bibliothèque (Films, Séries…) hors téléviseur, à partir de 1100 px de
  large et hors gabarit compact. `app/lib/screens/library/library_screen.dart`,
  `app/lib/screens/library/widgets/library_desktop_spotlight.dart`, `librarySpotlightEyebrow`
  (sorti de `desktop_search_spotlight.dart`). Le téléphone garde sa grille ; le téléviseur garde
  `LibraryTvView` (ADR-0125).

## Contexte

La recherche du bureau (ADR-0139) pose à gauche la fiche du titre survolé : image de fond, logo ou
titre, métadonnées et résumé (`LibrarySpotlight`). L'utilisateur l'aime et a demandé la même vue
dans les onglets Films et Séries, qui ne montraient qu'une grille d'affiches pleine largeur.

## Décision

- `LibraryScreen` enveloppe sa grille dans `LibraryDesktopSpotlight` quand la page fait au moins
  `LibraryDesktopSpotlight.minWidth` (1100 px, le seuil de la recherche), hors gabarit compact,
  catalogue chargé et non vide. En dessous, la page est inchangée.
- Le volet présente la première affiche, puis la dernière que le pointeur survole ou que le focus
  du clavier atteint (`LibrarySpotlightTarget`, un `ValueNotifier` : survoler ne redessine que la
  fiche). Il est `IgnorePointer` : la grille déborde sur son image.
- La grille garde son en-tête (nom, décompte, tri) et son défilement ; elle commence simplement
  après le volet. Les cartes perdent leur cartouche (`showDetails: false`), que le volet dit déjà.
- Le surtitre est celui de la recherche (type, « Vu » ou temps restant) : un seul helper,
  `librarySpotlightEyebrow`.

## Conséquences

- Le volet prend ~420 px : à 1100 px de large, la grille perd environ trois colonnes.
- Passer le seuil en redimensionnant la fenêtre remonte la grille en haut (le `CustomScrollView`
  change de parent). Accepté : rare, et la recherche n'a pas ce cas parce qu'elle garde une pile
  fixe ; à reprendre de la même façon si cela gêne.
