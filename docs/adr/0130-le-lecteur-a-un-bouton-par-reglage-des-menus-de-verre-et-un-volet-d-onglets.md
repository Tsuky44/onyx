# ADR-0130 — Le lecteur a un bouton par réglage, des menus de verre et un volet d'onglets

- **Statut :** accepté. Maquette validée par l'utilisateur (2026-11-14, onze planches, « c'est très
  bien, j'aime beaucoup, fais les modifs », puis « adapte ce player à tout le reste ») ; rendu vérifié
  sur des captures de l'app en 1920 × 1080, 1440 × 810 et 844 × 390, **pas encore vu sur une
  Apple TV**.
- **Date :** 2026-11-14
- **Portée :** `screens/player/widgets/onyx/` (`onyx_controls_rows.dart`, `onyx_tv_tabs.dart`,
  `onyx_tabs.dart`, `onyx_settings_menu*.dart`, `onyx_menu_style.dart`, `onyx_menu_section.dart`,
  `onyx_glass_panel.dart`, `onyx_capsule_button.dart`, `onyx_chrome_theme.dart`),
  `screens/player/widgets/tabs/`, `widgets/player_tab_sheet.dart`, `widgets/next_episode_page.dart`,
  `widgets/player_question_window.dart`, `widgets/player_video_stage.dart`,
  `widgets/player_tv_scale.dart`, `hooks/use_player_tabs.dart`, `hooks/use_player_stats.dart`,
  `hooks/use_episode_navigation.dart` (`deferNextEpisode`), `player_screen_overlays.dart`.
- **Remplace**, dans l'[ADR-0124](0124-le-lecteur-onyx-d-un-televiseur-prend-l-arrangement-du-lecteur-d-apple.md),
  le bouton « Réglages » (son point 3) et les trois onglets (son point 5), et fait le « second
  chantier » qu'elle avait écarté : les panneaux réunis en un volet à onglets. Son arrangement tient :
  rien au milieu de l'image, le titre en bas à gauche, la barre fine, la télécommande sur la barre.
- **Contredit** l'[ADR-0048](0048-un-seul-lecteur-le-chrome-onyx.md) sur un point, parce que la
  maquette validée le demande : le lecteur pose de nouveau du verre flouté sur le film. Pas le verre
  groupé qu'elle a retiré (un `BackdropGroup` permanent sous tout le chrome) : des panneaux ponctuels,
  ouverts à la demande. Le chrome au repos reste sans flou.
- **Change** l'échelle du lecteur sur téléviseur (`PlayerTvScale`), réglée jusque-là sur les
  1920 points de l'Apple TV.

## Contexte

L'app a deux lecteurs sur Apple TV : l'écran natif d'AVKit et le chrome Onyx, celui qui s'affiche par
défaut (`NativeTvPlayerPreference.defaultMode`). L'utilisateur voulait le lecteur Onyx « super
complet » : tout ce que le chrome avait, plus ce que l'écran natif avait reçu (les statistiques,
l'épisode suivant avec son anneau, les questions en fenêtre, les menus avec leur seconde ligne). La
maquette validée réunit les deux ; rien n'y est inventé.

Trois défauts du chrome d'avant, que la maquette corrige :

- **Un index à traverser.** Sur un téléviseur, la qualité, la vitesse, le format d'image et la
  minuterie étaient derrière un seul bouton « Réglages » : trois pas de télécommande pour changer de
  qualité. Les menus eux-mêmes étaient de petites listes grises de 292 px, « les petits menus » de
  l'utilisateur.
- **Trois panneaux pour trois onglets.** « Infos » dépliait un texte sous la rangée, « Épisodes »
  ouvrait une feuille du bas avec sa propre portée de focus, « Regarder ensemble » une fenêtre au
  centre. Les chapitres étaient au fond du menu, les statistiques nulle part.
