# ADR-0139 — Un seul arrangement du lecteur sur tous les écrans

- **Statut :** accepté. Maquette validée par l'utilisateur (2026-11-17, onze planches, « ok c'est
  validé, fais l'ADR et code tout ») ; rendu vérifié sur des images du chrome en 1280 × 720,
  760 × 428 et 844 × 390, **pas encore vu sur un ordinateur, un téléphone ni une Apple TV**.
- **Date :** 2026-11-17
- **Portée :** `screens/player/widgets/onyx/onyx_pointer_chrome.dart` (nouveau),
  `onyx_controls_layer.dart`, `onyx_controls_rows.dart` (`_buildEssentialActions`),
  `onyx_handheld_chrome.dart`, `onyx_tv_tabs.dart` (`pointer`), `onyx_progress_bar.dart`
  (`OnyxSegmentedBarPainter`), `onyx_chrome_buttons.dart` (`OnyxVolumeControl.glass`,
  `onyxWindowButtons`), `onyx_chrome_theme.dart` (`pointerCarriesTabs`, les tailles `wide` et
  `compact`), `player_screen_chrome.dart`, `player_screen_overlays.dart`,
  `utils/app_platform_*.dart` (`isTouchBrowser`).
- **Remplace** ce que l'[ADR-0048](0048-un-seul-lecteur-le-chrome-onyx.md) gardait de l'ancien
  arrangement à souris (le titre en gras, les icônes plates, le transport en bas à gauche, l'heure
  de fin) et son point de rupture à 800, qui ne choisit plus qu'entre deux jeux de tailles.
- **Contredit** l'[ADR-0136](0136-sur-un-ecran-tenu-en-main-le-lecteur-prend-l-arrangement-de-l-apple-tv.md)
  sur trois points, parce que l'utilisateur le demande sur la maquette : son point 6 (les onglets
  sous la barre d'un écran tenu en main), la taille de ±10 s (0,64 de lecture/pause) et
  « l'ordinateur et le web à la souris gardent le leur ». Le reste tient.
- **Change**, dans l'[ADR-0124](0124-le-lecteur-onyx-d-un-televiseur-prend-l-arrangement-du-lecteur-d-apple.md),
  le dessin des chapitres sur la barre (son point 4 parlait d'une barre continue).

## Contexte

Le lecteur avait trois arrangements. Deux étaient faits sur le modèle du lecteur d'Apple : celui
d'un téléviseur (ADR-0124, 0130, 0137) et celui d'un écran tenu en main (ADR-0136). Le troisième,
celui d'une souris (Windows, macOS, Linux, le web), était resté tel qu'avant : le titre en gras,
huit icônes plates, lecture et ±10 s en bas à gauche, l'heure de fin. Un navigateur ouvert sur un
téléphone recevait ce troisième, dans sa version empilée. Demande de l'utilisateur : « reprends le
player de l'Apple TV et iOS et fais la même chose pour tous les autres environnements, il faut
qu'on ait plus ou moins tout pareil partout ».

## Décision

**Le lecteur n'a qu'un arrangement, décliné selon ce qui pilote l'écran : la télécommande, le
doigt, la souris.** Partout : le logo en haut à gauche, ce qu'on regarde en une ligne en bas à
gauche, l'essentiel en boutons ronds de verre à sa droite, la barre fine à repère, le temps écoulé
à gauche et le temps restant à droite, des menus de verre posés sur leur bouton, « Passer l'intro »
en capsule.

1. **Sous une souris, l'arrangement d'un téléviseur** (`_buildPointerChrome`). Rien au milieu de
   l'image : un clic sur l'image met en pause, Espace aussi, les flèches déplacent de dix secondes.
   La première maquette y posait lecture et ±10 s, comme sur un téléphone ; l'utilisateur les a
   retirés (« ça sert à rien sur PC et web »). L'épisode précédent et le suivant sont dans la
   rangée de boutons, en bas à droite.
2. **Ce qui reste propre à la souris est en haut** : Retour à gauche, sous les feux de la fenêtre
   d'un Mac ; à droite le volume (une capsule de verre, réduite au bouton muet sous 560 de large),
   l'image dans l'image et le plein écran, là où un écran tenu en main a son verrou.
3. **Les onglets sont sous la barre, avec le volet d'un téléviseur** (`OnyxTvTabs.pointer`) : un
   clic ouvre le volet, la barre remonte ; un second clic sur l'onglet, un clic sur l'image ou
   Échap le referme. Le volet ne suit pas le focus : rien ne dit qu'on a fini de lire quand le
   pointeur le quitte.
4. **L'heure de fin se lit au survol du temps restant.** Elle n'est plus écrite sous la barre,
   comme sur les autres écrans.
5. **Dans une fenêtre trop petite pour le volet** (moins de 800 de large ou de 560 de haut,
   `OnyxChromeTheme.pointerCarriesTabs`), les onglets passent derrière un bouton, comme au point 6.
   La même fonction sert le chrome, qui dessine, et l'écran du lecteur, qui pose la feuille.
6. **Sur un écran tenu en main, plus d'onglets sous la barre.** Un bouton rond les ouvre, entre
   l'épisode précédent et les sous-titres (sa place a été fixée par l'utilisateur sur la
   maquette) : « Épisodes » pour une série, « Infos » pour un film. La feuille qu'il ouvre
   (`PlayerTabSheet`) porte tous les onglets. La rangée coûtait 44 points de haut à un écran qui
   en a 390.
