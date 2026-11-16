# ADR-0106 — Sources sans décodeur matériel sur l'écran natif d'Apple TV : HLS transcodé

- **Statut :** remplacée par l'[ADR-0133](0133-pas-de-lecteur-natif-sur-l-apple-tv.md) (lecteur natif retiré le 2026-11-14). Avant : accepté, réalisé — testé en Go et en Dart, chaîne FFmpeg exécutée sur des sources
  de test (AV1 HDR10, MPEG-2 4:2:2 entrelacé). **Jamais vu sur une vraie Apple TV** : le simulateur
  n'a aucun décodeur matériel.
- **Date :** 2026-11-05
- **Portée :** `app/lib/screens/player/playback/native_tv_decoding.dart`,
  `app/lib/screens/player/playback/native_tv_source.dart`,
  `app/lib/screens/player/hooks/player_controller_native_tv.dart`,
  `app/lib/services/playback_capabilities.dart` (`aetherNativeTv`),
  `app/lib/models/media_tracks.dart`, `server/streaming/capabilities.go`, `plan.go`, `probe.go`,
  `ffmpeg.go`, `encoder_hevc.go`.
- **Complète** [ADR-0105](0105-lecteur-natif-sur-apple-tv.md), dont une conséquence était qu'une
  partie des films (VC-1, MPEG-2, H.264 10 bits, AV1) ne verrait jamais le lecteur natif, et
  [ADR-0014](0014-capacites-de-lecture-declarees-par-le-client.md) (capacités déclarées).

## Contexte

L'écran natif d'Apple TV présente l'`AVPlayer` d'AetherEngine. Le moteur n'en a un que sur sa route
native : quand la puce ne décode pas l'image, il décode lui-même (route logicielle), sans
`AVPlayer`, et l'écran natif rend la main à Flutter. Sont concernés le VC-1 et le WMV3, le MPEG-2 et
le MPEG-1, le MPEG-4 Part 2, l'AV1 (pas de décodeur sur l'Apple TV 4K actuelle), le VP9, le H.264
au-delà de 8 bits, la chrominance 4:2:2 ou 4:4:4 et l'entrelacé.

