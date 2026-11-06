# ADR-0110 — Un seul système de focus : dpad

- **Statut :** proposé. La phase 0 (rapport [`refonte-navigation-dpad-phase0.md`](../refonte-navigation-dpad-phase0.md))
  a tout vérifié au simulateur et sans écran, rien sur une vraie Apple TV. Les phases 2 à 5 montent
  dpad **derrière le drapeau de compilation `ONYX_TV_NAV=dpad`** (défaut `legacy` : sans lui, l'app
  est celle d'avant la refonte) ; vues au simulateur Apple TV seulement. Aucun essai sur une vraie
  Apple TV n'a été fait : l'utilisateur ne peut pas tester pour le moment. **Le drapeau reste**
  jusqu'à ce que cette recette soit verte, et disparaît au plus tard en phase 8 (le plan le
  retirait avant la phase 3).
  - **Passe à « accepté »** quand les cases du rapport §5 sont vertes sur une vraie Apple TV avec les
    deux générations de Siri Remote (Menu/‹ en un seul Retour et rendu au système à la racine,
    `onLongSelect` sur les deux générations, touche maintenue sans pas perdu à la cadence native,
    glissé vif sans `immobile`, coût d'une flèche ≤ 4 ms en `--profile` sur la machine la plus lente,
    une annonce VoiceOver par carte), puis sur Android TV (un seul Retour, touche maintenue) et webOS.
    Le constat chiffré de chaque case s'ajoute alors ici.
  - **Passe à « rejeté »** si l'une de ces cases est rouge sur machine réelle sans parade dans
    `lib/tv/nav/` ou `lib/tv/input/` (plan §9 : pas de fork avant constat). On retire alors `dpad` du
    `pubspec.yaml`, `lib/tv/nav/`, `lib/tv/input/` et le guard test, et l'ADR-0109 redevient pleine.
- **Date :** 2026-11-06
- **Portée :** `pubspec.yaml` (`dpad: 3.3.0`), `lib/tv/nav/` (`OnyxDpad`, `TvBack`, `TvFocusable`,
  `TvRegion`, `TvDpadFocusable`, `TvForegroundRoute`, `tv_nav_theme.dart` ; en phase 3
  `TvPaneRegion`, `TvContainedSteps`, `TvCardDirections`, `TvSlideEdges`, `TvWideCard` ; en phase 5
  `TvBackStep`, `TvBackKeyAction`), `lib/screens/shell/shell_tv_back.dart`, `lib/tv/input/`
  (`TvArrowGate`, `StepTarget`), `test/support/tv_nav_harness.dart`,
  `test/no_parallel_focus_system_test.dart`. Plan : [`refonte-navigation-dpad.md`](../refonte-navigation-dpad.md).
- **Remplace :** [ADR-0109](0109-le-focus-tv-entre-une-fois-ou-la-zone-le-decide.md) pour ce qui
  touche aux entrées de zone (`TvFocusEntries`, `TvTraversalPolicy`), une fois la phase 2 fusionnée.
- **Garde :** [ADR-0008](0008-focus-visible-du-lecteur-tv.md) (focus toujours visible, notre anneau),
  [ADR-0039](0039-force-du-geste-sur-le-trackpad-de-l-apple-tv.md) (un défilement par pas, force du
  geste, jamais de multi-pas vertical), [ADR-0108](0108-le-pont-d-accessibilite-de-l-apple-tv-ne-fait-plus-defiler.md)
  (garde-fou du pont d'accessibilité tvOS).

## Contexte

La navigation au D-pad s'est construite par couches qui se corrigent l'une l'autre (ADR-0006, 0008,
0039, 0108, 0109) : action des flèches et élan (`tv_key_repeat`), politique de parcours et entrées
de zone (`tv_focus_entry`), mémoire (`tv_focus_memory`), volets (`tv_focus_panes`), rangées du
lecteur (`tv_focus_rows`), défilement par pas (`tv_focus_scroll`), cible et Retour (`tv_focus`),
plus des gestionnaires de touches isolés dans les écrans. Environ 1 500 lignes, et chaque correction
en appelle une autre : deux `requestFocus` et deux défilements par flèche, un double Retour sur
Android, des sauts à l'autre bout de l'écran.

Le paquet `dpad` 3.3.0 fait l'essentiel de ce travail : régions avec mémoire, parcours TV, défilement
jusqu'à la cible, touches de télécommande. La lecture de son code et la phase 0 ont établi ce qu'il
impose (plan §2, rapport §3) :