- **Un chrome un tiers trop petit.** Les tailles télé du chrome (marge de 53, boutons de 44, titre de
  28) sont les 80, 66 et 42 points du lecteur d'Apple divisés par 1,5 : elles ont été dessinées pour
  une mise en page de 1280 de large, celle de toutes les pages d'un téléviseur (`TvUiScale`). Le
  lecteur, lui, se mettait en page sur 1920. Sur l'Apple TV le titre faisait donc 28 points là où
  Apple en met une quarantaine, et les heures 15 points, sous le minimum que tvOS recommande à trois
  mètres. Les planches, dessinées sur 1280, montraient la bonne taille.

## Décision

1. **Sur un téléviseur, un bouton rond par réglage** (`_buildTvActions`) : épisode précédent,
   sous-titres, audio, qualité, vitesse de lecture, format d'image, minuterie de veille, épisode
   suivant. Chacun ouvre le menu de ce seul réglage (`OnyxSettingsMenu.standalone`) : pas d'index, la
   télécommande arrive sur le choix en cours, **Retour ferme le menu**. Le bouton reste allumé tant que
   son menu est ouvert (`OnyxIconButton.lit`). Le chrome nomme un menu par `OnyxMenuSection` et donne
   le bouton lui-même comme repère (`onOpenMenu(section, anchor)`), sans une clé par bouton.
2. **Les menus sont des panneaux de verre** (`OnyxGlassPanel`, `OnyxMenuStyle`), partout : coins de
   26, lignes de 46 ou 60 selon qu'elles portent une seconde ligne, la coche à gauche, un filet entre
   les groupes de la minuterie. Sur un téléviseur la ligne focalisée est une pastille blanche à
   l'encre noire qui dépasse de 5 px (`FocusFill`, ADR-0112). Sous une souris ou un doigt, les mêmes
   menus en plus serré (300 de large, lignes de 40), et la roue crantée garde son index : une barre
   de téléphone n'a pas la place de six boutons de plus.
3. **Le verre** : un fond sombre à 72 % sur un flou (`GlassBlur`), ou à 95 % sans flou en mode léger
   et sur les téléviseurs LG (`glassBlurs`). Le texte se lit dans les deux cas : le flou est un plus,
   jamais ce qui porte la lisibilité.
4. **Cinq onglets** (`OnyxTab`) : Infos, Épisodes, Chapitres, Regarder ensemble, Stats. L'écran du
   lecteur décide lesquels existent (`_tabEntries`) et donne à chacun de quoi se construire ; le chrome
   ne connaît qu'un nom et un constructeur (`OnyxTabEntry`). Un onglet sans rien à montrer n'existe
   pas. `PlayerTabsController` tient l'onglet ouvert, une seule vérité pour les deux présentations :
   - **sur un téléviseur, un volet sous la barre** (`OnyxTvTabs`) : descendre de la barre sur un onglet
     ouvre son volet, la barre remonte ; gauche et droite changent d'onglet, Bas entre dans le
     contenu, et le volet se referme quand la télécommande le quitte. La rangée d'onglets fait entrer
     sur l'onglet ouvert (sinon remonter d'une carte changeait de volet) ;
   - **ailleurs, une feuille du bas** (`PlayerTabSheet`) avec les mêmes onglets et les mêmes contenus,
     ouverte par un bouton de la barre : « Épisodes » sur une série, « Infos » sur un film dans le
     même emplacement, « Regarder ensemble ». Elle remplace `PlayerEpisodesPanel` et la fenêtre de
     séance.
   Le volet tient le chrome affiché comme un menu ; Retour le ferme avant de masquer le chrome.
5. **L'onglet Stats lit le moteur en Dart** (`PlayerLiveStats`, par `PlaybackSession.readDiagnostics`
   que tous les moteurs servent), une fois par seconde et seulement tant que l'onglet est à l'écran.
   Les douze lignes de l'écran natif, dans le même ordre. Une mesure que le moteur ne donne pas
   s'écrit « — ».
