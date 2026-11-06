# Refonte de la navigation TV sur dpad 3.3.0 — plan de migration

- **Statut :** plan, décision proposée par l'ADR-0110. Phase 1 faite (fondations non montées), phase 2 faite derrière le drapeau `ONYX_TV_NAV` (défaut `legacy`) ; ni l'une ni l'autre n'est essayée sur une vraie Apple TV.
- **Date :** 2026-11-06
- **Branche d'essai :** `spike/dpad-tvos` (banc d'essai `app/lib/spike/dpad_spike_main.dart`, supprimé en fin de phase 1).
- **Prolonge / remplace :** remplace en pratique le mécanisme de l'ADR-0109 (entrées de zone) ; garde l'ADR-0008 (focus toujours visible), l'ADR-0039 (un défilement par pas, force du geste) et l'ADR-0108 (garde-fou du pont d'accessibilité tvOS).
- **Sources lues :** code de `dpad-3.3.0` (`root.dart`, `traversal.dart`, `region.dart`, `focusable.dart`, `key_set.dart`) et README de `flutter_tvos-1.1.3`. Les constats du §2 en viennent ; chacun est marqué *lu* (vrai par construction) ou *à mesurer* (dépend de la machine).

## 1. Pourquoi, et ce qu'on veut au bout

La navigation au D-pad repose aujourd'hui sur une pile de mécanismes qui se
corrigent les uns les autres (ADR-0006, 0008, 0039, 0108, 0109) :

| Mécanisme actuel | Fichier | Lignes |
|---|---|---|
| Action des flèches + `nextOnLine` + élan | `tv/tv_key_repeat.dart` | 227 |
| Politique de parcours + entrées de zone | `tv/tv_focus_entry.dart` | 95 |
| Mémoire de zone | `tv/tv_focus_memory.dart` | 175 |
| Volets (réglages) | `tv/tv_focus_panes.dart` | 163 |
| Rangées (lecteur) | `tv/tv_focus_rows.dart` | 207 |
| Défilement par pas | `tv/tv_focus_scroll.dart` | 153 |
| Cible de focus, anneau, raccourcis, Retour | `tv/tv_focus.dart` | 493 |
| Gestionnaires de touches isolés | `player_*`, `episode_tile`, `app_slider`, `hero_carousel`… | ≈ 55 occurrences |

**Objectif : un seul système de focus.** dpad décide où va le focus, comment
une zone se souvient et quand la page défile. À côté, il ne reste que ce que
dpad ne sait pas faire et qu'aucun SDK ne fera à notre place : **le Retour
système** (tvOS et Android l'envoient en `popRoute`, pas en touche), **la
cadence et la force des flèches** (répétition Android, trackpad de la Siri
Remote), le clavier à l'écran, le garde-fou du focus.

**Critères de réussite** (mesurés à la phase 8) :

1. Un seul point d'installation (`OnyxDpad`), deux widgets publics pour les
   écrans (`TvFocusable`, `TvRegion`), un seul point d'interception des
   flèches (`TvArrowGate`) et un seul point de Retour (`TvBack`). Un guard
   test interdit le reste.
2. Plus aucun second `requestFocus` ni second défilement par pas de flèche.
3. Le code de `lib/tv/` qui gère le focus passe d'environ 1 500 lignes à moins
   de la moitié ; chaque fichier reste sous 800 lignes (ADR-0052).
4. Sur la machine la plus lente visée, le traitement d'une flèche (de la
   touche au focus posé) tient sous **4 ms** et aucun pas ne fait sauter une
   image (build `--profile`, timeline DevTools).
5. Recette complète verte sur Android TV, Apple TV (simulateur **et** vraie
   machine), webOS, clavier de bureau, et aucune régression au toucher.

## 2. Ce que le code de dpad impose (constats)

Ces points changent le plan d'origine. Ils sont là pour que personne n'ait à
les redécouvrir sur la télé.

| # | Constat | Conséquence pour Onyx |
|---|---|---|
| C1 | *Lu.* `Dpad` n'écoute pas `didPopRoute` : il n'observe que le cycle de vie. Son `onBack` ne se déclenche que sur une **touche** (`escape`, `goBack`, `gameButtonB`). | Sur Apple TV, le moteur envoie Menu/‹ en `popRoute` (README `flutter_tvos`) : **`onBack` de dpad ne verra jamais Menu.** Le Retour se centralise chez nous (`TvBack`, phase 5), pas dans dpad. |
| C2 | *Lu.* Le `goBack` d'Android est dans `DpadKeySet.defaultBack` ; Android l'envoie aussi en `popRoute`. | **Double Retour garanti** sur Android avec le jeu de touches par défaut. `OnyxDpad` retire `goBack` du jeu sur Android, comme `isSelfHandledBackKey` aujourd'hui. |
| C3 | *Lu.* `Dpad(enabled: false)` laisse les raccourcis installés et **avale les flèches** (pour que celles du framework ne naviguent pas). `restoreFocus` (vrai par défaut) pose un focus au démarrage et à chaque perte. | Ne **jamais** utiliser `enabled: false` pour le mode non-TV : le bureau perdrait ses flèches et le téléphone afficherait un focus. Hors TV : jeu de touches **vide** et `restoreFocus: false`. `TvMode.enabled` est un `ValueNotifier` qui peut basculer en cours de route : `Dpad` reste toujours monté, seule sa configuration change (pas de reparentage, pas de perte d'état). |
| C4 | *Lu.* Les raccourcis de dpad vivent dans un `Shortcuts` posé par `MaterialApp.builder`, donc **sous** les `shortcuts:` de `MaterialApp` et **au-dessus** de tous les écrans. Un `Focus(onKeyEvent:)` d'écran voit la touche **avant** dpad ; un gestionnaire `HardwareKeyboard` la voit avant tout le monde mais ne peut pas l'arrêter. | Le lecteur et les curseurs gagnent par construction : le risque « les `onKeyEvent` passent-ils avant dpad ? » devient un simple test d'invariant. Les raccourcis directionnels de `MaterialApp.shortcuts` deviennent inutiles et sont retirés. Le point d'interception des flèches (`TvArrowGate`) se place **juste sous** `Dpad`, pas en `HardwareKeyboard`. |
| C5 | *Lu.* Chaque flèche parcourt `scope.traversalDescendants` de la route : coût linéaire en nombre de cibles construites. | Sur l'accueil (≈ 10 rangées × cartes du cache), c'est le premier suspect de lenteur. `cacheExtent` des rangées à borner, mesure en phase 0 sur la machine la plus lente (critère 4). |
| C6 | *Lu.* Si rien n'est construit dans la direction, dpad fait défiler puis **réessaie** (`_scrollForMore`) : la carte non construite d'une `ListView.builder` est atteinte. Le réessai attend la fin de l'animation. | Une flèche maintenue peut arriver pendant ce réessai : c'est exactement le cas « la rangée bloque » qu'a corrigé `TvKeyRepeat`. À mesurer, pas à supposer. |
| C7 | *Lu.* La mémoire de région est un `WeakReference<FocusNode>` + le **rectangle global** du dernier focus. La mémoire persistante est une `Map` **statique** indexée par `memoryKey`, pour toute l'app. | (a) Une carte détruite (liste rafraîchie, rangée reconstruite) est retrouvée par **position à l'écran**, pas par index ni par identifiant. (b) Deux profils partagent la même mémoire si la clé est la même. ⇒ `memoryKey` = `"<profil>/<écran>/<rangée>"`, `clearPersistentMemory()` à la déconnexion et au changement de profil, `ValueKey(mediaId)` sur chaque carte pour que le nœud suive l'élément. |
| C8 | *Lu.* `DpadEnterBehavior` = `restore` / `entry` / `nearest`. `restore` sans mémoire retombe sur l'élément `entry`. | `entersAtTop` (premier élément visible à la première visite) s'obtient sans code à nous : `enter: restore` + `entry: true` sur l'index 0. |
| C9 | *Lu.* Sur tvOS, Select arrive en `LogicalKeyboardKey.enter`, qui passe **et** par le jeu `select` de dpad **et** par l'`ActivateIntent` du framework. `DpadFocusable` évite le double déclenchement ; un `TvFocusable` qui enveloppe un bouton Material, non. | Test d'invariant « un Select = un `onSelect` » sur une cible simple **et** sur une cible qui contient un bouton. |
| C10 | *Lu.* `onLongSelect` est mesuré au temps entre la touche enfoncée et relâchée (`longSelectDuration`), pas aux répétitions. | Dépend de ce que le moteur tvOS envoie au relâcher de Select : à vérifier sur les deux générations de Siri Remote (phase 0). |
| C11 | *Lu.* 3.3.0 donne à chaque `DpadFocusable` une sémantique de bouton et une activation VoiceOver. | Risque de **double nœud sémantique** avec nos `Semantics` actuels, et d'interaction avec le pont d'accessibilité tvOS qui fait défiler les rangées tout seul (ADR-0108). Recette VoiceOver obligatoire. |
| C12 | *Lu.* `DpadThemeData.scrollPadding` est **un seul nombre**, pas des marges par côté. | La zone sûre tvOS (HIG : 60 pt en haut et en bas, 80 pt sur les côtés, en 1920 × 1080) se règle à 80 × `TvUiScale` ; le haut/bas reste porté par le padding des écrans. |
| C13 | *Lu.* Aucune régulation de la touche maintenue dans dpad. `TvRemoteConfig` (cadence de répétition) n'existe **que sur tvOS**. | La régulation d'Android (répétition ≈ 50 ms, origine de `TvKeyRepeat`) ne peut pas venir de `flutter_tvos` : elle reste chez nous, dans `TvArrowGate`. Sur tvOS, essayer d'abord `TvRemoteConfig`. |
| C14 | *Mesuré (phase 0, N1).* À la reprise (`resumed`), `restoreFocus` redonne le focus au dernier nœud encore monté, sans vérifier que sa route est au premier plan. Une route poussée en arrière-plan sans `autofocus` garde donc le focus **sous** elle. | `OnyxDpad` remet le focus dans la route au premier plan à chaque reprise (§3) ; ticket upstream chez `fluttercandies/dpad` (texte dans `refonte-navigation-dpad-phase0.md` §4). |
| C15 | *Mesuré (phase 2, simulateur Apple TV).* Les régions de dpad ne s'emboîtent pas : un élément appartient à la région la plus proche, et une flèche cherche d'abord **dans la région du focus** avant d'en sortir. Une région autour de toute la page de l'accueil faisait donc préférer, sous le bandeau, « Tout voir » de la deuxième rangée (élément direct de la page) aux cartes de la première (qui appartiennent à leur rangée). | Une page n'est pas une région sous dpad : `TvRegion.page` ne pose rien (il garde `TvFocusMemory(entersAtTop)` avec l'ancien système). Épinglé par `shell_navigation_map_test` (« depuis Bandeau, Bas → Reprendre 0 »). La mémoire « où j'étais dans cet onglet », qui remontait jusqu'à l'onglet avec l'ancien système, n'existe plus que par rangée. |

## 3. Architecture cible

Quatre couches, un rôle chacune. C'est la règle qui empêche « 12 plugins qui
gèrent le focus ».

```
ENTRÉE      moteur flutter-tvos / Android / webOS / clavier
            touches (flèches, enter, escape, goBack, médias)
            + popRoute (Menu tvOS, Retour Android)
            + points du doigt (flutter_tvos, addRawListener)
   │
RETOUR      tv/nav/tv_back.dart        (popRoute + touche → une seule décision)
   │
CADENCE     tv/input/tv_arrow_gate.dart (Focus juste sous Dpad)
            répétition régulée, glissé fort = N pas, élan
   │
FOCUS       dpad 3.3.0 (une seule instance, à la racine)
            tv/nav/… (OnyxDpad, TvFocusable, TvRegion, thème)
```

Ordre réel d'une flèche (constat C4) : écran focalisé (`Focus.onKeyEvent`
du lecteur, des curseurs) → `TvArrowGate` → `Shortcuts` de dpad → politique
de parcours → `ensureVisible` de la cible. Un seul `requestFocus`, un seul
défilement.