| # | Constat | Ce qu'Onyx en fait |
|---|---|---|
| C1 | `onBack` de dpad ne voit que des **touches** ; Menu/‹ de l'Apple TV arrive en `popRoute`. | Le Retour se décide chez nous, dans `TvBack`, sur `didPopRoute` **et** sur l'`onBack` de dpad. |
| C2 | `goBack` est dans le jeu de touches par défaut ; Android l'envoie aussi en `popRoute`. Mesuré : 2 routes dépilées par appui. | `OnyxDpad` retire `goBack` du jeu sur Android ; `TvBack` absorbe en plus le second Retour d'origine différente à moins de 300 ms. |
| C3 | `enabled: false` laisse les raccourcis et avale les flèches ; `restoreFocus` pose un focus au démarrage. | Hors TV : jeu de touches **vide** et `restoreFocus: false`, jamais `enabled: false`. `Dpad` reste monté quand `TvMode.enabled` bascule : seule sa configuration change. |
| C4 | Les raccourcis de dpad sont sous `MaterialApp.shortcuts` et au-dessus des écrans : un `Focus.onKeyEvent` d'écran passe avant. | Le lecteur et les curseurs gagnent par construction. `TvArrowGate` se pose juste sous `Dpad`. |
| C5 | Chaque flèche parcourt les cibles construites de la route (coût linéaire). | `cacheExtent` des rangées borné en phase 2 ; critère « ≤ 4 ms » à mesurer sur machine. |
| C6 | Rien de construit dans la direction : dpad fait défiler puis réessaie. Mesuré : 2 pas perdus sur 16 à 40 ms de répétition, aucun à 80 ms. | `TvArrowGate` régule la répétition (110 ms, la cadence de l'ancien `TvKeyRepeat`) ; `StepTarget` borne les multi-pas aux cartes construites. |
| C7 | La mémoire persistante est une table **statique** par `memoryKey`, retrouvée par position à l'écran. | `TvRegion` range sa clé sous le profil (`"<profil>/<écran>/<zone>"`) ; `OnyxDpad` appelle `DpadRegionState.clearPersistentMemory()` quand le profil change (la méthode est sur `DpadRegionState`, pas sur `DpadRegion`). |
| C8 | `restore` sans mémoire retombe sur l'élément `entry`. | `entersAtTop` devient `entry: true` sur le premier élément (phase 2). |
| C9 | Sur tvOS, Select arrive en `enter`, vu par dpad et par l'`ActivateIntent` du framework. Mesuré : un seul `onSelect`. | Épinglé par un test d'invariant sur une cible simple et sur une cible qui enveloppe un bouton. |
| C10 | `onLongSelect` se mesure entre l'appui et le relâchement. | À vérifier sur les deux Siri Remote ; `TvNavTheme.longSelectDuration` = 500 ms. |
| C11 | Chaque `DpadFocusable` porte une sémantique de bouton. | Recette VoiceOver obligatoire avant la phase 2 (double annonce, pont ADR-0108). |
| C12 | `scrollPadding` est un seul nombre. | La marge latérale de la zone sûre tvOS : 80 pt sur 1920, soit ≈ 53 px de page ; le haut et le bas restent au padding des écrans. |
| C13 | dpad ne régule pas la touche maintenue ; `TvRemoteConfig` n'existe que sur tvOS. | Régulation dans `TvArrowGate` ; `TvRemoteConfig` d'abord sur tvOS si la machine réelle le valide. |
| C14 / N1 | À la reprise, `restoreFocus` rend le focus au dernier nœud monté sans vérifier que sa route est au premier plan. | **Parade `OnyxDpad`** (ci-dessous). Ticket amont à ouvrir chez `fluttercandies/dpad` (texte au rapport §4). |
| N2 | Des touches qui arrivent plus vite que l'application du focus partent toutes du même focus. Mesuré au simulateur : 12 pressions → 1 pas. | Rôle de `TvArrowGate` en phase 6 : regrouper une rafale en N pas et un seul `requestFocus`. |
| N3 | dpad note la mémoire à la **demande** de focus, pas à l'arrivée. | Sans effet hors rafale ; disparaît avec N2. |
| N4 | Un `DpadFocusable` rend son enfant non focalisable : le `onPressed` d'un bouton enveloppé n'est jamais appelé par Select. | `TvFocusable` reçoit l'action en `onSelect` ; le guard test l'exige de chaque `TvFocusable`. |
| N5 | `restoreFocus` ne repose pas le focus après un `unfocus()` explicite. | Tranché en phase 2 : `restoreFocus` seul, voir plus bas. |
| C15 | Les régions de dpad ne s'emboîtent pas ; une flèche cherche d'abord dans la région du focus (mesuré au simulateur, phase 2). | Une page n'est pas une région : `TvRegion.page`. Voir plus bas. |

## Décision

**dpad est le seul système de focus de l'app**, derrière une façade de deux widgets pour les écrans
(`TvFocusable`, `TvRegion`) et quatre pièces qui font ce que dpad ne fait pas.

- **`OnyxDpad`** (`lib/tv/nav/onyx_dpad.dart`) est le seul `Dpad`, posé dans `MaterialApp.builder`,
  toujours monté. Sur téléviseur : jeu de touches complet, sans `goBack` sur Android (C2), avec le
  Retour du navigateur (téléviseur LG) et Y de manette pour le menu ; `restoreFocus: true` ; thème
  `TvNavTheme`. Hors téléviseur : jeu vide et `restoreFocus: false` (C3). Il écoute `TvMode.enabled`
  sans reparenter l'app. Il publie le profil qui navigue (`TvNavScope`) et vide la mémoire de dpad
  quand ce profil change (C7).
- **Parade N1, tranchée :** à chaque `AppLifecycleState.resumed`, une image après la restauration
  de dpad, `OnyxDpad` regarde si le focus primaire est dans la route au premier plan de chacun des
  navigateurs qui l'englobent (`TvForegroundRoute`). Sinon, il donne le focus à la portée de la route
  au premier plan ; dpad y pose alors son élément d'entrée (`entry`, sinon le premier candidat), comme
  après un `push`. Un seul endroit choisit l'élément d'entrée. La parade se retire quand la
  correction amont est dans la version épinglée.
- **`TvBack`** (`lib/tv/nav/tv_back.dart`) est le seul à décider du Retour. Il se monte **au-dessus**
  de `MaterialApp` : Flutter consulte les observateurs dans l'ordre d'inscription, et celui de
  `WidgetsApp` dépile sans demander. Deux entrées (`didPopRoute`, `onBack` de dpad), une règle : ce
  qui peut se fermer se ferme, ce qui est poussé se dépile (`maybePop` du navigateur racine), et à la
  racine Retour est rendu au système — on ne retient jamais Menu à la racine (App Review tvOS). Deux
  Retours d'origines différentes à moins de 300 ms sont un seul appui. Depuis la phase 5, le contenu
  d'un onglet remonte d'abord à l'en-tête, et l'en-tête, quel que soit l'onglet, rend Retour au
  système (voir « Phase 5 »).
- **`TvArrowGate`** (`lib/tv/input/tv_arrow_gate.dart`) est le seul intercepteur de flèches, juste
  sous `Dpad` : il laisse passer, retient une répétition trop rapprochée (C6, C13), ou fait N pas
  d'un coup vers la carte que calcule **`StepTarget`** (horizontal seulement, borné aux cartes
  construites), avec un seul `requestFocus`.
