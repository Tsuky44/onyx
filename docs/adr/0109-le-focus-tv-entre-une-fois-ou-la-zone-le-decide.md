# ADR-0109 — Le focus TV entre une fois, là où la zone le décide

- **Statut :** accepté. Vérifié par les tests de focus et la suite complète ; pas encore à la
  télécommande d'un vrai téléviseur ni sur le simulateur Apple TV.
- **Date :** 2026-11-06
- **Portée :** `tv/tv_focus_entry.dart` (nouveau), `tv/tv_focus_memory.dart`, `tv/tv_key_repeat.dart`,
  `screens/shell/main_shell.dart`, `main.dart`.
- **Prolonge :** [ADR-0039](0039-force-du-geste-sur-le-trackpad-de-l-apple-tv.md) (un seul défilement
  par pas). Ne contredit aucune ADR.

## Contexte

Deux mécanismes déplaçaient le focus **après** qu'il s'était posé sur l'élément trouvé par la
géométrie :

- `TvFocusMemory` réagissait à `onFocusChange` de sa zone par un second `requestFocus` vers l'élément
  mémorisé ;
- `_landOnSelectedTab`, dans le shell, faisait de même vers l'onglet affiché quand le focus entrait
  dans l'en-tête.

Chaque flèche coûtait alors deux demandes de focus et deux défilements : le premier visait l'élément
géométrique, le second l'élément voulu, à la frame suivante. C'est le saut double observé en montant
sur une rangée ou sur l'en-tête.

## Décision

La politique de parcours demande aux zones **avant** de poser le focus.

- Une zone s'inscrit sur son nœud de focus avec `TvFocusEntries.register(nœud, entrée)`. L'entrée reçoit
  l'élément que la géométrie a trouvé et celui que la télécommande quitte, et répond par l'élément à
  prendre à la place, ou nul.
- `TvTraversalPolicy` (racine) et `TvWidgetOrderTraversalPolicy` (zones qui veulent l'ordre des
  widgets) passent par `TvFocusEntries.requestFocus` : les zones qui entourent l'élément trouvé sont
  consultées de l'extérieur vers l'intérieur, puis le focus est demandé une seule fois et
  `TvFocusScroll` fait un seul défilement. Le déplacement horizontal de `TvDirectionalFocusAction`
  passe par le même point.
- `TvFocusMemory` répond l'élément mémorisé, ou le premier visible à la première visite d'une zone
  `entersAtTop`. L'en-tête du shell répond l'onglet affiché quand on y monte sur un onglet ; la
  recherche et le compte restent atteignables tels quels.
- L'en-tête a son propre `FocusTraversalGroup` (ordre des widgets). Les zones se libèrent au `dispose`.

## Conséquences

- Plus de second `requestFocus` ni de défilement vers un élément abandonné aussitôt.
- Un `FocusTraversalGroup` **ne confine pas** le parcours directionnel de Flutter : il cherche dans
  tout le `FocusScope`. Le groupe de l'en-tête fixe son ordre de tabulation, pas ses frontières ; ce
  sont les réponses d'entrée qui évitent l'hésitation entre onglets et bandeau. Un `FocusScope` par
  zone confinerait Haut/Bas et casserait le passage d'une rangée à l'autre : écarté.
- Une zone ne répond qu'au parcours aux flèches. Un `requestFocus()` direct (Retour qui rend la
  télécommande à un onglet, un `autofocus`) ne passe plus par elle, ce qui est voulu : l'appelant a
  déjà choisi son nœud.
- Restent pour la phase suivante : l'asymétrie de `TvDirectionalFocusAction` (horizontal par
  `nextOnLine`, vertical par Flutter), qui garde pour l'instant gauche/droite sur la ligne.
- Épinglé par `test/tv_focus_entry_test.dart` et `test/tv_focus_memory_test.dart`.
