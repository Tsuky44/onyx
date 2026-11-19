# ADR-0158 — Sous Windows, le libmpv officiel de mpv, puis le rendu D3D11 de libmpv

- **Statut :** proposé. Phase 1 en cours : le changement de libmpv est prêt, la porte n'est pas
  franchie. Phase 2 commencée en parallèle, puis ouverte à tous en Automatique pour un essai à
  grande échelle (voir le journal d'avancement en fin de page).
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
   que l'ADR-0095 avait retiré. Une texture qui ne montre aucune image dans le délai de démarrage,
   ou un périphérique perdu (TDR), fait passer **la lecture en cours** sur ANGLE, sans changer de
   lecteur mpv. L'écran noir est retenu sur disque pour l'adaptateur et son pilote ; un pilote mis
   à jour retente D3D11. *(Révisé le 2026-11-19, voir le journal.)*
5. **Un réglage « Rendu vidéo » : Ancien / Nouveau / Automatique**, ouvert à tous sous Windows,
   **Automatique par défaut**, en français et en anglais. Nouveau force D3D11 et le décodage sans
   copie ; Ancien est le chemin de la phase 1. *(Remplace « automatique / compatibilité », voir le
   journal du 2026-11-19.)*
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

## Journal d'avancement

### 2026-11-19 — phase 1, le changement de binaire

**Ligne de base.** Le jeu de fichiers, le protocole et le relevé à remplir sont dans
[`docs/libmpv-windows-ligne-de-base.md`](../libmpv-windows-ligne-de-base.md). La ligne de base se
mesure en mode profile sur `tsuky` juste avant ce changement (shinchiro), puis après lui : le même
code, seul le libmpv change. Le changement attend donc sur la branche locale `tsuky-libmpv-042`
jusqu'à ce que la ligne de base soit prise. Pas encore faite.

**L'archive.** `libmpv-v0.42.0-x86_64-w64-mingw32-lgpl.zip`, asset de la release v0.42.0 de mpv
(05/11/2026), épinglée par son SHA-256 (`8e5f7743…6fce`, celui que GitHub affiche). Sa signature
PGP (`.asc`) est valide, clé `D83F 25E4 4BD6 B948 724A B75F 6580 1323 38AB D4E2` de Kacper
Michajłow, mainteneur de mpv. La DLL elle-même n'a pas de signature Authenticode. Le zip a la même
disposition que l'archive de shinchiro : `include/mpv/*.h`, `libmpv-2.dll`, `libmpv.dll.a`, plus
deux `.jar` de libbluray (menus BD-J), retirés à l'extraction. Le téléchargement passe à SHA-256
(`download_and_verify` prend l'algorithme ; ANGLE garde son MD5).

**La licence.** mpv est configuré avec `-Dgpl=false`, sur l'image FFmpeg de BtbN en variante
`lgpl`, qui compile avec `--enable-version3` : la DLL est sous LGPLv3. Le zip ne contient que le
texte de la LGPL 2.1 (celui de mpv). Ajouté aux licences des composants livrés
(`app/assets/legal/third_party*.txt`).

**Le correctif binaire** de l'ADR-0019 est retiré. Il n'aurait plus rien à corriger : le build
officiel n'a pas `egl-angle` (ni l'interop `d3d11-egl`, ni le contexte `angle`). La texture Flutter
n'en a pas besoin, media_kit fournit lui-même le contexte d'ANGLE à l'API de rendu.

**Le contenu, comparé à shinchiro** (DLL chargée, `decoder-list`, listes `help` de `hwdec`, `vo` et
`gpu-api`) :

| | shinchiro (0.41.0-1012) | officiel 0.42.0 LGPL |
|---|---|---|
| API cliente | 2.5 | 2.6 |
| Décodeurs audio et vidéo | 519 | 516 |
| TrueHD, DTS (`dca`), E-AC-3, AC-3, HEVC, AV1, VC-1, MPEG-2, FLAC, Opus | oui | oui |
| Décodeurs en moins | — | AVS2 (`libdavs2`), Speex (`libspeex`), huit variantes ADPCM rares, AHX |
| Décodeurs en plus | — | AMR (`libopencore`), `libopenh264`, `libaom-av1`, deux ADPCM, deux formats d'image |
| `d3d11va`, `d3d11va-copy` (H.264, HEVC, AV1, VC-1, MPEG-2, VP9) | oui | oui |
| Sorties | `gpu-next`, `gpu`, `libmpv`, `direct3d`… | les mêmes sans `direct3d` |
| `gpu-api` | `d3d11`, `vulkan`, `opengl` (`angle`, `win`, `dxinterop`) | `d3d11`, `vulkan`, `opengl` (`win`, `dxinterop`) |
| libass | 0.17.x | 0.17.x |
| Flux réseau | libcurl (`curl-enabled=yes`) | libcurl (`curl-enabled=yes`) |

Rien de ce qui manque n'est utilisé : la fenêtre Dolby Vision 5 demande `vo=gpu-next` sans fixer
`gpu-api`, et l'app ne demande ni `direct3d` ni `angle`. Les fonctions que media_kit 1.2.6 et le
plugin vidéo appellent sont toutes exportées. Ses liaisons générées portent un en-tête 1.109, mais
il tourne déjà sur une API 2.x avec shinchiro.

Ce contrôle est désormais automatique : `check_libmpv.ps1` charge la DLL après chaque extraction et
fait échouer la configuration si un décodeur, libcurl, libass, `gpu-next`, `d3d11va-copy` ou une
fonction appelée manque. Il passe sur les deux DLL, et ne dépend pas du GPU de la machine.

**Le réseau (le risque n° 1).** Lu dans `stream/stream_curl.c` (v0.42.0) : le libcurl de mpv
reçoit `http-proxy` en `CURLOPT_PROXY`, donc tunnel `CONNECT` pour du HTTPS, et TLS de bout en bout
avec le nom de l'URL. Entre la capture de shinchiro et la 0.42.0, ce code n'a changé que de forme
(`SETOPT`) et pour trois corrections de requêtes (réponse vide, 416, fichier vide). Les flux que FFmpeg ouvre lui-même (les
segments HLS) passent aussi par ce libcurl (`curl_avio`). Essai réel, DLL chargée seule (`vo=null`,
`ao=null`) derrière un relais `CONNECT` de test sur 127.0.0.1 :

- **Le relais est suivi** : `CONNECT test-videos.co.uk:443` et `CONNECT onyx.tsuky.ovh:443` reçus,
  rien d'autre.
- **Le nom TLS est le bon derrière Cloudflare** : vers le serveur Onyx, TLS 1.3, ALPN h2,
  certificat `*.tsuky.ovh` vérifié (`tls-verify=yes` par défaut).
- **Premier démultiplexeur** (`loadfile` → `FILE_LOADED`, fichier MKV derrière Cloudflare, relais
  qui connaît déjà l'adresse comme celui de l'app) : 0.42.0 autour de 95 ms, shinchiro autour de
  167 ms, sur 18 ouvertures en alternance (référence ADR-0036 : 117 ms). L'écart vient de
  shinchiro : son libcurl interroge le DNS (enregistrement HTTPS) avant même d'envoyer le
  `CONNECT`, environ 80 ms. Celui de mpv n'interroge rien. Une seule ouverture à 11,2 s, la toute
  première, quand le relais de test résolvait encore le nom lui-même (la signature des 11 s de DNS
  de ce poste, ADR-0036). Pas reproduite en plus de 20 ouvertures depuis. À surveiller dans
  `PLAYER STARTUP` pendant la semaine de test.
- **La reconnexion** : `stream-lavf-o` (`reconnect=1…`) ne s'applique toujours pas, et ne
  s'appliquera pas : ces options sont celles du HTTP de FFmpeg, que libcurl remplace. La reprise
  existe pourtant : le flux libcurl réessaie lui-même un transfert coupé, à partir de l'octet
  atteint (`curl-max-retries`, 5 par défaut). Tunnel coupé à 3 Mo en pleine lecture : les deux DLL
  rouvrent un `CONNECT`, reprennent à l'octet près et lisent jusqu'au bout.

Le relais est suivi : la phase continue.

**Reste avant la porte** : la ligne de base, puis la version de test, la liste de parité complète
sur la machine de référence et une semaine chez un utilisateur Windows en HTTPS. Le statut reste
« proposé ».

### 2026-11-19 — phase 1, premier essai sur la machine de Tsuky, fusion locale dans `tsuky`

Build profile (`STORE_BUILD=true`), DLL chargée vérifiée : `libmpv-2.dll` **v0.42.0**. Décodage
`d3d11va-copy` partout, comme prévu.

| Fichier | Audio | `shown` | ticket → `shown` |
|---|---|---|---|
| H.264 1080p, 1re ouverture | DTS 2ch | 5 812 ms | 879 ms |
| le même, 2e ouverture | DTS 2ch | 883 ms | 698 ms |
| HEVC 1080p | E-AC-3 6ch → 2ch | 577 ms | 426 ms |
| HEVC 1080p 25 i/s, piste VF choisie au démarrage | E-AC-3 2ch | 1 153 ms | 457 ms |
| HEVC 3832×1600 | E-AC-3 5.1 | 629 ms | 442 ms |

Un seul point de comparaison avec shinchiro, le même fichier H.264 dans la même journée :
`shown=2158ms`, ticket → `shown` 1 020 ms. Ce n'est pas la ligne de base : celle-ci n'a pas été
mesurée avant la fusion, par choix de Tsuky.

Les attentes vues pendant ces lectures ne viennent pas de libmpv :
- le ticket à 4,9 s de la première ouverture, et les `connectionTimeout` de l'API, viennent du DNS
  de ce poste (11 s par nom, quel que soit le domaine : des cartes réseau sans DNS IPv6 réel
  interrogent les adresses `fec0:0:0:ffff::*` par défaut) ;
- les vidages de cache en pleine lecture (« 2 s regarnies en 7 s, par rafales ») sur le fichier
  H.264, comme avec shinchiro : la ligne mesurée (6,9 à 19 Mbit/s, instable) ne tient pas son débit.

Le changement est fusionné en local dans `tsuky`, sans poussée ni version de test. **Reste avant
la porte** : TrueHD, DTS-HD MA, sous-titres PGS/ASS/VobSub, HDR10 avec tone mapping, fenêtre DV5,
HLS transcodé, séance de 2 h, puis la version de test d'une semaine chez un utilisateur Windows en
HTTPS.

### 2026-11-19 — phase 2 commencée avant la porte de la phase 1, les deux rendus cohabitent

**Décision de Tsuky.** La phase 2 commence tout de suite, sans attendre la porte de la phase 1, pour
tout tester d'un coup sur de vraies machines. Ça s'écarte du garde-fou « une variable à la fois » :
le libmpv 0.42.0 et le rendu D3D11 arrivent ensemble. Ce qui le rend acceptable :

- **Les deux chemins cohabitent dans le code**, et le nouveau ne s'active que sur demande. Le point 5
  (« Rendu vidéo : automatique / compatibilité » pour tous) est remplacé par un réglage **réservé
  aux admins, sous Windows seulement**, avec trois valeurs :
  - **Ancien** : ANGLE et `d3d11va-copy`, le chemin de la phase 1 ;
  - **Nouveau** : le rendu D3D11 de libmpv et `auto-safe`, avec repli sur ANGLE si mpv refuse de
    créer le contexte ;
  - **Automatique** : D3D11 → ANGLE → logiciel, avec la retombée sur panne du point 4.
- **Par défaut : Ancien**, pour tout le monde. Un compte qui n'est pas admin (propriétaire, ou tous
  les droits, le critère de `Permissions.isAdmin`) reste sur Ancien quoi qu'il y ait d'enregistré.
  Seul un admin qui change le réglage passe sur le nouveau chemin. Le choix s'applique à la lecture
  suivante.
