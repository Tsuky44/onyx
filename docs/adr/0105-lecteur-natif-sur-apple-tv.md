# ADR-0105 — Un `AVPlayerViewController` natif pour le lecteur de l'Apple TV

- **Statut :** accepté, réalisé — compilé et testé en Dart ; jamais essayé sur une vraie Apple TV (le
  simulateur prend toujours la route logicielle d'AetherEngine). Le réglage vaut « Onyx » par défaut
  jusqu'à la recette décrite dans `docs/agents/native-tv-player-manual-tests.md`.
- **Date :** 2026-11-04 ; mise à jour du 2026-11-05 (transcodage HLS, sous-titres image, parité)
- **Portée :** `packages/onyx_player_apple/` (`pigeons/messages.dart`, `NativePlayerPresenter.swift`,
  `PlayerHost.swift`, `NativeInfoPanelController.swift`, `NativeNextUpProposalController.swift`, `NativeOverlayView.swift`,
  `NativeBitmapSubtitles.swift`), `app/lib/screens/player/playback/native_tv_*.dart`,
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
   `OnyxAppleNativeSpec` (titre, affiche, menus cochés, actions contextuelles et, depuis la parité,
   chapitres, actions du panneau d'infos, épisode suivant, question, onglets, annonce et
   `interceptSeeks` ; tout traduit côté Dart) ; `nativeEvents` remonte `action`, `menuSelected`,
   `subtitleSelected`, `dismissed`, `unavailable`, puis `transport`, `userSeeked`, `seekRequested`,
   `panelRowSelected`, `panelTabSelected` et `userActivity`. `updateNative` n'est envoyé que si la
   spec a changé, et Swift ne réaffecte que les morceaux qui ont changé (un menu ouvert reste ouvert).
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
   3. piste image (PGS, VobSub) en Direct Play — levé par l'[ADR-0107](0107-sous-titres-image-sur-l-ecran-natif-apple-tv.md) :
      le natif les peint lui-même, et ne rend la main que s'il n'a pas pu poser sa couche ;
   4. piste texte en HLS : le serveur la sert à part et Flutter la peint (ADR-0031), AVKit ne la voit
      pas.

   Après un refus ou un Menu de l'utilisateur, l'écran natif n'est plus jamais représenté pour ce
   lecteur. L'épisode suivant ferme l'ancien (`dismissNative`) avant d'ouvrir le nouveau, qui a son
   propre `AVPlayer`.
5. **Un réglage, Onyx par défaut.** « Lecteur Apple TV » (Natif ou Onyx), visible sur tvOS seulement.
   `isNativeTvPlayerEligible()` vaut `AppPlatform.isTvOS` et le réglage Natif. Le défaut passera à
   Natif quand la recette sur appareil sera passée.

## Parité avec l'interface Onyx (2026-11-05)

Inventaire et contrat : `docs/agents/native-tv-parity.md`. Les gestes d'AVKit qui allaient droit à
l'`AVPlayer` remontent maintenant à Dart, qui les fait passer par les chemins de l'interface Onyx :

- **Transport.** Lecture et pause (télécommande, Centre de contrôle, app Remote) donnent `transport` ;
  les commandes de Dart sont marquées dans `PlayerHost` et ne reviennent pas. Sauts, balayage et
  chapitres donnent `userSeeked`. La séance partagée, `StillWatching` et les comptes à rebours les
  voient.
- **HLS.** `interceptSeeks` : AVKit ne cherche pas, il remonte `seekRequested` et Dart cherche
  (`seekToAbsoluteSeconds`, qui peut reconstruire la session). Une session qui ne part pas du début
  (reprise, recherche hors de ce qu'elle a encodé) replie vers Onyx (`hlsOffset`) : la timeline
  d'AVKit repartirait de zéro.
- **Menus.** Secondes lignes (`UIMenuElement.subtitle`) pour Qualité, Audio et Format d'image ;
  menu Minuterie de veille. Le menu Vitesse d'AVKit et l'image dans l'image sont coupés.
- **Épisodes.** Chapitres en `navigationMarkerGroups`, reposés sur chaque item ; épisode précédent
  et suivant en `infoViewActions` (ce qui retire « Lire depuis le début ») ; épisode suivant en
  `AVContentProposal` avec le compte à rebours de Dart, jamais accepté de lui-même (« Plus tard »
  gèle le compte à rebours et ne repropose pas pour cet épisode).
- **Questions.** « Vous regardez encore ? », langue manquante (au lancement ou au suivant), saison
  suivante, épisode à venir et lecture reprise ailleurs passent par un `UIAlertController` : seul
  le démarrage bloqué rend encore l'écran Flutter (`_needsFlutterScreen`).
- **Panneau d'infos.** Onglets Épisodes (saisons, épisodes, avancement), Regarder ensemble
  (démarrer, code, participants, quitter) et Stats (lues sur le moteur chaque seconde par Swift).
- **Annonces de la séance** dans le `contentOverlayView`, au-dessus des sous-titres image.

Le transcodage des sources sans décodeur matériel (VC-1, MPEG-2, AV1, H.264 10 bits, entrelacé) est
décidé par l'[ADR-0106](0106-sources-sans-decodeur-materiel-sur-l-ecran-natif-apple-tv.md), les
sous-titres image par l'[ADR-0107](0107-sous-titres-image-sur-l-ecran-natif-apple-tv.md).

## Conséquences

- **Ce qui reste en repli Onyx :**
  - la route logicielle quand le transcodage échoue (le fichier est alors ouvert tel quel) ;
  - une session HLS qui ne commence pas au début du film (`hlsOffset`) : toute reprise d'une source
    transcodée, et toute recherche hors de la fenêtre encodée, tant que le serveur ne sert pas une
    timeline complète ;
  - une piste texte en HLS (`overlaySubtitles`) : le serveur la sert à part et Flutter la peint ;
  - une piste image que le natif n'a pas pu peindre (`bitmapSubtitles`, sans `contentOverlayView`) ;
  - le démarrage bloqué (« Réessayer »), et tout refus de présentation.
- **Adapté :** les cartes de fin deviennent des alertes ; le compte à rebours de l'épisode suivant est
  un chiffre dans un anneau (le contrat n'a pas de libellé traduit) ; les unités des stats (`fps`,
  `Mb/s`) ne sont pas traduites ; « Copier » le code de séance n'existe pas ; la pastille qui se
  remplit du saut d'intro automatique n'existe pas (le saut se fait, sans compte à rebours visible).
- **Impossible avec AVKit :** les vignettes de la barre (AVKit ne les tire que d'une playlist I-frame),
  le logo du titre, les marqueurs de segments sur la barre (`AVInterstitialTimeRange` replierait
  l'intro en un point), le zoom et le recadrage libre (seul le format d'image du menu reste).
- **Pas encore fait :** les sous-titres image ne remontent pas avec la barre de transport ; la touche
  « avance rapide » ne passe pas à l'épisode suivant.
- **Rien n'est vérifié sur appareil :** le simulateur prend toujours la route logicielle. La recette
  (`docs/agents/native-tv-player-manual-tests.md`) couvre chaque point marqué « à confirmer à
  l'appareil » dans l'inventaire : secondes lignes, chapitres hors HLS, proposition en retard, focus
  des onglets, `transport` parasite, focus vide après Menu, HDR et Dolby Vision.
- La copie tvOS des sources Swift (`tvos/`) est vérifiée par `onyx_player_apple_sources_test.dart`.