- **`TvFocusable`** garde son API. Sur dpad (`TvDpadFocusable`), l'action passe par `onSelect`
  (N4), le toucher reste à l'enfant (`tapToSelect: false`), le menu de la carte passe par l'appui
  long, la touche menu ou Y, et l'anneau reste celui d'Onyx, dessiné dans le `builder` (pas de
  `DpadHighlight`, pas d'effet « soulevé » tvOS : changement de design hors périmètre).
- **`TvRegion`** a cinq formes (`.rail`, `.grid`, `.list`, `.tabs`, `.pane`) qui fixent l'entrée et
  les bords. Sous `OnyxDpad`, c'est une `DpadRegion` dont la clé est rangée sous le profil ; ailleurs,
  elle délègue à l'ancien système à l'identique.
- **Règles, gardées par `test/no_parallel_focus_system_test.dart` :** les écrans n'emploient ni
  `DpadFocusable`, ni `DpadRegion`, ni `Dpad.of`, ni l'import de dpad (seul `lib/tv/` le fait) ; un seul
  `Dpad`, dans `onyx_dpad.dart` (une racine imbriquée pour le chrome du lecteur demandera sa propre
  ADR) ; aucun nouveau `FocusTraversalGroup`, politique de parcours, intent directionnel, `Shortcuts`,
  `onKeyEvent`, gestionnaire global de touches, `Scrollable.ensureVisible` ni widget de l'ancien
  système hors de la liste de l'existant, qui ne fait que rétrécir ; chaque `TvFocusable` porte son
  action en `onSelect`.
- **`pubspec.lock` :** produit par le Flutter standard. flutter-tvos (Flutter 3.44) le réécrit au
  build ; ce lock-là ne se commite jamais.

## Phase 2 : décisions et constats

**Décisions du plan §10**, prises le 2026-11-06 sur les recommandations : notre anneau, sans
highlight volant ni effet « soulevé » ; pas de racine `Dpad` imbriquée (le chrome du lecteur en
demanderait une ADR) ; bêta derrière `ONYX_TV_NAV=dpad` ; entrée d'une rangée par sa mémoire
(`restore`), sinon par l'élément `entry` ; Menu dans le contenu d'un onglet remonte d'abord à
l'en-tête (phase 5) ; Lecture/Pause sur une affiche : rien pour l'instant.

**Le drapeau.** `TvNavEngine` (`lib/tv/nav/tv_nav_engine.dart`) lit
`String.fromEnvironment('ONYX_TV_NAV')` une fois ; une valeur inconnue retombe sur `legacy`.
Seul `main.dart` le consulte : il monte `TvNavRoot` (`TvBack` au-dessus de `MaterialApp`,
`OnyxDpad` puis `TvArrowGate` dans son `builder`, raccourcis sans rien de directionnel, plus
de `TvTraversalPolicy` ni de `TvDirectionalFocusAction`) ou l'ancien système tel quel.
`TvFocusable` et `TvRegion` suivent ce qui est monté (`TvNavScope`) : les écrans ne changent pas,
et un test monte l'un ou l'autre système sans recompiler (`TvNavHarness.forEachEngine`).

**`restoreFocus` de dpad gagne, `TvFocusGuard` n'est pas monté sous dpad.** Les deux reposent le
focus quand il se perd ; montés ensemble, c'est deux `requestFocus` pour une perte. dpad couvre
ce que le garde-fou couvrait (carte détruite, avec en plus la position à l'écran ; route poussée
sans `autofocus` ; reprise, complétée par la parade N1) et le fait sans code à nous. Reste N5 :
après un `unfocus()` explicite (les appels de l'app suivent l'envoi d'un formulaire, la fermeture
d'une recherche ou la sortie d'un champ sur le web LG), dpad ne repose rien ; mais la flèche suivante part de la portée vide et
`DpadTraversalPolicy` pose alors son candidat initial, et une vue qui a perdu le focus de la
plateforme (focus « garé », téléviseur LG) le retrouve à la première flèche (`_move` restaure le
dernier nœud). Ce qui est perdu : un OK pressé dans cet état ne fait rien, la première touche
utile doit être une flèche. À rejouer sur le web LG en phase 4.

**C15, mesuré au simulateur : une page n'est pas une région.** Les régions de dpad ne
s'emboîtent pas, et une flèche cherche d'abord dans la région du focus. Posée autour de tout
l'accueil (le `TvFocusMemory(entersAtTop: true)` de l'onglet traduit tel quel), une région faisait
sauter, sous le bandeau, toute la première rangée pour « Tout voir » de la deuxième : un élément
direct de la page, quand les cartes appartiennent à leur rangée. `TvRegion.page` ne pose donc
rien sous dpad. Conséquence assumée : la mémoire « où j'étais dans cet onglet », qui remontait
avec l'ancien système d'une rangée à l'onglet, ne vit plus que par rangée ; à la première visite,
on entre dans un onglet par l'élément le plus proche de l'onglet de l'en-tête, pas par le coin
haut-gauche.

