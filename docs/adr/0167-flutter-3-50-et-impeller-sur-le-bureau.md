# ADR-0167 — Flutter 3.50 et Impeller sur le bureau, Windows compris

- **Statut :** proposé. Branche à part (`claude/flutter-3-50-85638b`), rien de publié : la phase 2
  de l'ADR-0158 (rendu D3D11 de libmpv, version 1.2.0) se juge encore une semaine sur les journaux
  avant que cette montée parte. Décision de Tsuky (2026-11-23) : Impeller sous Windows aussi, pas
  seulement sur Mac. Le plan d'origine gardait Skia sous Windows et prévoyait un essai d'Impeller à
  part, piloté par un réglage. Tranche la piste « Impeller sous Windows » que l'ADR-0025 laissait
  « à essayer avec une mesure en main » : la mesure est ci-dessous.
- **Date :** 2026-11-23
- **Portée :** `.github/workflows/{ci,release,server,tvos}.yml` (`FLUTTER_VERSION`,
  `FLUTTER_TVOS_VERSION`), `scripts/build-tvos-ipa.sh`, `app/pubspec.yaml` (plancher `flutter`,
  `file_picker` bloqué sous 13.4), `app/pubspec.lock`, `app/windows/runner/main.cpp` (commentaire
  du moteur), `app/android/` (Gradle, AGP, Kotlin) et les `buildscript` de `onyx_player_android`
  et `onyx_background_downloads`, `shaders/scroll_edge_blur.frag`,
  `screens/shell/desktop_header_search.dart` (flèches de la recherche),
  `screens/player/playback/mpv_diagnostics.dart`, `tool/frame_timeline.dart` (nouveau, non livré).

## Contexte

L'app était en Flutter 3.44 (3.44.2 en CI, 3.44.4 en local), avec flutter-tvos `v3.44.9`. Sur le
bureau, l'interface passait par Skia : Metal sur Mac, ANGLE/D3D11 sous Windows. Depuis la 3.47,
Impeller est le moteur par défaut sur macOS, Windows et Linux. La 3.50 apporte des correctifs pour
Windows (OpenGL ES 3 par défaut avec repli ES2, une recopie plein écran de moins par image, un
plantage corrigé sur les textures externes).

Version retenue : **3.50.1** (stable du 2026-11-20, Dart 3.14.0, révision `ae9b586f34`). Le numéro
vient de `releases_windows.json` de Flutter, et le zip a été vérifié par son SHA-256. Pour tvOS :
**flutter-tvos `v3.50.1-tvos.1.12.2`**, la dernière étiquette sur la même ligne.

Ce que les sources du SDK 3.50.1 montrent, lu dans `engine/src/flutter/shell/platform/` :

- **Windows** (`windows/flutter_windows_engine.cc`) : `enable_impeller = true` par défaut. Le
  client C++ expose `DartProject::set_impeller_switch(ImpellerSwitch)`. Hors release,
  `FLUTTER_ENGINE_SWITCHES` passe outre (`--enable-impeller=false`) ; en release, les variables
  d'environnement sont ignorées (`common/engine_switches.cc`, `#ifndef FLUTTER_RELEASE`). Impeller
  n'a **pas de rendu logiciel de secours** : sans surface GPU, le moteur refuse de démarrer.
- **macOS** (`darwin/macos/framework/Source/FlutterDartProject.mm`) : Impeller est actif par défaut
  (`FLTEnableImpeller`). Le wide gamut vaut `enableImpeller && MTLGPUFamilyApple3`, puis le moteur
  le règle par écran selon `canRepresentDisplayGamut:NSDisplayGamutP3`. Contrairement à iOS
  (`FLTEnableWideGamut`), **macOS n'a pas d'interrupteur propre au wide gamut** : il vient avec
  Impeller sur un Mac Apple Silicon et un écran P3, ou disparaît avec lui.

## Décision

1. **Flutter 3.50.1 partout** : les trois workflows, avec flutter-tvos `v3.50.1-tvos.1.12.2` dans
   `release.yml`, `tvos.yml` et `scripts/build-tvos-ipa.sh`. tvOS est monté en même temps parce
   que le lock résolu par la 3.50 exige Flutter ≥ 3.47 (`material_ui`, `cupertino_ui`, `hooks`…) :
   flutter-tvos 3.44 ne le résoudrait plus.
2. **Impeller sur le bureau, Windows compris.** Rien n'est forcé dans `main.cpp`, puisque le défaut
   de la 3.50 est Impeller. Le journal le confirme au lancement : `Using the Impeller rendering
   backend (OpenGLESSDF)`. Le commentaire de `main.cpp` dit comment repasser en Skia hors release
   pour comparer.