6. **Au générique, une page présente l'épisode suivant** (`NextEpisodePage`) : l'image se range en haut
   à gauche (`PlayerVideoStage`), l'épisode qui vient montre son image, son titre, l'anneau du compte
   à rebours, « Lire » et « Plus tard ». La page ne lance rien : le compte à rebours reste celui
   d'`EpisodeNavigationController`. « Plus tard » (et Retour, et un tap sur l'image rangée) range la
   page pour de bon (`deferNextEpisode`) : la pastille d'avant, fermée, revenait à la position
   suivante avec un compte à rebours neuf.
7. **Les questions arrivent dans une même fenêtre de verre** (`PlayerQuestionWindow`) : « Vous regardez
   encore ? » et la lecture reprise sur un autre appareil. La réponse attendue est blanche hors
   téléviseur, et sous la télécommande sur un téléviseur.
8. **Le lecteur se met en page sur 1280** (`PlayerTvScale.designWidth = TvUiScale.designWidth`). Tout
   ce qu'il pose sur l'image passe par cette échelle, y compris les pages de fin et les fenêtres de
   question, qui restaient à la taille brute de l'écran.

### Écarté

- **Ranger les trois pages de fin dans la fenêtre de question** (langue absente, saison suivante,
  épisode pas encore sorti), comme l'écran natif le fait par des alertes. Ce sont des pages riches
  (affiche, pastilles, état d'une demande) qui marchent ; les réduire à un titre et trois boutons
  perdrait de l'information pour une uniformité que la maquette ne montrait que dans une note.
- **Un bouton par réglage hors téléviseur.** La barre d'un téléphone est pleine, et un index d'un clic
  ne coûte rien à une souris.
- **Des cartes de chapitres avec image.** Le serveur ne garde pas de vue par chapitre ; la vignette de
  la barre montre déjà l'endroit visé.
- **Un focus qui n'ouvre pas le volet** (OK pour l'ouvrir). Il n'y a rien d'autre à faire d'un onglet
  qu'on a rejoint, et le lecteur d'Apple fait de même.

## Conséquences

- **Le chrome d'un téléviseur est une fois et demie plus grand qu'avant sur l'Apple TV**, et prend
  les mêmes proportions sur Android TV et sur les téléviseurs LG. Revenir en arrière est une
  constante (`PlayerTvScale.designWidth`), mais les tailles des menus et du volet ont été réglées pour
  1280.
- Le menu des réglages n'a plus d'index sur un téléviseur ; il reste celui des autres écrans, où les
  chapitres y figurent encore.
- `OnyxControlsLayer` perd `overview` et gagne `onOpenMenu`, `openMenu`, `tabs`, `openTab`,
  `onTabChanged`, `onOpenInfo`. `placeSettingsPopup` prend le contexte du bouton, pas une clé.
- Un fichier de moins sur la liste de `no_parallel_focus_system_test` : la rangée d'épisodes se pose
  par le calcul, sans `Scrollable.ensureVisible`.
- L'écran natif d'Apple TV n'est pas touché : il garde son engrenage et ses alertes.
- Épinglé par `test/onyx_controls_layer_test.dart` (boutons, volet, focus), 
  `test/player_chrome_navigation_map_test.dart` (carte et pile du Retour, les deux systèmes),
  `test/onyx_settings_menu_tv_test.dart` (menu seul), `test/player_tabs_test.dart`,
  `test/player_episodes_tab_test.dart`, `test/player_live_stats_test.dart`,
  `test/next_episode_page_test.dart`, `test/player_question_window_test.dart`,
  `test/player_tv_scale_test.dart`.

## À vérifier sur l'appareil

| Quoi | Pourquoi ici seulement |
| --- | --- |
| La taille du chrome vue du canapé | L'échelle a changé ; les captures ne disent pas la distance. |
| Le flou des panneaux sur l'image | Dépend de la façon dont le moteur compose la vidéo sous Flutter. |
| Le volet qui s'ouvre au glissé du pavé | Le pavé envoie des pas ; leur cadence ne se teste pas ici. |
| Les valeurs de l'onglet Stats | Ce que le moteur de l'Apple TV sait dire de lui-même. |
