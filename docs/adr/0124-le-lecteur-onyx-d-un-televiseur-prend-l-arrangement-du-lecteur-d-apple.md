# ADR-0124 — Le lecteur Onyx d'un téléviseur prend l'arrangement du lecteur d'Apple

- **Statut :** accepté. Maquette validée par l'utilisateur (2026-11-13, « parfait, fais que tout marche
  comme maintenant ») ; rendu vérifié sur une capture de l'app, pas encore vu sur une Apple TV.
  L'[ADR-0130](0130-le-lecteur-a-un-bouton-par-reglage-des-menus-de-verre-et-un-volet-d-onglets.md)
  remplace son bouton « Réglages » par un bouton par réglage (point 3) et ses trois onglets par un
  volet de cinq (point 5), et met le lecteur à l'échelle des pages.
- **Date :** 2026-11-13
- **Portée :** `screens/player/widgets/onyx/onyx_controls_rows.dart` (`_buildTvChrome`),
  `onyx_tv_tabs.dart` (`OnyxTvTabs`), `onyx_chrome_buttons.dart` (`OnyxIconButton.glass`,
  `OnyxChromeTab`), `onyx_progress_bar.dart` (`marker`), `onyx_skip_intro_button.dart` (`capsule`),
  `onyx_chrome_theme.dart` (`OnyxChromeMetrics.tv`).
- **Remplace** l'arrangement télé de l'[ADR-0006](0006-chrome-du-lecteur-a-la-telecommande.md) et de
  l'[ADR-0008](0008-focus-visible-du-lecteur-tv.md) (trois rangées : menus en haut,
  transport au milieu, barre en bas). Leurs invariants tiennent toujours : chrome affiché, une commande
  a le focus ; un Retour défait une couche.

## Contexte

L'app a deux lecteurs sur Apple TV : l'écran natif d'AVKit (ADR-0105, ADR-0119, ADR-0120) et le chrome
Onyx, dessiné par Flutter. Le second gardait l'arrangement des premières versions télé : un bouton
Retour et les menus en haut, cinq boutons de transport au milieu de l'image, la barre en bas. Demande
de l'utilisateur : « refais le player Onyx pour qu'il soit exactement comme le player Apple ».

Sur un téléviseur, les boutons au milieu de l'image doublent la télécommande : OK met déjà en pause,
gauche et droite déplacent déjà, Retour quitte déjà.

## Décision

**Sur téléviseur, le chrome Onyx a l'arrangement du lecteur d'Apple.** Hors téléviseur, rien ne change.

1. **Rien au milieu de l'image, pas de bouton Retour.** Lecture, pause et ±10 s sont à la
   télécommande, comme avant quand le chrome était masqué.
2. **En bas à gauche le titre**, en gras, et dessous la ligne de l'épisode ou l'année (l'ordre du
   lecteur d'Apple, l'inverse des autres arrangements).
3. **À droite du titre, des boutons ronds de verre** (`OnyxIconButton.glass`, 44 px) : épisode
   précédent, sous-titres, audio, réglages, épisode suivant. Blancs à l'encre noire sous la
   télécommande (`FocusFill`, ADR-0112), et non plus remplis de l'accent.
4. **Une barre fine et blanche** (`OnyxProgressBar.marker`) : elle ne vire plus à l'accent sous la
   télécommande, elle s'épaissit et son repère vertical s'allonge. Dessous, le temps écoulé à gauche et
   le temps restant à droite, sans l'heure de fin.
5. **Sous la barre, des onglets** (`OnyxTvTabs`) : « Infos » déplie le résumé sans quitter le chrome ;
   « Épisodes » et « Regarder ensemble » ouvrent les panneaux que le lecteur avait déjà. Un onglet sans
   rien à ouvrir n'est pas dessiné.
6. **Le logo du titre en haut à gauche**, quand il existe. Sans logo, rien : le titre est déjà écrit
   au-dessus de la barre.
7. **« Passer l'intro » est une capsule de verre** à droite, au-dessus des boutons, toujours hors du
   fondu du chrome.
8. **La télécommande arrive sur la barre.** Trois rangées parcourues en ligne droite
   (`TvRegion.controlRows`) : les boutons ronds, la barre, les onglets ; « Passer l'intro » en est une
   quatrième, tout en haut. Le lecteur demandait déjà le focus sur lecture/pause puis, à défaut, sur
   la barre : sans bouton lecture, c'est la barre qui le prend, sans rien changer à
   `player_screen_remote.dart`.

Tout ce que le chrome faisait reste atteignable : les menus de pistes et de réglages s'ouvrent des
mêmes boutons, la liste des épisodes et la séance à plusieurs des onglets.

### Écarté

- **Refaire les panneaux en feuilles du bas à onglets**, comme la troisième planche de la maquette.
  La liste des épisodes est déjà un panneau du bas ; l'unifier avec la séance et les infos est un
  second chantier, à faire si l'essai le demande.
- **Garder un bouton lecture discret.** Il redevient la cible d'entrée de la télécommande, et la barre
  cesse de répondre à gauche et à droite au premier appui.

## Conséquences

- **Android TV et le web des téléviseurs LG** prennent le même chrome (`isTv`).
- `OnyxControlsLayer.onBack` et `playPauseFocusNode` ne servent plus sur téléviseur ; ils restent
  ceux des arrangements à souris et à doigt.
- Épinglé par `test/onyx_controls_layer_test.dart` (mise en page, focus, onglets) et
  `test/player_chrome_navigation_map_test.dart` (carte et invariants, les deux systèmes de navigation).
