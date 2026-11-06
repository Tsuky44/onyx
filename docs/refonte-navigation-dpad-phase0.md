# Refonte de la navigation TV sur dpad 3.3.0 — rapport de la phase 0

- **Statut :** mesures simulateur et headless faites ; recette vraie Apple TV, Android TV et webOS **à faire** (procédures au §5).
- **Date :** 2026-11-06
- **Plan :** [`refonte-navigation-dpad.md`](refonte-navigation-dpad.md) (§2 constats C1–C13, §5 phase 0, §7 recette).
- **Branche :** `spike/dpad-tvos`, rien de commité.
- **Banc d'essai :** `app/lib/spike/` (jetable, supprimé en phase 1) :
  - [`dpad_spike_main.dart`](../app/lib/spike/dpad_spike_main.dart) : l'app du banc (accueil, fiche, dialogue, réglages dans l'en-tête) ;
  - [`spike_probe.dart`](../app/lib/spike/spike_probe.dart) : les instruments (compteurs, chrono, origine du Retour, service VM) ;
  - [`spike_widgets.dart`](../app/lib/spike/spike_widgets.dart) : cartes instrumentées, `Focus` d'écran (C4), accueil chargé ;
  - [`spike_remote*.dart`](../app/lib/spike/spike_remote.dart) : `TvRemoteConfig` derrière un import conditionnel (le web ne compile pas `dart:ffi`) ;
  - [`dpad_spike_test.dart`](../app/lib/spike/dpad_spike_test.dart) : vérification headless des constats lus (10 cas).

## 1. Verdict

**dpad : retenu à risque.** Rien de ce qui est mesurable hors vraie machine ne
l'écarte : un seul `requestFocus` et au plus un ordre de défilement par flèche,
2 à 4 ms de la touche au focus posé (simulateur, mode debug), mémoire de
rangée, entrée de zone, dialogue, Retour par `popRoute`, mode non-TV et
priorité des `onKeyEvent` d'écran se comportent comme le plan l'a lu.

Trois choses empêchent de dire « retenu » sans réserve :

1. **Aucune case n'a tourné sur une vraie Apple TV.** Selon la règle du plan,
   c'est elle qui décide (Menu, Select long, touche maintenue, glissé, coût en
   `--profile`, VoiceOver). Procédures au §5.
2. **N1 — défaut de dpad :** après une reprise de l'app, dpad peut rendre le
   focus à une carte **sous** la route affichée (constaté au simulateur et
   reproduit en test). Tranché : parade `OnyxDpad` (§4).
3. **N2 — touches en rafale :** des touches qui arrivent plus vite que
   l'application du focus partent toutes du même focus et se perdent (12
   pressions injectées → 1 pas). À mesurer sur la vraie Siri Remote (glissé
   vif) ; c'est précisément le rôle de `TvArrowGate` en phase 6.

**Ce qui bloquerait la phase 1 :** une case rouge au §5 sur vraie Apple TV
(en particulier Menu à la racine, `onLongSelect` muet sur une génération de
Siri Remote, ou un coût de flèche au-dessus de 4 ms en `--profile` malgré un
`cacheExtent` borné).

## 2. Environnement et méthode

| Élément | Valeur |
|---|---|
| Simulateur | Apple TV 4K (3rd generation) (at 1080p), tvOS 27.0, UDID `2E4642D7-…`, build **debug** (JIT) |
| SDK tvOS | flutter-tvos, Flutter 3.44.9 |
| SDK hôte | Flutter 3.44.2 (`flutter analyze`, `flutter test`) |
| Pilotage | outil iOS Simulator, `press_key` (flèches, `return`) ; lecture par le service VM (`ext.spike.log`, `ext.spike.state`, `ext.spike.set`, `ext.spike.action`) |
| Android TV | **sauté** : ce Mac n'a ni émulateur ni image système Android (SDK en lignes de commande seulement) ; l'émulateur `emulator-5554` est sur la machine Windows |
| webOS | **sauté** : le simulateur webOS 26 est sur la machine Windows ; le banc compile maintenant pour le web (§5.10) |

**Lire une ligne du banc.** Chaque ligne commence par `[DPAD] +<ms depuis le démarrage>`. Une pression (KeyDown ou KeyRepeat) donne :