AetherEngine prend une URL HLS distante et la confie telle quelle à `AVPlayer` (route
`remoteBypass`, AE#154) : c'est déjà ce que fait le menu Qualité sur Apple. Il suffit donc que le
serveur produise un flux qu'AVPlayer décode en matériel.

## Décision

1. **Décider avant d'ouvrir.** `avKitDecodeObstacle` (Dart, pure) dit, depuis la liste des pistes,
   si AVKit décode en matériel : H.264 8 bits, HEVC 8 et 10 bits, 4:2:0, progressif ; Dolby
   Vision 5, 8.1 et 8.4 ; le profil 7 sur sa couche de base (le jour où l'app réglera la double
   couche, `dualLayerDolbyVision` le fait transcoder). Un champ que le serveur ne dit pas laisse
   passer. Sur Apple TV avec le réglage Natif, la liste part avec le ticket et l'ouverture l'attend
   au plus 1,5 s (`NativeTvSource`). Ouvrir le fichier d'abord aurait présenté l'écran natif sur la
   route logicielle, qui le refuse pour toute la vie du lecteur, et payé un démarrage pour rien.
2. **Une session HLS au lieu du fichier**, ouverte comme celle du web : au barreau de la source,
   au plus 1080p (le plafond de l'ADR-0060 : l'image est réencodée de toute façon), reprise
   comprise, l'Auto plafonné là et sans retour au Direct Play. Les capacités déclarées sont
   `PlaybackCapabilities.aetherNativeTv` : celles d'AVPlayer en matériel, avec trois paramètres
   nouveaux, absents de toutes les autres requêtes :
   - `encode=hevc` : le client accepte un réencodage HEVC Main 10 ;
   - `progressive=1` : une source entrelacée n'est pas recopiée ;
   - `h264bitdepth=8` : le H.264 10 bits n'est pas recopié, le HEVC Main 10 si.
3. **Le serveur garde le HDR en HEVC, et seulement le HDR.** Une source HDR réencodée pour un client
   qui a dit `encode=hevc`, `hdr=1` et 10 bits part en HEVC Main 10 (`hvc1`), ses étiquettes de
   couleur posées sur chaque image (`setparams`, PQ ou HLG, BT.2020), sans tone mapping. Le reste
   reste en H.264 : mesuré sur 10 s de 1080p bruité (8 cœurs Apple), libx264 veryfast prend 6,5 s,
   libx265 ultrafast 13,7 s et superfast 19,9 s. Le HEVC n'apporterait rien à une source SDR
   qu'AVPlayer lit très bien en H.264, et coûterait deux à trois fois plus de calcul. Le profil 5
   reste sur libplacebo et le H.264 (ADR-0060).
4. **L'encodeur HEVC suit celui de l'opérateur** : libx265 (ultrafast, `-forced-idr`) derrière
   libx264, le HEVC du même circuit derrière un encodeur matériel (VideoToolbox, NVENC, Quick Sync,
   VAAPI en `p010`). Il est essayé une fois, en 10 bits. Un circuit sans HEVC Main 10 ne renvoie pas
   vers libx265 : l'opérateur a pris le matériel parce que le processeur est rare. Sans encodeur
   HEVC, le serveur retombe sur le H.264 tone-mappé, comme avant.
5. **Tout réencodage d'une source entrelacée la désentrelace** (`bwdif`, une image par image
   source), avant la mise à l'échelle et avant un sous-titre incrusté, pour tous les clients : sans
   lui, l'image sortait peignée. La sonde lit `field_order` ; sa version passe à 3, donc chaque média
   est resondé à sa prochaine lecture.
6. **Repli.** Une session qui ne s'ouvre pas (serveur trop ancien, refus, échec) ouvre le fichier
   tel quel : route logicielle et interface Onyx, comme avant. Avec le réglage Onyx, ou pour un
   fichier téléchargé, rien ne change.
7. **L'audio d'une session HLS sur Apple rouvre la session.** Sur la route `remoteBypass`, AVPlayer
   garde le choix de la rendition et le moteur ignore `selectAudioTrack`. Un changement de langue
   y rouvre la session avec `?audio=N` (`engineSwitchesHlsAudio`), sur iPhone, Mac et Apple TV.

## Conséquences

- **Ces films passent par l'écran natif**, au prix d'un transcodage serveur et d'une image au plus
  en 1080p (le menu Qualité permet d'en demander plus, ou l'original, qui revient à Onyx).
- **Un sous-titre texte garde l'interface Onyx sur ce flux**, comme pour tout HLS (règle de repli
  de l'ADR-0105, cas 4) : la session écrit ses WebVTT à part et Flutter les peint. AetherEngine sait
  injecter des sous-titres déclarés au chargement dans le master qu'il passe à AVPlayer (#316) ;
  ce serait la voie pour les montrer dans AVKit. Un sous-titre image, lui, est incrusté et le natif
  tient.
- **Coût serveur** : un AV1 4K HDR devient un 1080p HEVC Main 10 en libx265 ultrafast, à peu près le
  coût du tone mapping qu'il remplace. Un hôte trop lent fait descendre l'Auto.
- **À vérifier sur une Apple TV 4K** : la route `remoteBypass` et l'écran natif sur un VC-1, un
  MPEG-2 entrelacé, un H.264 10 bits et un AV1 HDR10 ; la bascule du téléviseur en HDR10 ou HLG
  (critères d'affichage posés par le moteur depuis l'item, `applyRemoteHLSDisplayCriteria`) ; le
  changement de langue audio, qu'AVPlayer peut choisir d'après les langues du système plutôt que
  d'après `DEFAULT=YES` ; la reprise et le menu Qualité.
