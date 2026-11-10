# ADR-0113 — Changer de rangée ramène à sa première carte

- **Statut :** accepté
- **Date :** 2026-11-10
- **Portée :** l'entrée dans une `TvRegion.rail`, sous les deux systèmes de focus :
  `tv/nav/tv_rail_start.dart` (`TvRailStart`), `tv/nav/tv_rail_region.dart` (`TvRailRegion`, sous
  dpad), `TvFocusMemory.entersAtStart` (ancien système). Change la règle « une rangée rend la carte
  qu'on y avait quittée », posée par `TvFocusMemory` et reprise par l'ADR-0110 (tableau de
  `TvRegion`, ligne `rail`).

## Contexte

Une page TV est faite de zones : l'en-tête, le bandeau, « Reprendre », puis une rangée par
catégorie. En passant d'une rangée à l'autre, le focus allait sur la carte juste en dessous de celle
qu'on quittait, ou sur celle qu'on avait quittée la fois d'avant. Depuis la quatrième carte de
« Reprendre », on tombait au milieu de « Films », sans voir où la rangée commençait ni ce qu'on avait
sauté. Demande de l'utilisateur : quand on change de zone, on revient tout à gauche, à la première
carte, d'où qu'on vienne.

## Décision

1. **On entre dans une rangée (`TvRegion.rail`) par sa première carte**, la plus à gauche, quelle que
   soit la carte qu'on quitte et quelle que soit celle qu'on y avait quittée. C'est la règle par
   défaut (`entersAtStart: true`).
2. **Une rangée qu'on a fait défiler loin revient à son début.** La liste ne garde qu'un écran de
   cartes construites de part et d'autre, donc la première carte n'existe plus. La plus à gauche des
   cartes construites prend d'abord le focus. Deux images plus tard (après le défilement que la
   carte lance vers elle-même, qu'il interrompt), la rangée saute à son début et la vraie première
   carte prend le focus.
3. **La logique tient en un seul endroit**, `TvRailStart`. Sous dpad, `TvRailRegion` l'appelle dans
   `resolveEnter`, comme `TvPaneRegion` (méthode `@internal` de dpad 3.3.0, à relire à chaque
   montée de version). Sous l'ancien système, `TvFocusMemory` l'appelle dans `entryFor`.
4. **Exceptions** (`entersAtStart: false`, la mémoire reste) : les saisons d'une série, qui rendent la
   saison où l'on était, et « Qui regarde ? », une seule rangée où Haut depuis « Gérer » rend la
   personne d'où l'on venait.

## Conséquences

- On perd sa place dans une rangée en la quittant : avancer de dix cartes, descendre et remonter
  ramène au début. C'est voulu, et c'est l'inverse de ce que promettait `TvFocusMemory`.
- La mémoire des zones reste pour tout le reste : grilles, listes, volets des réglages, et le
  contenu d'un onglet (sous l'ancien système, redescendre de l'en-tête rend la carte quittée). Le
  retour d'une fiche repose le focus sur la carte ouverte, par le navigateur, pas par l'entrée de
  la rangée.
- Le retour au début d'une rangée défilée loin fait deux poses de focus, contrairement à
  l'ADR-0109 (une seule pose par flèche). Cela n'arrive qu'au-delà d'un écran de défilement.
- Épinglé par `test/tv_rail_start_test.dart` (les deux systèmes) et
  `test/shell_navigation_map_test.dart` ; les tests de la mémoire elle-même passent
  `entersAtStart: false`.
