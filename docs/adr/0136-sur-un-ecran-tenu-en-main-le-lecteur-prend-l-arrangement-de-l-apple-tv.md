# ADR-0136 — Sur un écran tenu en main, le lecteur prend l'arrangement de l'Apple TV

- **Statut :** accepté. Maquette validée par l'utilisateur (2026-11-16, six planches, « ok j'aime
  bien mais réduire un poil les icônes de paramètres, mets l'essentiel sur l'écran, le reste dans un
  menu ») ; rendu vérifié sur des images du chrome en 844 × 390, 640 × 360, 1180 × 820 et 400 × 700,
  **pas encore vu sur un iPhone ni sur un téléphone Android**.
- **Date :** 2026-11-16
- **Portée :** `screens/player/widgets/onyx/onyx_handheld_chrome.dart` (nouveau),
  `onyx_chrome_layout.dart` (le délégué de mise en page, sorti de `onyx_controls_layer.dart`),
  `onyx_controls_layer.dart` (`handheld`), `onyx_chrome_theme.dart`
  (`OnyxChromeMetrics.handheld`), `onyx_chrome_buttons.dart` (`glassDisc`, `onPicture`, `lit`),
  `onyx_progress_bar.dart` (`rowHeight`), `onyx_tabs.dart` (`hitHeight`, `fontSize`),
  `onyx_settings_menu.dart` (`indexOmits`), `player_screen_chrome.dart`.
- **Contredit** l'[ADR-0124](0124-le-lecteur-onyx-d-un-televiseur-prend-l-arrangement-du-lecteur-d-apple.md)
  (« hors téléviseur, rien ne change ») et, dans
  l'[ADR-0130](0130-le-lecteur-a-un-bouton-par-reglage-des-menus-de-verre-et-un-volet-d-onglets.md),
  la façon d'ouvrir la feuille des onglets (« un bouton de la barre ») — pour les écrans tenus en
  main seulement, parce que l'utilisateur le demande. Elle **confirme** ce que l'ADR-0130 avait
  écarté, « un bouton par réglage hors téléviseur » : la première maquette le proposait, l'utilisateur
  l'a refusé.

L'[ADR-0137](0137-sur-un-televiseur-aussi-l-essentiel-a-son-bouton-et-la-roue-crantee-ouvre-le-reste.md)
ramène ensuite cette rangée de boutons sur le téléviseur : les deux arrangements la partagent
(`_buildEssentialActions`).

## Contexte

Le lecteur avait deux chromes : celui d'un téléviseur, refait sur le modèle du lecteur d'Apple
(ADR-0124, ADR-0130), et celui des autres écrans, resté tel qu'avant — le titre et sept icônes plates
à droite, la barre, puis lecture et ±10 s en bas à gauche. Demande de l'utilisateur, capture d'iPhone
à l'appui : « améliore l'UI du player comme celui qu'on a fait sur Apple TV ».

Sur un iPhone couché, le bloc du bas occupait 155 points sur 390, dont une rangée entière pour quatre
boutons de transport alignés à gauche, loin du pouce comme de l'œil.

## Décision

**Un écran tenu en main (`AppPlatform.isMobile` hors téléviseur : téléphone et tablette) prend
l'arrangement d'un téléviseur, adapté au doigt.** L'ordinateur et le web à la souris gardent le leur.

1. **Lecture/pause et ±10 s sont au milieu de l'image**, sans dégradé derrière eux : leur icône porte
   son ombre (`OnyxIconButton.onPicture`). Sur un téléviseur ils doublaient la télécommande ; ici un
   toucher sur l'image ne fait qu'afficher le chrome, et il faut un bouton pour mettre en pause. Leur
   milieu tombe à 42 % de la hauteur, et jamais sur une barre (`_OnyxChromeLayout.centre`). Les
   épisodes précédent et suivant n'y sont pas : sous le pouce, à cette taille, un épisode changé par
   erreur coûte plus cher que dix secondes.
2. **Ce qu'on regarde, en une ligne, en bas à gauche** (`_buildIdentityLine`) : le nom de l'épisode
   pour une série, le titre pour un film, dans le même dessin. Le logo du titre, en haut à côté du
   bouton Retour, dit la série ; sans logo, ou le temps qu'il arrive, son nom en toutes lettres en
   tient la place (`_buildTitleMark`). La maquette validée écrivait là le titre en gras et l'épisode
   dessous, comme un téléviseur ; l'utilisateur l'a retiré en voyant la 1.1.54 sur son iPhone
   (« supprime le titre, y'a déjà le logo en haut, et pour les films mets le titre comme le nom des
   épisodes »).
