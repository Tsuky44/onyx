# Une image `-nvidia` pour les cartes NVIDIA, et l'image y reste sur la carte

- **Statut :** accepté, à la demande de l'utilisateur (2026-11-27 : « fais en sorte de prendre en
  compte les cartes graphiques, j'ai une P2200 dans mon serveur »). L'étape `nvidia` a été
  construite et lancée dans un conteneur **sans carte** (voir « Vérifié »). **Rien n'a encore tourné
  sur une vraie carte NVIDIA** : ni NVENC, ni la chaîne CUDA, ni le Vulkan de la carte.
- **Date :** 2026-11-27
- **Portée :** `server/Dockerfile` (étapes `ffmpeg-nvidia` et `nvidia`),
  `server/docker-entrypoint.sh` (`su-exec` ou `gosu`), `server/streaming/encoder.go` (`-forced-idr`,
  `surface: "cuda"`, `surfaceArgs`), `hardware_filters.go` (`hardwareDecodeArgs`,
  `hardwareUploadFilter`, `usesHardwareFilters`), `ffmpeg.go` (`-pix_fmt`),
  `.github/workflows/server.yml` et `release.yml` (tags `-nvidia`), `server/README.md`, `README.md`.
- **Précise** l'[ADR-0023](0023-encodeur-materiel-optionnel.md) et **prolonge**
  [la chaîne VAAPI ne ramène plus le 4K en mémoire](2026-11-25-fytroz-la-chaine-vaapi-ne-ramene-plus-le-4k-en-memoire.md),
  dont la chaîne matérielle sert maintenant aussi NVENC.

## Contexte

`h264_nvenc` et `hevc_nvenc` sont pilotés par le serveur depuis l'ADR-0023, mais l'image Docker ne
pouvait pas s'en servir, pour deux raisons indépendantes :

1. **Le FFmpeg d'Alpine n'a pas NVENC.** Son APKBUILD (3.24, FFmpeg 8.1.3) n'a ni `ffnvcodec` ni
   `--enable-nvenc` : `VIDEO_ENCODER=h264_nvenc` y répond « Unknown encoder » et retombe sur
   libx264.
2. **musl ne charge pas le pilote.** Les bibliothèques que le NVIDIA Container Toolkit injecte dans
   le conteneur (`libcuda.so.1`, `libnvidia-encode.so.1`, `libnvcuvid.so.1`) sont compilées pour la
   glibc. Recompiler FFmpeg sous Alpine ne suffirait donc pas.

Et une fois NVENC joignable, `-hwaccel auto` ramènerait chaque image décodée en mémoire avant la
mise à l'échelle logicielle : le défaut que l'ADR du 2026-11-25 a retiré à VAAPI.

## Décision

### L'image

1. **Une seconde image, pas une nouvelle base.** `docker build --target nvidia` produit une variante
   Ubuntu 24.04 ; l'image Alpine reste la dernière étape du Dockerfile, donc celle d'un `docker
   build` sans cible, et ne change pas. Les tags sont ceux de l'image Alpine suivis de `-nvidia`
   (`latest-nvidia`, `v1.4-nvidia`, `fytroz-nvidia`), publiés par les deux workflows. amd64
   seulement.
2. **Le FFmpeg 8.1 de BtbN, en `gpl-shared`.** La même branche que celui d'Alpine 3.24, avec NVENC,
   NVDEC, `scale_cuda`, libplacebo et Vulkan, lié à la seule glibc. `gpl-shared` plutôt que la
   construction statique : `ffmpeg` et `ffprobe` y partagent leurs `libav*` (205 Mo contre 350).
   L'adresse suit `latest` de la branche 8.1 : BtbN ne garde ses constructions datées que 14 jours
   (ou la dernière du mois), une adresse figée casserait le build. `FFMPEG_NVIDIA_URL` la remplace.
3. **`libva`, `libva-drm`, `libva-x11` et `libdrm` sont installées, bien qu'inutiles à NVIDIA.** Ce
   FFmpeg les ouvre à la demande par des amorces qui **arrêtent le processus** (`abort`) quand le
   fichier manque. Or `-hwaccel auto` essaie VAAPI dès que CUDA ne répond pas. Mesuré : sans ces
   bibliothèques, toute session d'un hôte où la carte n'est pas visible mourait sur
   `libva-drm.so.2: cannot open shared object file`. Avec elles, l'essai échoue proprement et le
   décodage reste logiciel.
4. **L'image règle `VIDEO_ENCODER=auto`.** L'ADR-0023 veut que le matériel soit un choix de
   l'opérateur : prendre l'image `-nvidia` est ce choix. Sans carte visible, l'essai du démarrage
   échoue et le journal dit que libx264 est pris.
5. **L'image règle `NVIDIA_VISIBLE_DEVICES=all` et
   `NVIDIA_DRIVER_CAPABILITIES=compute,video,utility,graphics`**, que le Toolkit lit : il ne reste
   à l'opérateur que `runtime: nvidia` (sur Unraid : `--runtime=nvidia` et le plugin Nvidia-Driver).
   `graphics` apporte le Vulkan de la carte : la course de `vulkan_device.go` (ADR du 2026-11-25)
   l'essaie contre le Vulkan logiciel pour le Dolby Vision profil 5 et garde le plus rapide.
6. **`gosu` à la place de `su-exec`** dans cette image : Ubuntu ne fournit pas `su-exec`, les deux
   prennent `uid:gid commande`, et `docker-entrypoint.sh` prend celui qu'il trouve.

### Les commandes

7. **NVENC force des IDR.** `-force_key_frames` ne donne chez NVENC qu'une image I ordinaire sans
   `-forced-idr 1` ; un segment HLS doit commencer sur une IDR pour se décoder seul. Ajouté aux
   réglages de `h264_nvenc`, que `hevc_nvenc` reprend.
