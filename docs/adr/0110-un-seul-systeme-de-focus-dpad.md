# ADR-0110 — Un seul système de focus : dpad

- **Statut :** proposé. La phase 0 (rapport [`refonte-navigation-dpad-phase0.md`](../refonte-navigation-dpad-phase0.md))
  a tout vérifié au simulateur et sans écran, rien sur une vraie Apple TV. La phase 2 monte dpad
  **derrière le drapeau de compilation `ONYX_TV_NAV=dpad`** (défaut `legacy` : sans lui, l'app
  est celle d'avant la refonte) ; vue au simulateur Apple TV seulement. Aucun essai sur une vraie
  Apple TV n'a été fait : l'utilisateur ne peut pas tester pour le moment.
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
  `TvRegion`, `TvDpadFocusable`, `TvForegroundRoute`, `tv_nav_theme.dart`), `lib/tv/input/`
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
  Retours d'origines différentes à moins de 300 ms sont un seul appui. La remontée du contenu d'un
  onglet vers l'en-tête s'ajoute en phase 5.
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
- Reste ouvert, et à écrire ici : les mesures de la recette sur machine réelle (statut), les critères
  du plan §1 mesurés en phase 8, et le retrait de `TvFocusGuard` avec le drapeau.
