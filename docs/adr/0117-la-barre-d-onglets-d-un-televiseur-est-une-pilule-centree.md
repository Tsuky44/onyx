# ADR-0117 — La barre d'onglets d'un téléviseur est une pilule centrée

- **Statut :** accepté. Vu en image rendue par un test (1280 × 720, police de l'app) ; pas encore sur
  une vraie Apple TV.
- **Date :** 2026-11-12
- **Portée :** `screens/shell/shell_tv_header.dart` (nouveau), `widgets/global/tv_tab_bar.dart`
  (nouveau), `screens/shell/shell_indexer_status.dart` (extrait de l'en-tête des grands écrans),
  `screens/shell/main_shell.dart`, `desktop_window.dart` (`shellHeaderHeight`).
- **Prolonge :** [ADR-0112](0112-sur-televiseur-la-commande-focalisee-se-remplit-de-blanc.md) (une
  seule commande blanche à l'écran). Ne contredit aucune ADR ; `PROJECT_DESIGN.md` §8 (l'onglet affiché
  se lit à un trait, pas à une pilule) reste vrai hors téléviseur.

## Contexte

Le téléviseur montait l'en-tête des grands écrans tel quel : une bande de verre pleine largeur à 6 px
du bord haut, la marque et les onglets serrés à gauche, un champ de recherche de 200 px et le compte à
droite. L'onglet affiché se lisait à un trait de 2 px sous un texte de 13 px, et l'onglet focalisé à un
voile gris cerclé de blanc. Depuis un canapé, on cherchait où l'on était. L'utilisateur a demandé la
barre des apps de salon, avec l'en-tête d'Emby pour modèle : la marque à gauche, une pilule d'onglets
au centre, le profil à droite.

## Décision

1. **Un en-tête à lui pour le téléviseur.** `MainShell` monte `ShellTvHeader` quand `TvScope` est
   vrai, `ShellDesktopHeader` sinon, dans la même `ShellHeaderZone` : nœuds de focus des onglets,
   entrée de zone (ADR-0109, ADR-0110) et Retour ne changent pas. Les mêmes entrées, les mêmes droits,
   les mêmes ancres de visite guidée.
2. **La pilule.** `TvTabBar` est une capsule de verre de 44 px, toujours au centre de l'écran : la
   marque et les actions occupent deux colonnes de même largeur de part et d'autre. Les onglets en
   trop défilent dans la pilule (le nombre de bibliothèques n'est pas borné).
3. **Trois états, portés par la capsule de l'onglet** (`TvTabBarItem`) : le texte seul au repos ; une
   capsule de verre clair pour l'onglet affiché ; la capsule blanche et le texte noir pour l'onglet
   focalisé (`FocusFill`, ADR-0112), à peine agrandie (1,04). Texte de 15 px (22 pt sur Apple TV) au
   lieu de 13.
4. **Plus de bande pleine largeur.** Seule la pilule porte du verre ; un voile sombre qui se dissout
   vers le bas garde la marque et le compte lisibles quand une page défile dessous.
5. **Des marges de téléviseur.** 22 px au-dessus de la pilule (33 pt), la gouttière des pages sur les
   côtés. `shellHeaderHeight` rend cette hauteur sur un téléviseur, et les pages s'y calent d'elles-mêmes.
6. **La recherche est une entrée de la pilule**, la dernière, sous la forme d'une loupe
   (`GlassCatalogSearch.tabBarTrigger`, un `TvTabBarItem` à icône). D'abord posée à droite, à côté du
   profil ; ramenée dans la barre après le premier essai sur Apple TV (2026-11-12), comme dans les apps
   de salon. Une icône et non le mot : avec sept onglets, un libellé de plus poussait le dernier hors
   de la pilule. OK l'ouvre ; s'y arrêter ne l'ouvre pas (`selectOnFocus: false`), puisqu'elle pousse
   une page au lieu d'afficher un onglet.
7. **À droite, le disque du profil seul.** Son nom, d'abord affiché à côté, est dans son menu.

## Conséquences

- **Android TV et le web des téléviseurs LG** prennent la même barre : ils passent par le même
  `TvScope`.
- L'onglet se choisit au focus après un court arrêt, comme sur tvOS : décidé sur maquettes, voir
  l'[ADR-0118](0118-le-style-de-salon-du-televiseur.md), point 4.
- `GlassNavTab` et `ShellDesktopHeader` ne changent pas : leurs tests restent ceux du bureau.
  `shell_navigation_map_test` éprouve toujours un en-tête de `GlassNavTab` monté à la main, donc plus
  l'onglet qu'un téléviseur monte ; les règles de zone qu'il vérifie sont les mêmes.
- Épinglé par `test/shell_tv_header_test.dart`.
