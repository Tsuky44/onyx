# ADR-0133 — Pas de lecteur natif sur l'Apple TV : l'interface Onyx seulement

- **Statut** : acceptée
- **Date** : 2026-11-14
- **Portée** : `packages/onyx_player_apple/` (`pigeons/messages.dart`, `PlayerHost.swift`, `AetherPlayer.swift`, `EventStreams.swift`), `app/lib/screens/player/` (écran, contrôleur, sessions de lecture), `app/lib/screens/settings/pages/playback_page.dart`, `app/lib/services/playback_capabilities.dart`
- **Remplace** : ADR-0105, ADR-0106, ADR-0107, ADR-0119 et ADR-0120

## Contexte

L'ADR-0105 avait ajouté un `AVPlayerViewController` par-dessus Flutter sur l'Apple TV, derrière
le réglage « Lecteur Apple TV » (Natif ou Onyx, Onyx par défaut). Les ADR-0106, 0107, 0119 et 0120
l'avaient complété : HLS transcodé pour les sources sans décodeur matériel, couche de sous-titres
image côté plugin, ouverture sans plan noir, parité des gestes avec l'interface Onyx.

Le réglage est resté sur « Onyx », sa valeur par défaut, et ne servira pas : le lecteur de l'Apple TV reste
l'interface Onyx, la même que sur les autres téléviseurs (ADR-0124). Garder l'écran natif, c'était
entretenir une seconde interface de lecteur (spec Pigeon, cinq contrôleurs Swift, parité de chaque
menu) que personne n'utilisait.

## Décision

1. **Le réglage disparaît**, avec tout ce qu'il ouvrait : `NativeTvPresenter` et ses fichiers
   `native_tv_*`, `NativePlayerPresenter.swift` et ses contrôleurs, `presentNative`,
   `updateNative`, `dismissNative`, `nativeEvents` et `setLoadSubtitles` du contrat Pigeon.
2. **Plus de source choisie pour AVKit.** Une source que la puce ne décode pas repart sur la route
   logicielle d'AetherEngine, comme avant l'ADR-0106 : l'app ne déclare plus les capacités
   `aetherNativeTv`, ni les champs `encode`, `progressive` et `h264bitdepth` qui n'existaient que
   pour elles.
3. **Le serveur ne change pas.** Il sait toujours lire `encode=hevc`, `progressive=1` et
   `h264bitdepth` : ce sont des capacités génériques, aucun client ne les envoie aujourd'hui.

## Conséquences

- Une ancienne valeur « Natif » enregistrée sur une Apple TV n'est plus lue : la lecture passe par
  l'interface Onyx.
- Revenir à un lecteur natif voudrait dire repartir de l'historique git de ces ADR, pas d'un
  interrupteur.