7. **±10 s font 0,8 de lecture/pause** sur un écran tenu en main, au lieu de 0,64 : « légèrement
   plus petits », pas des commandes secondaires.
8. **La barre se coupe à chaque chapitre** (`OnyxSegmentedBarPainter`), sur tous les écrans : un
   vide de 4 points entre deux tronçons aux bouts ronds, à la place du trait blanc posé sur une
   barre continue. Un chapitre au bord, ou à moins de 8 points du précédent, ne coupe pas.
9. **Un navigateur piloté au doigt est un écran tenu en main** (`AppPlatform.isTouchBrowser`, le
   pointeur principal « grossier », jamais un téléviseur LG). Il en prend le chrome et les
   gestes ; il lui manque la luminosité, que la page ne pilote pas, et il gagne un bouton « Plein
   écran » à côté du verrou, parce que la page a une barre d'adresse à faire sortir.
10. **La roue crantée n'ouvre que le reste partout** : qualité, vitesse, format d'image,
    minuterie. Les sous-titres et l'audio ont leur bouton dans les trois arrangements.

### Écarté

- **Lecture et ±10 s au milieu de l'image sous une souris**, comme le lecteur de l'app TV d'Apple
  sur un Mac. Refusé par l'utilisateur.
- **Garder l'heure de fin sous la barre d'un ordinateur.** Elle était le seul texte que les autres
  écrans n'avaient pas ; le survol la rend sans rangée de plus.
- **Le volet qui s'ouvre au survol d'un onglet.** Un pointeur traverse la rangée pour aller
  ailleurs ; le volet s'ouvrirait sans qu'on l'ait demandé.
- **Un bouton des onglets sur un téléviseur.** La télécommande descend sur la rangée d'onglets en
  un pas, et le volet s'y ouvre tout seul (ADR-0130).

## Conséquences

- Le bouton de vitesse à un clic disparaît d'un ordinateur : la vitesse est dans la roue crantée.
  Le bouton « Regarder ensemble » aussi : c'est un onglet.
- `OnyxControlsLayer` perd `onCycleSpeed`, `playbackRate`, `onOpenWatchParty` et
  `watchPartyActive`, et gagne `handheldFullscreen`. Les rangées `_buildUtilities` et
  `_buildTransport` sont retirées.
- Les tailles `OnyxChromeMetrics.wide` et `compact` deviennent celles du chrome d'une souris : des
  cibles de 44 et des disques de verre de 38 partout.
- Un correctif du chrome se fait toujours une fois (ADR-0048) : les trois déclinaisons partagent
  `_buildTitleMark`, `_buildIdentityLine`, `_buildEssentialActions`, la barre et les menus.
- Épinglé par `test/onyx_controls_layer_test.dart` (rien au milieu, disques de verre, onglets et
  volet d'une souris, heure de fin au survol), `test/onyx_handheld_chrome_test.dart` (le bouton
  des onglets et sa place, ±10 s, le plein écran d'un navigateur) et
  `test/onyx_segmented_bar_test.dart` (les coupures).

## À vérifier sur l'appareil

| Quoi | Pourquoi ici seulement |
| --- | --- |
| Le clic sur l'image sans bouton lecture, sur un ordinateur | Une habitude ne se juge pas sur une image. |
| Le volet d'onglets à la molette et au glissé | La rangée d'épisodes défile à l'horizontale. |
| `(pointer: coarse)` sur un iPad avec souris, un portable tactile | Ce que le navigateur répond dépend de la machine. |
| Les coupures de chapitre vues du canapé | Quatre points sur 1280, six sur une Apple TV. |
| Le plein écran d'un navigateur de téléphone | Safari sur iPhone ne l'accorde pas à toute page. |