```
[DPAD] +51234ms press #23 dn Arrow Right r0 c10 → r0 c11 focus=1.9ms frame=15.8ms rf=1 fc=1 scr=1 cmd=1 (anim:rangee0) desc=84 écran=avant-dpad
```

| Champ | Sens |
|---|---|
| `dn` / `rep` | KeyDown / KeyRepeat |
| `A → B` / `immobile` | focus avant et après la pression |
| `focus=` | de la touche (vue par `HardwareKeyboard`) au focus posé (écouteur du `FocusManager`) |
| `frame=` | de la touche à la fin de l'image suivante ; `-` = l'image est arrivée après la clôture de la pression (ligne `image tardive` à part) |
| `rf` | appels à `requestFocus` sur les nœuds du banc (cible > 1 = **DOUBLE**) |
| `fc` | changements du focus primaire |
| `scr` / `cmd` | `ScrollStartNotification` / ordres `animateTo`-`jumpTo` reçus par les listes du banc ; un `animateTo` qui en interrompt un autre n'émet pas de second `ScrollStart`, seul `cmd` le voit |
| `desc` | cibles focalisables de la route (coût linéaire de dpad, C5) |
| `écran=avant-dpad` | le `Focus(onKeyEvent:)` d'écran a vu la touche avant que dpad ne demande le focus (C4) |

Autres lignes : `back via didPopRoute (…)`, `back via dpad.onBack (touche …)`,
`DOUBLE RETOUR` (les deux voies en moins de 800 ms), `evt onSelect …`,
`evt onLongSelect …`, `up <touche> tenue=<ms>`, `focus hors touche → …`
(focus posé sans touche : `restoreFocus`, réessai, autofocus), `cycle de vie → …`.

## 3. Résultats

### 3.1 Cases de la phase 0 (plan §5)

