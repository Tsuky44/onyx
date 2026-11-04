# ADR-0105 — Un `AVPlayerViewController` natif pour le lecteur de l'Apple TV

- **Statut :** accepté, réalisé — compilé et testé en Dart ; jamais essayé sur une vraie Apple TV (le
  simulateur prend toujours la route logicielle d'AetherEngine). Le réglage vaut « Onyx » par défaut
  jusqu'à la recette décrite dans `docs/agents/native-tv-player-manual-tests.md`.
- **Date :** 2026-11-04
- **Portée :** `packages/onyx_player_apple/` (`pigeons/messages.dart`, `NativePlayerPresenter.swift`,
  `PlayerHost.swift`), `app/lib/screens/player/playback/native_tv_*.dart`,
  `app/lib/screens/player/player_screen_native_tv.dart`, le réglage Lecteur Apple TV.
- **Complète :** ADR-0038 (AetherEngine sur les appareils Apple). Étude préalable :
  `docs/agents/spike-native-tv-player.md`.

## Contexte

Sur Apple TV, le lecteur est une interface Flutter dessinée au-dessus de la vue d'AetherEngine. Elle
ne ressemble pas au lecteur du système : pas de barre de transport tvOS, pas de panneau d'infos, pas
de geste de balayage natif. AetherEngine publie pourtant un `AVPlayer` (`engine.currentAVPlayer`) que
`AVPlayerViewController` sait présenter tel quel.

## Décision

1. **`AVPlayerViewController` par-dessus Flutter, `PlayerScreen` reste le cerveau.** Progression,
   segments, épisode suivant, mémoire des pistes, qualité et séance partagée tournent sur la même
   session ; Swift n'applique que la dernière spec reçue. `NativeTvPresenter` (Dart) décide
   quand présenter, `NativePlayerPresenter.swift` fait la présentation.
2. **Pigeon comme pont.** `presentNative`, `updateNative` et `dismissNative` descendent une
   `OnyxAppleNativeSpec` (titre, affiche, menus cochés, actions contextuelles, tout traduit côté
   Dart) ; `nativeEvents` remonte `action`, `menuSelected`, `subtitleSelected`, `dismissed` et
   `unavailable`. `updateNative` n'est envoyé que si la spec a changé.
3. **Les corrections du spike.**
   - *Route logicielle = pas de lecteur natif.* Sur cette route `currentAVPlayer` vaut `nil` : AVKit
     affiche une roue sur un plan vide, son joué. Le choix se fait sur `engine.videoRoute`, pas sur le
     codec ; le natif répond `unavailable/softwareRoute` et rend la main à Flutter.
   - *L'audio passe par un menu personnalisé.* Le moteur ne sert qu'une rendition audio, AVKit ne
     voit que la piste active : le menu Audio est un `transportBarCustomMenuItems`, dont le choix
     remonte en `menuSelected`.
   - *Les sous-titres sont déclarés au `load`* (`LoadOptions.prepareNativeSubtitles`, via
     `setLoadSubtitles`), sinon ils n'arrivent pas dans le menu AVKit. Le choix fait dans ce menu est
     relayé par `systemCaptionRequest` (aucune piste active) et par l'observation de la sélection
     média de l'item (une piste déjà active), puis Dart rappelle `selectSubtitleTrack`.
4. **Règle de repli** (`nativeTvFallbackFor`), relue à chaque construction de l'écran, sans couper la
   lecture. Par ordre de priorité :
   1. refus du natif (`presentationFailed`, `unsupported`) ;
   2. route logicielle ;
   3. piste image (PGS, VobSub) en Direct Play ;
   4. piste texte en HLS : le serveur la sert à part et Flutter la peint (ADR-0031), AVKit ne la voit
      pas.

   Après un refus ou un Menu de l'utilisateur, l'écran natif n'est plus jamais représenté pour ce
   lecteur. L'épisode suivant ferme l'ancien (`dismissNative`) avant d'ouvrir le nouveau, qui a son
   propre `AVPlayer`.
5. **Un réglage, Onyx par défaut.** « Lecteur Apple TV » (Natif ou Onyx), visible sur tvOS seulement.
   `isNativeTvPlayerEligible()` vaut `AppPlatform.isTvOS` et le réglage Natif. Le défaut passera à
   Natif quand la recette sur appareil sera passée.

## Conséquences

- **Fonctions Onyx perdues en mode natif :** zoom et recadrage libre (seul le format d'image du
  menu reste, répercuté sur `videoGravity`), statistiques de lecture, toast et pastilles de « Regarder
  ensemble » (la séance tourne, mais rien ne s'affiche), cartes et pastilles de l'interface Flutter —
  pour le générique, la carte de fin ou « Toujours là ? », le natif rend la main à Flutter le temps
  qu'il faut.
- **Des overlays natifs sont possibles plus tard** (`contentOverlayView`, `customInfoViewControllers`)
  pour rendre Regarder ensemble ou les stats ; rien n'est fait.
- **Sous-titres image et route logicielle restent sur l'interface Flutter** : une partie des films
  (VC-1, MPEG-2, H.264 10 bits, AV1 sans décodeur matériel) ne verra jamais le lecteur natif.
- **Deux points à confirmer sur appareil :** le focus UIKit reste vide une à trois secondes après
  Menu, et le HDR / Dolby Vision (Match Content) n'a pas pu être vérifié au simulateur.
- La copie tvOS des sources Swift (`tvos/`) est vérifiée par `onyx_player_apple_sources_test.dart`.
