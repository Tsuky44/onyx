# ADR-0158 — Sous Windows, le libmpv officiel de mpv, puis le rendu D3D11 de libmpv

- **Statut :** proposé. C'est le plan de mise en place ; rien n'est encore changé.
- **Date :** 2026-11-19
- **Portée :** le libmpv livré sous Windows (`packages/media_kit_libs_windows_video`), la sortie
  vidéo du plugin (`packages/media_kit_video/windows`), le choix du décodeur
  (`app/lib/screens/player/hardware_decoding.dart`).
- **Prolonge** l'[ADR-0019](0019-decodage-sans-copie-sous-windows.md) et
  l'[ADR-0095](0095-recopie-systematique-sous-windows.md). **Ne touche pas** à
  l'[ADR-0061](0061-fenetre-mpv-sous-l-app-windows.md) : le Dolby Vision profil 5 garde la fenêtre
  de mpv.

## Contexte

- **Le libmpv livré** vient de shinchiro (SourceForge), une capture git du 30/08/2026. On l'a pris
  parce que le build de media_kit n'avait pas TrueHD, et qu'il est abandonné depuis 2024. À
  l'époque, mpv ne publiait aucune libmpv Windows qu'on puisse épingler. Ce build est
  probablement compilé en GPL, ce qui se discute dans une app sous PolyForm Noncommercial.
- **mpv 0.42.0 (05/11/2026)** publie pour la première fois `libmpv-2.dll`, signée, en **GPL et en
  LGPL** (`-Dgpl=false`). L'app ne se sert d'aucun filtre `af`/`vf` (vérifié), donc rien de ce que
  le build LGPL retire n'est utilisé.
- **La même version ajoute `MPV_RENDER_API_TYPE_D3D11`** (`render_d3d11.h`). libmpv dessine alors
  avec `ra_d3d11` dans une texture D3D11 qu'on lui fournit, et son décodage `d3d11va` est celui de
  mpv seul : `CopySubresourceRegion1` de la zone utile, sur le GPU. Il n'y a plus de bande verte par
  construction, et plus de recopie en mémoire vive (ADR-0095). Le moteur de rendu est `gl_video`
  (`vo_gpu`), le même que sur le chemin ANGLE actuel. Lu dans `video/out/d3d11/libmpv_d3d11.c` et
  `video/out/gpu/libmpv_gpu.c` (v0.42.0).
- **Le plugin vidéo** crée déjà son propre périphérique D3D11 (sans `SINGLETHREADED`), une texture
  de rendu interne et une texture publique partagée avec Flutter (`DxgiSharedHandle`), recopiées
  sous un mutex (`ANGLESurfaceManager::Draw/Read`). ANGLE ne sert qu'à poser OpenGL ES par-dessus.
  Le rendu D3D11 de libmpv peut reprendre ce schéma tel quel, sans ANGLE.

## Décision

Deux changements, **livrés séparément**, chacun réversible par un commit, avec un repli
automatique sur le chemin actuel. Jamais les deux dans la même version.

## Garde-fous communs

1. **Une variable à la fois.** Chaque phase part en version de test (`x.y.Z`) et n'avance qu'une
   fois sa porte franchie. La suivante ne commence pas avant.
2. **Le chemin actuel reste dans le code** (ANGLE + `d3d11va-copy`, puis le rendu logiciel). Une
   panne du nouveau chemin y retombe toute seule, et la retombée se journalise (`ClientLog`).
3. **Une ligne de base mesurée avant de toucher quoi que ce soit** (premier pas de la phase 1), et
   chaque porte se juge contre elle, pas à l'œil.
4. **La liste de parité** ci-dessous est rejouée entièrement à chaque porte.

### Liste de parité (à rejouer à chaque porte)