| Case | Mesure | Cible | Statut |
|---|---|---|---|
| **Menu / ‹ (C1)** | Menu non injectable au simulateur (`press_key` n'a pas de Menu ; `delete` ne produit aucun évènement). Le message `popRoute` du moteur, rejoué à l'identique (`ext.spike.action do=popRoute`) : une ligne `back via didPopRoute (sans touche)`, aucun `dpad.onBack`, fiche dépilée, focus rendu à la carte d'origine (`focus hors touche → r0 c11`) ; dialogue fermé, focus rendu à « Dialogue ». Headless : `popRoute` → `onBack` de dpad appelé 0 fois. | un seul Retour par appui ; à la racine, retour à l'écran d'accueil de l'Apple TV | **non vérifiable au simulateur** (voie `popRoute` verte) → §5.1 |
| **Touche maintenue (C6, C13)** | Headless, rangée `ListView.builder` de 40 cartes, 16 touches depuis c8 : répétition 80 ms → c24, **0 pas perdu** ; 40 ms → c22, **2 pas perdus** (pendant le réessai de dpad). Simulateur : `press_key count` envoie des KeyDown à ≈ 8 ms d'écart, pas des KeyRepeat → voir N2. `TvRemoteConfig` poussé sans erreur de poignée de main (`TvRemoteConfig keyRepeatInterval=150ms tvos=true`), effet non observable (l'injection clavier ne passe pas par la répétition native de la Siri Remote). | aucun pas perdu à la cadence native | **non vérifiable au simulateur** ; risque confirmé sous 80 ms → §5.2 |
| **Glissé vif et élan** | Pas de surface tactile au simulateur (les `swipe` échouent). | un seul défilement fluide par glissé | **non vérifiable au simulateur** → §5.3 |
| **Select long (C10)** | Headless : appui 120 ms → `onSelect`=1, `onLongSelect`=0 ; 650 ms → `onSelect`=0, `onLongSelect`=1. Simulateur : Select court sur une carte à `onLongSelect` → `onSelect` au relâcher (`up Enter tenue=2ms`), route poussée. Select long non injectable. | `onLongSelect` sur les deux générations de Siri Remote | **non vérifiable au simulateur** (logique de dpad verte) → §5.4 |
| **Coût d'une flèche (C5, critère 4)** | Simulateur debug, hôte Mac : accueil (84 cibles) `focus` 1,9–4,3 ms (≈ 2,7 ms médian) ; accueil chargé 10 × 40, `cacheExtent` par défaut (40–50 cibles) 1,7–3,5 ms ; `cacheExtent` 3000 px (96–120 cibles) 2,2–3,3 ms. `frame` 8–28 ms (debug). Ouverture d'une route : 158 ms (fiche), 264 ms (dialogue), premier build JIT. | ≤ 4 ms en `--profile` sur la machine la plus lente, aucune image sautée | **non vérifiable au simulateur** (debug sur Mac ≠ Apple TV en profile) → §5.5 |
| **Un `requestFocus`, un défilement par flèche** | Toutes les pressions simples mesurées : `rf=1 fc=1`, `cmd` 0 ou 1 (`anim:rangee0` au bord d'une rangée, `anim:page` en descendant), jamais `DOUBLE`. | 1 et ≤ 1 | **vert** (simulateur) |
| **VoiceOver (C11)** | Non testé : pas de VoiceOver piloté au simulateur. | une annonce par carte, pas de défilement parasite | **non vérifiable au simulateur** → §5.6 |
| **Clavier tvOS plein écran** | Vu au spike d'origine (champ de la fiche). Le banc garde un `TextField` nu : `TvDeferredKeyboard` relève de la phase 4. | — | **déjà vu** ; à rejouer sur machine → §5.7 |
| **Autres entrées** (MFi, HDMI-CEC, iPhone) | — | une touche = une action | **non vérifiable au simulateur** → §5.8 |
| **Dialogue** | Ouvert depuis l'en-tête : focus sur « Annuler » (autofocus), ↓ bloqué (`evt bloqué down`), → vers « OK », `popRoute` → fermé, focus rendu à « Dialogue ». | focus piégé puis rendu | **vert** (simulateur) |
| **Android TV : parcours + double Retour (C2)** | Émulateur absent de ce Mac. Headless : un appui Retour Android simulé comme Android 16 le fait (touche `goBack` puis `popRoute`) dépile **2 routes** avec le jeu de touches par défaut, **1** sans `goBack`. | 1 route par appui | **non vérifiable ici** (constat lu vert) → §5.9 |
| **webOS** | Simulateur sur la machine Windows. | flèches, Entrée, Retour | **sauté** → §5.10 |

### 3.2 Constats C1–C13 (plan §2)

| # | Résultat chiffré | Cible | Statut |
|---|---|---|---|
| C1 | Headless : `popRoute` → `onBack` dpad = 0 appel, route dépilée. Simulateur : `popRoute` rejoué → `back via didPopRoute`, aucun `dpad.onBack`. | `onBack` ne voit jamais `popRoute` | **vert** (Menu réel → §5.1) |
| C2 | Headless : jeu par défaut → 2 routes dépilées pour un appui ; jeu sans `goBack` → 1. | 1 | **vert** pour la parade (sans `goBack`) ; double Retour confirmé avec le jeu par défaut |
| C3 | Simulateur, mode `nonTv` (jeu vide, `restoreFocus: false`) : au démarrage `focus=_ModalScopeState … Focus Scope` (aucune carte) ; après `unfocus`, rien n'est reposé ; les flèches naviguent encore par les raccourcis du framework (`rf=1`, scope → L0 c0 → L0 c1). Mode `fige` (`enabled: false`) : flèche avalée (`immobile rf=0`). Headless : idem, et Tab passe à la carte suivante. | hors TV : aucun focus imposé, flèches et Tab intacts ; `enabled: false` interdit | **vert** |
| C4 | Simulateur : toutes les flèches portent `écran=avant-dpad` ; capture ← active → `evt C4 écran a consommé ←`, `immobile rf=0`. Un Select sur un `DpadFocusable` n'atteint pas le `Focus` d'écran (la cible le consomme d'abord). | l'écran passe avant dpad | **vert** |
| C5 | `desc` = 84 (accueil), 40–50 (chargé, cache par défaut), 96–120 (cache 3000) ; `focus` reste 1,7–4,3 ms à ces tailles (debug, Mac). | ≤ 4 ms en profile sur la machine la plus lente | **non vérifiable au simulateur** → §5.5 |
| C6 | Headless : 40 ms de répétition → 2 pas perdus sur 16 au-delà des cartes construites ; 80 ms → 0. | aucun pas perdu | **rouge sous 80 ms** (attendu : `TvArrowGate`/`TvRemoteConfig`) ; cadence réelle → §5.2 |
| C7 | Headless : même `memoryKey` après destruction de l'écran → c5 restauré (la mémoire statique survit et **fuit**) ; clé namespacée `profilB/…` → c0 ; après `DpadRegionState.clearPersistentMemory()` → c0. NB : la méthode est sur `DpadRegionState`, pas `DpadRegion`. | clé `"<profil>/<écran>/<rangée>"` + vidage | **vert** (la parade du plan tient) |
| C8 | Simulateur, accueil chargé : depuis L0 c1, ↓ → **L1 c0** (`entry`, première visite) ; plus tard ↑ depuis L3 c0 → **L2 c1** (mémoire). | `restore` + `entry` sur l'index 0 | **vert** |
| C9 | Simulateur et headless (Enter et Select) : cible simple → `onSelect`=1 ; `DpadFocusable` qui enveloppe un `ElevatedButton` → `onSelect`=1, `onPressed`=**0** ; bouton Material nu → `onPressed`=1. | un Select = une action | **vert**, avec N4 |
| C10 | Headless : vert (voir §3.1). | `onLongSelect` sur les deux Siri Remote | **non vérifiable au simulateur** → §5.4 |
| C11 | — | une annonce par carte | **non vérifiable au simulateur** → §5.6 |
| C12 | Lu (`DpadThemeData.scrollPadding` est un `double`). Rien à mesurer. | — | **lu** |
| C13 | `TvRemoteConfig` accepté par le natif sans erreur ; effet → §5.2. Hors tvOS c'est un no-op (vu dans `flutter_tvos`). | répétition réglable sur tvOS | **non vérifiable au simulateur** |

### 3.3 Nouveaux constats

| # | Constat | Preuve | Conséquence |
|---|---|---|---|
| **N1** | À la reprise (`resumed`), dpad redonne le focus au dernier nœud « utilisable » sans vérifier que sa route est encore au premier plan (`_restoreFocus(resumed: true)` → `last.requestFocus()`, `DpadMarks.isUsable` ne teste que monté + `canRequestFocus`). Une route poussée pendant que l'app est en arrière-plan, sans autofocus, laisse donc le focus **sous** elle : les flèches naviguent dans l'écran caché. | Simulateur : accueil chargé poussé pendant une pause → `focus: tab Accueil` (route du dessous), ↓ → `r0 c0` invisible. Test `N1` : focus = c3 sous la route affichée. | Cas réel : reprise de lecture, lien profond, `PlaybackHandoffWatch`. Parades possibles : chaque route a un `autofocus` (une entrée de `TvRegion` ne suffit pas : `entry` n'est pas `autofocus`), ou `OnyxDpad` corrige à la reprise (si le focus n'est pas dans la route courante, `requestFocus` sur son entrée), et un ticket upstream. **Tranché : parade `OnyxDpad`** (§4). |
| **N2** | Des touches qui arrivent plus vite que l'application du focus sont toutes traitées depuis le même focus : seule la dernière compte. | Simulateur : 12 KeyDown injectés à ≈ 8 ms → 1 pas (`immobile rf→L2 c3` × 11) ; 12 appels séparés à ≈ 15 ms → 9 pas (3 perdus) ; les 3 premières pressions après un lancement arrivent groupées de la même façon. Cause exacte non établie (lot de messages du moteur ou injection du simulateur). | Sur vraie Siri Remote, un glissé vif émet des rafales : `TvArrowGate` (phase 6) doit les regrouper en N pas et un seul `requestFocus` (ce que le plan prévoit). À mesurer au §5.3. |
| **N3** | dpad note la mémoire de région **à la demande** de focus (`_requestFocus` → `noteFocus` avant `requestFocus`), pas à l'arrivée. | Après la rafale de démarrage, « tab Films » (demandé, jamais focalisé) est resté la mémoire de l'en-tête : ↑ depuis r0 c11 → tab Films. | Sans effet hors rafale ; disparaît si `TvArrowGate` regroupe les rafales (N2). |
| **N4** | Un `DpadFocusable` qui enveloppe un bouton Material (`excludeChildFocus: true` par défaut) **remplace** l'action du bouton : `onPressed` n'est jamais appelé par Select. | C9 ci-dessus. | `TvFocusable` doit recevoir l'action en `onSelect`, ou ne pas envelopper de bouton ; à inscrire dans le guard test de phase 1. |
| **N5** | `restoreFocus` ne repose pas le focus après un `unfocus()` explicite : dpad le tient pour délibéré (même scope). Il ne répare que la perte par destruction ou un changement de route. | Simulateur, mode `tv` : `après unfocus (mode tv) : focus=… Focus Scope`. | `TvFocusGuard` (ou équivalent) reste utile pour le focus « garé » ; à trancher en phase 2 (plan §4, ligne « Focus perdu »). |

## 4. Recommandation

**dpad retenu à risque : poursuivre la phase 0 sur vraie machine, ne pas
ouvrir la phase 1 avant.**

- Faire le §5 sur une vraie Apple TV avec les deux générations de Siri
  Remote, puis Android TV (émulateur + box) et webOS. Si une case est rouge
  sur machine réelle, on s'arrête (plan §5, §9).
- **N1 — tranché : parade `OnyxDpad`.** À chaque `AppLifecycleState.resumed`,
  `OnyxDpad` vérifie que le focus primaire est dans la route au premier plan ;
  sinon il le pose sur l'entrée de cette route (élément `entry`, sinon le
  premier candidat). Un ticket est à ouvrir chez `fluttercandies/dpad` (texte
  ci-dessous, à déposer par l'équipe ; il n'est pas encore ouvert). La parade
  reste tant que la correction upstream n'est pas dans la version épinglée.
- Inscrire N2, N4 et N5 dans l'ADR de sortie : ils ne bloquent pas, mais ils
  fixent ce que `TvArrowGate`, `TvFocusable` et le garde-fou de focus doivent
  faire.

**Texte du ticket upstream (N1), à déposer sur `fluttercandies/dpad` :**

```markdown
**Title:** Focus restored to a covered route after app resume (`restoreFocus`)

**Version:** dpad 3.3.0, Flutter 3.44 (flutter-tvos and Android TV)

**What happens**
When the app comes back to `AppLifecycleState.resumed`, `_DpadState._restoreFocus(resumed: true)`
calls `requestFocus()` on the last focused node as soon as `DpadMarks.isUsable(last)` is true.
`isUsable` only checks that the node is attached, mounted and `canRequestFocus`. It does not check
that the node's route is still the current one.

If a route without an `autofocus` item is pushed while the app is in the background (deep link,
playback handoff, notification), the last focused node is still mounted in the route below. On resume,
focus goes back to that hidden node, and arrow keys then navigate inside a screen the user cannot see.

**Steps to reproduce**
1. `MaterialApp(builder: Dpad.wrap(), home: A)`, where A has a few `DpadFocusable`s; focus one of them.
2. Send `inactive` → `hidden` → `paused`.
3. Push route B (its `DpadFocusable`s have no `autofocus`).
4. Send `hidden` → `inactive` → `resumed`, then pump.

**Expected:** focus lands in B (its `entry` item, or its first candidate), as for a normal push.
**Actual:** focus is back on A's node, under B.

**Suggested fix**
On a resumed restore, only reuse `last` when it belongs to the current route, for example when
`ModalRoute.of(last.context!)?.isCurrent ?? true` holds. Otherwise fall through to the initial
candidate of the focused scope. A regression test can follow the steps above.
```

## 5. Procédures sur vraie machine

### 5.0 Installer le banc sur une Apple TV

Depuis `app/`, Apple TV appairée dans Xcode (Window › Devices and Simulators) :

```bash
~/flutter-tvos/bin/flutter-tvos devices
```

```bash
~/flutter-tvos/bin/flutter-tvos run -d <id_apple_tv> --profile -t lib/spike/dpad_spike_main.dart
```

- Les lignes `flutter: [DPAD] …` défilent dans ce terminal. Sinon : app
  Console du Mac › l'Apple TV › filtre `[DPAD]`.
- Les réglages sont dans l'en-tête, à la télécommande : **Mode** (tv →
  tvSansGoBack → nonTv → fige ; nonTv et fige reviennent seuls à tv après
  30 s), **Répét.** (défaut → 150 ms → 250 ms), **C4** (capture de ←),
  **Cache** (défaut → 0 → 3000), **Chargé** (accueil 10 × 40), **Lâcher**
  (`unfocus`).
