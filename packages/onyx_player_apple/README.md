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
| `updateNative(spec)` | Applique titre, affiche, menus cochés (Vitesse, Format, Qualité, Audio) et actions contextuelles. |
| `dismissNative()` | Ferme ; émet `dismissed/requested`. Sans effet si rien n'est présenté. |
| `setLoadSubtitles(…)` | Déclare les sous-titres au `load` (requis pour le menu AVKit). |
| `nativeEvents` | `action`, `menuSelected`, `subtitleSelected`, `dismissed`, `unavailable`. |

Événements notables : Menu sur la télécommande donne `dismissed/userDismissed` (sans pause ni arrêt
de la lecture : c'est à Dart) ; la route logicielle donne `unavailable/softwareRoute` puis la
fermeture, sans `dismissed` ; `subtitleSelected` demande à Dart de rappeler `selectSubtitleTrack`.

Limites : iOS et macOS répondent `unavailable/unsupported` ; la route logicielle, les sous-titres
image et le HLS avec sous-titre texte restent sur l'interface Flutter ; ni zoom, ni statistiques, ni
toast « Regarder ensemble » ; non vérifié sur appareil (recette :
`docs/agents/native-tv-player-manual-tests.md`).