| Domaine | Ce qui doit marcher comme aujourd'hui |
|---|---|
| Codecs vidéo | H.264, HEVC 8 et 10 bits, AV1, VC-1, MPEG-2 ; 4K HDR10 avec tone mapping |
| Codecs audio | AAC, AC-3, E-AC-3 (Atmos), **TrueHD**, **DTS / DTS-HD MA**, FLAC, Opus ; downmix « dialogue en avant » (ADR-0005) |
| Sous-titres | SRT, ASS (styles), PGS, VobSub ; WebVTT externe ; sous-titres en direct HLS |
| Réseau | Direct Play HTTPS par le relais (ADR-0036, `http-proxy`), TLS vers Cloudflare, reconnexion, reprise après coupure, nouveau ticket |
| Lecture | seek court et long (`hr-seek`), reprise au point connu, changement de piste audio et de sous-titres, vitesse, volume |
| Transcodage | HLS à chaque palier, qualité Auto, session préparée (`standby`) |
| Moteur | réutilisation entre épisodes, enchaînement automatique, image dans l'image, plein écran, redimensionnement, réduction |
| Dolby Vision 5 | fenêtre `gpu-next` (ADR-0061), couleurs justes |
| Diagnostic | `PLAYER STARTUP`, statistiques, `hwdec-current`, images perdues |
| Durée | séance de 2 h sans mémoire qui monte, ni décalage du son |

## Phase 1 — Le libmpv officiel 0.42.0 en LGPL, rien d'autre

Le rendu et le décodage ne changent pas : ANGLE, `d3d11va-copy`.

0. **La ligne de base, avant tout changement.** Constituer le jeu de fichiers de référence (un
   par ligne du tableau de parité) et le noter dans `docs/` (nom, codec, piste, ce qu'on regarde).
   Mesurer sur la machine de référence, pour chaque fichier, avec le libmpv actuel : démarrage
   (`PLAYER STARTUP`), processeur et GPU moyens sur 2 minutes, images perdues, `hwdec-current`.
1. `media_kit_libs_windows_video/windows/CMakeLists.txt` : l'archive devient l'asset de la release
   GitHub de mpv (`libmpv-v0.42.0-x86_64-w64-mingw32-lgpl.zip`), avec son empreinte épinglée comme
   aujourd'hui. Adapter l'extraction à la disposition du zip (en-têtes, bibliothèque d'import que
   lie `media_kit_video` : `libmpv.dll.a`).
2. Retirer `patch_libmpv.ps1` et les MD5 « corrigés ». Il ne sert qu'à l'interop `d3d11-egl`, que
   Windows n'utilise plus depuis l'ADR-0095.
3. Vérifier ce que contient le build, par un petit test natif qui charge la DLL :
   `mpv_client_api_version` compatible avec les liaisons de media_kit 1.2.6 ; `decoder-list` avec
   `truehd`, `dca`, `eac3`, `hevc`, `av1` ; `d3d11va` disponible ; libass ; libplacebo (fenêtre DV5).
4. **Le risque à regarder en premier : le réseau.** Le build de shinchiro ouvre les flux par
   libcurl (ADR-0036) ; celui de mpv passe peut-être par le HTTP de FFmpeg. À vérifier :
   - le relais `CONNECT` (`http-proxy`) est bien suivi pour du HTTPS ;
   - le nom envoyé en TLS est le bon derrière Cloudflare ;
   - le temps jusqu'au premier démultiplexeur (117 ms mesurés en ADR-0036) ;
   - les options `stream-lavf-o` de reconnexion, qui pourraient enfin s'appliquer.

   Si le relais n'est pas suivi, la phase s'arrête là et on garde shinchiro.
5. Mettre à jour l'ADR-0019 (le correctif binaire disparaît) et la licence des composants livrés
   (LGPLv3).

**Porte :** toute la liste de parité passe ; démarrage et charge à ±10 % de la ligne de base ;
version de test chez au moins un utilisateur Windows en HTTPS pendant une semaine sans régression ;
puis version de prod.

## Phase 2 — Le rendu D3D11 de libmpv dans le plugin vidéo

1. **Une classe `D3D11SurfaceManager`** à côté d'`ANGLESurfaceManager`, avec la même interface
   (`Draw`, `Read`, `SetSize`, `handle`, `width`, `height`) et le même schéma éprouvé :
   - le même choix d'adaptateur qu'aujourd'hui, pour rester sur le GPU de Flutter (portables à
     deux GPU) ;
   - une texture de rendu interne (`BIND_RENDER_TARGET`, `B8G8R8A8`) donnée à mpv par
     `MPV_RENDER_PARAM_D3D11_FBO` ;
   - une texture publique partagée ;
   - `CopyResource` dans `Read` sous le même mutex que `Draw`. C'est ce qu'exige
     `render_d3d11.h` : personne d'autre ne touche au contexte immédiat pendant un rendu de mpv.
