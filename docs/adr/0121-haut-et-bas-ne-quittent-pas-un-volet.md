# ADR-0121 — Haut et bas ne quittent pas un volet

- **Statut :** accepté. Reproduit puis épinglé par un test sur les deux systèmes de navigation ; signalé
  par l'utilisateur sur une vraie Apple TV (version 1.1.42).
- **Date :** 2026-11-12
- **Portée :** `tv/tv_focus_panes.dart` (`TvFocusPanes.moveWithinPane`, `admits`, `boundaryOf`),
  `tv/tv_focus_entry.dart` (`TvFocusEntries.requestFocus`), `tv/tv_key_repeat.dart`
  (`TvDirectionalFocusAction`), `tv/nav/tv_pane_region.dart` (dpad).
- **Prolonge** l'[ADR-0109](0109-le-focus-tv-entre-une-fois-ou-la-zone-le-decide.md), qui notait qu'un
  `FocusTraversalGroup` ne confine pas le parcours directionnel et écartait un `FocusScope` par zone.

## Contexte

Les réglages d'un téléviseur ont deux volets : la liste des catégories à gauche, la page de la
catégorie à droite. Survoler une catégorie l'ouvre. Retour de l'utilisateur : « quand je suis dans un
menu et que je descends, ça descend dans les autres menus ».

Le parcours directionnel de Flutter cherche dans tout l'écran. En bas d'une page, plus rien ne suit
dans le volet ; il prend alors ce qu'il trouve plus bas ailleurs : une catégorie de la liste, à gauche,
qui s'ouvre aussitôt qu'elle a le focus. On descendait dans « Serveurs » et l'on se retrouvait dans une
autre catégorie. Le défaut ne se voit que là où la liste descend plus bas que la page, donc sur une
page courte et à la taille d'un téléviseur (1280 × 720) ; les cartes de navigation existantes
tournaient en 1920 × 1080 et ne le voyaient pas. Sous dpad, le volet avait `verticalEdge: leave` et
faisait de même.

## Décision

**Dans un volet, haut et bas n'en sortent pas ; seules gauche et droite passent de l'un à l'autre.**

- Ancien système (celui qui est livré) : `TvDirectionalFocusAction` fait son déplacement vertical par
  `TvFocusPanes.moveWithinPane`. Pendant ce déplacement, `TvFocusEntries.requestFocus`, par où passe
  toute demande de focus du parcours, refuse une cible hors du volet de départ (`admits`). Le focus
  reste où il est, et la page défile s'il lui reste du contenu (`TvFocusScroll.scrollPast`), comme
  avant.
- dpad : `TvPaneRegion` passe à `verticalEdge: DpadEdgeBehavior.stop`.

Écarté : un `FocusScope` par volet. Il confinerait aussi gauche et droite, que `TvFocusPanes.next`
fait passer exprès d'un volet à l'autre.

## Conséquences

- Hors d'un volet, rien ne change : les rangées de l'accueil, les fiches et l'en-tête gardent leur
  parcours.
- Les volets ne servent aujourd'hui qu'aux réglages. Un écran qui en poserait sous un en-tête
  atteignable par Haut devrait le rendre atteignable autrement.
- Épinglé par `test/settings_navigation_map_test.dart` (trois cas, à la taille d'un téléviseur).