- Les deux phases gardent chacune leur porte. Celle de la phase 1 se juge sur Ancien ; celle de la
  phase 2, en comparant Ancien et Nouveau sur la même machine et le même libmpv.

**Ce qui a été fait**, d'après `render_d3d11.h` et `render.h` du zip 0.42.0 épinglé (en-tête
identique à celui du zip, relu en entier) et `video/out/d3d11/libmpv_d3d11.c` :

1. **`D3D11SurfaceManager`** (`packages/media_kit_video/windows/d3d11_surface_manager.{h,cc}`),
   à côté d'`ANGLESurfaceManager`, avec la même interface (`Draw`, `Read`, `SetSize`, `handle`,
   `width`, `height`) plus `device()` et `render_target()`. Même choix d'adaptateur que le chemin
   ANGLE (l'adaptateur par défaut sous Windows 10, le premier énuméré avant), donc que Flutter.
   Périphérique sans `SINGLETHREADED` (exigé pour `d3d11va` sans copie), niveaux 11_1 à 9_3 comme
   la sortie `d3d11` de mpv, protection multithread posée. Texture interne `BIND_RENDER_TARGET`
   `B8G8R8A8` donnée à mpv par `MPV_RENDER_PARAM_D3D11_FBO`, texture publique partagée
   (`DxgiSharedHandle`), `CopyResource` + `Flush` dans `Read` sous le même mutex que `Draw`. Une
   recréation de texture ratée (pilote redémarré) ne lève pas : la texture reste nulle, les rendus
   suivants échouent et se comptent.
2. **`VideoOutput`** essaie D3D11 (seulement si Dart le demande) → ANGLE → logiciel. Pour D3D11, le
   contexte de rendu se crée avant la texture Flutter : un refus de mpv ne laisse rien derrière lui.
   Le chemin retenu est journalisé (`media_kit: VideoOutput: render path: …`) et remonte à Dart
   avec l'identifiant de texture (`VideoOutput.Resize`, champ `renderApi`). Chaque rendu réussi ou
   raté est compté, et `VideoOutputManager.GetRenderInfo` rend ces compteurs sans jamais bloquer le
   fil de Flutter.
3. **Le décodeur** : `HardwareDecoding.windowsAuto`, fonction pure testée sur les trois cas.
   D3D11 → `auto-safe` ; ANGLE → `auto-copy-safe` ; logiciel ou inconnu → `auto-copy-safe`
   (inchangé). Les préférences « Compatible » et « Logiciel » restent ce qu'elles sont.
4. **La retombée sur panne** : trois secondes après la première image, une texture D3D11 sans aucun
   rendu réussi marque l'appareil pour la session (comme `zeroCopyFailed` sur Android) et l'écrit
   en erreur dans le `ClientLog`. En Automatique, la lecture suivante prend ANGLE ; en Nouveau,
   l'admin a demandé D3D11 et le garde. Le rattrapage « décodé en logiciel → copie » que
   l'ADR-0095 avait retiré revient, pour la seule texture D3D11. Pas de vérification sur un profil
   5 : sa fenêtre mpv (ADR-0061) a pris la place de la texture.
5. **Le moteur mis en commun** garde le chemin demandé à sa création. Un moteur préparé pour un
   autre chemin que celui demandé maintenant est jeté et reconstruit (réglage changé, D3D11 marqué
   en panne, admin connecté après le préchauffage).
6. **Le diagnostic** dit le chemin effectif : une note `rendu d3d11` dans `PLAYER STARTUP`,
   `render=d3d11 (auto → d3d11)` dans la ligne `Playback:`, une ligne « Rendu vidéo » dans les
   statistiques.

Ne changent pas : la fenêtre DV5, le contrôleur, les surfaces Flutter, les autres plateformes. Le
statut reste « proposé ».

### 2026-11-19 — phase 2 ouverte à tous, Automatique par défaut, Nouveau force le sans-copie

**L'essai de Tsuky** sur sa machine : Rendu vidéo = Nouveau et Décodage matériel = Compatible
donnaient `render=d3d11` mais `hwdec=d3d11va-copy`. Sur Rapide : `hwdec=d3d11va`, « Allocated a
fixed pool of 26 hw surfaces », un HEVC Main 10 4K affiché, redimensionnement juste, aucune erreur
D3D11. Le nouveau chemin marche.

**Décisions de Tsuky**, pour un essai à grande échelle : « Tous, défaut Automatique » et « Nouveau
force le sans-copie ». Elles reviennent sur l'entrée précédente :

- **Le réglage Rendu vidéo est ouvert à tous sous Windows**, plus seulement aux admins. Il vaut
  **Automatique par défaut**, y compris pour qui ne l'a jamais touché. Il n'y a plus de barrière de
  droits dans le code.
- **Sur la texture D3D11 (Nouveau ou Automatique), le décodage est toujours sans copie**
  (`auto-safe`), sauf sur « Logiciel ». « Compatible » ne vaut plus que pour ANGLE. La règle reste
  une fonction pure (`HardwareDecoding.windowsValue`), testée sur les 18 combinaisons (3 rendus ×
  3 préférences × appareil pris ou non à décoder en logiciel). Un appareil pris à décoder en
  logiciel au-dessus de 1440 lignes repasse sur la copie, sur Rapide comme sur Compatible.
- **Le diagnostic dit ce que mpv reçoit** : `asked auto → auto-safe` en D3D11, et plus
  `auto-copy-safe` (`HardwareDecoding.describe` prend le chemin de rendu).

**La retombée sur panne est durcie**, puisque c'est désormais le chemin de tout le monde :

- **La lecture en cours passe sur ANGLE**, plus seulement la suivante. La sortie native libère son
  contexte de rendu D3D11 (ce qui coupe la vidéo de mpv : sa sortie et son décodeur sont détruits,
  surfaces d3d11va comprises, et la piste vidéo désélectionnée), crée celui d'ANGLE sur le même
  lecteur mpv, puis Dart repose le décodeur de l'ancien chemin et resélectionne la piste vidéo. Le
  son, la position, les pistes et le moteur mis en commun ne bougent pas. Lu dans
  `video/out/vo_libmpv.c` (`mpv_render_context_free`) et `player/client.c` (`do_kill`), v0.42.0.
  En Automatique seulement : Nouveau force D3D11, une panne y est journalisée sans bascule.
- **Ce qui déclenche** (`MpvD3D11Fallback.judge`, relevé toutes les 2 s des compteurs de la sortie) :
  aucune image rendue 3 s après la première image annoncée ; un périphérique perdu
  (`GetDeviceRemovedReason`, relevé au premier rendu raté : TDR, pilote redémarré) ; ou au moins
  10 rendus ratés de suite sans aucun réussi. Un contexte que mpv refuse à la création retombe
  déjà sur ANGLE dans `VideoOutput`.
- **L'écran noir est retenu sur disque**, sous la clé adaptateur + pilote (`vendeur:appareil:version
  du pilote`, lue par DXGI sur l'adaptateur que prennent D3D11 et Flutter). Une machine cassée ne
  redonne pas un écran noir à la première lecture de chaque lancement ; un pilote mis à jour
  change la clé, et D3D11 est retenté. Un périphérique perdu en route ne l'est que pour la session :
  la cause peut être passagère.

**Ce qui remonte au serveur** sans demander de journaux aux testeurs : la tranche de journal de
chaque lecture (`PlaybackReporter`) contient la ligne `Playback:` avec `hwdec=…`, `render=…` et le
réglage, l'adaptateur et son pilote ; chaque retombée est une ligne d'erreur (raison, adaptateur,
pilote, réglage, chemin suivant), ce qui garde l'historique de la lecture côté serveur. Le résumé
de statistiques porte `video_output`, que l'export des journaux affiche en « Rendu vidéo ».

**La recherche plus lente vue en D3D11** (image +2,90 s / reprise +4,05 s, contre +1,14 s /
+2,04 s en ANGLE, à une autre position du film, une seule fois). Rien ne change sans preuve. Ce qui
a été regardé :

- le pool de 26 surfaces d3d11va ne retient pas les images sautées par `hr-seek` : elles sont
  rendues au pool dès qu'elles sont jetées, et le décodage sans copie fait moins de travail que la
  recopie ;
- `hr-seek`, le cache et le relais sont les mêmes sur les deux chemins ; l'image d'après une
  recherche dépend surtout de la distance à l'image clé (GOP) et du réseau, qui changent d'une
  position à l'autre ;
- une piste plausible propre à D3D11 : `ra_d3d11` compile ses shaders (shaderc → SPIRV-Cross →
  `D3DCompile`) à la première utilisation de chaque variante, et l'écrit en `v`
  (« Compiled a … shader in …ns »). Une variante nouvelle après une recherche coûterait sa
  compilation une fois par lancement.

À mesurer avant toute conclusion : même fichier, même position de départ, cinq recherches de la
même amplitude sur chaque chemin, en relevant les lignes de recherche (image, reprise, débit du
cache) et, dans le journal de mpv, les compilations de shaders qui suivent.

**La porte de la phase 2 se jugera sur le test à grande échelle**, plus sur un essai manuel
préalable : Tsuky met la version de test chez tout le monde, sans repasser Automatique et Ancien à
la main (« non pas grave on va mettre en test à tout le monde »). Ce qui a été vérifié sur sa
machine avant : un HEVC Main 10 4K en `d3d11va` sur la texture D3D11 ; et, avec cette version, un
lancement sans réglage enregistré qui part en `auto → d3d11` (AMD Radeon RX 6800 XT, pilote lu
par DXGI), `render path: d3d11`. La bascule en pleine lecture n'a pas tourné sur une vraie
machine : elle se juge dans les journaux des testeurs (lignes « échec D3D11 » et « après la
bascule »). Pour la provoquer exprès, `--dart-define=ONYX_FORCE_D3D11_FALLBACK=true` fait passer la
première texture D3D11 sur ANGLE sans rien retenir sur disque ; jamais dans une version publiée.
Ce que la porte regarde dans ces journaux : les retombées et leurs adaptateurs (Intel, NVIDIA,
AMD, portables à deux GPU), un `hwdec=no` sur D3D11, les TDR, le plein écran, le
redimensionnement, l'image dans l'image, l'enchaînement d'épisodes, et les temps de recherche
sur les deux chemins.

Le statut reste « proposé ».