3. **Wide gamut sur Mac : gardé**, puisqu'il ne se sépare pas d'Impeller. Les deux lecteurs du Mac
   n'y passent pas : `onyx_player_apple` (AetherEngine) et `onyx_mpv_macos` posent des vues natives
   composées par le système (`PlayerSurfaceView`, `MpvHostView`), et la couleur de la vidéo HDR/DV ne
   dépend donc pas de la surface Flutter. Seule la texture de media_kit (BGRA 8 bits sRGB) passe par
   cette surface ; Impeller la gère en couleur sRGB étendue. L'iPhone tourne déjà ainsi.
4. **`pub upgrade` dans les contraintes existantes**, sans montée majeure. Les majeures disponibles
   (`flutter_local_notifications` 23, `window_manager` 0.7, `screen_retriever` 0.4…) restent hors
   de cette montée. `file_picker` est bloqué sous 13.4 : la 13.4 déprécie `getDirectoryPath` pour
   `pickDirectory`, qui rend une URI `content://` sur Android, là où la bibliothèque de l'appareil
   attend un chemin. Le plancher `flutter: '>=3.50.1'` est ajouté à l'app. La version de langage
   (`sdk`) reste la même : la relever est un autre changement.
5. **Les forks de `packages/`** (media_kit_video et libs, `onyx_*`) gardent leurs contraintes. Ils
   compilent et passent leurs tests en 3.50.1 sans changement.

### Ruptures corrigées

