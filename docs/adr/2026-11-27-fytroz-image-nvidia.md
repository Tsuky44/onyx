# ADR 2026-11-27 (fytroz) : une image `-nvidia` pour les cartes NVIDIA

> Précise l'ADR-0023 (encodeur matériel optionnel) et l'ADR-0155 (un seul compose).

- **Statut :** accepté, à la demande de l'utilisateur (2026-11-27 : « fais en sorte de prendre en
  compte les cartes graphiques, j'ai une P2200 dans mon serveur »). L'étape `nvidia` a été
  construite et lancée dans un conteneur sans carte (voir « Vérifié ») ; **aucune session n'a encore
  tourné sur une vraie carte NVIDIA.**
- **Date :** 2026-11-27
- **Portée :** `server/Dockerfile` (étapes `ffmpeg-nvidia` et `nvidia`),
  `server/docker-entrypoint.sh` (`su-exec` ou `gosu`), `server/streaming/encoder.go`
  (`-forced-idr` pour NVENC), `docker-compose.yml`, `.env.example`,
  `.github/workflows/server.yml` et `release.yml` (tags `-nvidia`), `server/README.md`, `README.md`.

## Contexte

`h264_nvenc` et `hevc_nvenc` sont pilotés par le serveur depuis l'ADR-0023, mais l'image Docker ne
pouvait pas s'en servir, pour deux raisons indépendantes :

1. **Le FFmpeg d'Alpine n'a pas NVENC.** Son APKBUILD (3.24, FFmpeg 8.1.3) n'a ni `ffnvcodec` ni
   `--enable-nvenc` : `VIDEO_ENCODER=h264_nvenc` y répond « Unknown encoder » et retombe sur
   libx264.
2. **musl ne charge pas le pilote.** Les bibliothèques que le NVIDIA Container Toolkit injecte dans
   le conteneur (`libcuda.so.1`, `libnvidia-encode.so.1`, `libnvcuvid.so.1`) sont compilées pour la
   glibc. Recompiler FFmpeg sous Alpine ne suffirait donc pas.

## Décision

1. **Une seconde image, pas une nouvelle base.** `docker build --target nvidia` produit une variante
   Ubuntu 24.04 ; l'image Alpine reste la dernière étape du Dockerfile, donc celle d'un `docker
   build` sans cible, et ne change pas d'un octet. Les tags sont ceux de l'image Alpine suivis de
   `-nvidia` (`latest-nvidia`, `v1.4-nvidia`, `v1.4.2-nvidia`), publiés par les deux workflows.
   amd64 seulement.
2. **Le FFmpeg 8.1 de BtbN, en `gpl-shared`.** La même branche que celui d'Alpine 3.24, avec NVENC,
   NVDEC, libplacebo et Vulkan, lié à la seule glibc. `gpl-shared` plutôt que la construction
   statique : `ffmpeg` et `ffprobe` y partagent leurs `libav*` (205 Mo contre 350). L'adresse suit
   `latest` de la branche 8.1 : BtbN ne garde ses constructions datées que 14 jours (ou la dernière
   du mois), une adresse figée casserait le build. `FFMPEG_NVIDIA_URL` la remplace.
3. **`libva`, `libva-drm`, `libva-x11` et `libdrm` sont installées, bien qu'inutiles à NVIDIA.** Ce
   FFmpeg les ouvre à la demande par des amorces qui **arrêtent le processus** (`abort`) quand le
   fichier manque. Or `-hwaccel auto`, présent dans chaque commande, essaie VAAPI dès que CUDA ne
   répond pas. Mesuré : sans ces bibliothèques, toute session d'un hôte où la carte n'est pas
   visible mourait sur `libva-drm.so.2: cannot open shared object file`. Avec elles, l'essai échoue
   proprement et le décodage reste logiciel.