- Après la séance : flutter-tvos réécrit `app/pubspec.lock`. Ne pas le
  commiter ; le régénérer avec le Flutter standard :

```bash
flutter pub get
```

### 5.1 Menu / ‹ (C1)

1. Sur l'accueil, descendre sur **r1 c0**, Select → la fiche s'ouvre.
2. Presser **Menu** (Siri Remote 1re génération) puis refaire avec **‹**
   (2e génération et suivantes).
3. Lire, pour chaque appui : `back via didPopRoute (…)` et/ou
   `back via dpad.onBack (touche …)`, et `up Escape` s'il y a une touche.
4. Revenir sur l'accueil, focus sur **tab Accueil**, presser Menu.

**Vert :** à l'étape 3, une seule ligne `back via …` par appui, **aucune**
`DOUBLE RETOUR`, la fiche se ferme et `focus hors touche → r1 c0` suit. À
l'étape 4, l'app passe à l'écran d'accueil de l'Apple TV (`cycle de vie →
inactive`, puis `hidden`/`paused`). Noter quelle voie arrive (popRoute seul,
touche seule, les deux) : c'est la règle tvOS de `TvBack` (phase 5).

### 5.2 Touche maintenue (C6, C13)

1. En-tête › **Chargé**. Focus sur L0 c0.
2. Maintenir → 3 s (2e génération : anneau, côté droit ; 1re génération :
   appuyer-maintenir le bord droit de la surface).
3. Lire les lignes `press #n rep Arrow Right …` : l'écart entre deux `+…ms`
   donne la cadence réelle ; compter les `immobile` avant L0 c39.
