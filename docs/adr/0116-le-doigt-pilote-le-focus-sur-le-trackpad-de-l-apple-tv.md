# ADR-0116 — Sur le trackpad de l'Apple TV, c'est le doigt qui pilote le focus

- **Statut :** accepté, écrit sous Linux. Le Dart est analysé et testé à la milliseconde ; **aucun geste
  n'a été fait sur une vraie Siri Remote avec ce modèle**, et ses réglages sont des estimations.
- **Date :** 2026-11-12 ; réglage du même jour après le premier essai sur Apple TV (voir « Réglage »)
- **Portée :** `tv/touchpad_motion.dart` (`TouchpadMotion`, `TouchpadCoast`, `TouchpadAxisTuning`),
  `tv/tv_touchpad.dart`, `tv/tv_key_repeat.dart` (`TvDirectionalFocusAction` ne multiplie plus les pas),
  `tv/nav/tv_nav_root.dart`, `screens/player/player_screen_remote.dart` (l'écouteur dit s'il s'est servi
  du geste).
- **Remplace** le point 3 de l'[ADR-0039](0039-force-du-geste-sur-le-trackpad-de-l-apple-tv.md)
  (accélération et élan greffés sur les flèches du moteur) et revient sur l'alternative qu'elle écartait
  au point 2. Ses points 1 (un seul défilement par pas) et 4 (la barre de lecture suit le doigt) restent.

## Contexte

L'ADR-0039 gardait les flèches que le moteur de flutter-tvos tire d'un glissé et leur donnait du poids :
une flèche arrivée pendant un glissé vif valait 2 ou 3 pas, et un doigt levé à plus de 10 u/s laissait
six pas d'élan. Retour de l'utilisateur sur son Apple TV : « quand tu slides d'un côté ça n'avance que
d'un, ce ne sont pas les déplacements fluides de l'Apple TV ».

La cause est dans ce que le moteur envoie. Il tire **une** flèche quand le doigt a parcouru 0,3 unité,
puis des répétitions à cadence fixe : leur nombre ne dit presque rien de la longueur ni de la vitesse du
geste (constat déjà fait pour la barre de lecture, ADR-0039 point 4). Un geste lent de toute la largeur
du pavé et un coup de pouce donnaient la même chose, et les seuils d'accélération (8 et 13 u/s) ne
réagissaient qu'à un vrai coup sec. L'interface d'Apple, elle, lit le doigt : le focus avance avec lui,
et repart sur sa lancée quand on le lâche.

## Décision

1. **Le trajet fait les pas.** `TouchpadMotion` accumule le déplacement du doigt et rend un pas
   (`takeStep`) chaque fois qu'il a parcouru un pas de surface : 0,22 unité pour le premier pas d'un
   geste (un coup de pouce répond tout de suite), puis 0,40 à l'horizontale et 0,55 à la verticale. La
   surface fait 2 unités : un balayage lent d'un bord à l'autre vaut 5 affiches, ou 4 lignes.
2. **La vitesse allonge le trajet.** Dans ce qui défile sur l'axe du geste, le même trajet vaut jusqu'à
   2,6 fois plus de pas à l'horizontale (entre 2,5 et 11 u/s) et 1,5 fois à la verticale. Deux pas ne
   se suivent jamais à moins de 40 ms à l'horizontale, 90 ms à la verticale : le parcours vertical des
   fiches fait défiler puis réessaie, et perdait des pas sous 80 ms (ADR-0110, constat C6).
3. **Le lâcher garde son élan.** Un doigt levé à plus de 4,5 u/s (8 à la verticale) rend un
   `TouchpadRelease`. `TouchpadCoast` en tire une lancée : la vitesse décroît de façon exponentielle
   (63 % perdus en 260 ms), un pas chaque fois qu'elle a couvert un pas de trajet, 18 au plus (2 à la
   verticale), jusqu'à ce que le pas suivant soit à plus de 220 ms. Poser le doigt, cliquer, appuyer
   sur une touche ou atteindre le bout de la rangée l'arrête ; le bout de la rangée, c'est deux pas de
   suite sans effet, un seul pouvant tomber sur une carte pas encore construite. Un coup de pouce trop
   court pour un pas en vaut quand même un (`flick`).
4. **Un pas est une flèche comme une autre.** `TvTouchpad._pressArrow` fait parcourir à l'arbre de
   focus une flèche appuyée puis relâchée, du nœud focalisé vers la racine, par les mêmes `onKeyEvent`
   et les mêmes raccourcis qu'une touche. Rangées, grilles, menus, curseurs et chrome du lecteur
   réagissent au doigt sans le savoir, dans les deux systèmes de navigation (ADR-0110).