4. **L'image règle `VIDEO_ENCODER=auto`.** L'ADR-0023 veut que le matériel soit un choix de
   l'opérateur : prendre l'image `-nvidia` est ce choix. Sans carte visible, l'essai du démarrage
   échoue et le journal dit que libx264 est pris. `VIDEO_ENCODER=libx264` dans `.env` y ramène.
   L'image règle aussi `NVIDIA_VISIBLE_DEVICES=all` et
   `NVIDIA_DRIVER_CAPABILITIES=compute,video,utility`, que le Toolkit lit : il ne reste à
   l'opérateur que `runtime: nvidia` (sur Unraid : `--runtime=nvidia` et le plugin Nvidia-Driver).
5. **NVENC force des IDR.** `-force_key_frames` ne donne chez NVENC qu'une image I ordinaire sans
   `-forced-idr 1` ; un segment HLS doit commencer sur une IDR pour se décoder seul. Ajouté aux
   réglages de `h264_nvenc`, que `hevc_nvenc` reprend. Épinglé par
   `TestNVENCForcesIDRAtSegmentBoundaries`.
6. **`gosu` à la place de `su-exec`** dans cette image : Ubuntu ne fournit pas `su-exec`, les deux
   prennent `uid:gid commande`, et `docker-entrypoint.sh` prend celui qu'il trouve.

### Écarté

- **Passer l'image unique sous Ubuntu.** Tous les serveurs en place changeraient de FFmpeg et de
  pilotes VAAPI pour une carte que la plupart n'ont pas, et l'image grossirait pour tous.
- **`gcompat` sous Alpine** pour charger le pilote glibc : non pris en charge par NVIDIA, et le
  FFmpeg d'Alpine n'a de toute façon pas NVENC.
- **jellyfin-ffmpeg** : une branche 7.1 quand le serveur est écrit et testé contre la 8.1.
- **Régler `runtime` par une variable du compose.** `runtime: ${…:-runc}` suppose que `runc` est le
  runtime par défaut de l'hôte ; une ligne à décommenter ne suppose rien, comme `devices` pour
  VAAPI.

## Vérifié

Dans une réplique locale de l'étape `nvidia` (mêmes paquets, même FFmpeg, n8.1.3), **sans carte** :

- `go test ./...` du serveur, 28 paquets verts avec le FFmpeg de l'image, tests d'intégration
  compris ;
- `-hwaccel auto` sur une source HEVC 10 bits : CUDA puis VAAPI échouent, la session encode ;
- libplacebo sur le Vulkan logiciel (le chemin Dolby Vision profil 5, ADR-0060) ;
- démarrage avec `PUID=99` : le serveur tourne sous ce compte par `gosu`, le journal dit
  `VIDEO_ENCODER=auto found no working hardware encoder, using libx264`, `/api/ping` répond.

**Pas vérifié :** l'encodage et le décodage sur une vraie carte. `TestHardwareEncodersProduceAlignedSegments`
rejoue une session contre tout encodeur matériel présent ; il n'a jamais vu de NVENC.

## Conséquences

- **Pilote NVIDIA 570 ou plus récent sur l'hôte** : ce FFmpeg parle l'API du Video Codec SDK 13.0.
  Un pilote plus ancien fait échouer l'essai du démarrage, et le serveur reste sur libx264 en le
  disant.
- Le décodage passe aussi par la carte (NVDEC, par le `-hwaccel auto` existant) pour les codecs
  qu'elle connaît ; l'image redescend en mémoire pour les filtres. La mise à l'échelle et le tone
  mapping restent sur le processeur, pour la raison du §3 de l'ADR-0023 : un seul graphe de filtres
  quel que soit l'encodeur. `scale_cuda` existe dans ce FFmpeg et reste à brancher, avec la machine
  pour l'essayer.
- L'image pèse environ 630 Mo : Ubuntu, Mesa (lavapipe, LLVM) et FFmpeg.
- Deux listes de paquets à tenir, et la sonde de santé et le point d'entrée écrits deux fois dans
  le Dockerfile.
- `publish-image.sh` et `publish-image.ps1` ne publient que l'image Alpine : la variante sort des
  workflows.
