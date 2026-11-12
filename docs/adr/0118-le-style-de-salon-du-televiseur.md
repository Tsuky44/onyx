# ADR-0118 — Sur téléviseur, le style des interfaces de salon

- **Statut :** accepté. Choisi par l'utilisateur sur maquettes le 2026-11-12 ; testé en Dart, pas encore
  vu sur une vraie Apple TV.
- **Date :** 2026-11-12
- **Portée :** `widgets/global/poster_card.dart` (`PosterLift`, `PosterCard.railRoom`, `tvLift`),
  `utils/responsive.dart` (`mediaRowCardWidth`, `mediaRowGap`), `widgets/global/media_row.dart`,
  `screens/home/home_screen.dart`, `theme/app_theme.dart` (`_capsuleOnTv`),
  `screens/settings/widgets/settings_tile.dart` (extrait de `settings_ui.dart`),
  `screens/settings/settings_screen.dart`, `widgets/global/tv_tab_bar.dart`,
  `widgets/global/account_menu.dart`.
- **Remplace** l'[ADR-0111](0111-anneau-de-focus-blanc-autour-des-affiches.md) pour le focus des
  affiches sur téléviseur. **Étend** l'[ADR-0112](0112-sur-televiseur-la-commande-focalisee-se-remplit-de-blanc.md)
  aux lignes de réglage. **Amende** l'[ADR-0117](0117-la-barre-d-onglets-d-un-televiseur-est-une-pilule-centree.md) :
  l'onglet se choisit au focus. **Contredit `PROJECT_DESIGN.md` §4**, qui rangeait le « scale-on-focus
  1.1 » parmi ce qui ne se transpose pas d'Apple TV : l'utilisateur l'a demandé pour l'app de salon, et
  il ne vaut que sur téléviseur.

## Contexte

L'utilisateur a demandé une interface « dans le style Apple TV » et a validé des maquettes
(avant/après, à l'échelle de la page TV de 1280 px). L'app était déjà proche de ce style, mais ses
repères de focus avaient été pensés au bureau puis portés au salon : un anneau de 2,5 px autour d'une
affiche qui grandissait de 5 %, un bord bleu de 1,5 px sur la catégorie de réglages visée, un voile
bleu de 16 % sur la ligne visée, des boutons en rectangle arrondi.

## Décision

1. **Une affiche focalisée se soulève, sans anneau.** Sur téléviseur, `PosterLift` la fait grandir de
   10 % depuis son pied (`PosterCard.tvLift`) et lui donne une ombre profonde. C'est la taille et
   l'ombre qui disent où est le focus. En mode léger (ADR-0086), où l'ombre est retirée, l'anneau
   revient : 10 % de taille ne suffiraient pas seuls. `railRoom` réserve le soulèvement au-dessus de
   la rangée (30 px), et la rangée ne découpe plus ce qui dépasse.
2. **Six affiches par rangée** au lieu de sept et demie : 176 px de large, 24 px d'écart. Le titre
   d'une rangée passe à 24 px, graisse 700.
3. **Le bandeau de l'accueil part du haut de l'écran**, derrière la pilule des onglets. Son texte est
   calé en bas, loin de la barre ; sans bandeau, le texte d'accueil garde sa marge.
4. **S'arrêter sur un onglet l'affiche**, sans OK, après 220 ms (`TvTabBarItem.selectDelay`) :
   traverser la barre d'un glissé ne monte pas chaque onglet survolé. OK reste immédiat.
5. **Un bouton est une capsule** (`AppTheme._capsuleOnTv`, dans `focusRinged`) : tous les boutons du
   thème et ceux qui passent par `focusRinged`.
6. **Dans les réglages, ce qui est visé se remplit de blanc** et son texte passe au noir : la
   catégorie (capsule) et la ligne (`SettingsTile`). Ce qui est à droite d'une ligne est le widget de
   l'appelant, avec ses couleurs claires : il est repeint en encre d'un bloc (`ColorFiltered`,
   `srcIn`), sauf un interrupteur, dont la couleur dit l'état. La ligne ne se remplit que si **elle**
   a le focus : quand la télécommande est sur son menu ou son bouton, c'est lui qui le montre.
   Envelopper ce widget au moment où il prenait le focus le faisait renaître et le lui faisait perdre
   (droite depuis une catégorie revenait à la catégorie) ; une clé garde aussi son état.

7. **Un menu est un quart plus grand que la page** (`AppTheme.tvMenuBoost`, après le premier essai
   sur Apple TV : le menu du compte restait « trop petit »). Le thème porte le texte ;
   `AppTheme.menuScaleOf` donne le même facteur à ce qu'il ne sait pas porter, et le menu du compte
   s'en sert pour la hauteur de ses lignes, ses icônes et sa largeur.

## Conséquences

- **Android TV et le web des téléviseurs LG** prennent le même style : tout passe par `TvScope` ou
  `TvMode`. Hors téléviseur, rien ne change.
- **Le titre de l'affiche focalisée reste dans son cartel** (`PosterCardDetails`, ADR-0099), au pied
  de l'affiche, et non sous elle comme sur la maquette : la place sous une rangée est celle de la
  rangée suivante.
- **« Reprendre » reste en affiches portrait.** La maquette validée les montre en cartes paysage,
  mais l'accueil ne reçoit pas d'image paysage pour ces éléments : il faut que le serveur l'envoie
  (`backdrop_url` sur les éléments de `continue_watching`), ce qui attend l'accord de l'utilisateur.
- Dans une grille, l'affiche soulevée recouvre un peu la rangée du dessus et ses voisines : c'est le
  comportement des collections de tvOS.
- Épinglé par `test/poster_focus_ring_test.dart`, `test/tv_living_room_style_test.dart` et
  `test/shell_tv_header_test.dart`.