**Mémoire et clés.** Les rangées de l'accueil ont une clé de mémoire (`home/<titre>`, sous le
profil) ; celles d'une fiche (titres similaires, casting, saisons) n'en ont pas : la mémoire
persistante de dpad se retrouve par position à l'écran, et une clé partagée par toutes les fiches
poserait le focus, dans le casting d'un film, là où on l'avait laissé dans un autre (C7). Les
cartes de l'accueil sont clées par média, sous dpad seulement (`TvRegion.itemKey`) : l'ancien
garde-fou, devant une carte recréée, renvoyait le focus en haut de la page. Pas de
`findChildIndexCallback` : le nœud focalisé suivrait sa carte déplacée hors de l'écran au
rechargement de « Reprendre la lecture ».

**Le lecteur** garde `TvFocusRows` : ses rangées traitent toutes les flèches dans un
`onKeyEvent`, qui passe avant dpad (C4) ; ses `TvFocusable` deviennent des `TvDpadFocusable`
(OK par `onSelect`, même anneau, y compris sur un nœud qui arrive déjà focalisé).

## Phase 3 : décisions et constats

**Le drapeau reste.** Le plan retirait `ONYX_TV_NAV` avant la phase 3. Décidé le 2026-11-06 : il
reste, défaut `legacy`, parce qu'aucun essai n'a été fait sur une vraie Apple TV et que
l'utilisateur ne peut pas tester pour le moment ; sans lui, l'app doit rester celle de `main`.
Il disparaît quand la recette sur vraie Apple TV est verte, au plus tard en phase 8. Chaque
écran migré marche donc dans les deux modes, et ce que l'ancien système faisait dans un écran
(un `Focus(onKeyEvent:)`) est **déplacé à l'identique** dans la branche `legacy` de la façade
(`TvCardDirections.legacy`, `TvSlideEdges`), qui part avec le drapeau. La liste du guard test
rétrécit d'autant : `settings_screen`, `episode_tile` et `hero_carousel` en sortent.

**Volets (`TvRegion.panes` / `.pane`).** Sous dpad, `TvRegion.panes` ne pose rien (C15) et
chaque volet est une `TvPaneRegion`, une `DpadRegion` qui reprend trois règles de
`TvFocusPanes` que dpad n'a pas : sans souvenir, on entre sur le **premier** élément du volet
(le plus haut), pas sur celui à la même hauteur ; le souvenir est le dernier élément focalisé
du volet, même focalisé hors de dpad (une ligne de réglage est un `InkWell`, que dpad ne note
pas) ; droite entre dans le bouton posé au bout d'une ligne cliquable et gauche en ressort
(`TvContainedSteps` : dpad ne cherche que ce qui est *à droite* du rectangle quitté, et un
bouton contenu dans sa ligne ne l'est jamais). Elle surcharge `DpadRegionState.resolveEnter`
(`@internal` dans 3.3.0) et pose une sous-classe de `DpadTraversalPolicy` sous le groupe de la
région : deux points à relire à chaque montée de dpad.

**Puces des réglages (`SettingsChoiceFocus`).** Le parcours de dpad préfère aussi ce qui est
dans le faisceau, mais, entre deux cibles du faisceau, c'est la plus proche *en travers* qui
gagne, au centre près. Depuis un menu aligné à droite, la porte d'entrée de la rangée (toute la
ligne, centre au milieu) perdait contre le menu suivant, et Bas sautait la rangée. Une seconde
porte au quart droit de la ligne la rend atteignable ; avec l'ancien système, les deux portes
mènent à la même puce.

