# Spike : lecteur natif Apple TV (étape 0)

Date : 2026-11-04. Moteur : AetherEngine 7.42.0 (`f5af2a38`), Xcode 27, simulateur Apple TV 4K (3e gén.) sous tvOS 27.0, flutter-tvos `v3.44.9-tvos.1.5.1`.
Fichier non commité. Le code du spike est retiré du dépôt. Une copie est conservée dans le dossier de notes partagé (`side-session-notes/…/spike-native-tv/`), avec le banc macOS et les journaux.

## Verdict : GO sous conditions

Les deux critères de no-go ne sont pas atteints.

- **Le focus revient à Flutter** après Menu. Observé une fois dans le simulateur. À reconfirmer sur l'appareil.
- **Le rendu fonctionne sur la route native**. Le moteur lit, décode et sert l'image sans vue liée, et l'`AVPlayer` publié est celui que prend `AVPlayerViewController`.

Le plan doit intégrer trois corrections, sans quoi l'étape 1 sera fausse :

1. **Route `software` = pas de lecteur natif.** Sur cette route, `engine.currentAVPlayer` vaut `nil` : `AVPlayerViewController` affiche une roue qui tourne sur un plan vide, alors que le son joue. Pour les sources de cette route, `PlayerScreen` doit garder l'interface Flutter actuelle. Le choix se fait sur `engine.$videoRoute`, pas sur le codec (README AetherEngine, #298).
2. **L'audio ne passe pas par le menu natif.** Le groupe `audible` de l'item n'expose que la piste active, car le moteur sert une seule rendition audio. Le choix de la langue audio doit donc passer par une entrée `transportBarCustomMenuItems` qui appelle `selectAudioTrack`.
3. **Les sous-titres doivent être déclarés au `load`.** Sinon, ils n'arrivent pas dans le menu natif. Aujourd'hui, `AetherPlayer.setExternalSubtitle` les ajoute après coup (`addExternalSubtitleTrack`) : il faut les passer dans `LoadOptions.externalSubtitles` avec `prepareNativeSubtitles = true`, puis répondre au choix fait dans le menu AVKit (voir Q5).

## Méthode

