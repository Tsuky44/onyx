# ADR-0168 — `material_ui` à la place du Material du SDK

- **Statut :** proposé. Branche à part (`claude/material-ui-migration-38c6f6`, coupée de `tsuky`),
  rien de publié. Décision de Tsuky (2026-11-24) : migrer maintenant, comme étape à part après la
  montée de Flutter et Impeller (ADR-0167), pour qu'une seule variable change à la fois. Solde la
  « Dette connue » de l'ADR-0167.
- **Date :** 2026-11-24
- **Portée :** `l10n/material_localizations.dart` (nouveau) et `test/material_localizations_test.dart`
  (nouveau), l'ADR-0047 (Material suit désormais la langue), les imports de 550 fichiers de `app/lib`, `app/test` et `app/tool`,
  `app/pubspec.yaml` et `app/pubspec.lock`, `lib/theme/legacy_material_bridge.dart` (nouveau),
  `lib/main.dart` et `lib/screens/shared_link/shared_link_app.dart` (`MaterialApp.builder`),
  `test/material_ui_migration_guard_test.dart` (réécrit), `test/legacy_material_bridge_test.dart`
  (nouveau), les forks `packages/media_kit_video` (5 fichiers et `pubspec.yaml`) et
  `packages/onyx_player_android` (`onyx_player_view.dart`).

## Contexte

Depuis Flutter 3.47, `package:flutter/material.dart` et `package:flutter/cupertino.dart` sont
dépréciés (`@Deprecated('Use package:material_ui/material_ui.dart instead…')` sur la bibliothèque,
lu dans le SDK 3.50.1). Pour la montée en 3.50.1, chaque import portait un
`// ignore: deprecated_member_use` (ADR-0167).

Vérifié avant de coder :

- **Versions.** Sur pub.dev, la dernière `material_ui` est la **1.11.1** (publiée le 2026-11-16),
  la dernière `cupertino_ui` la **1.1.7**. Toutes deux exigent Flutter ≥ 3.47 et Dart ≥ 3.13. Le
  lock de la 3.50.1 les tirait déjà, aux mêmes versions, par `cached_network_image` (qui dépend de
  `material_ui`) et `cupertino_icons` (de `cupertino_ui`).
- **`material_ui` est une copie, pas un réexport.** Ses `Theme`, `ThemeData`, `MaterialApp`,
  `MaterialLocalizations`… sont d'autres classes que celles du SDK. Un widget de l'ancien Material
  placé sous une app `material_ui` ne trouve pas d'ancien `Theme` : `Theme.of` retombe sur le thème
  clair par défaut (primaire violet `0xFF6750A4`, police du système), et
  `MaterialLocalizations.of` n'a pas de textes. `test/legacy_material_bridge_test.dart` le montre.
- **`dart fix --apply --code=migrate_design_widgets`** (le correctif est dans l'analyseur du SDK,
  pas dans `material_ui`) remplace la ligne d'import sur place (`flutter/material.dart` →
  `material_ui/material_ui.dart`, `flutter/cupertino.dart` → `cupertino_ui/cupertino_ui.dart`) et
  ajoute `material_ui: any` et `cupertino_ui: any` à la fin du bloc `dependencies`. Il ne touche
  ni aux `ignore` du dessus, ni à l'ordre des imports, ni au code : les noms sont les mêmes.
- **Le pont officiel, `MaterialUiCompatibilityBridge`** (`material_ui`,
  `lib/src/migration_utility.dart`) pose un ancien `Theme` construit à partir du thème
  `material_ui` (schéma de couleurs, 15 styles de texte, densité, plateforme ; aucun thème de
  composant) et un `Localizations.override` avec, par défaut, les `Global*Localizations` de
  `flutter_localizations`. Il est lui-même `@Deprecated` (« utilitaire temporaire »).
- **Localisations.** `material_ui` fournit ses propres `GlobalMaterialLocalizations`
  (`GlobalMaterialLocalizations.delegates` couvre Widgets, Material et Cupertino). L'app, elle,
  n'en branche aucune : pas de `localizationsDelegates` ni de `locale` sur `MaterialApp`. C'est
  voulu par l'ADR-0047 : « Material n'est pas localisé […] ses rares textes propres restent en
  anglais dans les deux langues ».

## Décision

1. **La migration de l'app passe par l'outil officiel**, tel quel. 548 imports de Material et 2 de
   Cupertino (`theme/app_page_transitions.dart`, `test/premium_chrome_test.dart`) changent, les
   550 `ignore` de l'ADR-0167 tombent. `material_ui ^1.11.1` et `cupertino_ui ^1.1.7` deviennent
   des dépendances directes, rangées et commentées. `flutter analyze` est propre dès ce premier
   commit, sans autre retouche.

