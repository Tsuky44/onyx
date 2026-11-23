# ADR : Le lecteur de l'Apple TV démarre sans attente évitable, et une Apple TV HD ne décode plus en logiciel

- **Statut :** accepté. Écrit sous Linux : le Dart est analysé et testé, **le Swift n'a été compilé
  sur aucun Mac et rien n'a été mesuré sur un appareil**. La CI de l'Apple TV dira si le Swift
  compile ; les gains restent à lire sur la ligne `PLAYER STARTUP` d'une vraie Apple TV.
- **Date :** 2026-11-23
- **Portée :** `packages/onyx_player_apple/` (`pigeons/messages.dart`, `AetherPlayer.swift`,
  `FastStart.swift`, `PlayerHost.swift`, `lib/src/onyx_apple_player.dart`),
  `app/lib/services/playback_capabilities.dart`, `app/lib/screens/player/playback/`
  (`playback_session.dart`, `aether_playback_session.dart`, `direct_play_video_gate.dart`,
  `resume_settle.dart`, `startup_timeline.dart`), `app/lib/screens/player/hooks/`
  (`player_controller_startup.dart`, `player_controller_direct_play_gate.dart`,
  `player_controller_tracks.dart`, `use_player_controller.dart`),
  `app/lib/screens/player/player_screen_startup.dart`, `app/lib/screens/player/player_engine.dart`.
- **Prolonge** l'[ADR-0038](0038-aetherengine-sur-les-appareils-apple.md) et
  l'[ADR-0093](0093-changement-de-piste-audio-et-premier-segment-sur-apple.md).
  **Contredit l'ADR-0038** sur un point : « AetherEngine lit tout, en Direct Play » ne vaut plus
  pour une puce sans décodeur HEVC matériel, parce que « lire » y voulait dire décoder en logiciel.

## Contexte

Demande : que films et séries se lancent tout de suite sur l'Apple TV, y compris sur une Apple TV
HD, où la lecture « bug énormément ».

Un démarrage en une milliseconde n'existe pas : il faut un ticket, une connexion, la sonde du
conteneur et une première image décodée. Ce qui se retire, ce sont les attentes qui ne servent à
rien. La lecture du code en a trouvé six.

1. **Une Apple TV HD décode le HEVC en logiciel.** Sa puce A8 n'a pas de décodeur HEVC.
   AetherEngine le constate (`VTCapabilityProbe`) et passe sur sa route logicielle (libavcodec) :
   deux cœurs de 2014 ne tiennent pas un 1080p HEVC, et pas du tout un 4K. L'app déclarait pourtant
   les mêmes capacités que pour une Apple TV 4K et ouvrait tout en Direct Play.
2. **Chaque session HLS du serveur était sondée deux fois avant d'être lue.** Le plugin ouvrait une
   playlist comme un fichier : le moteur tentait de la démultiplexer avec FFmpeg, échouait, la
   relisait, téléchargeait la tête du premier segment pour vérifier qu'il n'était pas du HEVC en
   MPEG-TS, puis la confiait à AVPlayer, qui redemandait le tout. Payé à chaque changement de
   qualité et à chaque repli en transcodage, plus l'attente d'un segment que le serveur n'a pas
   encore écrit.
3. **Le cache du lecteur se levait sur l'horloge, pas sur l'image.** Le contrôleur attendait que la
   position avance, relevée quatre fois par seconde, alors que la couche vidéo tenait déjà une
   image, souvent avant même que la réserve ne laisse partir la lecture.
4. **`play` attendait le serveur sans borne.** Le contrôleur ouvrait le flux à la seconde connue
   de l'accueil après 400 ms, mais l'écran attendait ensuite la réponse de `/progress`, aussi
   longue soit-elle (un serveur qui interroge Emby met des secondes), avant d'appeler `play`.
5. **Le raccourci de démarrage regardait la réserve toutes les 150 ms** et exigeait toujours deux
   secondes d'avance, même sur une ligne qui en livre dix par seconde.
6. **Le premier lecteur du processus payait le chargement de FFmpeg** et du pont de journal
   d'AetherEngine devant l'utilisateur.

## Décision

1. **L'appareil dit ce que sa puce décode** (`OnyxApplePlayerApi.deviceCapabilities`,
   `VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)`), une fois au lancement. Sans décodeur
   HEVC, l'app prend `PlaybackCapabilities.aetherWithoutHevc` : Direct Play pour le seul H.264
   8 bits jusqu'en 1080p (`DirectPlayVideoLimits`), et le reste demandé au serveur en H.264 SDR,
   qu'AVPlayer décode alors en matériel. Jamais au-dessus de 1080p.