- **Simulateur tvOS.** Fichier jetable `SpikeNativeTV.swift` sous `#if os(tvOS)` dans le plugin, lancé par `-onyxSpike <film>` depuis `OnyxPlayerApplePlugin.register`. Il présente un `AVPlayerViewController` par-dessus le `FlutterViewController` racine, puis enchaîne `load`, changement d'audio, nouveau `load`, `reloadAtCurrentPosition` et l'attente de Menu. Toutes les APIs du plan y sont branchées.
- **Limite du simulateur, découverte en route.** Il n'y a aucun décodeur matériel VideoToolbox : `[VTProbe] canHardwareDecode codec=27 1920x1080 -> false (status=-12906)`, donc `dispatch: codec=27 → software`. Tout film, même H.264 SDR, y prend la route logicielle. La route native y est donc invérifiable.
- **Banc macOS headless**, pour la route native. Petit exécutable SwiftPM qui utilise le même AetherEngine 7.42.0, sans aucune vue liée, avec les mêmes `LoadOptions` que `AetherPlayer.open`. Les comportements du moteur testés (identité de l'`AVPlayer`, items, groupes de sélection, sous-titres) sont du code commun à toutes les plateformes. Il en sort `dispatch: codec=27 → native`, puis `effective video route = loopback`.
- **Films de test** générés avec ffmpeg, 2 min chacun : MKV HEVC Main10 HDR10 (PQ, BT.2020, métadonnées mastering et CLL) avec deux pistes AC-3 (eng et fre), la même chose en H.264 SDR, et un WebVTT de deux répliques.

## Réponses

### Q1. Le moteur joue-t-il sans `AetherPlayerView` attachée ?

**Oui, sur la route native** (banc macOS, H.264 et HDR10, aucune vue liée) :

```
[t+2s] route=loopback phase=playing rate=1.0 tcs=2 itemTime=1.48 size=(1920.0, 1080.0) status=1 firstFrame=true
[t+6s] route=loopback phase=playing rate=1.0 tcs=2 itemTime=5.50 ...
videoOutput hasNewPixelBuffer=true pixelBuffer=true
[HDR10] [t+6s] route=loopback phase=playing rate=1.0 itemTime=5.84 format=hdr10
```

L'horloge avance, l'item est `readyToPlay` et des images décodées sortent. Le moteur ne bloque pas la lecture en attendant une couche.

**Non, sur la route logicielle** (simulateur) : le son joue, mais l'image part dans une couche hors hiérarchie. Le moteur le dit lui-même : `[SWHost] 41 frames decoded into a display layer that is in no view hierarchy … renders into that layer, not through AVPlayerViewController, so audio plays and no picture can appear`. Capture : `logs/avpvc-software-route-spinner.png`, une roue AVKit sur fond noir.

**La vue cachée attachée** n'est pas nécessaire sur la route native. Sur la route logicielle, elle ne règle rien : l'image irait dans une vue invisible. Seule une vue visible (Flutter, ou une `AetherPlayerView` dans `contentOverlayView`, non testé) affiche cette route.

### Q2. `engine.currentAVPlayer` change-t-il à chaque rechargement ?

**Non pour un rechargement, oui après `stop()`.** C'est l'item qui change à chaque fois (banc macOS, identités d'objets) :

| Action | `currentAVPlayer` | `currentAVPlayerItem` |
|---|---|---|
| premier `load` | A | item 1 |
| `selectAudioTrack` (changement d'audio) | A, identique | item 2 |
| nouveau `load` à la position courante (changement de qualité) | A, identique | item 3 |
| `reloadAtCurrentPosition()` | A, identique | item 4 |
| `stop(resetDisplayCriteria: false, finalTeardown: false)` puis `load` (épisode suivant) | **B, nouveau** | item 5 |

`BILAN: AVPlayer distincts=2 items distincts=5`. Sur la route logicielle, il passe à `nil`.

**Faut-il réaffecter `playerVC.player` ?** Oui. Il faut observer `engine.$currentAVPlayer` et réaffecter seulement quand l'identité change (`!==`). Le moteur prévient que republier la même instance relance l'enregistrement AVKit (commentaire d'`AetherEngine+Loading.swift`). Sur `nil` (route logicielle), il faut basculer sur l'interface Flutter. Pour ce qui dépend de l'item, observer `engine.$currentAVPlayerItem`. `externalMetadata` passe par `engine.setExternalMetadata(_:)`, que le moteur rejoue sur chaque nouvel item.

### Q3. Après Menu, le focus revient-il à Flutter ?

**Oui** (simulateur, un essai, Menu appuyé depuis le panneau du simulateur pendant la présentation) :

```
delegate : playerViewControllerShouldDismiss -> true
delegate : willBeginDismissalTransition
delegate : didEndDismissalTransition
focus +0.0s après fermeture : nil presented=nil
focus +1.0s après fermeture : nil presented=nil
focus +3.0s après fermeture : FlutterSemanticsObject <FlutterSemanticsObject: 0x105843ae0> presented=nil
```

Ensuite, une flèche droite déplace bien le focus dans l'accueil Flutter : la capture montre la carte « Blacklist » de « Reprendre la lecture » en surbrillance.

Deux réserves :

- **Le focus UIKit reste `nil` une à trois secondes** après la fermeture. Il faut vérifier sur l'appareil qu'aucun appui n'est perdu pendant ce temps.
- **L'appui Menu n'a pas pu être rejoué par mes outils.** Xcode 27 n'a plus de Simulator.app, et `press_key` n'a pas de touche Échap (Delete ne fait rien). L'essai reste donc unique.

### Q4. HDR et Dolby Vision (Match Content) passent-ils ?

**Non vérifiable ici.** Le simulateur annonce `DisplayCapabilities observed: hdr=false hdr10=false hlg=false dv=false` et `DisplayCriteria skipped: Match Content disabled`, et il est de toute façon sur la route logicielle. Le banc macOS confirme seulement la détection (`format=hdr10` sur la route `loopback`), pas l'affichage.

Test exact à faire sur une vraie Apple TV 4K branchée à un téléviseur HDR10 et Dolby Vision :

1. Réglages tvOS : Vidéo et audio, Format SDR 4K, Adapter le contenu à la plage dynamique **et** à la fréquence d'images activés.
2. Lancer le spike (copie dans les notes) ou l'étape 1, avec `playerVC.appliesPreferredDisplayCriteriaAutomatically = false`. Le moteur reste seul à écrire les critères d'affichage, comme le recommande le README AetherEngine (« Host setup on tvOS »). Passer `matchContentEnabled: AVDisplayManager.isDisplayCriteriaMatchingEnabled`.
3. Lire, dans cet ordre, un remux HDR10 (HEVC Main10, PQ), un Dolby Vision profil 8.1 et un Dolby Vision profil 5.
4. Pour chacun :
   - le téléviseur bascule (bandeau HDR10 ou Dolby Vision) ;
   - le journal moteur affiche `DisplayCriteria … apply` sans `-11868` ni `-15628` ;
   - `window.avDisplayManager.preferredDisplayCriteria` n'est pas `nil` ;
   - `engine.videoRoute == .loopback` ;
   - un appui sur Menu rend le mode SDR (avec `stop()` simple) ;
   - le passage à l'épisode suivant (`stop(resetDisplayCriteria: false)` puis `load`) ne repasse pas par le SDR.
5. Recommencer avec Match Content désactivé : l'image doit être convertie en SDR sans écran noir.

### Q5. Les sous-titres WebVTT du serveur apparaissent-ils dans le menu natif ?

**Oui, à condition de les déclarer au `load`. Non avec le code actuel du plugin** (banc macOS) :

| Mode | Groupe `legible` de l'item |
|---|---|
| `addExternalSubtitleTrack` après `load` (ce que fait `AetherPlayer.setExternalSubtitle`) | `aucun groupe` |
| `LoadOptions.externalSubtitles` + `prepareNativeSubtitles = true` | `["French/fr"] sélection=aucune` |

Le texte arrive bien à AVPlayer quand l'hôte reprend la main : `selectSubtitleTrack(index: 100000)`, puis `setNativeSubtitleRendering(true)`. Le journal montre `native subtitle select done: selected=French`, puis `legible reçu: ["@1.0s SPIKE SOUS-TITRE WEBVTT ligne 1"]`.

**Piège :** si c'est AVKit (ou les sous-titres automatiques du système) qui choisit la piste, le moteur la désélectionne aussitôt. Il le journalise (`Sodalite#65: legible option "French" was selected from outside the engine … deselected again, publishing the request`) et publie `engine.systemCaptionRequest`. Pour que le choix fait dans le menu natif tienne, l'hôte doit écouter `systemCaptionRequest`, puis appeler `selectSubtitleTrack` et `setNativeSubtitleRendering(true)`. Sinon, ajouter un menu Sous-titres dans `transportBarCustomMenuItems`. Le simulateur n'a pas permis de voir le menu AVKit lui-même, faute de route native.

## APIs tvOS du plan

Toutes compilent avec le SDK tvOS 27, via `flutter-tvos build tvos --debug --simulator` (code exit 0) :

| API | Statut |
|---|---|
| `AVPlayerItem.externalMetadata` | Confirmée. Passer par `engine.setExternalMetadata(_:)`, rejoué sur chaque item : le moteur remplace l'item à chaque rechargement (Q2). |
| `AVPlayerViewController.transportBarCustomMenuItems` (`[UIMenuElement]`, `UIMenu` et `UIAction`) | Confirmée. |
| `AVPlayerViewController.contextualActions` (`[UIAction]`) | Confirmée. |
| `AVPlayerViewController.customInfoViewControllers` (`[UIViewController]`, avec `title`) | Confirmée. `infoViewActions` aussi. |
| `AVPlayerViewControllerDelegate` : `playerViewControllerShouldDismiss`, `…WillBeginDismissalTransition`, `…DidEndDismissalTransition` | Confirmé, et les trois sont appelés à l'exécution sur Menu (Q3). |
| `appliesPreferredDisplayCriteriaAutomatically` | Confirmée. À mettre à `false` (le moteur écrit les critères). |

Correction au plan : il faut ajouter `engine.$videoRoute` (bascule vers Flutter sur `.software`), `engine.$currentAVPlayerItem`, `engine.systemCaptionRequest` et `setNativeSubtitleRendering(_:)` à la liste des points de contact avec le moteur.

## Autres constats

- **Sources de la route logicielle sur un vrai appareil.** Tout codec que VideoToolbox ne décode pas en matériel : VC-1, MPEG-2, MPEG-4 Part 2, H.264 10 bits, AV1 sur les puces sans AV1 matériel, et les sources lisibles seulement d'un bout à l'autre. Pour ces films, l'étape 1 doit garder l'interface Flutter.
- **Plantage au lancement dans le simulateur tvOS 27.** Lancée par `simctl launch --console-pty`, l'app a planté une fois dans `UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption` (`EXC_BREAKPOINT`, rapport `Runner-2026-11-04-143119.ips`). tvOS 27 signale l'absence de cycle de vie UIScene. Lancée normalement, elle démarre. Quelqu'un a commencé l'adoption d'UIScene dans `app/tvos/Runner` pendant le spike (`AppDelegate.swift`, `Info.plist` et `Main.storyboard` modifiés à 14:32-14:34) ; cela ne vient pas de ce spike.
- **Effets de bord de `flutter-tvos build`** dans le dépôt :
  - `pod install` a réécrit `app/tvos/Runner.xcodeproj/project.pbxproj` (intégration CocoaPods) et `app/tvos/Runner.xcworkspace/contents.xcworkspacedata`, et a créé `app/tvos/Podfile.lock`, `app/tvos/Pods/`, `app/tvos/Flutter/` et `app/tvos/Runner.xcworkspace/xcshareddata/swiftpm/`. Pour ne pas écraser les modifications faites en parallèle dans `app/tvos/`, rien n'a été restauré. Les versions produites par le build sont copiées dans le scratchpad de la session.
  - Son `pub get` a rétrogradé cinq paquets dans `app/pubspec.lock` (Flutter 3.44 de flutter-tvos). Le fichier a été restauré à l'identique.