**Cartes à boutons (`TvFocusable.onDirection`, `childFocus`).** Sous dpad, l'enfant d'un
`TvFocusable` est exclu du focus (N4) : les icônes d'une ligne d'épisode, le menu d'une ligne de
téléchargement n'étaient plus atteignables. `childFocus` les garde focalisables ;
`onDirection` est le `DpadFocusable.onDirection` de dpad (une flèche que la carte prend avant le
parcours), étendu aux cibles internes de la carte pour gauche et droite. Sans `onDirection`,
une carte `childFocus` entre dans ses boutons à droite et en ressort à gauche. Sous dpad, tout
ce que contient une carte `childFocus` sort du parcours directionnel : haut et bas passent de
carte en carte sans s'arrêter sur le menu de la ligne suivante ni sur l'`InkWell` qui double la
carte (vu sur les téléchargements), et depuis une icône ils vont à la carte voisine, puisque la
carte contient l'icône. Le menu d'un téléchargement en cours est
atteignable sous dpad ; avec l'ancien système, la ligne inactive le rendait inatteignable.

**Bandeau (`TvRegion.slide`).** Une zone par diapositive, posée **dans** la page : au bord
(`stop`), dpad fait d'abord défiler ce qui défile entre le focus et la zone, et autour du
`PageView` ce serait lui, de 80 % de page, avant l'`onEdge` qui tourne la diapositive. Le
défilement automatique ne tourne que si rien du bandeau n'a le focus : il ne déplace pas le
focus (épinglé par `tv_navigation_test`).

**Cartes pleine largeur (`TvFocusable.wide`).** Même cause que les puces : le bandeau
« Reprendre » d'une lecture en cours ailleurs, centré sur toute la largeur entre le bouton du
bandeau et la première rangée, tous deux calés à gauche, était sauté par Haut comme par Bas.
Sous dpad, `TvWideCard` pose une porte invisible au quart gauche de la carte, dans une zone dont
la carte est l'entrée : dpad trouve la porte et pose le focus sur la carte en un seul
`requestFocus`. Sans effet avec l'ancien système.

**Entrées de rangée.** La bulle de la saison affichée est l'entrée de sa rangée (`entry`) : Bas
depuis « Ajouter à une liste » tombait sur la saison 8, sous l'icône. Les avatars du sélecteur
sont une `TvRegion.rail` : gauche depuis le premier partait sur « Retour ».

**Reste ouvert : les grilles en sliver.** Une `TvRegion` ne s'enveloppe pas autour d'un sliver
(son `Focus` y pose un nœud de sémantique) : les grilles des listes et des bibliothèques n'ont pas
de mémoire sous dpad, et revenir de « Nouvelle liste » ramène à la tuile la plus proche du bouton,
pas à celle qu'on regardait (case sautée dans `lists_navigation_map_test`). À traiter avec une
forme sliver de `TvRegion`.

**« Lire » sur une fiche.** C'est une pastille Material (`HeroPill`, un `InkWell`), pas un
`TvFocusable` : la marquer `entry` demanderait de l'envelopper, ce qui changerait l'ancien mode.
Elle garde son `autofocus`, que dpad laisse passer avant sa propre restauration ; la parade N1
(reprise) retombe, elle, sur le premier élément de la fiche. À reprendre quand le drapeau part.

**`TvFocusCaption` gardé.** Il n'agit pas sur le focus : il écoute `FocusManager` et écrit le
nom de l'icône focalisée. Il marche tel quel sous les deux systèmes.

**Le Bas perdu de l'onglet Films** (phase 2) : ce n'était pas dpad. Pendant le chargement, le
menu de tri était la seule cible sous l'en-tête ; Bas sautait au bout de la ligne, sur ce petit
menu à peine marqué, et le Bas suivant tombait sur l'affiche la plus à droite. Le tri sort du
parcours tant que la grille charge, dans les deux modes (seul changement visible sans le
drapeau), épinglé par `library_screen_tv_test`.