Organisation de `lib/tv/` :

| Fichier | Contenu | Remplace |
|---|---|---|
| `tv/nav/onyx_dpad.dart` | **le seul** `Dpad.wrap(...)`. Toujours monté ; écoute `TvMode.enabled`. TV : jeu de touches complet sans `goBack` sur Android (C2), `restoreFocus: true`, thème Onyx. Hors TV : jeu vide, `restoreFocus: false` (C3). À chaque `AppLifecycleState.resumed`, vérifie que le focus primaire est dans la route au premier plan, sinon le pose sur son entrée (élément `entry`, sinon le premier candidat) (C14). `onBlockedMove` → retour sonore/haptique éventuel. | `tvSelectShortcuts`, `webTvShortcuts`, raccourcis directionnels de `main.dart`, `TvTraversalPolicy` |
| `tv/nav/tv_back.dart` | `TvBack` : un `WidgetsBindingObserver.didPopRoute` **et** l'`onBack` de dpad appellent la même fonction ; dédoublonnage par plateforme ; règle de la racine (§5, phase 5). | `TvBackIntent/Action`, `isSelfHandledBackKey` |
| `tv/nav/tv_focusable.dart` | `TvFocusable` (même API publique) au-dessus de `DpadFocusable`, avec l'anneau d'Onyx dans le `builder` ; respecte `FocusHighlightMode` et `LiteMode`. | `tv_focus.dart` |
| `tv/nav/tv_region.dart` | `TvRegion` au-dessus de `DpadRegion`, constructeurs nommés `.rail`, `.grid`, `.tabs`, `.pane`, `.list` ; fabrique la `memoryKey` namespacée (C7). | `TvFocusMemory`, `TvFocusRows`, `TvFocusPanes`, `TvFocusEntries` |
| `tv/nav/tv_nav_theme.dart` | `DpadThemeData` d'Onyx : `scrollPadding` = zone sûre (C12), alignement, durées tirées d'`app_motion`. | `TvFocusScroll` |
| `tv/input/tv_arrow_gate.dart` | `Focus` non focalisable sous `Dpad` : laisse passer, retient ou multiplie une flèche. Appelle `StepTarget`. | `TvDirectionalFocusAction`, `TvKeyRepeat` (régulation) |
| `tv/input/step_target.dart` | carte d'arrivée de N pas dans une rangée horizontale, bornée aux cartes construites. | `nextOnLine` |
| `tv/input/…` | `TvTouchpad`, `TouchpadMotion`, `siri_remote_touches*` (inchangés sur le fond) | — |
| inchangés | `tv_mode`, `tv_ui_scale`, `tv_deferred_keyboard`, `tv_focus_guard`, `tv_semantics_scroll_guard`, `web_tv_field_exit` (à réévaluer), `tv_pairing_link` | — |

