# ADR-0122 — Le pavé de la Siri Remote va posément sur les commandes

- **Statut :** accepté. Réglé d'après un retour sur une vraie Apple TV (version 1.1.42) ; les valeurs
  restent des estimations à confirmer au prochain essai.
- **Date :** 2026-11-12
- **Portée :** `tv/touchpad_motion.dart` (`TouchpadPace`, `TouchpadAxisTuning.preciseHorizontal`,
  `preciseVertical`), `tv/tv_touchpad.dart` (`TvTouchpad.paceOf`), `tv/tv_touchpad_pace.dart`
  (`TvTouchpadPace`), `screens/settings/settings_screen.dart`, `screens/settings/widgets/settings_page.dart`.
- **Prolonge** l'[ADR-0116](0116-le-doigt-pilote-le-focus-sur-le-trackpad-de-l-apple-tv.md), dont elle
  garde le réglage pour les affiches.

## Contexte

Retour de l'utilisateur après deux versions du nouveau pavé : « la navigation sur les affiches de
films, c'est parfait ; par contre sur les boutons de la barre du haut ou les paramètres c'est super
rapide. Fais en sorte que sur les boutons ça soit plus lent et plus smooth. »

L'ADR-0116 n'accélérait et ne lançait une liste que « dans quelque chose qui défile sur l'axe du
geste », en pensant aux rangées et aux grilles. Deux commandes défilent aussi :

- la pilule des onglets (ADR-0117) est un défilement horizontal, puisque le nombre de bibliothèques
  n'est pas borné : elle prenait le gain ×2 et la lancée de dix pas d'une rangée d'affiches. Un coup
  de pouce traversait toute la barre, et chaque onglet survolé plus de 220 ms montait sa page ;
- une page de réglages est une liste verticale : gain, lancée de deux lignes, et un pas tous les
  100 ms sur des catégories qui s'ouvrent au simple survol.

Même sans gain, le trajet d'un pas (0,26 puis 0,50 unité) est celui d'une affiche : un glissé
ordinaire passait deux ou trois boutons.

## Décision

**Le rythme du pavé suit ce que le focus désigne** (`TouchpadPace`, lu à chaque événement du doigt) :

- **vif** (`browse`) sur une carte : le réglage de l'ADR-0116, inchangé ;
- **posé** (`precise`) sur une commande : plus de trajet par pas, ni gain ni lancée, et un pas tous
  les 160 ms au plus.

| | Horizontale, vif | Horizontale, posé | Verticale, vif | Verticale, posé |
|---|---|---|---|---|
| premier pas d'un geste | 0,26 | 0,30 | 0,32 | 0,34 |
| trajet par pas | 0,50 | 0,80 | 0,65 | 0,90 |
| gain maximal | 2,0 | aucun | 1,25 | aucun |
| pas de lancée au plus | 10 | 0 | 2 | 0 |
| écart minimal entre deux pas | 55 ms | 160 ms | 100 ms | 160 ms |

Posé, un glissé ordinaire (la moitié de la surface) avance d'un cran, un balayage lent d'un bord à
l'autre de trois, et le focus s'arrête avec le doigt. Le coup de pouce trop court pour un pas en vaut
toujours un.

`TvTouchpad.paceOf` décide, dans cet ordre :

1. **la zone l'a déclaré** (`TvTouchpadPace`) : l'écran des réglages et chaque `SettingsPage` se
   déclarent posés ;
2. **une cible de moins de 64 px de haut est une commande** : un onglet (36), un bouton (36 à 56),
   une puce, une ligne de menu (50). La hauteur est celle de la mise en page, que ni l'échelle du
   téléviseur ni le soulèvement d'une affiche ne changent ;
3. **le reste est une carte** : la plus basse, la vignette d'un épisode, fait 101 px.

Trois précisions :

- le rythme se lit à chaque événement : un geste parti d'un bouton reprend le rythme des affiches dès
  que son pas l'a posé sur une rangée, mais il ne lance rien au lâcher ;
- une lancée qui arrive sur une commande s'arrête (remonter une grille ne traverse pas la barre
  d'onglets) ;
- un pas posé n'est pas une glissade (`TvTouchpad.isGliding`) : le défilement qui le suit prend sa
  durée ordinaire (200 ms) et non celle d'une flèche maintenue (90 ms). C'est le « plus smooth » des
  réglages.

### Écarté

- **La taille seule.** Mesuré sur l'écran des réglages : une ligne fait de 72 à 171 px de haut avec
  son texte et son choix, plus qu'une vignette d'épisode (117) ou qu'un portrait. Aucun seuil ne
  sépare les deux, d'où la déclaration de zone.
- **Marquer chaque carte.** Plus de vingt widgets de carte, sans ancêtre commun : la liste aurait
  toujours une carte de retard, et l'oubli rendrait lente une rangée jugée « parfaite ».
- **Ne corriger que la pilule et les réglages.** La demande dit « sur les boutons » : ceux de la
  fiche, du bandeau de l'accueil, des menus et des dialogues prennent le même rythme par leur taille.

## Conséquences

- Les lignes hautes hors des réglages (une liste de plus de 64 px par ligne dans un dialogue) gardent
  le rythme vif tant que leur écran ne se déclare pas avec `TvTouchpadPace.precise`.
- Les flèches de l'anneau et leur répétition ne changent pas : seul le doigt est concerné, donc seule
  l'Apple TV.
- Épinglé par `test/touchpad_motion_test.dart` (groupe « le rythme posé »), `test/tv_touchpad_test.dart`
  (pilule qui défile, zone déclarée, carte), `test/shell_tv_header_test.dart` et
  `test/settings_navigation_map_test.dart`.
- **À régler sur une Apple TV**, dans `TouchpadAxisTuning.preciseHorizontal` et `preciseVertical` :
  encore trop vif, monter `step` ; trop lent pour une longue liste, le baisser vers 0,65.