2. **Cette décision se prend avant d'ouvrir le fichier.** La liste des pistes part avec le ticket ;
   sur un appareil limité, le contrôleur l'attend (1,5 s au plus) et saute l'ouverture du fichier
   quand `serverQualityForUndecodableVideo` rend un barreau : la session du serveur est la première
   chose que le moteur ouvre, au point de reprise. Sur un appareil qui lit tout, aucune attente
   n'est ajoutée. Si le serveur refuse la session, le fichier s'ouvre quand même.
3. **Une playlist va droit à AVPlayer** (`LoadOptions.nativeRemoteHLS` pour toute URL `.m3u8`).
4. **Le moteur annonce sa première image** (`hasFirstFrameReadyForDisplay`, dans l'instantané
   d'état) et `PlaybackSession.firstFrames` la porte au contrôleur, qui lève son cache à l'image
   même. Les autres moteurs se taisent sur ce flux et gardent la déduction par l'horloge.
5. **`play` n'attend plus `/progress`** quand le flux est déjà ouvert à un point connu
   (`settledResumePoint`). La réponse tardive déplace encore la lecture si elle contredit ce point
   de plus de cinq secondes et que la lecture n'a pas quitté ses trente premières secondes
   (`resumeNeedsLateCorrection`).
6. **Le raccourci de démarrage relève la réserve toutes les 50 ms** et part à une seconde d'avance
   quand elle se remplit au moins deux fois plus vite qu'elle ne se lit ; deux secondes sinon.
7. **AetherEngine est amorcé sur l'Apple TV** trois secondes après la première image de l'app
   (`PlayerEnginePool.prewarm`) : un lecteur créé puis détruit sans rien ouvrir.

### Écarté

- **Réduire la sonde FFmpeg** (8 Mo, 5 s) : c'est elle qui trouve les pistes, et une sonde trop
  courte les perd sans erreur. Sans appareil pour mesurer, on n'y touche pas.
- **Demander le ticket avant l'appui sur Lecture** (à la mise au point du bouton) : le serveur
  ouvrirait des droits de lecture pour des films qu'on ne lance pas.
- **Garder le décodage logiciel sur l'Apple TV HD pour le HEVC 720p** : aucune mesure ne dit où est
  le seuil, et un seuil faux se paie en image qui saccade.
- **Forcer la route logicielle ou matérielle du moteur** (`preferredDecodePath`) : il n'existe pas
  de décodeur matériel à forcer, c'est la source qu'il faut changer.

## Conséquences

- Sur une Apple TV HD, un film HEVC ou 4K coûte un transcodage au serveur. Le menu Qualité garde
  la ligne du fichier d'origine pour qui veut le décodage logiciel ; l'Auto n'y remonte pas.
- Un fichier téléchargé reste lu tel quel sur l'Apple TV HD : hors ligne, pas de serveur.
- Une reprise demandée « en pause » (relais d'un autre serveur) part en lecture sur ce chemin-là :
  la session du serveur s'ouvre lecture lancée.
- L'image peut apparaître, figée, un instant avant que la lecture parte. C'est voulu : elle prouve
  que le film est là.
- La ligne `PLAYER STARTUP` gagne `picture` (première image annoncée par le moteur) et `gated`
  (ouverture du fichier sautée), et se clôt à `playing` quand l'image l'a précédée.

## À vérifier sur un appareil

1. Apple TV HD, film HEVC : le journal dit `sans décodeur matériel … HLS 1080p`, la route
   `remoteBypass`, et l'image ne saccade plus.
2. Apple TV 4K : `PlaybackCapabilities: … aetherengine`, Direct Play comme avant.
3. Changement de qualité : le journal du moteur ne contient plus `AE#154` (sonde ratée d'une
   playlist) et la bascule est plus courte.
4. La ligne `PLAYER STARTUP` avant et après, sur le même film.

Épinglé par `test/playback_capabilities_test.dart`, `test/direct_play_video_gate_test.dart`,
`test/resume_settle_test.dart`, `test/startup_timeline_test.dart` et, pour le Swift que seul Xcode
compile, `test/onyx_player_apple_sources_test.dart`.