2. **Les forks de `packages/`**, un par un :

   | Fork | Import de l'ancien Material | Décision |
   |---|---|---|
   | `media_kit_video` | 5 fichiers | **Migré** par le même `dart fix`, dépend de `material_ui`, plancher Flutter 3.47. Son `SubtitleView` (sous-titres de la texture : Windows, web) pose un `Material` : resté sur l'ancien, il aurait pris le thème par défaut et les sous-titres auraient perdu la police de l'app. Les quatre autres fichiers (commandes de media_kit) ne sont pas affichés par l'app (`controls: null`), migrés pour ne plus laisser d'ancien import. |
   | `onyx_player_android` | 1 fichier | **`widgets.dart`** : rien de Material n'y sert (`PlatformViewLink`, `StatelessWidget`). Aucune dépendance ajoutée. |
   | `onyx_player_apple`, `onyx_mpv_macos`, `onyx_background_downloads`, `media_kit_libs_*` | aucun | rien à faire |

3. **Les dépendances de pub.dev restent sur l'ancien Material, derrière un pont.** Elles ne sont
   pas à nous. Ce que l'app en affiche vraiment (relevé dans leurs sources et nos appels) :

   | Dépendance | Ce que l'app en affiche | Lit l'ancien thème ? |
   |---|---|---|
   | `dpad` | `DpadFocusable`, `DpadRegion` | Seulement pour la couleur par défaut des effets et du surligneur volant ; nos `effects` sont vides et le surligneur n'est pas utilisé. Sans `Theme` ancien, dpad prend le blanc. |
   | `mobile_scanner` | `MobileScanner` (lier une TV) | Son écran d'erreur par défaut : couleurs constantes, icône. |
   | `octo_image` (par `cached_network_image`) | rien de Material : nos `placeholder` et `errorWidget` sont à nous | Ses indicateurs de progression par défaut le liraient. |
   | `window_manager` | l'API de fenêtre ; nos boutons de légende sont à nous | Son `WindowCaption`, que l'app n'utilise pas. |
   | `qr_flutter` | `QrImageView` | Non (couleurs constantes). |
   | `flutter_shaders` (par `flutter_animate`), `nested` (par `provider`) | rien de Material | Non. |
   | `audio_video_progress_bar` | **rien** : déclaré dans `pubspec.yaml`, importé nulle part | — |

   Aucun chemin affiché aujourd'hui ne dépend donc du pont. Il est posé quand même, dans le
   `builder` des deux `MaterialApp` (l'app et la page du lien partagé), pour qu'un chemin d'erreur
   rare ou une montée de dépendance ne fasse pas réapparaître le thème clair sans bruit.

4. **Notre pont, `LegacyMaterialBridge`, plutôt que celui de `material_ui`.** Même correspondance
   (couleurs, styles de texte avec la police, densité, plateforme), mais :
   - pas de widget déprécié à poser (l'import et les délégués de traduction le sont, dans un
     seul fichier listé) ;
   - l'ancien thème est gardé par thème (`Expando`) au lieu d'être recalculé à chaque
     construction du `builder`, qui suit chaque changement de `MediaQuery` (redimensionnement) ;
   - ses textes sont ceux de l'ancien Material **dans la langue de l'app** : les délégués de
     `flutter_localizations` (dépréciés avec l'ancien Material, d'où deux `ignore` listés par la
     garde), qui suivent la `locale` héritée de `MaterialApp`.

5. **Material suit la langue de l'app** (décision de Tsuky, 2026-11-24, commit à part de la
   migration). Jusqu'ici, l'ADR-0047 laissait Material en anglais dans les deux langues. Les deux
   `MaterialApp` prennent désormais, par `l10n/material_localizations.dart`
   (`AppMaterialLocalizations`) :
   - `localizationsDelegates` : `GlobalMaterialLocalizations.delegates` de `material_ui`
     (Material, Cupertino, widgets) ;
   - `supportedLocales` : `fr` et `en_US` (l'anglais américain, comme les dates de
     `LocaleFormats`) ;
   - `locale` : celle d'`AppLanguage`. Changer de langue reconstruit déjà l'app entière sous une
     nouvelle clé (`main.dart`), Material suit donc à chaud.

   Les dépendances restées sur l'ancien Material sont traduites aussi, par le pont (point 4).
   L'ADR-0047 est mise à jour. Vérifié en FR et en EN par `test/material_localizations_test.dart` :
   infobulle du bouton retour, copier et coller, titre de la page des licences, sélecteur de date
   affiché, changement de langue à chaud, et les mêmes textes vus par l'ancien Material.

   **Coût sur le web**, mesuré sur deux builds `flutter build web --wasm --release
   --no-web-resources-cdn --pwa-strategy=none` (les options de `scripts/build-web.sh`), avant et
   après ce seul changement :

   | Fichier | Sans traduction | Avec | Écart | Écart compressé (gzip -9) |
   |---|---|---|---|---|
   | `main.dart.js` (repli JS : webOS, Safari, Firefox) | 5 931 443 o | 6 396 887 o | +465 Ko (+7,8 %) | +95 Ko (1 713 → 1 809 Ko) |
   | `main.dart.wasm` (WasmGC) | 5 341 903 o | 5 672 746 o | +331 Ko (+6,2 %) | +109 Ko (1 936 → 2 045 Ko) |
   | dossier `build/web` entier | 52,3 Mo | 53,1 Mo | +0,8 Mo | — |

   Un navigateur ne charge qu'un des deux fichiers : environ **+100 Ko compressés** par
   chargement. Le surcoût vient des tables de traduction de Material dans ~80 langues, deux fois
   (celles de `material_ui` pour l'app, celles de `flutter_localizations` pour le pont), alors que
   deux langues servent. Il se réduirait avec des délégués qui ne construisent que
   `MaterialLocalizationFr` et `MaterialLocalizationEn` ; non fait ici (changement à part, à
   peser contre une copie des réglages de dates des délégués officiels).

6. **Garde.** `test/material_ui_migration_guard_test.dart` passe du plafond (548) à l'interdiction :
   - aucun import de `flutter/material.dart` ou `flutter/cupertino.dart` dans `lib/`, `test/`,
     `tool/` ni dans le Dart de nos forks, sauf trois exceptions listées avec leur raison : le pont
     et les deux tests qui lisent ce que voit l'ancien Material ;
   - une exception qui ne sert plus doit sortir de la liste ;
   - l'`ignore: deprecated_member_use` n'est admis qu'au-dessus de ces imports, sur les deux
     délégués de traduction du pont, et sur les quatre lignes de `tv_nav_harness.dart`
     (inchangées) ;
   - chaque `MaterialApp` de `lib/` pose `LegacyMaterialBridge`.

## Différences de rendu

### Ce que le code de `material_ui` 1.11.1 change par rapport au Material du SDK 3.50.1

Comparaison classe par classe des deux sources (commentaires retirés, même formatage), puis
croisement avec les composants que l'app utilise. Le gros des différences est du déplacement (les
valeurs par défaut M3 passent dans `generated/`, identiques), des ajouts optionnels (variantes
« Material 3 Expressive », `contrastLevel`, clic du milieu sur `InkWell`, `supportingTextPadding`…)
désactivés par défaut, et des corrections sur des composants absents de l'app (curseurs,
onglets, sélecteur d'heure, `SearchAnchor`, `MenuAnchor`, `NavigationRail`, tableaux).