5. **Les flèches que le moteur tire du même glissé sont retenues**, avant tout l'arbre de focus
   (`FocusManager.addEarlyKeyEventHandler`). Une flèche est « du glissé » si le doigt est sur la surface,
   a parcouru plus de 0,06 unité depuis son contact et bouge à plus de 0,8 u/s au moment où elle arrive,
   ou si elle arrive moins de 120 ms après un lâcher en mouvement. Sa répétition et son relâchement sont
   retenus avec elle. Une flèche sans doigt en mouvement (anneau cliquable, tape sur un bord, manette,
   app Remote de l'iPhone) passe telle quelle, et un clic n'est jamais un glissé.
6. **La verticale reste sage.** L'essai du 2026-09-29 (ADR-0039) avait trouvé une verticale accélérée
   « trop forte » : un glissé vers le bas sautait des rangées entières. Elle suit donc le doigt presque
   sans gain, et sa lancée ne dépasse jamais deux éléments.
7. **Le lecteur.** Un écouteur de déplacement répond vrai quand il s'est servi du geste : la barre de
   lecture suit alors le doigt et le geste ne fait pas de pas de focus en plus, ni de coup de pouce au
   lâcher.
8. **Dans un champ de texte, le doigt ne pilote rien** : clavier ouvert, c'est lui qui a la
   télécommande ; fermé, la flèche du moteur sort du champ par `WebTvFieldExit`, qui la lit avant tout
   l'arbre de focus et ferait un second pas à côté du nôtre.

### Écarté

- **Couper les flèches de glissé à la source** par `TvRemoteConfig` (seuils hors d'atteinte). Le code
  du moteur n'est pas publié : rien ne dit que le seuil discret natif lit `shortSwipeThreshold`. Et si
  le flux tactile n'arrivait pas, plus rien ne bougerait. Retenir les flèches a la propriété inverse :
  **sans flux tactile, rien n'est retenu et tout se comporte comme avant.**
- **Rejouer les pas par le canal `flutter/keyevent`.** Ils passeraient par `HardwareKeyboard`, dont
  l'état (« flèche enfoncée ») se mêlerait à celui des vraies flèches du moteur, retenues au même
  moment.
- **Faire défiler la rangée au pixel sous le doigt**, focus posé à l'arrêt. C'est ce que fait tvOS
  dans ses propres collections, mais le focus d'Onyx est un nœud Flutter par carte : il faudrait un
  focus « flottant » dessiné à part, donc un second système de focus (interdit par l'ADR-0110).

## Réglage après le premier essai (2026-11-12)

Premier essai sur une vraie Apple TV, version 1.1.41 : le modèle plaît, mais « c'est un peu rapide ».
Les valeurs de la décision ci-dessus sont celles de la première version ; celles qui tournent
maintenant, dans `TouchpadAxisTuning` :

| | Horizontale, avant | Horizontale, après | Verticale, avant | Verticale, après |
|---|---|---|---|---|
| premier pas d'un geste | 0,22 | 0,26 | 0,28 | 0,32 |
| trajet par pas | 0,40 | 0,50 | 0,55 | 0,65 |
| gain maximal | 2,6 (2,5 à 11 u/s) | 2,0 (3,5 à 12 u/s) | 1,5 | 1,25 |
| vitesse de lancée | 4,5 u/s | 6 u/s | 8 u/s | 9 u/s |
| durée de la lancée | 260 ms | 200 ms | 200 ms | 180 ms |
| pas de lancée au plus | 18 | 10 | 2 | 2 |
| écart minimal entre deux pas | 40 ms | 55 ms | 90 ms | 100 ms |

Un balayage lent d'un bord à l'autre vaut maintenant 4 affiches (5 avant) ou 3 lignes (4 avant) ; un
geste vif lâché, 8 affiches environ au lieu de 12.

Second essai (2026-11-12) : les affiches sont « parfaites », les onglets et les réglages « super
rapides » ; les commandes prennent leur propre réglage
([ADR-0122](0122-le-pave-va-posement-sur-les-commandes.md)).

## Réglage après le troisième essai (2026-11-13)

Retour : « dans les médias elle est encore trop sensible, baisse-la un peu : si on était à 60 %, passe
à 40 % ». Un tiers de moins partout, pour les affiches seulement.

| | Horizontale, avant | Horizontale, après | Verticale, avant | Verticale, après |
|---|---|---|---|---|
| premier pas d'un geste | 0,26 | 0,32 | 0,32 | 0,40 |
| trajet par pas | 0,50 | 0,75 | 0,65 | 0,95 |
| gain maximal | 2,0 | 1,5 | 1,25 | 1,15 |
| vitesse de lancée | 6 u/s | 6,5 u/s | 9 u/s | 10 u/s |
| durée de la lancée | 200 ms | 180 ms | 180 ms | 180 ms |
| pas de lancée au plus | 10 | 6 | 2 | 1 |
| écart minimal entre deux pas | 55 ms | 60 ms | 100 ms | 100 ms |

Un glissé ordinaire et posé (la moitié de la surface) vaut maintenant une affiche ou une rangée, un
balayage lent d'un bord à l'autre trois affiches (quatre avant) ou deux rangées (trois avant), et un
coup sec lâché à 10 u/s laisse courir trois affiches au lieu de cinq.

## Conséquences

- **Tout est à régler sur une Apple TV**, dans `TouchpadAxisTuning` : `step` (trajet par pas),
  `maxGain` (accélération), `coastFrom` et `coastDecay` (élan), `maxCoastSteps`. Trop nerveux : monter
  `step` ou baisser `maxGain`. L'élan part trop loin : baisser `coastDecay`.
- **Tenir le doigt au bord du pavé ne répète plus** : la répétition que le moteur tirait d'un glissé
  tenu est retenue avec sa flèche. La touche maintenue de l'anneau garde la sienne.
- **Un clic sur l'anneau dans les 150 ms qui suivent un glissé du même doigt est retenu** : le doigt
  bouge encore. C'est le prix de la règle du point 5, à revoir si l'essai le fait sentir.
- `TvTouchpad.boostFor` et `stepsFrom` disparaissent ; `TvArrowGate` garde son paramètre `stepsFor`,
  qui vaut toujours un pas. Sous dpad, les pas de la lancée passent encore par `glideStepper`.
- **Un pas du doigt ne passe ni par `HardwareKeyboard` ni par les gestionnaires précoces** :
  `TvFocusGuard` (focus perdu) ne le voit pas. La flèche du moteur retenue, elle, les traverse encore
  tous, et c'est elle qui réveille un focus garé.
- **Android TV** n'est pas touché : sa télécommande n'a pas de surface tactile.
- Épinglé par `test/touchpad_motion_test.dart` (le modèle) et `test/tv_touchpad_test.dart` (le pilote,
  sur les deux systèmes de navigation).