8. **`h264_nvenc` a une surface, `cuda`.** La chaîne matérielle écrite pour VAAPI le sert telle
   quelle : `-hwaccel cuda -hwaccel_output_format cuda`, `scale_cuda`, et pour une source HDR la
   descente à la taille du barreau, le tone mapping zscale, puis le renvoi. Les options de
   `scale_cuda` que la chaîne emploie (`force_original_aspect_ratio`, `force_divisible_by`,
   `format`) sont lues dans les sources de FFmpeg 8.1.
9. **Le périphérique CUDA n'est ouvert que pour ces sessions** (`surfaceArgs` :
   `-init_hw_device cuda=gpu -filter_hw_device gpu`), pas dans `deviceArgs`. NVENC encode sans
   périphérique nommé ; le nommer partout en ferait le périphérique des filtres d'une session
   libplacebo, qui veut Vulkan (ADR-0060).
10. **`-extra_hw_frames 8` sur ce décodage.** Quand la source est déjà à la taille et au format du
    barreau, `scale_cuda` laisse passer les images du décodeur, et NVENC en retient au moins quatre
    (`nb_surfaces`, `nvenc.c`) quand NVDEC n'en prévoit que trois de marge : « No decoder surfaces
    left ». Huit est une marge raisonnée, **pas mesurée**.
11. **La chaîne matérielle sort toujours une image du périphérique.** NVENC n'a pas de filtre
    d'envoi à lui : `hardwareUploadFilter` lui donne `format=nv12,hwupload` après le tone mapping,
    et `-pix_fmt` n'est plus passé quand la chaîne matérielle est prise (une conversion logicielle
    depuis une image CUDA est refusée par FFmpeg).
12. **Une session libplacebo ne prend pas la chaîne matérielle.** Avec VAAPI, l'encodeur d'une
    telle session redevenait déjà logiciel ; NVENC reste, puisqu'il prend des images logicielles,
    et c'est `usesHardwareFilters` qui s'efface. Sans cela, libplacebo se retrouvait au milieu
    d'une chaîne CUDA : trouvé par `TestCUDALeavesTheFilterDeviceToLibplacebo`.

Les trois gardes de la chaîne VAAPI valent pour CUDA : l'essai du démarrage par la commande d'une
session, `HARDWARE_FILTERS=off`, et le retrait pour tout le serveur si une session meurt avec elle
avant son premier segment.

### Écarté

- **Passer l'image unique sous Ubuntu.** Tous les serveurs en place changeraient de FFmpeg et de
  pilotes VAAPI pour une carte que la plupart n'ont pas.
- **`gcompat` sous Alpine** pour charger le pilote glibc : non pris en charge par NVIDIA, et le
  FFmpeg d'Alpine n'a de toute façon pas NVENC.
- **jellyfin-ffmpeg** : une branche 7.1 quand le serveur est écrit et testé contre la 8.1.
- **Le tone mapping sur la carte.** Ce FFmpeg n'a pas de `tonemap_cuda` ; libplacebo sur le Vulkan de
  la carte le ferait pour le HDR10 aussi, mais c'est un autre graphe et une autre mesure.

## Vérifié

Dans une réplique locale de l'étape `nvidia` (mêmes paquets, même FFmpeg, n8.1.3), **sans carte** :

- `go test ./...` du serveur, vert avec le FFmpeg de l'image, tests d'intégration compris ;
- `-hwaccel auto` sur une source HEVC 10 bits : CUDA puis VAAPI échouent, la session encode ;
- libplacebo sur le Vulkan logiciel (le chemin Dolby Vision profil 5) ;
- démarrage avec `PUID=99` : le serveur tourne sous ce compte par `gosu`, le journal dit
  `VIDEO_ENCODER=auto found no working hardware encoder, using libx264`, `/api/ping` répond.

Épinglé par `server/streaming/hardware_filters_cuda_test.go` et
`TestNVENCForcesIDRAtSegmentBoundaries`.

## À vérifier sur un serveur NVIDIA

1. Au démarrage : `Streaming: video encoder h264_nvenc (hardware=true)`, puis
   `Streaming: cuda decodes HEVC 10-bit` et `Streaming: hardware filters on (cuda)`. Un refus dit
   pourquoi, avec l'erreur de FFmpeg : c'est la ligne à rapporter.
2. `Streaming: libplacebo renders on …` nomme la carte, ou le rendu logiciel si le Vulkan de la
   carte n'est pas vu dans le conteneur.
3. Sur une source 4K HDR10 vers 1080p : `encodé à N×` au-dessus de 1, et `nvidia-smi` qui montre
   le décodage et l'encodage.
4. Une source déjà en 1080p SDR, le cas du §10 : la session ne meurt pas sur
   `No decoder surfaces left`.
5. Les segments font la durée demandée (`TestHardwareEncodersProduceAlignedSegments` n'a jamais vu
   de NVENC).

## Conséquences

- **Pilote NVIDIA 570 ou plus récent sur l'hôte** : ce FFmpeg parle l'API du Video Codec SDK 13.0.
  Un pilote plus ancien fait échouer l'essai du démarrage, et le serveur reste sur libx264 en le
  disant.
- Le tone mapping d'une source HDR10 reste sur le processeur, sur une image déjà réduite.
- L'image pèse environ 630 Mo : Ubuntu, Mesa (lavapipe, LLVM) et FFmpeg.
- Deux listes de paquets à tenir, et la sonde de santé et le point d'entrée écrits deux fois dans
  le Dockerfile.
- `publish-image.sh` et `publish-image.ps1` ne publient que l'image Alpine : la variante sort des
  workflows.
