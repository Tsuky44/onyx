# onyx_player_apple

Le lecteur d'Onyx sur iPhone, Mac et Apple TV : [AetherEngine](https://github.com/superuser404notfound/AetherEngine)
dans une vue native, derrière un contrat Pigeon. Voir l'[ADR-0038](../../docs/adr/0038-aetherengine-sur-les-appareils-apple.md).

## Organisation

| Chemin | Rôle |
|---|---|
| `pigeons/messages.dart` | Le contrat Dart↔Swift, seule source de vérité. |
| `lib/` | `OnyxApplePlayer` (commandes, flux d'état, de sous-titres et de journal) et `OnyxApplePlayerView` (la vue native). |
| `darwin/onyx_player_apple/` | Le paquet Swift d'iPhone et Mac, et **les seules sources Swift à modifier**. |
| `tvos/` | Le paquet Swift de l'Apple TV. Ses sources sont une copie de `darwin/`. |
| `tool/sync_tvos.dart` | Recopie les sources vers `tvos/` et corrige la garde d'import de Pigeon. |

## Après une modification

```
dart run pigeon --input pigeons/messages.dart   # si le contrat a changé
dart run tool/sync_tvos.dart                    # toujours
```

`app/test/onyx_player_apple_sources_test.dart` échoue tant que la copie tvOS n'est pas à jour.

## Contraintes

- SwiftPM uniquement : AetherEngine n'existe pas en CocoaPods.
- iOS 18, tvOS 18 et macOS 15 au minimum, les planchers d'AetherEngine.
- AetherEngine est sous LGPL-3.0 avec une exception pour les magasins d'applications : une
  modification du moteur lui-même doit être publiée, pas le code de l'app.

## Lecteur natif tvOS

Sur Apple TV, `OnyxApplePlayer` peut présenter un `AVPlayerViewController` par-dessus Flutter
(`NativePlayerPresenter.swift`, tvOS seulement). `PlayerScreen` reste le cerveau : le natif affiche
la dernière spec reçue. Décision : [ADR-0105](../../docs/adr/0105-lecteur-natif-sur-apple-tv.md).

| API | Rôle |
|---|---|
| `presentNative(spec)` | Présente le contrôleur (un second appel vaut `updateNative`). Peut se faire pendant le `load`. |
| `updateNative(spec)` | Applique la spec par morceaux : seul ce qui a changé est réaffecté, pour qu'un menu ouvert ou le focus d'un onglet tienne. |
| `dismissNative()` | Ferme ; émet `dismissed/requested`. Sans effet si rien n'est présenté. |
| `setLoadSubtitles(…)` | Déclare les sous-titres au `load` (requis pour le menu AVKit). |
| `nativeEvents` | Les gestes de l'utilisateur, voir ci-dessous. |

Ce que porte la spec (`OnyxAppleNativeSpec`), tous les textes traduits par Dart :

| Champ | Côté AVKit |
|---|---|
| `title`, `subtitle`, `overview`, `posterUrl` | `externalMetadata`, rejouée par le moteur sur chaque item. |
| `menus` (options avec `detail`) | `transportBarCustomMenuItems`, seconde ligne en `UIMenuElement.subtitle`. |
| `actions` | `contextualActions` (« Passer l'intro », « Épisode suivant »). |
| `infoActions` | `infoViewActions`, deux au plus ; vide retire « Lire depuis le début ». |
| `chapters` | `navigationMarkerGroups`, reposés sur chaque item ; vide laisse ceux du fichier. |
| `nextUp` | `AVContentProposal` présentée par `NativeNextUpProposalController`, jamais acceptée d'elle-même. |
| `prompt` | `UIAlertController` ; reposé seulement quand son `id` change. |
| `panels` | `customInfoViewControllers` (`NativeInfoPanelController`) ; le panneau `stats` lit le moteur chaque seconde. |
| `toast` | `NativeOverlayView` dans le `contentOverlayView`, au-dessus des sous-titres image. |
| `interceptSeeks` | Les navigations de l'utilisateur ne sont pas appliquées : `seekRequested`, et Dart cherche. |

Événements : `action` (bouton, réponse à une question, « Lire » / « Plus tard » de la proposition),
`menuSelected`, `subtitleSelected` (Dart rappelle `selectSubtitleTrack`), `dismissed` (Menu donne
`userDismissed`, sans pause ni arrêt de la lecture), `unavailable` (`softwareRoute`,
`bitmapSubtitles`, `presentationFailed`, `unsupported`), `transport` (lecture ou pause décidée dans
AVKit, jamais pour une commande de Dart), `userSeeked`, `seekRequested`, `panelRowSelected`,
`panelTabSelected` et `userActivity` (cinq secondes au moins entre deux). Les positions sont en temps
de l'item, en millisecondes.

Le natif coupe le menu Vitesse d'AVKit (`speeds = []`) et l'image dans l'image, et peint lui-même les
sous-titres image (`NativeBitmapSubtitles.swift`, ADR-0107).

Limites : iOS et macOS répondent `unavailable/unsupported` ; une piste texte en HLS et une session
HLS qui ne part pas du début restent sur l'interface Flutter, comme la route logicielle quand le
transcodage échoue (ADR-0106) ; non vérifié sur appareil (recette :
`docs/agents/native-tv-player-manual-tests.md`).