Règles d'architecture (gardées par un test, voir §6) :

- **Les écrans n'importent que `TvFocusable` et `TvRegion`.** Ni `DpadFocusable`
  ni `DpadRegion` en direct, ni `FocusTraversalGroup`, `FocusTraversalPolicy`,
  `DirectionalFocusIntent`, `Shortcuts` pour naviguer, ni `Dpad.of(context)`
  hors de `tv/`.
- **Un seul `Dpad`** dans l'app. Une racine imbriquée n'est admise que pour le
  chrome du lecteur, et se justifie dans l'ADR.
- **Un seul intercepteur de flèches** (`TvArrowGate`) et **un seul Retour**
  (`TvBack`). Aucun `HardwareKeyboard.addHandler` qui agit sur le focus.
- Liste blanche courte pour les `onKeyEvent` qui ne sont pas de la navigation
  (curseurs de valeur, raccourcis du lecteur, `routePlayerKey`), une raison par
  entrée.
- Le design reste celui d'Onyx : notre anneau via le `builder`. Le
  « highlight volant » (`DpadHighlight`) et l'effet « soulevé » à la tvOS
  (agrandissement + ombre + parallaxe au doigt) sont des changements de
  design : hors périmètre, décision à part (§10).

## 4. Correspondance ancien → nouveau