4. Revenir (‹), en-tête › **Répét.** sur 150 ms (ligne `TvRemoteConfig
   keyRepeatInterval=150ms tvos=true`), refaire 1–3, puis 250 ms.

**Vert :** à une cadence donnée, chaque `rep` avance d'une carte (aucun
`immobile` avant la dernière carte, aucun `DOUBLE`), et la cadence mesurée
suit le réglage (≈ 80, 150, 250 ms). Noter la plus petite cadence sans pas
perdu : c'est le réglage par défaut de `TvRemoteConfig` à retenir.

### 5.3 Glissé vif et élan (N2)

1. **Chargé**, focus sur L2 c0.
2. Glisser vite vers la droite sur la surface, une fois, puis trois fois de
   suite.
3. Lire la série de lignes `press` du glissé.

**Vert :** pas de `immobile` au milieu d'une série, `cmd` ≤ 1 par ligne,
aucun `DOUBLE`, défilement de la rangée fluide à l'œil. Rouge (attendu sans
`TvArrowGate`) : plusieurs lignes `immobile rf→<même carte>` d'affilée — c'est
N2 sur machine réelle.

### 5.4 Select long (C10)

1. Accueil, rangée 0 (titre « Select long = onLongSelect »), focus sur r0 c2.
2. Clic bref : lire `up Select` ou `up Enter tenue=…ms` puis
   `evt onSelect r0 c2` (la fiche s'ouvre), revenir.
3. Clic maintenu 1 s : 2e génération clic central, 1re génération clic de la
   surface.

**Vert :** à l'étape 3, `evt onLongSelect r0 c2` une fois, **pas**
d'`evt onSelect`, et `tenue` ≈ la durée réelle (≥ 500 ms). Rouge : `tenue`
proche de 0 (le moteur envoie le relâcher tout de suite) ou aucun
`onLongSelect`. Faire les deux générations.

### 5.5 Coût d'une flèche (C5, critère 4)

1. Build `--profile` (§5.0) sur la machine la plus lente visée.
2. **Chargé**, puis **Cache** sur 3000 (revenir à l'accueil, régler, rouvrir
   Chargé).
3. 20 flèches simples espacées (→ et ↓ mélangées).
4. Lire `focus=` et `frame=` de chaque ligne `press`.

**Vert :** `focus` médian ≤ 4 ms, aucune `image tardive`, `frame` ≤ 16,7 ms
(60 Hz). Refaire avec **Cache** par défaut pour comparer `desc`. Pour la
preuve image par image : DevTools (lien affiché par `flutter-tvos run`) ›
Performance.

### 5.6 VoiceOver (C11)

1. Réglages de l'Apple TV › Accessibilité › VoiceOver › activé.
2. Lancer le banc, parcourir r1 de c0 à c8 puis descendre sur r2.

**Vert :** une seule annonce par carte (son libellé, une fois), aucune ligne
`défilement hors touche` pendant que le focus ne bouge pas (sinon la rangée
voisine défile seule : garde-fou ADR-0108). Noter toute double annonce.

### 5.7 Clavier tvOS

1. r1 c0 › Select › fiche, ↓ jusqu'au **Champ**, Select.
2. Le clavier plein écran s'ouvre ; taper « abc », valider.
3. ↓ depuis le champ.

**Vert :** clavier ouvert, texte saisi dans le champ, focus de retour sur le
champ, puis ↓ → `Sous le champ`.

### 5.8 Autres entrées

- **Manette MFi :** A sur une carte → `evt onSelect …` une fois ; B sur la
  fiche → `back via dpad.onBack (touche Game Button B …)` et pas de
  `didPopRoute` (ou l'inverse, mais une seule voie).
- **Télécommande du téléviseur (HDMI-CEC) :** flèches, OK, Retour → mêmes
  lignes que la Siri Remote.
- **Télécommande de l'iPhone (centre de contrôle) :** flèches, Select,
  Retour.

**Vert :** une touche = une ligne `press` qui bouge d'un pas, un Retour = une
seule ligne `back via …`.

### 5.9 Android TV (émulateur `emulator-5554` puis box)

Sur la machine qui a l'émulateur, depuis `app/` :

```bash
flutter run -d emulator-5554 -t lib/spike/dpad_spike_main.dart
```

1. **Double Retour (C2) :** mode `tv` (défaut), r1 c0 › Select › fiche › Retour.
   Rouge attendu : `DOUBLE RETOUR` et l'accueil sous la fiche disparaît aussi
   (deux routes). En-tête › **Mode** › `tvSansGoBack`, refaire. **Vert :** une
   seule ligne `back via didPopRoute`, une seule route dépilée.
2. **Touche maintenue :** **Chargé**, maintenir → du D-pad 3 s. Lire l'écart
   entre lignes `rep` et compter les `immobile`. **Vert :** aucun pas perdu ;
   sinon noter la cadence (≈ 50 ms attendu, origine de `TvKeyRepeat`).
3. Refaire 2 sur une vraie box en `--profile` (la répétition y diffère).

### 5.10 webOS

Le banc compile pour le web (flutter_tvos est derrière un import
conditionnel). Depuis `app/` :

```bash
flutter build web -t lib/spike/dpad_spike_main.dart -o build/spike_web
```

Le servir et l'ouvrir dans le simulateur webOS (ou une TV LG) à la place de
l'app : flèches, Entrée, Retour (touche 461 ou `browserBack`), champ de la
fiche. Les lignes `[DPAD]` sont dans la console (Tools › Inspector). **Vert :**
une flèche = un pas, Entrée = `evt onSelect`, Retour = une seule ligne
`back via …`. NB : le jeu de touches du banc n'a pas `browserBack` ; s'il
reste muet, c'est le constat attendu pour la phase 4 (ajouter le Retour LG au
jeu `back`).

## 6. Reproduire les mesures de ce rapport

- Headless (depuis `app/`) : `flutter test lib/spike/dpad_spike_test.dart`
  → 10 tests verts, une ligne `[DPAD]` par constat.
- Simulateur : build `~/flutter-tvos/bin/flutter-tvos build tvos --simulator
  --debug -t lib/spike/dpad_spike_main.dart`, `press_key`, puis
  `ext.spike.log` sur l'URL du service VM lue dans
  `xcrun simctl spawn <udid> log show --predicate 'eventMessage CONTAINS "Dart VM service"'`.
- Garde-fous de `test/` qui scannent `lib/` : verts sur le banc, sauf
  `no_bare_text_field_test` (le `TextField` nu de la fiche, présent dès le
  spike d'origine, voulu pour tester dpad sans `TvDeferredKeyboard`). Le banc
  est supprimé en phase 1 ; ne pas le fusionner tel quel.
