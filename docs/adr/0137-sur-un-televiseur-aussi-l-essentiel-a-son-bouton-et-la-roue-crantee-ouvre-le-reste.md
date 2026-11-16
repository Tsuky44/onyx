# ADR-0137 — Sur un téléviseur aussi, l'essentiel a son bouton et la roue crantée ouvre le reste

- **Statut :** accepté. Demandé par l'utilisateur devant le lecteur tactile de
  l'[ADR-0136](0136-sur-un-ecran-tenu-en-main-le-lecteur-prend-l-arrangement-de-l-apple-tv.md)
  (2026-11-16, « beaucoup mieux, fais pareil sur la TV ») ; rendu vérifié sur une image du chrome en
  1920 × 1080, **pas encore vu sur une Apple TV**.
- **Date :** 2026-11-16
- **Portée :** `screens/player/widgets/onyx/onyx_controls_rows.dart` (`_buildEssentialActions`, qui
  remplace `_buildTvActions` et la rangée de l'ADR-0136), `onyx_chrome_buttons.dart` (`glassDisc`),
  `player_screen_chrome.dart` (`_chromeCarriesEssentials`).
- **Remplace** le point 1 de
  l'[ADR-0130](0130-le-lecteur-a-un-bouton-par-reglage-des-menus-de-verre-et-un-volet-d-onglets.md)
  (« sur un téléviseur, un bouton rond par réglage ») et son « pas d'index » pour la roue crantée,
  parce que l'utilisateur le demande maintenant. Le reste de l'ADR-0130 tient : les menus de verre,
  le menu d'un seul réglage pour les sous-titres et l'audio, le volet d'onglets, l'échelle.

## Contexte

L'ADR-0130 avait donné à un téléviseur un bouton rond par réglage : épisode précédent, sous-titres,
audio, qualité, vitesse, format d'image, minuterie, épisode suivant. Huit disques de 44 contre le
titre. La même rangée, proposée pour le téléphone, a été refusée par l'utilisateur (« réduire un
poil les icônes, mets l'essentiel sur l'écran, le reste dans un menu »), et le résultat lui a assez
plu pour qu'il le demande sur le téléviseur.

## Décision

1. **La rangée d'un téléviseur est celle d'un écran tenu en main** (`_buildEssentialActions`, une
   seule fonction pour les deux) : épisode précédent, sous-titres, audio, roue crantée, épisode
   suivant.
2. **Les sous-titres et l'audio gardent le menu de leur seul réglage** (`standalone`) : la
   télécommande arrive sur le choix en cours, Retour ferme.
3. **La roue crantée ouvre l'index du reste** : qualité, vitesse de lecture, format d'image,
   minuterie de veille (`indexOmits` : ni les sous-titres ni l'audio, qui ont leur bouton, ni les
   chapitres, qui ont leur onglet). OK entre dans un réglage, Retour ou Gauche remonte à l'index, un
   second Retour ferme : le parcours d'avant l'ADR-0130, que le menu savait encore faire.
4. **Le disque d'un bouton de verre fait 38 dans une place de 44**, et son icône 20
   (`OnyxIconButton.glassDisc`), partout. L'écart entre deux boutons ne change pas : ce qui rétrécit
   est ce qu'on voit, pas la place.
5. **Le bouton reste allumé tant que son menu est ouvert**, la roue crantée comprise
   (`openMenu == OnyxMenuSection.root`).

### Écarté

- **Garder un bouton pour la qualité**, le réglage qu'on change le plus après la langue. La demande
  est « pareil » ; un sixième bouton se rajoute d'une ligne si l'essai le réclame.
- **Les commandes de lecture au milieu de l'image**, comme sur un écran tenu en main. La
  télécommande les porte déjà (ADR-0124).

## Conséquences

- Changer de qualité, de vitesse, de format ou de minuterie coûte deux pas de plus qu'avec
  l'ADR-0130 : la roue crantée, puis la ligne.
- Android TV et le web des téléviseurs LG prennent la même rangée (`isTv`).
- Épinglé par `test/onyx_controls_layer_test.dart` (la rangée, le bouton allumé, la taille du
  disque) et `test/player_chrome_navigation_map_test.dart` (la roue crantée, son index et son
  Retour, dans les deux systèmes de navigation).

## À vérifier sur l'appareil

| Quoi | Pourquoi ici seulement |
| --- | --- |
| La taille des disques vue du canapé | 38 points sur 1280, soit 57 sur l'Apple TV : un rendu ne dit pas la distance. |
| L'index au glissé du pavé de la télécommande | Le pavé envoie des pas ; leur cadence ne se teste pas ici. |
