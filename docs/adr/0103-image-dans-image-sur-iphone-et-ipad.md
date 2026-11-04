# ADR-0103 — L'image dans l'image arrive sur iPhone et iPad

- **Statut :** accepté, réalisé — le Swift n'a pas été essayé sur un iPhone, seulement compilé
- **Date :** 2026-11-03
- **Portée :** `packages/onyx_player_apple` (`PictureInPictureBridge.swift`, le contrat Pigeon),
  `app/lib/services/picture_in_picture.dart`, `AetherPlaybackSession`. iPhone et iPad seulement.
  Prolonge l'[ADR-0012](0012-image-dans-image.md).

## Contexte

L'ADR-0012 donnait l'image dans l'image à Android et la refusait à iOS, pour une raison précise :
`AVPictureInPictureController` met à l'écran une couche AVFoundation, et le lecteur d'alors rendait
par mpv dans une texture Flutter, qui n'en est pas une. Y arriver demandait un second chemin de
rendu.

Cette raison n'existe plus. Depuis l'[ADR-0038](0038-aetherengine-sur-les-appareils-apple.md),
l'image d'un iPhone passe par une vraie vue native qui héberge la couche d'AetherEngine : une
`AVPlayerLayer` quand AVPlayer lit, une `AVSampleBufferDisplayLayer` quand FFmpeg décode. Ce sont
exactement les deux couches que le contrôleur d'iOS sait prendre. Le moteur publie l'une et l'autre
(`nativePlayerLayer`, `softwarePiPSource`) et attend de l'hôte qu'il bâtisse le contrôleur.

## Décision

**Contredit l'ADR-0012, §3 : iOS a désormais la petite fenêtre**, avec le même contrat qu'Android.

- **La fenêtre est armée, pas ouverte.** iOS ne laisse pas l'app la demander après coup. Le lecteur
  arme la fenêtre (`setPictureInPictureArmed`), et le système l'ouvre au geste d'accueil
  (`canStartPictureInPictureAutomaticallyFromInline`). Le service Dart `PictureInPicture` reste la
  seule porte de l'écran du lecteur : il parle à `MainActivity` sur Android et au plugin sur iOS, et
  l'écran ne sait pas lequel.
- **Un contrôleur par couche.** Le plugin bâtit l'`AVPictureInPictureController` autour de la couche
  native quand elle existe, sinon autour de celle du décodage logiciel (le transport — pause,
  saut de 10 s — passe alors par `SoftwarePiPSource`). Les deux changent à chaque ouverture : le
  contrôleur est reconstruit quand la couche change, jamais pendant que la fenêtre est ouverte, où
  le moteur prolonge lui-même la lecture sur l'épisode suivant.
- **Le moteur est prévenu.** `pictureInPictureActive` passe à vrai dès `willStart`, avant que l'app
  ne parte en arrière-plan : c'est lui qui retient le moteur de couper l'image et l'audio.
- **Fermer met en pause, restaurer non**, comme sur Android. Le système ne distingue pas les deux
  dans `didStop` ; le plugin note le passage par `restoreUserInterface…` et en déduit la fermeture.
  Le natif met en pause lui-même, parce que Dart peut dormir quand l'app est en arrière-plan.
- **Ni Mac, ni Apple TV.** Un ordinateur a déjà ses fenêtres, et le lecteur de la télévision n'a pas
  de chrome pour celle-ci (ADR-0012, §4). Le même type existe sur ces cibles, vide, pour qu'`AetherPlayer`
  n'ait pas de branche par plateforme.

## Conséquences

- Le fond audio (`UIBackgroundModes: audio`) et la session `.playback` étaient déjà en place pour
  la lecture écran verrouillé ; la fenêtre n'en demande pas d'autre.
- **Pas encore vu sur un appareil.** La compilation est vérifiée, pas le comportement : l'entrée au
  geste d'accueil, la fermeture contre la restauration, la reprise sur l'épisode suivant et le
  chemin logiciel (VP9, AV1 sans décodeur matériel) demandent un iPhone, et l'ADR-0038 attend
  déjà sa phase 3 pour cela.
- Les sous-titres du fichier ne se voient dans la fenêtre que par ce que le moteur y compose (chemin
  logiciel) ou par ses renditions WebVTT natives ; ceux que Flutter peint par-dessus n'y sont pas.
  Les activer pour la fenêtre (`prepareNativeSubtitles`) est un chantier à part.