2. **`VideoOutput` essaie dans l'ordre D3D11 → ANGLE → logiciel.** On ne garde un chemin que si
   `mpv_render_context_create` réussit, et on journalise celui qui a été retenu.
3. **Le chemin retenu remonte à Dart** avec l'identifiant de texture. `HardwareDecoding` décide :
   - D3D11 → `auto-safe` (le `d3d11va` sans copie de mpv, qui rogne lui-même) ;
   - ANGLE → `auto-copy-safe`, comme aujourd'hui ;
   - logiciel → inchangé.

   La règle est une fonction pure, testée sur les trois cas.
4. **Retombée sur panne.** On rétablit pour Windows le rattrapage « décodé en logiciel → copie »
   que l'ADR-0095 avait retiré. Une texture qui ne montre aucune image dans le délai de démarrage
   marque l'appareil, comme `zeroCopyFailed` sur Android, et la lecture suivante prend ANGLE.
5. **Un réglage « Rendu vidéo : automatique / compatibilité »** dans les réglages de lecture, en
   français et en anglais, pour qu'un utilisateur se débloque sans nous attendre.
6. **Ce qui ne change pas :** la fenêtre DV5, le moteur mis en commun, le contrôleur, les surfaces
   Flutter.

**Porte :**
- toute la liste de parité, sur Intel, NVIDIA et AMD, et sur un portable à deux GPU ;
- redimensionnement, plein écran, réduction, image dans l'image et enchaînement d'épisodes ;
- un redémarrage du pilote (TDR) qui retombe proprement ;
- 4K HDR : la charge processeur baisse nettement par rapport à la ligne de base ;
- partout ailleurs : images perdues et démarrage au plus égaux à la ligne de base ;
- aucune bande verte sur les fichiers qui en montraient ;
- puis version de test, réglage par défaut chez les testeurs, et enfin version de prod.

## Phase 3 — Après stabilisation

- Statuts mis à jour : ADR-0019 (le sans-copie revient, par un autre chemin), ADR-0095 (la recopie
  n'est plus que le repli), cette ADR (acceptée).
- ANGLE reste comme repli tant qu'il ne coûte rien. On ne le retire qu'avec une ADR, et une fois
  que les journaux montrent qu'il ne sert plus.

## Hors du périmètre

- La sortie HDR et le Dolby Vision hors profil 5 dans la texture : Flutter compose en SDR 8 bits.
  Ça reste le rôle de la fenêtre de l'ADR-0061.
- Un libmpv construit par nous : écarté (ADR-0095, révision du 2026-11-19).

## Conséquences

- La source du libmpv devient le projet mpv lui-même, en version stable et signée. La licence LGPL
  est compatible avec une bibliothèque chargée dynamiquement.
- Le correctif binaire de l'ADR-0019 disparaît dès la phase 1.
- Une API de deux semaines entre dans le chemin principal à la phase 2. Le repli automatique sur
  ANGLE et le réglage de compatibilité en limitent le risque.
- Chaque porte demande un passage sur de vraies machines. `flutter test` ne voit ni le GPU ni le
  réseau.