- **Les flèches de la recherche du bureau** (`desktop_header_search.dart`). Depuis la 3.47
  (flutter/flutter#180883), `Action.overridable` cherche son remplaçant sous le **type exact de
  l'intention** (`ExtendSelectionVerticallyToAdjacentLineIntent`), et non plus sous le paramètre de
  type de l'action (`DirectionalCaretMovementIntent`). Déclarée sous ce dernier, l'action n'était
  plus trouvée : Bas restait au curseur du champ au lieu d'entrer dans la grille. Trois tests de
  `desktop_search_test.dart` l'ont attrapé. L'action est maintenant déclarée sous l'intention de
  ligne. C'est la seule clé de ce genre dans `lib/`.
- `mpv_diagnostics.dart` : `return await` dans le `try` (nouvelle règle
  `unawaited_return_in_try_block`). Un échec du relevé groupé retombe bien sur le relevé direct.
- Deux imports de `rendering.dart` devenus inutiles (`ScrollCacheExtent` est exporté par
  `material.dart` en 3.50).
- **Android, outillage.** La 3.50 refuse de construire sous Gradle 9.3.1, AGP 9.1.1 et Kotlin
  2.4.10 (`DependencyVersionChecker.kt`). Le projet avait Gradle 9.1.0, AGP 9.0.1 et Kotlin 2.3.20.
  Il passe aux versions du gabarit de la 3.50 : Gradle 9.5.0, AGP 9.3.1, Kotlin 2.4.20, toutes dans
  les mêmes majeures. Les `buildscript` de `onyx_player_android` et `onyx_background_downloads`
  suivent, pour ne pas avoir deux AGP dans la même build. La 3.50 prévient que `workmanager_android`
  applique encore le plugin Kotlin et qu'une version future le refusera.
- **`shaders/scroll_edge_blur.frag`** (ADR-0144) n'a plus qu'une sortie. Le compilateur de la 3.50
  signale qu'un `return` anticipé à côté d'un échantillonneur peut faire échouer le shader sous
  Windows (flutter/flutter#190809). Avec Impeller, Windows passe désormais par là.
- L'outil réordonne les registres de plugins générés (le `media_kit_video` surchargé passe en
  dernier) : c'est un fichier produit par l'outil, gardé tel quel.

### Point ouvert : `package:flutter/material.dart` est déprécié

Depuis la 3.47, `material.dart` et `cupertino.dart` sont dépréciés au profit des paquets
`material_ui` et `cupertino_ui`. Ce sont **551 des 554** remarques de `flutter analyze` en 3.50.1,
et la CI échoue sur les `info`. `material_ui` est une **copie distincte** de Material : son `Theme`
et son `MaterialApp` sont d'autres classes. Il faut donc aussi `MaterialUiCompatibilityBridge` et
les localisations de `material_ui`, parce que douze dépendances importent encore
`flutter/material.dart` (dpad, media_kit_video, audio_video_progress_bar, window_manager,
mobile_scanner, octo_image…). La question est posée à Tsuky : migrer dans cette montée, ou plus
tard, à part. La branche n'est pas verte en analyse tant que ce n'est pas tranché.

## Mesure

### Temps d'image sous Windows

Machine de Tsuky : Windows 11, AMD Radeon RX 6800 XT (pilote 32.0.21045.5002). Builds profile
`STORE_BUILD=true`. Fenêtre à sa taille de lancement. Compte connecté au vrai serveur, rendu vidéo
réglé sur « Nouveau » (D3D11).

**Méthode, à refaire à l'identique :**

1. Lancement avec un VM service fixe, par les variables que l'embedder lit hors release :
   `FLUTTER_ENGINE_SWITCHES=2`, `FLUTTER_ENGINE_SWITCH_1=vm-service-port=8181`,
   `FLUTTER_ENGINE_SWITCH_2=disable-service-auth-codes`. Attente de 12 s, puis un clic sur le logo
   pour le focus. Pour Skia sur une build 3.50 : `SWITCHES=3` et
   `SWITCH_3=enable-impeller=false`.
2. Pour chaque geste, `dart tool/frame_timeline.dart record <libellé> <fichier.jsonl> <s>`. La
   timeline du VM est un tampon circulaire (~280 images) : lue une seule fois, elle tronquait le
   relevé. L'outil la relit donc chaque seconde et dédoublonne. UI = `Animator::BeginFrame`,
   raster = `GPURasterizer::Draw`.
3. Les gestes, dans l'ordre, deux fois (passage 1 à froid, passage 2 à chaud) :
   **accueil** (14 s : trois crans de molette ×5 vers le bas, retour en haut), **fiche** (22 s :
   Films, première affiche, défilement, retour, Accueil), **lecteur** (40 s : la même fiche,
   Lecture/Reprendre d'un film 1080p H.264 en Direct Play, 12 s de lecture, commandes affichées
   puis masquées, retour). Les coordonnées exactes sont dans la note de session
   `flutter-3-50-protocole-mesure.md`.

Médianes UI / raster (ms), puis images au-delà de 16,7 ms UI / raster :

| Passage | 3.44.4 Skia | 3.50.1 Skia | 3.50.1 Impeller |
|---|---|---|---|
| accueil-1 | 0,56 / 1,72 · 5 / 6 | 2,35 / 1,72 · 6 / 7 | 2,23 / 2,94 · 5 / 1 |
| fiche-1 | 0,55 / 1,83 · 12 / 6 | 2,15 / 1,94 · 15 / 13 | 2,15 / 3,63 · 13 / 2 |
| lecteur-1 | 0,57 / 1,57 · 14 / 9 | 2,09 / 1,79 · 12 / 6 | 2,11 / 3,37 · 17 / 6 |
| accueil-2 | 0,56 / 1,78 · 6 / 4 | 1,98 / 1,63 · 6 / 2 | 1,95 / 3,06 · 5 / 1 |
| fiche-2 | 0,58 / 1,83 · 10 / 7 | 2,06 / 1,60 · 11 / 4 | 2,00 / 3,23 · 17 / 6 |
| lecteur-2 | 0,58 / 1,66 · 11 / 3 | 2,07 / 1,58 · 16 / 4 | 2,11 / 2,77 · 16 / 3 |
| **Total > 16,7 ms** | **58 / 35** | **66 / 36** | **73 / 19** |

Raster p99 au premier passage (saccades de premier affichage) : accueil 20,3 → 20,7 → **5,6 ms** ;
fiche 35,3 → 37,5 → **6,9 ms**.

Lecture :

- **Le temps UI médian passe de 0,6 à 2,1 ms avec le SDK 3.50, en Skia comme en Impeller.** Cela
  vient du framework ou du moteur de la 3.50, pas du moteur de rendu. La cause n'est pas trouvée.
  Le surcoût reste à un huitième du budget d'une image.
- **Impeller double le raster médian** (1,7 → 3,2 ms), mais **divise par deux les images raster
  hors budget** (35 → 19). Au premier affichage, elles passent de 21 (3.44) ou 26 (3.50 Skia) à 9 :
  sans compilation de shaders à la volée, les saccades de première visite disparaissent presque.

### Mémoire et processeur au repos

`scripts/perf/measure-windows.ps1`, 20 s par scénario, 20 s d'échauffement :

| Scénario | 3.44.4 Skia | 3.50.1 Skia | 3.50.1 Impeller |
|---|---|---|---|
| Accueil : CPU moyen / mémoire privée | 0,54 % / 516 Mo | 0,70 % / 528 Mo | 1,00 % / 705 Mo |
| Arrière-plan | 0,02 % / 514 Mo | 0,06 % / 521 Mo | 0,05 % / 648 Mo |
| Réduite | 0,06 % / 509 Mo | 0,05 % / 506 Mo | 0,02 % / 647 Mo |

L'ensemble de travail ne bouge pas (~315-320 Mo dans les trois cas). La **mémoire privée prend
environ 140 Mo avec Impeller**, et seulement avec lui : la 3.50.1 en Skia reste à ±12 Mo de la
3.44.4. C'est de la mémoire réservée par le moteur, pas résidente. L'ADR-0166 visait la RAM : ce
coût est à connaître avant de publier.

### La vidéo sous Impeller (Windows)

| Cas | Résultat |
|---|---|
| D3D11 (« Nouveau »), H.264 1080p | image, commandes par-dessus, `render=d3d11`, `hwdec=d3d11va` |
| Bascule D3D11 → ANGLE en pleine lecture (`ONYX_FORCE_D3D11_FALLBACK=true`, Automatique) | `render path: angle (fallback)`, puis `hwdec=d3d11va-copy · rendu=angle · 29 rendus, 0 ratés`, image revenue |
| Même essai, réglage « Nouveau » | pas de bascule, en Skia comme en Impeller (le réglage explicite tient le chemin) |
| Plein écran aller-retour, image dans l'image aller-retour (sur ANGLE) | image juste, lecture reprise |
| Dolby Vision 5 (Paradise S2E5, 4K HEVC, fenêtre gpu-next sous l'app, ADR-0061) | image à travers la surface transparente, sous-titres et commandes par-dessus |

**Incident, non reproduit.** Un lancement de la build Impeller a planté avant la première image :
`0xc0000005` à l'adresse 0, dans un fil du pilote AMD D3D11 (`amdxx64.dll`), juste après la
création des surfaces D3D11. Il n'a pas été reproduit sur les relances suivantes, ni sur aucune
autre build profile de la journée. Les vidages des 18–20 novembre (en 3.44) sont d'autres
plantages, dans `flutter_windows.dll` sous libmpv. À surveiller dans les journaux de la version de
test.

**`set_impeller_switch(Disabled)` n'a pas eu d'effet** dans la build profile 3.50.1, alors que les
sources le transmettent. La variable d'environnement, elle, repasse bien en Skia. La cause n'est
pas trouvée. Avant de s'appuyer sur ce levier comme repli en release, il faut le revérifier : en
release, c'est le seul.

### Android, analyse, tests

- `flutter test` en 3.50.1 : 2841 réussis, 11 ignorés, 1 échec, le même qu'en 3.44
  (`onyx_player_apple_sources_test` : fins de ligne CRLF du Swift généré dans une copie Windows).
- `flutter build apk --debug` : construit. Depuis le vrai chemin du worktree : sous un lecteur
  `subst`, la compilation Kotlin incrémentale échoue, parce que le projet et le cache pub ne sont
  pas sur la même racine.
- `flutter build windows --profile` : construit, sans avertissement de shader.
- `flutter analyze` : seules restent les dépréciations de `material.dart`/`cupertino.dart` (point
  ouvert ci-dessus).

## Conséquences

- **À vérifier sur Mac** (rien ne se compile pour Apple ici) :
  - `flutter build macos --debug` puis lancement sur un Mac Apple Silicon avec écran P3. Le
    journal doit annoncer Impeller, et les couleurs de l'interface (accents, dégradés, affiches)
    doivent rester celles de la 3.44.
  - `onyx_player_apple` en HDR10 et en DV, puis `onyx_mpv_macos` en DV5 : couleurs, sous-titres et
    commandes par-dessus la vue native (vues natives sur une surface Impeller).
  - Le repli media_kit sur Mac : une texture BGRA 8 bits sur une surface 10 bits.
  - Les flous (en-têtes de verre, ADR-0144/0157) et le shader `scroll_edge_blur.frag`, qui ne
    servait que sous Impeller et sert désormais aussi sur Mac.
  - `FLTEnableMergedPlatformUIThread=false` (Info.plist) : la 3.50 l'accepte encore, mais annonce
    qu'il deviendra non pris en charge.
  - iOS : `flutter build ios --debug --no-codesign`. Rien ne change pour le moteur (Impeller depuis
    longtemps).
  - tvOS : `scripts/build-tvos-ipa.sh` avec flutter-tvos `v3.50.1-tvos.1.12.2`, puis le parcours
    D-pad.
- **À vérifier sur appareil Android** : lecture (`onyx_player_android`, media3), téléchargements
  en arrière-plan, Android TV. Impeller y était déjà le moteur ; seul l'outillage Gradle change.
- **À vérifier en CI** : `ci.yml` (analyse + tests en 3.50.1), le job `build-tvos` de
  `release.yml`/`tvos.yml` avec le nouveau flutter-tvos, les builds Android/Windows/macOS/iOS de
  `release.yml` sans publier, et l'image serveur (`server.yml` construit le web en 3.50.1).
- **Le web** (`server.yml`, skwasm, ADR-0152) change de Flutter sans avoir été vérifié ici.
- Sous Windows, une panne de surface GPU laisse la fenêtre noire au lieu de retomber en logiciel
  (machines virtuelles, bureau à distance sans GPU). À surveiller dans les retours de la version de
  test.
- `tool/frame_timeline.dart` reste dans le dépôt pour refaire la mesure à l'identique à la
  prochaine montée.