3. **À droite du titre, l'essentiel en boutons ronds de verre** : sous-titres et audio, chacun avec
   son menu (`OnyxSettingsMenu.standalone`, posé sur son bouton), **la roue crantée pour le reste**,
   entre l'épisode précédent et le suivant quand il y en a. Le disque fait 38 dans une cible de 44
   (`OnyxIconButton.glassDisc`) : « un poil » plus petit, à la demande de l'utilisateur. Le bouton
   reste allumé tant que son menu est ouvert, et les commandes du milieu s'effacent : le panneau de
   verre se pose sur elles.
4. **L'index de la roue crantée ne liste que le reste** (`indexOmits`) : qualité, vitesse, format
   d'image, minuterie. Les sous-titres et l'audio ont leur bouton, les chapitres leur onglet. Quatre
   lignes tiennent sans défiler au-dessus de la rangée d'un téléphone couché ; les sept d'avant
   défilaient.
5. **La barre fine et son repère** (`OnyxProgressBar.marker`), dans une rangée qui garde la hauteur
   d'un doigt (`rowHeight`). Les temps écoulé et restant sont dessinés dans cette cible, sous le
   trait, plutôt que dans une rangée de plus. **Pas d'heure de fin**, comme sur un téléviseur.
6. **Les onglets sous la barre** (Infos, Épisodes, Chapitres, Regarder ensemble, Stats). En toucher
   un ouvre la feuille du bas (`PlayerTabSheet`) : un doigt ne « descend » pas sur un onglet. Les
   boutons « Épisodes », « Infos » et « Regarder ensemble » de la rangée d'avant disparaissent.
7. **Retour et le verrou sont des boutons de verre**, en haut. « Passer l'intro » est la capsule de
   verre d'un téléviseur, posée dans la marge de dégradé de la barre du bas : celle-ci garde sa
   hauteur, et les commandes du milieu ne bougent pas quand la capsule arrive.
8. **Un seul jeu de tailles** (`OnyxChromeMetrics.handheld`), que la largeur ne change pas : seule la
   marge s'élargit sur une tablette (`OnyxChromeTheme.tabletBreakpoint`). Sous 520 de large — une
   tablette en écran partagé — le titre et les boutons s'empilent.

### Écarté

- **Un bouton par réglage**, comme sur un téléviseur (la première maquette : huit boutons). Refusé
  par l'utilisateur : la rangée serrait le titre, et quatre de ces réglages ne se touchent presque
  jamais en cours de film.
- **Garder l'heure de fin** à côté du temps restant. La maquette validée ne la montre pas ; elle
  reste sur les écrans à souris.
- **Le volet d'un téléviseur sous la barre** (`OnyxTvTabs`). Il s'ouvre au focus, ce qu'un doigt n'a
  pas, et pousse la barre vers le haut d'un écran qui n'a que 390 points.
- **Affiner la barre de luminosité**, comme sur les planches. Son épaisseur est voulue (voir
  `onyx_brightness_slider.dart`) : un trait fin sur une image qui bouge ne se lit pas.

## Conséquences

- Le bouton « Plein écran » n'existe plus sur un écran tenu en main, où il ne faisait rien ; le
  bouton de vitesse non plus, la vitesse est dans la roue crantée.
- `OnyxIconButton.lit` allume un bouton hors téléviseur aussi ; `_openMenu` est tenu pour tout menu
  ouvert sur un écran tenu en main, y compris l'index.
- `onyx_controls_layer.dart` repasse à 669 lignes : son délégué de mise en page a son fichier.
- Épinglé par `test/onyx_handheld_chrome_test.dart` (places, cibles de 44, menus, onglets, petits
  écrans, index de la roue crantée).

## Corrigé après la 1.1.54, vue sur un iPhone

- **Le verrou flottait au milieu du haut de l'écran** dès qu'un logo était là : un `Flexible` suivi
  d'un `Spacer` laisse vide, à droite, ce que le logo ne prend pas de sa moitié de rangée. Le logo
  remplit maintenant sa place, calé à gauche.
- **L'image était à l'envers** : le verrou de paysage arrivé de `main` avec la 1.1.53
  (`PlayerLandscapeLock`) demande au système le côté que lit l'accéléromètre, dans les mots
  d'Android. iOS nomme les deux paysages à l'inverse (d'après le bouton principal, pas d'après le
  haut du téléphone) : les deux s'échangent sur iPhone (`orientationFor`).

## À vérifier sur l'appareil

| Quoi | Pourquoi ici seulement |
| --- | --- |
| Les commandes du milieu sur un plan très clair | L'ombre d'une icône se juge sur un vrai film. |
| Les onglets près de l'indicateur d'accueil d'un iPhone | Il ne se voit pas dans un rendu de test. |
| La rangée du titre contre l'îlot de l'iPhone | Les zones sûres réelles, pas celles simulées. |
| Le pouce sur ±10 s, téléphone tenu à deux mains | Une portée ne se mesure pas sur une image. |