Ce qui peut se voir dans l'app :

- **`SnackBar` dont l'action ne tient pas sur la ligne** (32 usages de `SnackBar`) : l'espace
  réservé à droite du texte passe de 40 % de la largeur à la marge horizontale, et le calcul tient
  compte de l'échelle de texte du système. Seulement quand l'action passe sous le texte.
- **`Dialog.fullscreen`** : la marge du clavier s'applique aussi au plein écran. L'app n'a pas de
  dialogue plein écran.
- **`Switch` sélectionné** : `surface.withOpacity(1.0)` devient `surface` ; identique avec notre
  `surface` opaque.
- **Transition `FadeForwards` sur Android** : désormais rendue par instantané. L'app ne l'utilise
  pas (`OnyxPageTransitionsBuilder` partout, glissé de Cupertino sur iOS).

### Vérification visuelle

Décision de Tsuky (2026-11-24) : **pas de comparaison de captures**. La vérification visuelle se fait
par sa relecture sur un exe, et il signale ce qui a changé et ce qu'il faut reprendre. Un premier
passage de captures web (Playwright, avec les scripts des captures de référence) a été lancé puis
abandonné : la base du serveur jetable, recopiée sans ses dates de fichiers, avait perdu
progressions et pistes, et les écarts relevés venaient de ces données, pas de Material.

Différences visibles déjà connues, à regarder en priorité :

- **Textes de Material en français** dans l'app française (voulu, point 5) : menu
  copier/coller des champs, infobulle du bouton retour, page des licences (« Licences »),
  sélecteur de date, et les autres textes par défaut de Material (« Annuler », « OK »…).
- Les quatre écarts de code relevés plus haut (`SnackBar` à action longue surtout).
- Rien d'autre n'est attendu : les valeurs par défaut de Material 3 (couleurs, tailles,
  typographie, ombres, focus) sont identiques entre les deux copies, et le thème de l'app ne
  change pas.

## Conséquences

- Plus aucune remarque de dépréciation de Material dans `flutter analyze`.
- Le pont reste tant qu'une dépendance importe l'ancien Material. Pour le retirer : plus aucune
  dépendance listée au point 3, puis supprimer `legacy_material_bridge.dart`, son test, ses deux
  usages, la partie « ancien Material » de `material_localizations_test.dart`, ses exceptions dans
  la garde et `flutter_localizations` du `pubspec.yaml`.
- `audio_video_progress_bar` n'est importé nulle part : il peut sortir de `pubspec.yaml` (changement
  à part).
- Vérifié ici : `flutter analyze` sans aucun problème ; `flutter test` à 2857 réussis, 11 ignorés,
  un échec qui existait déjà (`onyx_player_apple_sources_test`, fins de ligne CRLF) ; builds
  Windows release (`STORE_BUILD=true`, depuis un lecteur `subst`), web (`--wasm` comme
  `scripts/build-web.sh`, et sans `--wasm`) et APK debug (depuis le vrai chemin).
- **Non vérifié ici :** le rendu à l'écran (relecture de Tsuky sur un exe), iOS, macOS et tvOS
  (rien ne se compile pour Apple sur cette machine), et un vrai téléviseur (Android TV, webOS) au
  D-pad.