| Besoin | Aujourd'hui | Avec dpad |
|---|---|---|
| Cible focalisable | `TvFocusable` | `TvFocusable` → `DpadFocusable` (`onSelect`, `onLongSelect` pour `onContextMenu`, `scrollAlignment`, `enabled`, `autofocus`, `focusNode`, `semanticLabel`) |
| Mémoire d'une rangée | `TvFocusMemory` | `DpadRegion(memoryKey: "<profil>/<écran>/<rangée>")` + `ValueKey(mediaId)` sur les cartes (C7) |
| Premier élément visible à la première visite | `entersAtTop` | `enter: restore` + `entry: true` sur l'index 0 (C8) |
| Onglet affiché à l'entrée de l'en-tête | `TvFocusEntries.register` | `TvRegion.tabs` : `enter: entry`, `entry: true` sur l'onglet affiché |
| Gauche/droite sans quitter la ligne | `nextOnLine` | `horizontalEdge: stop` (rangées) / `lineWrap` (grilles) |
| Passage entre volets des réglages | `TvFocusPanes` | `TvRegion.pane` côte à côte, bord `leave`, `enter: restore` |
| Rangées du lecteur | `TvFocusRows` | régions du chrome (phase 7) |
| Un seul défilement par pas | `TvFocusScroll` | `autoScroll` de `DpadFocusable` + thème (`scrollPadding`, alignement) ; défilement de page au bout → `onBlockedMove` |
| Activer | `kTvSelectKeys` | `DpadKeySet.select` (tvOS envoie `enter`, C9) |
| Revenir | `kTvBackKeys`, `TvBackIntent` | `TvBack` (popRoute + touche) ; `DpadKeySet.back` sans `goBack` sur Android (C1, C2) ; `browserBack` / touche 461 pour webOS |
| Flèche maintenue régulée | `TvKeyRepeat` | `TvArrowGate` (Android, web) ; `TvRemoteConfig` en premier sur tvOS (C13) |
| Glissé fort = plusieurs pas, élan | `TvDirectionalFocusAction` + `TvTouchpad` | `TvArrowGate` + `StepTarget` → un seul `requestFocus` |
| Focus perdu | `TvFocusGuard` | `restoreFocus` de dpad seul, `TvFocusGuard` non monté (tranché en phase 2, ADR-0110) |
| Contenu d'un onglet (`entersAtTop`) | `TvFocusMemory(entersAtTop: true)` | `TvRegion.page` : pas de région sous dpad (C15) ; l'entrée est celle de la rangée où le focus arrive |
| Lecture/Pause hors du lecteur | rien | décision §10 |

## 5. Phases

Chaque phase est une ou plusieurs PR vers `main`. **`main` reste livrable à
chaque fusion.** Une phase ne commence qu'une fois la précédente fusionnée,
CI verte et recette de sa portée passée.

Règle de fond : **deux systèmes de parcours ne tournent jamais en même temps
dans la même zone.** C'est ce qui rend la phase 2 atomique.

### Phase 0 — Décider (reste du spike)

Déjà vu au simulateur Apple TV : démarrage de `Dpad.wrap`, flèches, rangées
qui défilent, mémoire, fiche, champ texte, dialogue.

