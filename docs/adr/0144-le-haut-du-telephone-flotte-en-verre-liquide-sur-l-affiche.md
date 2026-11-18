# ADR-0144 — Le haut du téléphone flotte en verre liquide sur l'affiche

- **Statut :** accepté. Maquettes « Le haut de l'écran » choisies par l'utilisateur le 2026-11-18 :
  « pour le haut normal je veux la C et ensuite au défilement je veux la A ca floute », et pour
  la capsule du bas « un poil plus transparente […] plus proche du liquid glass ». Rendu vérifié
  sur des images 390 × 844 en test, **pas encore vu sur un iPhone**.
- **Date :** 2026-11-18
- **Portée :** `screens/shell/mobile_top_bar.dart` (réécrit : `BrandPill`, `ScrollEdgeBlur`),
  `widgets/global/liquid_glass.dart` (nouveau), `widgets/global/account_menu.dart` (le rond
  `liquid`), `screens/shell/mobile_bottom_nav.dart` (la capsule prend `LiquidGlass`),
  `screens/home/home_screen.dart`, `widgets/global/hero_carousel.dart` et `hero_banner.dart`
  (`extendTop`) ; `GlassBarSurface` est retiré de `glass_chrome.dart`.
- **Prolonge** l'[ADR-0142](0142-la-barre-d-onglets-du-telephone-est-une-capsule-de-verre.md)
  (la capsule du bas) et reprend pour le téléphone ce que l'ADR-0118 faisait sur le téléviseur
  (l'affiche part du haut de l'écran).

## Contexte

Sur l'iPhone, la barre du haut posait un bandeau sombre de 112 points sous l'heure : le logo en
anneau à gauche, le compte à droite, et l'affiche de l'accueil ne commençait qu'en dessous, avec
une coupure nette (capture de l'utilisateur, 2026-11-18). La capsule du bas venait de passer au
verre (ADR-0142) : le haut et le bas de l'écran ne parlaient plus la même langue.

Trois propositions ont été dessinées, toutes avec l'affiche jusqu'en haut : A, deux ronds de verre
(logo, compte) ; B, le grand titre d'iOS ; C, le logo et le nom dans une pilule de verre, le compte
dans un rond. Pour le défilement, A floutait le haut de la page en fondu, B rangeait le titre dans
une bande de verre.

## Décision

1. **Au repos, la C.** Pas de bandeau. La marque (lentille et nom dessiné, `OnyxMark` +
   `OnyxWordmark`) dans une pilule de verre liquide, le compte dans un rond du même verre, tous
   deux de 44 points (la cible d'Apple), sous la barre d'état. La pilule ramène à l'accueil. Le
   nom revient sur le téléphone : il en était parti pour laisser la place au champ de recherche,
   qui est en bas depuis l'ADR-0142.
2. **Au défilement, le flou de la A.** Rien ne s'allume : ce qui défile se floute et s'assombrit
   en fondu sous les deux pièces de verre (`ScrollEdgeBlur`), comme dans les apps d'iOS 26, sur la
   barre d'état, la rangée, et 36 points sous elle. Flutter ne sait pas dégrader un flou : cinq
   bandes de flou de plus en plus léger (16 à 1,2), et par-dessus un voile vers la couleur de la
   page qui fond leurs marches. Sans flou (mode léger, webOS), le voile seul, plus dense.
3. **L'affiche de l'accueil monte sous la barre** sur téléphone, comme sur le téléviseur : le
   carrousel commence en haut de l'écran et le bandeau grandit de la hauteur de la barre
   (`extendTop`). Le titre, les boutons et la suite de la page restent où ils étaient ; seule
   l'image gagne le haut. Le voile du haut du bandeau garde l'heure lisible. Les autres onglets,
   sur fond noir, gardent leur marge sous la barre.
4. **Une seule matière, `LiquidGlass`**, pour la capsule et le rond du bas, la pilule et le rond
   du haut. Plus clair que le verre de l'ADR-0142 : flou de 12 au lieu de 22, voile blanc de 13 à
   3 % au lieu de 16 à 6 %, un reflet léger en bas, la couleur de ce qui passe dessous relevée de
   moitié (saturation 1,5), une ombre plus courte. La lentille de l'onglet affiché passe à 17 %.

### Écarté

- **B, le grand titre.** Le logo disparaissait, et un « Accueil » en 32 points sur l'affiche se
  disputait avec le titre du film.
- **Un bandeau de verre qui s'allume au défilement** (l'ancien `GlassBarSurface`, ou la B) : une
  arête nette en travers des affiches, là où iOS 26 fond le contenu dans le haut de l'écran.
- **Un vrai flou dégradé par un shader** : Flutter n'a pas d'API pour un flou dont la force varie,
  et un `ShaderMask` autour d'un `BackdropFilter` n'a pas été vérifié sur Impeller : trop de
  risque pour un effet de bord d'écran.

## Contraire à un choix d'avant

Le carrousel de l'accueil commençait **sous** la barre du haut, parce que, posée sur l'affiche, la
barre en masquait le haut et le titre (commentaire de `home_screen.dart`, sans ADR). La barre
n'est plus un bandeau, et le bandeau grandit d'autant : le titre ne bouge pas, et seules deux
pièces de verre de 44 points se posent sur le ciel de l'image.

## Conséquences

- Cinq flous en haut de l'écran pendant le défilement, plus ceux du bas : à surveiller sur un
  iPhone ancien. Le mode léger les retire tous.
- Le bouton de téléchargement de l'app (web) et l'indicateur d'analyse gardent leur style à côté
  du rond du compte.
- Épinglé par `test/phone_top_bar_test.dart` (la pilule et le rond, la même hauteur, pas de
  bandeau au repos, le fondu au défilement et sa hauteur, le bandeau qui grandit) et
  `test/phone_tab_bar_test.dart`.

## À vérifier sur l'appareil

| Quoi | Pourquoi ici seulement |
| --- | --- |
| Les marches entre les bandes de flou | Elles se jugent à l'œil sur de vraies affiches qui défilent. |
| Le coût des flous du haut et du bas ensemble | Il dépend du GPU. |
| Le verre plus clair sur une affiche très claire | Les noms des onglets doivent rester lisibles. |
| L'heure sur le ciel de l'affiche | Le voile du bandeau suffit-il sur un ciel blanc ? |