**Restent hors navigation**, dans la liste du guard test : la touche lecture/pause du bandeau
« Reprendre » (`remote_playback_banner`), le suivi de la bulle de saison qui grandit
(`season_bubbles`, un défilement à la fin de l'animation, pas par flèche), le défilement du
texte d'un document (`legal_document_screen`) et le zoom de la grille au clavier
(`poster_grid_zoom_region`).

## Phase 4 : champs texte, clavier à l'écran, web LG

**Le champ d'une carte `TvDeferredKeyboard` était exclu du focus sous dpad.** `DpadFocusable`
rend son enfant non focalisable (`excludeChildFocus`, N4) : OK sur le cadre du champ demandait le
clavier, mais le champ ne prenait jamais le focus, et le clavier restait fermé. Mesuré avec le
banc : après OK, `editable=false`. dpad prévoit le montage inverse pour un champ de saisie
(`excludeChildFocus: false`), que la façade expose en `TvFocusable.editable`. Sans effet avec
l'ancien système.

**`TvDeferredKeyboard` reprenait le focus au voisin.** Quand le champ perdait le focus, il rendait
le focus à son cadre à l'image suivante, pour ne laisser la télécommande nulle part. Sous dpad, une
flèche qui sort du champ pose déjà le focus sur le voisin : il le lui reprenait, et la
télécommande rebondissait sur la barre qu'elle venait de quitter. Sous dpad seulement, le champ ne
reprend plus le focus quand il est déjà sur une vraie cible hors du widget. Avec l'ancien système
la reprise reste inconditionnelle : `TvFocusGuard` donne parfois le focus lâché à l'élément
suivant avant elle, et c'est elle qui le corrige.

**`web_tv_field_exit`, mesuré** (`web_tv_field_exit_test`, dans les deux modes) :

| Touche, champ d'une ligne, clavier refermé | Ancien système (`WebTvFieldExit`) | dpad seul |
|---|---|---|
| Haut, Bas | sort, cadre du champ (webOS) ou voisin (Android, Apple TV) | sort vers le voisin, d'un seul appui |
| Gauche, Droite | webOS : reste au texte. Android, Apple TV : sort aussitôt | sort au bord du texte seulement |
| Texte sur plusieurs lignes | garde ses flèches | garde ses flèches, sort du tout début ou de toute fin |

- **webOS : dpad remplace `WebTvFieldExit`**, qui n'y est plus installé sous dpad
  (`TvMode.initialize`). Haut et Bas sortent par la règle de dpad, Gauche et Droite à ses bords.
- **Android TV et Apple TV : le filet reste, pour Gauche et Droite seulement.** Leur clavier ouvert
  garde la télécommande, et un champ resté focalisé après Retour laissait Gauche au curseur jusqu'au
  début du texte (« http://192.168.1.50 » : dix-neuf appuis). Sous dpad, `WebTvFieldExit` laisse
  Haut et Bas à dpad et ne prend plus que les deux flèches horizontales. Pas essayé sur machine
  réelle : ce sont les tests et le simulateur Apple TV qui l'établissent.

**Web LG.** Plus de `webTvShortcuts` sous dpad : `TvNavRoot.shortcuts` ne les monte pas
(`tvRemoteShortcuts(webTv: false)`) et l'ancien jeu ne vit plus que dans la branche `legacy`.
Les flèches et Entrée passent par le jeu de touches d'`OnyxDpad`, posé plus près du focus que les
raccourcis de page de `WidgetsApp` ; un interrupteur s'active à OK (`web_tv_dpad_test`).

**Retour de la télécommande LG.** Flutter web ne lit que `key` et `code` (`keyCode` n'entre pas
dans sa table) : un 461 resté `Unidentified` devient une touche inconnue. `web/webos_remote.js`
le réécrit en Échap avant Flutter (ADR-0076) ; Échap est déjà dans le jeu `back` d'`OnyxDpad`,
avec `browserBack` (nom que le moteur web donne au Retour d'un navigateur) et `goBack` (le nom
que le simulateur de LG lui donne), hors Android (C2). **Il n'y avait donc rien à ajouter** : la
phase 1 avait posé les trois, la phase 4 les épingle (`web_tv_dpad_test`). `flutter_test` ne
sait pas simuler `browserBack` ni `goBack`, le test de bout en bout est celui d'Échap.

**Constat sur l'ancien système, laissé tel quel.** Sur téléviseur, passer d'un champ au suivant
(touche d'action du clavier : `_focusNext`) rend le focus au cadre du champ quitté, pas au champ
suivant : la reprise inconditionnelle de `TvDeferredKeyboard` passe après la demande de focus du
suivant. `login_screen_keyboard_test` ne le voyait pas, ses champs n'étant pas différés ; porté
sur le banc en mode TV, ses quatre tests de chaîne ne passent qu'avec dpad et sont ignorés
(`skip`) avec l'ancien système, avec la raison. Pas corrigé : le plan demande l'ancien système à
l'identique, et la correction (ne pas reprendre le focus quand il est sur un autre champ) change
son comportement. À décider.

## Phase 5 : Retour, Menu, dialogues

**`TvBack` décide seul, sous dpad.** Ses entrées : `didPopRoute` (Menu/‹ de l'Apple TV, Retour
d'Android) et les touches Retour. Une touche arrive par l'`onBack` de dpad, ou, quand dpad se
tait (champ de saisie focalisé, ou touche rendue par `TvBack` à la racine), par `TvBackKeyAction`
dans les raccourcis de `MaterialApp`. Les deux voies lisent la même liste de touches
(`OnyxDpad.backKeysFor`, sans `goBack` sur Android). `TvBackAction` n'est plus monté sous dpad :
il dépilait la coquille et retenait Menu à la racine. L'ordre :

1. le clavier d'un champ différé se referme (`TvDeferredKeyboardState.releaseFocused`, que la
   coquille seule appelait), puis le dialogue, la feuille ou le menu du dessus se ferme ;
2. ce qui est poussé se dépile. 1 et 2 sont un seul geste : le `maybePop` du navigateur racine,
   quand sa route du dessus prend Retour (elle se dépile, ou un `PopScope` la retient, comme le
   lecteur). Sur téléviseur, la coquille n'a pas de navigateur imbriqué : fiches, feuilles et menus,
   même ceux qui prennent le navigateur le plus proche, sont des routes du navigateur racine. La
   route du dessus se lit par `popUntil` avec un prédicat qui accepte la première route : c'est la
   seule lecture publique et synchrone, et une touche doit savoir tout de suite si elle est
   consommée ;
3. les marches des écrans (`TvBackStep`, la plus récente d'abord, seulement si sa route est au
   premier plan) : la coquille (`ShellTvBack`) remonte le focus du contenu vers l'onglet affiché ;
4. sinon c'est la racine : `didPopRoute` rend faux, la touche n'est pas consommée, et l'appareil
   revient à son écran d'accueil.

**Décision : sur l'en-tête de n'importe quel onglet, Retour est rendu au système.** On ne revient
pas d'abord à l'accueil. C'est la convention tvOS : le `UITabBarController` de tvOS ne ramène pas à
son premier onglet, et Menu pressé sur la barre d'onglets quitte l'app vers l'écran d'accueil de
l'Apple TV, quel que soit l'onglet affiché. L'en-tête est la racine de l'app : y retenir Menu pour
changer d'onglet, c'est retenir Menu à la racine, ce que l'App Review tvOS refuse. La règle est la
même sur Android TV, webOS et au clavier : une seule règle se teste en une table, et quitter l'app
depuis son niveau le plus haut est aussi le comportement d'Android TV. Ce qui disparaît sous dpad,
et seulement là : le retour à l'accueil depuis un autre onglet, et le « appuyez de nouveau sur
Retour pour quitter » de l'accueil, qui retenait le premier Menu. L'ancien système garde les deux à
l'identique (`ShellTvBack`, branche `legacy`).

**Menu en `popRoute`, en Échap, ou les deux.** Rien n'a été essayé sur vraie Apple TV. Le
dédoublonnage par origine (deux Retours d'origines différentes à moins de 300 ms) couvre les trois
cas, dans les deux ordres, figés par `tv_back_rules_test`. Le lecteur lit encore ses touches
lui-même (phase 7), avant dpad (C4) : un Menu reçu en touche *et* en `popRoute` y défaisait deux
couches, avec les deux systèmes. Sous dpad, ses trois lectures de touche (`PlayerKeyBack`, le menu
ouvert, une section du menu de réglages) passent par `TvBack.claimKey`, qui note l'appui et avale la
seconde moitié. Sans `TvBack` (ancien système), `claimKey` rend toujours vrai : rien ne change.

**Dialogues, feuilles, menus.** L'inventaire de l'app compte une soixantaine de fenêtres. Toutes
sont des routes, sauf les menus du lecteur (`PlayerPopupHost`, un `OverlayEntry`), migrés en phase
7. Les menus de recherche du bureau et les aperçus au survol ne sont pas atteignables au D-pad. Sous
dpad, le focus entre dans la route (son `autofocus`, ou l'entrée que pose dpad), n'en sort pas aux
flèches, et Retour la ferme en rendant le focus à l'élément d'origine. C'est épinglé par
`tv_modal_focus_test` pour chaque mécanisme (`showDialog`, `showModalBottomSheet` sur le navigateur
proche et racine, `showMenu`, `DropdownButton`, route transparente de la présentation) et pour les
dialogues partagés qui se montent sans fournisseur (`confirmSettingsAction`, `showSynopsisDialog`,
`confirmDeleteRequest`, `askDeclineReason`, `showWatchListEditor`, `showRecoveryCodesDialog`). Aucun
dialogue n'a eu à être corrigé.

**Vu au simulateur Apple TV**, en `ONYX_TV_NAV=dpad`, `popRoute` rejoué par une extension de service
temporaire, non commitée, comme en phase 0. Échap est passé par le `keyMessageHandler`, comme une
touche du moteur ; le bouton Menu ne s'injecte pas.

| État | `popRoute` | Échap |
|---|---|---|
| Contenu de l'accueil (« Reprendre » du bandeau) | focus sur « Accueil » | idem, touche consommée |
| Contenu de Films (une affiche) | — | focus sur « Films », pas sur « Accueil » |
| Feuille « Ajouter à une liste » | fermée, focus rendu au signet ; flèches piégées avant | — |
| Dialogue « Relancer la détection » ouvert depuis un menu | fermé, focus rendu au crayon ; flèches piégées avant | — |
| Fiche (série, film) | dépilée, focus rendu à « Plus d'infos » | dépilée, focus rendu à l'affiche d'origine |
| En-tête, onglet Accueil | l'app passe à l'écran d'accueil de l'Apple TV | — |
| En-tête, onglet Films | l'app passe à l'écran d'accueil de l'Apple TV | touche non consommée |

**Constat sur le banc, corrigé.** `TvNavHarness.sendKey` livrait `goBack` à `HardwareKeyboard` seul,
que le `FocusManager` n'écoute pas : les tests de `goBack` passaient sans que la touche arrive nulle
part. Livrée pour de vrai, elle a montré un second jeu de touches Retour sous dpad : `TvNavRoot`
reprenait celles de l'ancien `tvRemoteShortcuts`, réglées sur `AppPlatform.isAndroid` et non sur la
liste d'`OnyxDpad`. Sur l'hôte de test, `goBack` y fermait un dialogue Android avant que `popRoute`
ne dépile la page dessous. `TvNavRoot` ne garde plus que OK et A, et la liste d'`OnyxDpad`.

**Guard test.** `no_parallel_focus_system_test` gagne « un seul Retour : TvBack ». Il recense les
`PopScope`, `NavigatorPopHandler` et touches Retour lues à la main hors de `lib/tv/nav/`. Chaque
entrée de la liste dit pourquoi : `TvBack` atteint le `PopScope` par `maybePop`, ou la touche passe
par `TvBack.claimKey`, ou c'est l'ancien système. La liste ne fait que rétrécir. `tv_back_action_test`
est porté sur le banc et tourne dans les deux modes. La classe `TvBackAction` reste, l'ancien
système la monte encore.

## Conséquences

- Phase 1 : aucun changement visible. `TvFocusable` est réexporté tel quel par
  `lib/tv/nav/tv_focusable.dart`, `TvRegion` délègue à l'ancien système faute d'`OnyxDpad` monté,
  et `OnyxDpad`, `TvBack`, `TvArrowGate` ne sont montés que par le banc de test
  (`test/support/tv_nav_harness.dart`).
- La cadence de répétition et le calcul du voisin sur la ligne n'ont plus qu'une source :
  `TvKeyRepeat.repeatInterval` renvoie à `TvArrowGate.defaultRepeatInterval`, et l'ancien
  `TvDirectionalFocusAction` appelle `StepTarget.nextOnLine`.
- Les invariants du plan §6.4 qui s'appliquent déjà sont épinglés : double Retour Android
  (`onyx_dpad_test`, `tv_back_test`), mode non-TV (`onyx_dpad_test`), un Select = un `onSelect`
  (`tv_dpad_focusable_test`), focus dans la route au premier plan après reprise, y compris pour une
  route poussée pendant la pause (`onyx_dpad_test`), mémoire vidée au changement de profil
  (`onyx_dpad_test`), un `Focus.onKeyEvent` d'écran avant dpad (`tv_arrow_gate_test`).
- Les deux systèmes ne tournent jamais dans la même zone : la phase 2 bascule la racine, la cible
  et les zones du shell d'un seul coup, derrière `--dart-define=ONYX_TV_NAV=dpad`.
- Une montée de dpad se fait dans `lib/tv/nav/` et `lib/tv/input/` seulement, après relecture de
  `root.dart`, `region.dart` et `focusable.dart` contre les constats ci-dessus.
- Phase 2 : sans drapeau, aucun changement visible ; avec `ONYX_TV_NAV=dpad`, la racine, la cible
  et les zones du shell passent sur dpad d'un seul coup. Les tests de focus tournent dans les deux
  modes ; la carte de navigation de l'accueil et de l'en-tête est `shell_navigation_map_test`.
- Phase 3 : sans drapeau, un seul changement visible (le tri d'une bibliothèque hors du parcours
  pendant son chargement) ; avec `ONYX_TV_NAV=dpad`, les réglages, la fiche, le bandeau, les
  téléchargements et les écrans de contenu passent sur dpad. Une carte de navigation par écran.
- Phase 4 : sans drapeau, aucun changement visible ; avec `ONYX_TV_NAV=dpad`, les champs texte
  s'ouvrent à OK et se quittent par les flèches, et webOS n'installe plus `WebTvFieldExit`. Le
  guard test ne grandit pas : `web_tv_field_exit.dart` y reste (Android TV, Apple TV).
- Phase 5 : sans drapeau, aucun changement visible ; avec `ONYX_TV_NAV=dpad`, Retour ne retient
  plus jamais Menu à la racine (plus de confirmation avant de quitter, plus de retour à l'accueil
  depuis un autre onglet), et un Menu reçu en touche et en `popRoute` ne défait qu'une couche, lecteur
  compris. Reste à mesurer sur vraie Apple TV : la voie par laquelle Menu arrive (rapport §5.1).
- Reste ouvert, et à écrire ici : les mesures de la recette sur machine réelle (statut), les critères
  du plan §1 mesurés en phase 8, et le retrait du drapeau (avec lui `TvFocusGuard`,
  `TvCardDirections.legacy` et `TvSlideEdges`).