Le banc d'essai gagne d'abord trois instruments : un compteur de
`requestFocus` et de défilements par touche, le temps de traitement d'une
flèche, et l'origine du Retour (`popRoute` ou touche). Puis, **sur une vraie
Apple TV**, avec une Siri Remote de **chaque génération** (surface tactile
seule ; anneau cliquable + surface) :

- [ ] **Menu / ‹ :** arrive en `popRoute` (README) ou en `escape` (commentaire
      de `tv_focus.dart`) ? Les deux à la fois ? Sur la page racine, l'app
      revient-elle à l'écran d'accueil de l'Apple TV ? (C1)
- [ ] **Touche maintenue :** le focus dépasse-t-il les cartes non construites,
      la rangée bloque-t-elle pendant le réessai de dpad ? D'abord sans
      réglage, puis avec `TvRemoteConfig(keyRepeatInterval: …)`. (C6, C13)
- [ ] **Glissé vif et élan :** un `requestFocus` sur la carte d'arrivée
      donne-t-il un seul défilement fluide ?
- [ ] **Select long :** `onLongSelect` se déclenche-t-il (clic de la surface
      sur la 1re génération, clic central sur la 2e) ? (C10)
- [ ] **Coût d'une flèche** sur l'accueil réel chargé, en `--profile`, sur la
      machine la plus lente visée (critère 4). (C5)
- [ ] **VoiceOver activé :** une seule annonce par carte, pas de défilement
      parasite de rangée voisine (garde-fou ADR-0108). (C11)
- [ ] Clavier tvOS plein écran sur un champ texte (`TvDeferredKeyboard`).
- [ ] Autres entrées : manette MFi, télécommande du téléviseur par HDMI-CEC,
      télécommande de l'iPhone (centre de contrôle).

Sur Android TV (émulateur **et** une vraie box si possible, la répétition y
diffère) et webOS : même parcours, plus le double Retour (C2).

**Sortie :** un ADR court « dpad retenu » (ou « dpad écarté, voici
pourquoi ») avec le constat chiffré de chaque case. **Si une case échoue sur
machine réelle, on s'arrête ici** : pas de fork avant constat (§9).

### Phase 1 — Fondations (sans changer un seul écran)

- ADR-0110 « Un seul système de focus : dpad » ; ADR-0109 annotée « remplacée
  pour ce qui touche aux entrées de zone ».
- `pubspec.yaml` : `dpad: 3.3.0` en version exacte, avec le commentaire exigé
  (pourquoi, ce qui la bloque). Politique du `pubspec.lock` : flutter-tvos
  (Flutter 3.44) le modifie ; ne jamais commiter un lock produit par
  flutter-tvos, vérifier que `dpad` se résout avec les deux SDK (CI
  `build-tvos`).
- Squelette `tv/nav/` et `tv/input/` : `TvFocusable`, `TvRegion` avec les
  **mêmes** API que les widgets actuels, encore branchés sur l'ancienne
  implémentation ; `OnyxDpad`, `TvBack`, `TvArrowGate` écrits et testés mais
  non montés.
- Banc de test commun `test/support/tv_nav_harness.dart` (détail au §6).
- **Guard test `no_parallel_focus_system_test.dart`** : scanne `lib/` à la façon
  de `no_bare_text_field_test.dart`. Au départ la liste blanche contient tout
  l'existant ; **elle ne fait que rétrécir** (comme `file_size_guard_test`).
- Supprimer `lib/spike/` ; garder la recette du §7.

**Sortie :** CI verte, aucun changement visible.

### Phase 2 — Racine, cible et zones du shell (atomique, derrière un drapeau)

Un seul changement, parce que l'ancienne politique et dpad ne cohabitent pas
dans une même zone. Pour pouvoir revenir en arrière sans revert, le choix du
moteur passe par un drapeau de compilation `--dart-define=ONYX_TV_NAV=dpad`
(défaut `legacy`) lu **une fois** au démarrage par `TvFocusable`, `TvRegion`
et `OnyxDpad`. Il vit le temps de la bêta de cette phase, puis est retiré
avant la phase 3.

- `main.dart` : `OnyxDpad` dans `MaterialApp.builder` ; retrait des
  `shortcuts`/`actions` directionnels, de `TvTraversalPolicy` et de
  `TvDirectionalFocusAction`. `TvArrowGate` monté juste sous `Dpad`.
- `TvFocusable` passe sur `DpadFocusable` (ses 19 fichiers ne changent pas).
- Zones du shell : `shell_tab_stack`, `media_row`, `poster_rail`,
  `detail_cast_section`, `season_bubbles` passent de `TvFocusMemory` à
  `TvRegion.rail` ; `main_shell` (en-tête) à `TvRegion.tabs`. Cartes clées
  par identifiant de média ; `cacheExtent` des rangées borné.
- `restoreFocus` de dpad contre `TvFocusGuard` : on en garde un seul.
- Garde-fou conservé tel quel : `TvSemanticsScrollGuard`.
- Le lecteur garde provisoirement `TvFocusRows` ; ses `onKeyEvent` passent
  avant dpad par construction (C4), un test le fige.

**Tests :** port de `tv_focus_entry_test`, `tv_focus_memory_test`,
`tv_navigation_test`, `shell_tab_stack_test`, `tv_focus_scroll_test`,
`tv_focus_test`, `tv_focus_ring_test` ; nouveaux : mémoire par profil (C7),
un Select = un `onSelect` (C9).
**Sortie :** accueil et onglets à la télécommande sur Android TV, simulateur
et vraie Apple TV, webOS ; plus de saut double ; la mémoire de rangée marche
et ne fuit pas d'un profil à l'autre.

**Fait (2026-11-06), branche `claude/dpad-phase2-6a8b60` :** drapeau lu une
fois par `main.dart` (`TvNavEngine`), qui monte soit `TvNavRoot` (`TvBack`
au-dessus de `MaterialApp`, `OnyxDpad` + `TvArrowGate` dans le `builder`,
raccourcis sans rien de directionnel), soit l'ancien système à l'identique.
`TvFocusable` est une façade qui suit ce qui est monté (`TvNavScope`), avec
`entry`. Zones du shell sur `TvRegion` ; en-tête dans `ShellHeaderZone`
(`TvRegion.tabs`, l'onglet affiché en `entry`). Écarts au plan, et pourquoi :
le contenu d'un onglet est un `TvRegion.page`, pas une région (C15) ; les
rangées de fiche (`poster_rail`, casting, saisons) n'ont pas de clé de
mémoire, pour que la mémoire ne passe pas d'une fiche à l'autre (C7) ; la clé
par média (`TvRegion.itemKey`) ne se pose que sous dpad et sans
`findChildIndexCallback` (sinon le nœud focalisé suit sa carte hors de
l'écran) ; `cacheExtent` des rangées gardé à un écran de part et d'autre
(`AppLayout.imageCacheExtent`), dans la fourchette mesurée en phase 0. Vu au
simulateur Apple TV en `ONYX_TV_NAV=dpad` : accueil, rangées, mémoire,
en-tête, onglet Films, fiche, retour par le bouton ‹. Menu/‹ de la Siri
Remote n'est pas injectable au simulateur. Reste : Android TV, webOS, vraie
Apple TV.

### Phase 3 — Écrans de contenu

- Réglages : `TvFocusPanes` → `TvRegion.pane` côte à côte (`settings_screen`,
  `settings_choice_focus`) ; `settings_choice_tile_tv_test`.
- Fiches film/série : `detail_actions` (« Lire » en `entry`, c'est lui que
  dpad focalise à l'ouverture), `detail_synopsis`, `episode_tile`,
  `season_bubbles` ; `TvFocusCaption` à réévaluer (peut disparaître avec
  `onFocusChange`).
- Hero carousel : son `onKeyEvent` devient `onDirection` quand c'est de la
  navigation ; vérifier que le défilement automatique ne déplace pas le focus
  (une page détruite sous le focus fait jouer `restoreFocus`).
- Listes, téléchargements, stats, profils, sélecteur d'avatar, remote playback.

**Tests :** `requests_screen_tv_test`, `remote_playback_banner_focus_test` et
une carte de navigation par écran (§6).

### Phase 4 — Champs texte, clavier, web LG

- Champs texte : dpad laisse les flèches au curseur et sort aux bords (un
  champ d'une ligne laisse toujours passer Haut/Bas). Mesurer si cela remplace
  `web_tv_field_exit` ; **garder** `TvDeferredKeyboard` (il gère le clavier à
  l'écran, pas le focus).
- Web LG (ADR-0076) : plus de `webTvShortcuts` ; Retour de la télécommande LG
  ajouté au jeu `back` ; `web_tv_dpad_test` porté.
- `login_screen_keyboard_test`, `tv_login_screen_test`, `tv_deferred_keyboard_test`.

### Phase 5 — Retour, Menu, dialogues

- `TvBack` est le seul à décider. Deux entrées, une sortie :
  - `didPopRoute` (Menu/‹ tvOS, Retour Android) ;
  - `onBack` de dpad (Échap au clavier, B de manette, Retour webOS).
  Sur Android, `goBack` n'est pas dans le jeu de touches (C2) ; la règle tvOS
  vient de la phase 0.
- Ordre de décision, conforme aux conventions tvOS :
  1. un dialogue, une feuille ou un menu ouvert se ferme ;
  2. une route poussée se dépile ;
  3. dans le contenu d'un onglet, le focus remonte à l'en-tête (onglet
     affiché) ;
  4. sur l'en-tête de l'onglet d'accueil : `didPopRoute` rend `false` et le
     système ramène à l'écran d'accueil de l'Apple TV. **On ne retient jamais
     Menu à la racine** (règle de l'App Review tvOS).
- Dialogues, feuilles, menus popup : focus piégé, puis rendu à l'élément
  d'origine (vu au spike, à rejouer sur chaque feuille de l'app).
- `tv_back_action_test` porté ou supprimé avec la classe ; nouveau test
  table-driven « état → effet du Retour » par plateforme.

### Phase 6 — Apple TV : le pont du trackpad

- `TvArrowGate` reçoit chaque flèche avant dpad et choisit : laisser passer
  (cas normal), retenir (répétition trop rapide), ou faire N pas (glissé vif).
- `StepTarget` reprend `nextOnLine` : carte d'arrivée de N pas dans une rangée
  horizontale, **bornée aux cartes construites** (sinon dpad fait défiler puis
  réessaie, C6) ; **jamais à la verticale** (ADR-0039).
- Application : un seul `Dpad.of(context).requestFocus(node)`, la flèche
  d'origine est consommée ; donc un seul défilement par pas.
- Élan : inchangé sur le fond, il passe par `StepTarget`.
- Répétition : `TvRemoteConfig` sur tvOS si la phase 0 l'a validé ; la
  régulation d'Android et du web reste dans `TvArrowGate` (C13).
- Le lecteur continue de lire le doigt directement (`addMoveListener`).
- `touchpad_motion_test`, `tv_touchpad_test`, `tv_key_repeat_test` portés.

### Phase 7 — Lecteur

À faire en dernier : c'est la zone la plus chargée (ADR-0006, 0008).

- Chrome affiché ⇒ une commande entourée (invariant ADR-0008) : barre de
  progression comme point d'atterrissage, rangée de boutons en région.
- Chrome masqué : les flèches vont à `routePlayerKey` (avance, recul), pas au
  parcours ; Select/clic de la surface affiche le chrome.
- `TvFocusRows` supprimé ; `onyx_controls_layer` (déjà au-dessus de 800 lignes
  dans `file_size_guard_test`) y perd ses rangées au passage.
- `routePlayerKey` (pur, testé) est **gardé** : il décide, dpad ne fait que
  déplacer le focus.
- Racine `Dpad` imbriquée pour le chrome seulement si une région ne suffit
  pas. Depuis 3.3.0 elle possède son propre rapport de focus et sa mémoire :
  la sortie du lecteur doit rendre le focus à la carte d'origine.
- Écran natif Apple TV (AVKit, ADR-0105) : hors périmètre, il a son propre
  moteur de focus.
- `player_key_routing_test`, `onyx_settings_menu_tv_test` portés.

### Phase 8 — Nettoyage et preuve

- Supprimer `tv_focus_entry`, `tv_focus_memory`, `tv_focus_panes`,
  `tv_focus_rows`, `tv_focus_scroll`, ce qui reste de `tv_focus.dart` et de
  `tv_key_repeat.dart`, et leurs tests.
- La liste blanche du guard test **doit être vide** (hors entrées justifiées).
- `app_motion.dart` : retirer ce qui ne sert plus.
- `.claude/skills/onyx-engineering/ui.md` (section « TV et télécommande »),
  `CONTEXT.md`, ADR-0006/0008/0039/0109 annotées.
- `graphify update .`
- Mesurer les critères du §1 et les écrire dans l'ADR-0110.

## 6. Stratégie de test

1. **Banc commun** `test/support/tv_nav_harness.dart` : monte un écran sous
   `OnyxDpad` en mode TV, surface de 1920 × 1080 (dpad raisonne en rectangles
   globaux : une surface de test de 800 × 600 donne d'autres voisins),
   `MediaQuery(disableAnimations: true)` pour que les défilements de dpad
   sautent au lieu d'animer (tests déterministes), helpers `press(direction)`,
   `back()`, `popRoute()`, `focusedLabel`.
2. **Port, pas réécriture à l'aveugle.** Les ≈ 34 fichiers de test qui touchent
   au focus se portent par phase avec ce banc. Un test supprimé sans
   équivalent se justifie dans la PR.
3. **Cartes de navigation.** Un test table-driven par écran : « depuis X,
   Haut/Bas/Gauche/Droite/Retour amène en Y ». C'est ce qui attrape les
   régressions de focus que personne ne remarque au toucher.
4. **Tests d'invariants** :
   - un seul `requestFocus` et un seul défilement par flèche (ADR-0109) ;
   - focus visible quand le chrome est affiché (ADR-0008) ;
   - pas de double Retour : `goBack` + `popRoute` sur Android, Menu sur tvOS ;
   - un Select = un `onSelect` (C9) ;
   - un `Focus.onKeyEvent` d'écran passe avant dpad (C4) ;
   - hors TV : flèches et Tab du bureau intactes, aucun focus posé au
     démarrage (C3) ;
   - mémoire vidée au changement de profil (C7) ;
   - focus dans la route au premier plan après reprise, y compris pour une
     route poussée pendant la pause (C14).
5. **Guard test** `no_parallel_focus_system_test` : liste blanche qui ne fait
   que rétrécir ; message d'échec qui explique le pourquoi.
6. **Commandes de vérification** à chaque PR, dans `app/` : `flutter analyze`,
   `flutter test` (fichier ciblé puis suite complète). Build tvOS :
   `~/flutter-tvos/bin/flutter-tvos build tvos --simulator --debug` ; mesure de
   performance : même commande en `--profile` sur la vraie machine.

## 7. Matrice de recette

Une case est cochée seulement après avoir regardé l'écran tourner.

| Cible | Quoi | Comment |
|---|---|---|
| Android TV 16 (émulateur) | tout le parcours, Retour simple | télécommande virtuelle |
| Box Android TV réelle | touche maintenue, Retour | si disponible ; la répétition diffère de l'émulateur |
| Apple TV (simulateur) | flèches, mémoire, dialogues, Retour | `press_key` ; lecture du focus par le service VM |
| **Apple TV réelle** | Menu, touche maintenue, glissé vif, élan, Select long, clavier, VoiceOver, coût d'une flèche | **seule preuve valable** pour les phases 0 et 6 ; les deux générations de Siri Remote |
| webOS (LG) | flèches, Entrée, Retour, champs | simulateur + une vraie TV si possible |
| Bureau (Windows, macOS) | Tab, flèches dans les champs, aucun focus imposé | clavier |
| Téléphone, web non-TV | aucune régression au toucher, aucun anneau | émulateur Pixel |

## 8. Risques et parades

| Risque | Parade |
|---|---|
| dpad a quelques jours de vie, API qui bouge | version exacte ; façade `TvFocusable`/`TvRegion` : le reste de l'app ne voit pas dpad ; montée de version = un seul endroit |
| Menu tvOS hors de portée de `onBack` (C1) | `TvBack` sur `didPopRoute`, validé en phase 0 |
| Double Retour Android (C2) | `goBack` retiré du jeu, test d'invariant |
| Mode non-TV cassé par `enabled: false` (C3) | jeu de touches vide + `restoreFocus: false`, test d'invariant |
| Mémoire qui fuit entre profils (C7) | clé namespacée, `clearPersistentMemory` au changement de profil |
| Focus sous la route affichée après une reprise (C14) | `OnyxDpad` le remet dans la route au premier plan à chaque `resumed`, test d'invariant ; retiré quand la correction upstream est dans la version épinglée |
| Lenteur sur l'accueil chargé (C5) | `cacheExtent` borné, critère 4 mesuré en phase 0 |
| Flèche maintenue plus vite que les cartes construites (C6, C13) | `TvRemoteConfig` sur tvOS, `TvArrowGate` ailleurs |
| Double annonce VoiceOver, défilement parasite (C11) | recette VoiceOver, garde-fou ADR-0108 conservé |
| Régression de défilement (ADR-0108, 0109) | tests d'invariants repris avant de supprimer l'ancien code |
| Perte du focus visible sous Windows / mode léger | pas de `DpadHighlight` ; notre anneau, `LiteMode` respecté |
| Lock de dépendances pollué par flutter-tvos | jamais commité tel quel, vérifié en CI |
| Phase 2 qui casse en production | drapeau `ONYX_TV_NAV`, bêta avant déploiement général |
| Migration trop longue | `main` livrable à chaque phase ; chaque phase se suffit |

## 9. Fork de dpad : dernier recours

Pas avant constat. Il se justifie seulement si, sur machine réelle,
`requestFocus` ne suffit pas (saccades, mémoire de région fausse), si le
coût d'une flèche dépasse le critère 4 malgré un `cacheExtent` borné, ou si
la régulation de la touche maintenue doit se faire dans `_move`. Dans ce cas :
**un seul patch minimal** (par exemple un hook de pas), proposé aussi en PR
upstream ; tout le reste du pont reste dans `tv/input/`.

## 10. Décisions prises avant la phase 2

Prises le 2026-11-06 sur les recommandations, l'utilisateur ayant demandé de
continuer ; inscrites dans l'ADR-0110.

1. **Highlight** : on garde notre anneau, sans highlight volant
   (`DpadHighlight`) ni effet « soulevé » tvOS pour cette refonte. Un
   changement de design se décidera à part.
2. **Racine imbriquée** pour le chrome du lecteur : non ; seulement si une
   région ne suffit pas, avec sa propre ADR (phase 7).
3. **Bêta** de la phase 2 derrière `ONYX_TV_NAV=dpad`, défaut `legacy`, avant
   le déploiement général. Le drapeau est retiré avant la phase 3.
4. **Entrée d'une rangée par le haut ou le bas** : mémoire de la rangée
   (`restore`), comme les apps TV ; sans mémoire, l'élément marqué `entry`,
   sinon le plus proche (C8).
5. **Menu dans le contenu d'un onglet** : remonter d'abord à l'en-tête
   (convention tvOS). Implémenté en phase 5, pas avant.
6. **Lecture/Pause sur une affiche** hors du lecteur : rien pour l'instant.
