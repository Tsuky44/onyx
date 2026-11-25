# Transcodage calé sur le serveur — plan

- **Statut :** plan, version 2, décisions prises le 2026-11-25 (§0). Implémentation du côté serveur lancée, phase par phase : lot rapide, phases 0 à 3, et le côté serveur des phases 4 et 5, faits sur `tsuky` (ADR [profil matériel et planificateur](adr/2026-11-25-tsuky-profil-materiel-et-planificateur.md), ADR [budget et admission](adr/2026-11-25-tsuky-budget-et-admission.md), ADR [tenue des barreaux et rétroaction](adr/2026-11-25-tsuky-tenue-des-barreaux-et-retroaction.md)). Le côté client des phases 4 et 5 reste à faire (« Reste à faire », après la phase 5).
- **Date :** 2026-11-25
- **Base :** `beta` à `2d8d4d77`, qui contient le travail de fytroz du 2026-11-25. Le plan part de ce code, pas de l'état d'avant.
- **Prolonge :** ADR-0022 (échelle de débits), ADR-0056 et ADR-0065 (qualité automatique), ADR-0060 (Dolby Vision 5), et les trois ADR de fytroz :
  - [démarrage du lecteur Apple TV](adr/2026-11-23-fytroz-demarrage-du-lecteur-apple-tv.md) ;
  - [la chaîne VAAPI ne ramène plus le 4K en mémoire](adr/2026-11-25-fytroz-la-chaine-vaapi-ne-ramene-plus-le-4k-en-memoire.md) ;
  - [libplacebo prend le périphérique Vulkan le plus rapide](adr/2026-11-25-fytroz-libplacebo-prend-le-peripherique-vulkan-le-plus-rapide.md).
- **Contredira :**
  - ADR-0023 §1 : le défaut de l'encodeur ne sera plus « libx264 sauf demande de l'opérateur », il sera mesuré. L'ADR VAAPI de fytroz réaffirme ce §1 (« rien ne change sans l'opérateur ») : **à décider avec fytroz avant la phase 2**. Son ADR Vulkan a déjà franchi ce pas pour le tone mapping, qui est choisi par la mesure sans aucune variable.
  - ADR-0033 : `MAX_TRANSCODES` ne comptera plus des sessions, mais un budget.
- **Sources lues :**
  - `server/streaming/` : `ffmpeg.go`, `encoder.go`, `encoder_hevc.go`, `hardware_filters.go`, `vulkan_device.go`, `tonemap_dovi.go`, `plan.go`, `quality.go`, `session.go`, `manager.go`, `handler.go`, `workspace.go`, `previews.go` ;
  - côté app : `player_controller_auto.dart`, `api/playback.dart`, `playback_capabilities.dart`, `direct_play_video_gate.dart`.

  Chaque chiffre est marqué *mesuré* (avec sa source) ou *estimé*.

## 0. Décisions (Tsuky, 2026-11-25)

1. **La mesure décide de l'encodeur.** Sans `VIDEO_ENCODER`, le serveur essaie libx264 et chaque encodeur matériel qui fonctionne, et le planificateur choisit par session. `VIDEO_ENCODER` devient un forçage. Ce choix contredit l'ADR-0023 §1 et ce que réaffirme l'ADR VAAPI de fytroz. L'ADR de la phase 2 le dit.
2. **Périmètre :** tout le côté serveur, du lot rapide de Tsuky jusqu'à la phase 5. Les changements de contrat qu'elles imposent vont jusqu'au modèle Dart et à `api_contract_test.dart` (ADR-0051). L'UI du client (mention dans le menu, `chooseAutoSource`) et les phases 6 à 8 viennent après.
3. **Le lot de fytroz** (HDR10 par libplacebo sur le circuit) reste à fytroz : il a la machine pour le mesurer.
4. **Pistes audio :** une petite machine en publie 2 (la piste choisie et la VO), une grosse jusqu'à 8.
5. **Auto ou manuel, vu par le serveur :** c'est le client qui dit `auto=1` quand l'Auto choisit. Sans ce paramètre (clients actuels, choix manuel), le barreau demandé est servi tel quel, avec un `capacity_warning` s'il est trop lourd. Un client déjà installé ne voit donc jamais sa qualité baisser. Ce point remplace le `manual=1` des phases 3 et 4.

## 1. Pourquoi

Le transcodage a été réglé pour une seule machine : le Xeon double socket de la prod, sans GPU. Le travail de fytroz a ouvert deux chemins GPU, mais chacun avec son propre essai, son propre forçage et son propre repli. Hors le Vulkan, rien n'est choisi par la mesure.

| Réglage | Valeur | Pensé pour |
|---|---|---|
| Encodeur | libx264 tant que `VIDEO_ENCODER` n'est pas posé | un hôte sans GPU où x264 est plus rapide que le circuit |
| Filtres sur le circuit | seulement avec `h264_vaapi` choisi par l'opérateur (fytroz) | — |
| Périphérique de libplacebo | **mesuré au démarrage**, le plus rapide (fytroz) | toute machine : c'est le modèle à généraliser |
| Preset x264 | `veryfast` jusqu'en 1080p, `ultrafast` en 4K | des cœurs en abondance |
| Threads par session | 16, fixe (`maxEncoderThreads`, `ffmpeg.go`) | un socket de Xeon |
| Sessions simultanées | `max(NumCPU/2, 4)` (`workspace.go`), une recopie compte comme un encodage | beaucoup de cœurs ; `NumCPU` ignore un `--cpus` Docker |
| Pistes audio publiées | jusqu'à 8, toutes encodées en continu | un CPU qui ne les sent pas |
| Compose | pas de `/dev/dri` | un hôte sans GPU |

Sur toute autre machine, ces réglages font l'inverse de ce qu'il faut. Le cas de fytroz le montre : sur un i7-10700K, un 4K Dolby Vision tenait 0,6×, avec les threads à 91 % et 99 °C. Un encodeur sous 1× ne prend jamais ses 32 s d'avance. Il n'est donc jamais mis en pause, et il sature le serveur pendant toute la lecture.

**Ce qu'on veut au bout :** le serveur sait ce que sa machine tient. Il en déduit seul :
- l'encodeur ;
- la chaîne de filtres et les périphériques ;
- le preset ;
- le nombre de sessions.

Ça doit marcher avec ou sans GPU, d'un Raspberry Pi à un Xeon. Les variables d'environnement ne sont plus des réglages nécessaires, seulement des forçages.

**Le menu Qualité du lecteur reste au spectateur.** Toute l'échelle reste affichée et choisissable, comme aujourd'hui (ADR-0056 §1 : un choix dans le menu retire la main à l'Auto). Ce que le serveur sait de sa machine sert à trois choses seulement :

- **choisir la recette** d'une qualité donnée (encodeur, preset, chaîne de filtres). C'est invisible : la qualité livrée est celle demandée ;
- **guider l'Auto** : le barreau d'ouverture, et la descente quand le serveur ne suit pas ;
- **prévenir** : un barreau que le serveur ne tiendra probablement pas est marqué dans le menu (« peut saccader sur ce serveur »), mais il n'est pas retiré.

Le serveur ne baisse jamais de lui-même une qualité choisie à la main.

**Critères de réussite** (vérifiés à la phase 8) :

1. Aucune session n'est acceptée si le serveur prévoit qu'elle tiendra moins de 1,3× la vitesse de lecture.
2. Une session qui passe sous 1× plus de 20 s déclenche une action. Selon le cas : un preset plus rapide à la reprise suivante, un barreau plus bas en Auto, un avertissement en manuel. Un serveur ne reste jamais saturé jusqu'à la fin sans que personne le sache.
3. Sans aucune variable posée, un serveur avec `/dev/dri` encode sur le GPU s'il y est plus rapide, et sur le CPU sinon. C'est ce que fait déjà le Vulkan de fytroz, étendu à tout le pipeline.
4. Avec un iGPU Intel : un transcodage SDR coûte moins de 0,2 cœur, et un HDR10 ou un DV5 4K → 1080p moins de 0,3 cœur.
5. Sans GPU, sur 4 cœurs : un 4K HDR10 → 1080p tient au moins 1,3×. Sinon, l'Auto ouvre plus bas, et le barreau est marqué dans le menu avant d'être lancé.
6. La mesure du premier démarrage dure moins de 20 s et ne bloque pas l'ouverture du serveur. Les démarrages suivants ne relancent aucun essai, y compris ceux qui tournent aujourd'hui à chaque démarrage (VAAPI, Vulkan).
7. Un barreau choisi dans le menu est toujours celui qui est livré.
8. En Auto, le Direct Play est pris chaque fois que l'appareil décode le fichier et que la ligne le porte, et la recopie passe avant tout transcodage (§5).
9. En Auto, la lecture n'est jamais plus basse que ce que permettent à la fois l'appareil, la ligne et le serveur. Quand une contrainte se lève (ligne remesurée, serveur libéré), l'Auto remonte dans les délais de l'ADR-0056.
10. Le journal de chaque session nomme son pipeline complet : décodage, filtres, tone mapping et périphérique, encodeur, preset.

## 2. Ce que fytroz a posé (dans `beta`)

### Trois choix au démarrage, chacun à sa façon

| Choix | Code | Comment | Forçage | Repli si une session meurt avant son premier segment |
|---|---|---|---|---|
| Encodeur H.264 | `encoder.go` : `detectVideoEncoder`, `encoderRuns` | `auto` essaie videotoolbox, nvenc, qsv puis vaapi, et prend le **premier qui marche**, sans mesurer | `VIDEO_ENCODER` (défaut : libx264) | aucun |
| Filtres sur le circuit (VAAPI) | `hardware_filters.go` : `detectHardwareFilters`, `hardwareFilterChain` | seulement avec `h264_vaapi`. On essaie la chaîne d'une session sur une source HEVC 10 bits HDR10 générée, en SDR et en HDR | `HARDWARE_FILTERS=off` | `noteHardwareSessionDied` retire la chaîne |
| Périphérique de libplacebo (DV5) | `vulkan_device.go` : `chooseVulkanDevice`, `libplaceboRace` | **course chronométrée** d'une seconde de 720p sur chaque périphérique qui marche, le plus rapide gagne | `VULKAN_DEVICE` | `noteVulkanSessionDied` revient au rendu logiciel |

Le Vulkan est le seul de ces choix qui soit fait **par la mesure, sans variable**. Ses étapes donnent le contrat que ce plan étend à tout le pipeline (phase 1) :

1. un essai de fonctionnement ;
2. une course chronométrée ;
3. le choix ;
4. le retrait de la recette si une session meurt ;
5. un forçage par variable ;
6. une ligne de journal qui dit le choix.

Ce qui manque à ces trois mécanismes :
- ils sont séparés : trois états globaux (`atomic`), trois façons d'essayer, trois retraits ;
- aucun ne sait combien coûte une session, donc aucun ne règle l'admission ni le nombre de threads ;
- ils tournent à chaque démarrage : 3 à 4 FFmpeg pour VAAPI, 2 à 3 pour Vulkan, plus la course ;
- les deux chemins GPU ne se parlent pas. Une session DV5 passe toujours par décodage logiciel, libplacebo sur le circuit, puis libx264, même quand `h264_vaapi` est actif.

### Les mesures

**Le banc existe** (phase 0) : `server/streaming/capacity/bench/`. Il génère les trois sources de 1080p (H.264 SDR, HEVC 10 bits, HEVC 10 bits HDR10) et chiffre chaque étape par soustraction d'une ligne de base, en cœur-secondes par mégapixel·image. Pour le lancer sur une machine, sans rien installer de plus que FFmpeg :

```bash
cd server && ONYX_BENCH=1 go test ./streaming/capacity/bench -run TestReport -v -timeout 30m
```

Le tableau sort dans le journal de `-v`. Aucun chiffre du banc n'est encore reporté ici : les tableaux ci-dessous restent ceux de fytroz, la prod et l'i7 n'ont pas été passés au banc.

**Machine sans GPU, 4 cœurs, FFmpeg 6.1** : 20 s de 4K HEVC 10 bits PQ vers 1080p, en cœur-secondes par seconde de film (*mesuré*, fytroz).

| Étape | Coût |
|---|---|
| Décodage HEVC 4K | 1,63 (47 %) |
| Mise à l'échelle (swscale) | 0,17 (5 %) |
| Tone mapping zscale (Hable) | 0,76 (22 %) |
| libx264 `veryfast` | 0,88 (26 %) |
| **Total HDR10** | **3,44 → 1,1×** ; 1,27× si les images arrivent déjà en P010 |
| Total DV5 (libplacebo sur lavapipe + libx264) | 9,06 → 0,39× |

Alléger la chaîne logicielle ne rapporte presque rien (*mesuré*, fytroz) :
- deux zscale au lieu de trois : −4 % ;
- mise à l'échelle par zscale : −9 % ;
- filtre de boucle sauté : −3 %, avec une image dégradée ;
- `lut3d` : plus lent.

**Le gain sans GPU ne viendra donc pas des filtres.** Il viendra du preset, du nombre de threads, et surtout de ne pas lancer ce que la machine ne tient pas.

**i7-10700K + UHD 630 (Comet Lake), Unraid, `/dev/dri` passé** (*mesuré*, fytroz) :
- course libplacebo : 419 ms sur le circuit, contre 856 ms en logiciel ;
- épisode 4K DV5 vers l'Apple TV HD : de **0,6× à 2,1×** une fois libplacebo sur le circuit ;
- zscale seul : 3,58× en 1080p ;
- chaîne VAAPI (décodage et mise à l'échelle sur le circuit, zscale sur le CPU) : vue active, **gain non mesuré** sur un HDR10.

**Apple Silicon, 8 cœurs, 20 s de 2160p** (*mesuré*, ADR-0023, `encoder.go`) :

| Encodeur | Vitesse | Cœurs |
|---|---|---|
| libx264 `ultrafast` | 10,3× | ~5,3 |
| libx264 `veryfast` | 4,5× | ~6,8 |
| `h264_videotoolbox` | 2,2× | ~0,4 |

C'est le compromis que le planificateur doit arbitrer : le circuit coûte quatorze fois moins de CPU, mais il va deux fois moins vite.

### Ce que fytroz a écarté ou laissé ouvert, et ce que le plan en fait

| Point | Pourquoi c'est resté | Dans ce plan |
|---|---|---|
| `tonemap_vaapi` | absent sur Comet Lake (Ice Lake et plus récents seulement), refuse une source sans métadonnées de mastering | phase 6, sur une machine Ice Lake ou plus récente (N100) ; pas sur l'i7 |
| Décodage sur le circuit pour les sessions DV5 | il faut deux périphériques (VAAPI et Vulkan) dans une commande | phase 6, priorité 1 : c'est 1,63 des ~2,7 cœurs qui restent |
| HDR10 par libplacebo sur le circuit, au lieu de zscale | pas étudié | lot rapide de fytroz : aucune nouvelle infrastructure, le périphérique est déjà choisi |
| Vulkan AMD (RADV) | personne pour l'essayer | phase 6 |
| Couleurs du circuit comparées au logiciel | non faites (VAAPI et libplacebo) | phase 0 |
| Le journal ne disait pas quel tone mapping tournait (deux jours perdus) | en partie corrigé (`libplacebo renders on …`) | critère 10, dans le lot rapide |
| Défaut de `VIDEO_ENCODER` | ADR-0023 §1 maintenu | tranché (§0.1) : la mesure décide, la variable force ; fait à la phase 2 |

## 3. Architecture

Trois modules *deep*, chacun avec une interface étroite, dans un sous-package `server/streaming/capacity/` :

```
            démarrage                         /start                        pendant la lecture
               │                                 │                                 │
        ┌──────▼──────┐   profil   ┌─────────────▼────────────┐   réservation  ┌───▼──────────┐
        │   Profiler  ├───────────►│ Planner (PlanPipeline)   ├───────────────►│  Scheduler   │
        │ essais      │            │ candidats → coût → choix │                │ budget, gel, │
        │ + bancs     │◄───────────┤                          │◄───────────────┤ rétroaction  │
        └─────────────┘ correction └──────────────────────────┘  vitesse réelle└──────────────┘
```

- **`Profile`** : ce que la machine sait faire, et à quel prix. Il est construit par le `Profiler` et persisté. Il **absorbe les trois choix du §2** : l'encodeur, les filtres VAAPI et le périphérique Vulkan deviennent des capacités du profil. La rétroaction le corrige.
- **`Pipeline`** : la recette d'une session (décodage, mise à l'échelle, tone mapping, encodeur, preset, threads, périphériques). `PlanPipeline(source, barreau, caps, profil, charge)` la choisit. `BuildFFmpegArgs` ne fait plus que la rendre en arguments. `hardwareFilterChain` et la chaîne libplacebo deviennent deux rendus parmi d'autres.
- **`Scheduler`** : il réserve le coût prévu de chaque session sur chaque ressource, refuse ou dégrade quand le budget manque, gèle ce qui ne sert plus, et renvoie la vitesse réelle au profil.

Les ressources comptées :
- le **CPU**, en cœurs ;
- le **décodeur** du GPU ;
- l'**encodeur** du GPU ;
- le **calcul** du GPU (Vulkan, filtres) ;
- la **RAM** ;
- le **disque** de l'espace de travail.

## 4. La règle de l'Auto

En Auto, le lecteur livre **toujours la meilleure image possible**. Quatre choses la limitent : le fichier, l'appareil, la ligne et le serveur. Aucune n'est supposée : chacune est lue ou mesurée.

### Les entrées

| Contrainte | D'où elle vient | Ce qu'elle borne |
|---|---|---|
| **Fichier** | les pistes (`handlers/playback.go`) : codecs, résolution, HDR/DV, débit (`source_bitrate_bps`), audio | le plafond : on n'invente pas de pixels (ADR-0022) |
| **Appareil** | `PlaybackCapabilities` : ce que la puce décode en matériel, la résolution qu'elle affiche (`directPlayVideo`, `DirectPlayVideoLimits`), HDR, Dolby Vision, canaux audio. Exemple : `aetherWithoutHevc` pour l'Apple TV HD, qui lit le H.264 8 bits jusqu'en 1080p, et rien au-dessus (fytroz, 2026-11-23) | ce qui peut se lire tel quel, et la résolution utile : rien au-dessus de l'écran |
| **Ligne** | la mesure des ADR-0056 et 0065, jamais une supposition | le **débit** |
| **Serveur** | la tenue de chaque barreau et la marge du moment (phases 3 à 5) | la **résolution** et le HDR gardé, parce que le coût d'un encodage suit les pixels, presque pas le débit |

Ce dernier point manque aujourd'hui. **La ligne borne le débit, le serveur borne la résolution.** Les deux contraintes se combinent au lieu de se confondre.

Aujourd'hui, quand c'est le serveur qui ne suit pas (`encoderBehind`), l'Auto ne fait rien, et il a raison : descendre en débit ne soulage pas un encodeur. Le cas de fytroz le confirme : à 0,7×, `1080p`, `1080p-20m` et `1080p-10m` donnaient la même vitesse.

### L'ordre de préférence

Le premier choix possible gagne :

1. **Direct Play.** L'appareil décode tout en matériel (conteneur, image, son), et la ligne porte le débit du fichier. Une ligne pas encore mesurée ne l'interdit pas : la lecture démarre en Direct Play, comme aujourd'hui (ADR-0065). Le serveur ne fait rien, et l'image est l'originale.
2. **Recopie.** L'image passe telle quelle ; seuls le conteneur, et parfois le son, changent.
   - Cas typiques : un MKV ou un son DTS que l'appareil ne lit pas, ou un navigateur.
   - Quand la ligne porte le fichier, le client envoie `remux=1`, ce qui lève le plafond de 12 Mbit/s (`COPY_BITRATE_CEILING_MBPS`). Aucun client ne l'envoie aujourd'hui.
   - Le coût pour le serveur est presque nul, et l'image reste l'originale.
3. **Transcodage au plus haut** :
   - **résolution** : la plus haute qui respecte à la fois la source, l'écran de l'appareil et la tenue `ok` du serveur ;
   - **débit** : à cette résolution, le plus haut qui tient sous 80 % de la ligne (ADR-0056) ;
   - si aucun débit de cette résolution ne passe sur la ligne, on descend en résolution : une image plus fine qui coupe ne vaut rien ;
   - **le HDR est gardé** (`encode=hevc`, ADR-0106) quand l'appareil l'affiche et que le serveur tient le HEVC à ce barreau. Sinon, il est tone mappé. Aucun client n'envoie `encode=hevc` aujourd'hui.
4. **Rien ne passe** : le barreau le plus bas, avec un message qui dit ce qui limite : « connexion lente » ou « serveur occupé » (FR/EN).

### Remonter

L'Auto ne reste pas en bas une fois la cause partie :

- **ligne** : la remontée sur mesure de l'ADR-0056 §4, sans changement ;
- **serveur** : quand de la marge revient (une session se termine), `/health` annonce le barreau plus haut que le serveur tient maintenant (`suggested_quality`, phase 5). L'Auto y passe par une session préparée, sans coupure (ADR-0056) ;
- **retour au Direct Play ou à la recopie** dès qu'une mesure de la ligne montre qu'elle porte le fichier.

Les délais et l'hystérésis restent ceux de l'ADR-0056, pour éviter les allers-retours.

### Où vit la décision

- **Côté client**, dans une seule fonction pure : `chooseAutoSource(fichier, appareil, ligne, serveur)`. Elle rend `directPlay`, `copy` ou `transcode(barreau, hdr)`. La ligne n'est connue que du client, comme dans l'ADR-0056.
- Elle remplace les choix aujourd'hui dispersés, qui appellent chacun `qualityForSourceHeight` de leur côté :
  - `serverQualityForUndecodableVideo` (`direct_play_video_gate.dart`, fytroz). Son comportement est repris tel quel : sur une Apple TV HD, un fichier HEVC ouvre directement la session du serveur, sans essai de Direct Play ;
  - `player_controller_direct_play_gate.dart` ;
  - `player_controller_dolby_vision.dart` ;
  - `player_controller_rescue.dart` ;
  - `player_controller_tracks.dart` ;
  - `auto_quality.dart`.

  Un guard test interdit ensuite de choisir une source ailleurs.
- **Le serveur donne les faits** (tenue des barreaux, marge, suggestion), pas la décision.
- **Testée en table**, avec une ligne par cas réel :
  - Apple TV HD + 4K HEVC HDR → transcodage H.264 SDR en 1080p, jamais plus haut ;
  - Apple TV HD + 1080p H.264 8 bits → Direct Play ;
  - webOS + MKV DTS → recopie ;
  - Android 4K HDR sur une ligne à 5 Mbit/s ;
  - serveur 4 cœurs sans GPU, occupé ;
  - iGPU libre ;
  - ligne pas encore mesurée.
- **En manuel, rien de tout ça ne s'applique** (§1).

## 5. Phases

### Lot rapide (tout de suite, avant la phase 0)

Petits changements sûrs, qui ne dépendent pas du profil.

**Tsuky :**
- **Threads** : `GOMAXPROCS(0)` à la place de `NumCPU`, dans `maxEncoderThreads` (`min(16, GOMAXPROCS)`) et dans le défaut de `MAX_TRANSCODES` (`workspace.go`). `GOMAXPROCS` suit le quota cgroup depuis Go 1.25, et `go.mod` est en 1.27.
- **Session remplacée gelée tout de suite** (SIGSTOP). Elle reste servie pendant ses 30 s de grâce (ADR-0033), mais elle ne prend plus de CPU.
- **Journal** : la ligne de démarrage de chaque session nomme son tone mapping (`zscale`, `libplacebo@<périphérique>`, aucun) et son décodage (critère 10).
- **Compose** : les lignes `/dev/dri` en commentaire, prêtes à décommenter. Sans elles, même le choix Vulkan de fytroz ne voit aucun circuit.

**Fytroz :**
- **HDR10 par libplacebo quand Vulkan est sur le circuit.** Quand `vulkanOnGPU()` est vrai, une source HDR10 peut passer par la même chaîne libplacebo que le DV5, au lieu de zscale (0,76 cœur). À mesurer sur l'i7, couleurs comprises, avant de l'activer. C'est le pas le moins cher vers le critère 4.

### Phase 0 — Mesurer avant de changer

- **Un banc reproductible**, dans `server/streaming/capacity/bench/`. Il reprend les sources que les essais de fytroz génèrent déjà (`hardwareProbeSampleArgs`, HEVC 10 bits marqué BT.2020 PQ avec `setparams`) et y ajoute :
  - 1080p H.264 SDR ;
  - 1080p HEVC 10 bits ;
  - 4K HEVC 10 bits HDR10 ;
  - un vrai extrait DV5, fourni à la main (impossible à synthétiser).
- **Temps CPU réel** de chaque session au journal : `ProcessState.SysUsage()` à la sortie, `/proc/<pid>/stat` pendant.
- **Ligne de base** sur trois machines :
  - la prod (Xeon) ;
  - l'i7-10700K + UHD 630 de fytroz, avec et sans `VIDEO_ENCODER=auto` ;
  - une machine 4 cœurs bridée (`docker --cpus=4` sur la prod, sans `/dev/dri`).
- **Les vérifications ouvertes de fytroz** :
  - gain de la chaîne VAAPI sur un HDR10 4K (vitesse et cœurs) ;
  - SDR 4K avec processeur presque au repos ;
  - couleurs du circuit comparées image par image au rendu logiciel, pour VAAPI comme pour libplacebo.

**Sortie :** un tableau du coût par étape et par machine dans ce document, et la ligne de base de chaque critère du §1.

### Phase 1 — Le profil matériel

**Inventaire**, sans rien lancer de lourd :
- cœurs réellement disponibles (`GOMAXPROCS(0)`) ;
- RAM disponible (limite cgroup, sinon `/proc/meminfo`) ;
- architecture et modèle du processeur ;
- périphériques : `/dev/dri/renderD*`, `/dev/nvidia*`, la liste Vulkan (`listVulkanDevices`, `parseVulkanDevices`) ;
- FFmpeg : version, encodeurs, filtres, `hwaccels`.

**Registre unique des essais.** Le contrat est celui du Vulkan de fytroz (§2) : essai, course, choix, retrait, forçage, journal. On y range ce qui existe :
- `encoderRuns` ;
- `detectHardwareFilters` (et sa troisième commande, qui dit si le circuit décode le HEVC 10 bits) ;
- `libplaceboRunsOn` et `libplaceboRace` ;
- `libplaceboUsable`.

Les globaux atomiques de chaque fichier deviennent des champs du `Profile`. Les morceaux de commande (`hardwareDecodeArgs`, `vulkanInitArgs`, `hardwareFilterChain`) restent dans leurs fichiers et servent au rendu de la phase 2.

**Bancs.** Quelques secondes par étape, en priorité basse, sur les sources de la phase 0. Le modèle est la course de fytroz (une seconde de 720p par périphérique). Pour chaque chemin qui marche, on mesure son débit en images par seconde, converti en coût par seconde de film :

| Étape | Variantes mesurées |
|---|---|
| Décodage | H.264 1080p, HEVC 10 bits 4K ; sur le CPU, et avec chaque `hwaccel` qui marche |
| Mise à l'échelle | swscale, `scale_vaapi`, `scale_cuda` |
| Tone mapping | zscale ; libplacebo sur chaque périphérique Vulkan ; `tonemap_vaapi` |
| Encodage 1080p et 720p | libx264 en `veryfast`, `superfast` et `ultrafast` ; chaque encodeur matériel |

On extrapole le reste (autres résolutions au prorata des pixels, *estimé*), puis la rétroaction corrige (phase 5).

**Cache.** Le profil est écrit dans `data/` en JSON, avec une empreinte : modèle du CPU, quota, périphériques, version de FFmpeg, version des pilotes, version du profil. On remesure si l'empreinte change, ou sur demande de l'administrateur. Un démarrage normal ne relance ni les essais VAAPI ni la course Vulkan (critère 6).

**Démarrage non bloquant.** Tant que le profil n'est pas prêt, on garde le comportement actuel, choix de fytroz compris. Les bancs ne tournent jamais pendant une session.

**Forçages.** `VIDEO_ENCODER`, `HARDWARE_FILTERS`, `VULKAN_DEVICE` et `MAX_TRANSCODES` gardent leur sens et passent avant la mesure.

**Sortie :** un `Profile` testé en table avec des profils fictifs :
- Pi 4 ;
- N100 ;
- i7 + UHD 630 ;
- Xeon sans GPU ;
- carte NVIDIA.

Les tests de fytroz (`hardware_filters_test.go`, `vulkan_device_test.go`) restent verts. Aucun changement de comportement à cette phase.

### Phase 2 — Le planificateur de pipeline

- **Décision de départ.** `PlanVideo` garde sa décision copier ou encoder : la recopie reste toujours le premier choix.
- **Recettes.** Si l'image doit être encodée, `PlanPipeline` **énumère les recettes valides** en combinant :
  - le décodage : CPU ou GPU ;
  - la mise à l'échelle : CPU ou GPU ;
  - le tone mapping : aucun, zscale, libplacebo sur un périphérique, ou `tonemap_vaapi` ;
  - l'encodage : x264 avec son preset, ou un encodeur matériel.

  Les recettes de fytroz deviennent des cas de cette énumération :
  - la chaîne VAAPI : décodage, mise à l'échelle et encodage sur le circuit, zscale sur le CPU ;
  - la chaîne DV5 : décodage sur le CPU, libplacebo sur le circuit, x264.
- **Coût.** Chaque recette a un coût prévu par ressource, tiré du profil.
- **Règle de choix** :
  1. éliminer ce qui ne tient pas 1,5× avec la charge actuelle (1,5× pour qu'une session repartie de zéro après un seek reprenne de l'avance) ;
  2. parmi le reste, s'il y a de la marge, prendre la meilleure image : x264 `veryfast` plutôt que le matériel, comme l'ADR-0023 l'avait mesuré ;
  3. sans marge, prendre la recette qui épargne la ressource la plus rare.

  Ça généralise à tout le pipeline le « le plus rapide gagne » que fytroz applique au périphérique Vulkan.
- **Refactor** :
  - `TranscodeOptions` perd `Encoder`, `HEVCEncoder` et `HardwareFilters` au profit d'un seul `Pipeline` ;
  - `usesHardwareFilters()` et les tests `encoder.surface` deviennent des lectures du pipeline ;
  - `ffmpeg.go` fait 769 lignes, près de la limite de 800 (ADR-0052) : le rendu du pipeline part d'abord dans son propre fichier.
- **Threads.** Le `-threads` vient du pipeline : la part de cœurs réservée, au plus `GOMAXPROCS`.
- **ADR.** Une ADR décrit le profil, le planificateur, et l'écart à l'ADR-0023 et à l'ADR VAAPI de fytroz, si la décision du §2 va dans ce sens.

**Sortie :** des tests en table, une ligne par couple (machine fictive, cas). Deux tests de non-régression :
- sur le Xeon, la commande produite reste identique à l'actuelle ;
- sur l'i7 avec `VIDEO_ENCODER=h264_vaapi`, elle reste celle de fytroz.

### Phase 3 — Admission et budget

**Statut :** faite sur `tsuky` le 2026-11-25, sans vraie machine (ADR [budget et admission](adr/2026-11-25-tsuky-budget-et-admission.md)). Écarts à ce qui suit :
- le client dit `auto=1` quand l'Auto choisit, au lieu de `manual=1` en manuel (§0.5). Sans paramètre, le barreau demandé est servi tel quel, avec `capacity_warning: "too_heavy"` ; en Auto, `capacity_warning: "degraded"` et `requested_quality`. Capacité `transcode_capacity` dans `/api/ping` ;
- le seuil d'admission est 1,3× (critère 1), sous le 1,5× que vise le planificateur pour choisir sa recette ; la limite dure (503 `server_busy`) est « aucun barreau ne suit la lecture » (moins de 1×) ;
- aucune UI : le lecteur n'affiche pas encore l'avertissement (phase 4) ;
- **disque : reporté.** Le budget de l'espace de travail par débit n'est pas fait ; la garde `HLS_MIN_FREE_MB` reste seule ;
- « petite machine » pour l'audio : 4 cœurs ou moins, sans circuit utilisable ;
- accès des phases 4 et 5 : `SessionManager.Budget()`, `Budget.Margin`, `Budget.Load`, `capacity.SpeedUnder`.

- **Budget par ressource.** `MAX_TRANSCODES`, qui compte des sessions, laisse la place à un budget :
  - une session réserve son coût prévu ;
  - une recopie ne coûte presque rien ;
  - une session en attente (`standby`) réserve aussi ;
  - une session remplacée rend sa réservation dès qu'elle est gelée (lot rapide).
- **Une demande qui dépasse le budget** prend d'abord une recette moins chère, à qualité égale. Ensuite :
  - en **Auto**, le barreau descend ;
  - en **manuel** (le client envoie `manual=1` à `/start`), le barreau demandé est servi tel quel, et la réponse porte un avertissement (`capacity_warning`) que le lecteur affiche (FR/EN).

  Le 503 avec `Retry-After` et une raison lisible (`server_busy`) ne sert qu'à la limite dure, quand le serveur ne peut plus rien ouvrir. C'est le cas aujourd'hui avec `MAX_TRANSCODES`.
- **Aperçus** : la passe de fond prend le périphérique Vulkan des sessions (fytroz). Elle ne tourne que sur le budget libre, et se met en pause dès qu'un encodage en a besoin.
- **Audio** : le nombre de pistes publiées est plafonné selon le profil. Une grosse machine en garde 8 ; une petite en garde 2, la piste choisie et la VO. Un changement de langue, rare, relance alors une session.
- **Disque** : le budget de l'espace de travail suit le débit des sessions. La garde actuelle `HLS_MIN_FREE_MB` reste.

**Sortie :** des tests du scheduler (accepter, dégrader, refuser, geler), et un test qui ouvre deux sessions trop lourdes : la seconde est dégradée, et elle n'est pas acceptée au prix de saturer la première.

### Phase 4 — Tenue des barreaux et nouvel Auto

**Statut :** côté serveur fait sur `tsuky` le 2026-11-25, sans vraie machine (ADR [tenue des barreaux et rétroaction](adr/2026-11-25-tsuky-tenue-des-barreaux-et-retroaction.md)). Chaque barreau de `/tracks` porte `fit` (`ok`, `limite`, `trop_lourd`), calculé comme l'admission le ferait, avec les capacités que le client déclare (mêmes paramètres que `/start`). Modèle Dart `QualityTier.fit`, contrat `media_tracks.json`. Écarts :
- **pas de capacité dans `/api/ping`** : l'absence de `fit` dit déjà « rien à dire », pour un serveur plus ancien comme pour un profil pas prêt ;
- la charge comptée est celle de toutes les sessions, celles du spectateur comprises (`/tracks` n'a pas de ticket) ;
- le menu, `chooseAutoSource` et l'ADR côté client restent à faire (voir « Reste à faire » après la phase 5).

- **Tenue prévue.** `QualityLadderFor(sourceHeight)` garde toute l'échelle. Il reçoit aussi le profil et la source, et donne à chaque barreau une tenue prévue : `ok`, `limite` ou `trop_lourd`. Deux exemples de `trop_lourd` :
  - la 4K en encodage sur un 4 cœurs sans GPU ;
  - un DV5 en 1080p sur lavapipe.

  Aucun barreau n'est retiré.
- **Contrat d'API.** La réponse des pistes (`handlers/playback.go`) porte cette tenue. C'est un changement de contrat : le fichier `contract/`, le modèle Dart et `api_contract_test.dart` changent ensemble (ADR-0051), et une capacité s'ajoute dans `handlers/ping.go`.
- **Menu Qualité** : un barreau `trop_lourd` reste choisissable, avec une mention discrète (« peut saccader sur ce serveur », FR/EN). Un serveur plus ancien n'envoie rien, et le menu reste celui d'aujourd'hui.
- **Auto** : `chooseAutoSource` et la règle du §4.
  - Le client envoie `remux=1`, `encode=hevc` et `manual=1` quand ils s'appliquent.
  - Les choix dispersés sont remplacés, et un guard test l'épingle.
  - Une ADR prolonge l'ADR-0056 et l'ADR Apple TV de fytroz : préférence Direct Play → recopie → transcodage, et une ligne qui borne le débit pendant que le serveur borne la résolution.

**Sortie :** les tests en table du §4 au vert. Sur un serveur plus ancien, sans tenue des barreaux, l'Auto se comporte comme aujourd'hui.

### Phase 5 — Rétroaction en continu

**Statut :** côté serveur fait sur `tsuky` le 2026-11-25, sans vraie machine (même ADR que la phase 4). Écarts et précisions :
- la correction est par classe de recette **sans le preset** (décodage, hauteur produite, tone mapping, encodeur, filtres logiciels) : une correction par preset laissait le planificateur fuir vers un preset jamais observé. Rapport borné à [0,5 ; 2,5], moyenne α = 0,25, facteur borné à [0,5 ; 3] ; un seul facteur pour la vitesse et la réservation, le plus prudent des deux signaux ;
- « preset d'abord, puis barreau » passe par un seul facteur par fichier (vitesse prévue sur vitesse vue, 20 minutes, borné à 4), que le planificateur applique : sa règle prend un preset plus rapide s'il tient, sinon l'admission fait descendre l'Auto ;
- `suggested_quality` peut valoir le barreau en cours : une recette plus légère y tient, rouvrir le même barreau suffit (vaut aussi en manuel) ;
- le retrait unifié retire aussi un encodeur du circuit choisi par la mesure ; un encodeur forcé ne l'est jamais. Raisons dans `TrialResult.Withdrawals` (`Profile.Withdrawn()`) ;
- `/health` a maintenant un contrat (`contract/hls_health.json`) et un modèle Dart (`HlsSessionHealth`), sans UI.

- **Correction du profil.** Chaque session rapporte sa vitesse réelle et son temps CPU au profil. Une correction lissée par classe de recette remplace l'estimation du banc. Deux raisons : les vrais fichiers sont plus durs que les sources synthétiques, et une machine qui chauffe ralentit (l'i7 à 99 °C).
- **Session sous 1×** pendant plus de 20 s, hors démarrage : la recette suivante pour ce fichier est plus légère (preset d'abord, puis barreau), et `/health` gagne un `suggested_quality`.
  - Aujourd'hui, le client voit `encoderBehind` mais ne fait rien, par choix, parce que ce n'est pas la ligne (`player_controller_auto.dart`).
  - Avec la suggestion du serveur, **l'Auto** peut changer de barreau sans accuser la ligne.
  - **En manuel**, la suggestion n'est qu'un message, et le spectateur garde son barreau.

  Ça étend l'ADR-0056 et demande une ADR courte.
- **Retrait des recettes qui échouent.** `noteHardwareSessionDied` et `noteVulkanSessionDied` deviennent un seul « retirer la recette du profil », valable pour toute recette dont les sessions meurent avant leur premier segment. Le profil garde la raison (l'erreur de FFmpeg), pour que l'administration la montre.

### Reste à faire (côté client, pour finir les phases 4 et 5)

Le serveur donne les faits ; rien côté app ne s'en sert encore. Sans ces points, les phases 4 et 5 ne changent rien pour le spectateur :

1. **Menu Qualité** : un barreau `QualityTier.fitTooHeavy` reste choisissable, avec une mention discrète « peut saccader sur ce serveur » / « may stutter on this server » (FR/EN). Un barreau sans `fit` s'affiche comme aujourd'hui. Afficher aussi `HlsSession.capacityWarning` (`too_heavy`, `degraded`).
2. **`chooseAutoSource`** (§4) : la fonction pure unique, avec ses tests en table et le guard test qui interdit de choisir une source ailleurs. Elle ouvre au plus haut barreau `ok` qui tient sur la ligne, et envoie :
   - `auto=1` quand l'Auto choisit ;
   - `remux=1` quand la ligne porte le fichier recopié ;
   - `encode=hevc` quand l'appareil affiche le HDR et que le serveur tient le HEVC.

   `/tracks` doit recevoir les mêmes capacités que `/start` pour que `fit` dise la recopie. Une ADR côté client prolonge l'ADR-0056 et l'ADR Apple TV de fytroz.
3. **Lecture de `suggested_quality`** (`HlsSessionHealth.suggestedQuality`) : en Auto, passer au barreau suggéré par une session préparée, sans accuser la ligne (y compris quand il vaut le barreau en cours : rouvrir) ; en manuel, un message seulement (FR/EN). L'Auto ne monte jamais au-dessus de ce que la ligne porte.

**Question ouverte pour Tsuky** (relevée en phase 2, inchangée) : le critère 4 (moins de 0,2 cœur par session sur un iGPU) contredit la règle « la meilleure image quand il y a de la marge ». Au repos, un i7 garde x264 `veryfast` et plusieurs cœurs par session ; le circuit ne gagne que faute de marge. Épargner le processeur même au repos, au prix de l'image, ou lire le critère 4 « sous charge » ?

### Phase 6 — Les chemins GPU qui manquent

Par ordre d'intérêt pour les petits serveurs :

1. **Intel, tout le pipeline sur le circuit (DV5 et HDR10).** Décodage VAAPI, puis `hwmap` vers le Vulkan déjà choisi, puis libplacebo, puis `hwmap` retour, puis `h264_vaapi`. C'est le pas que fytroz a laissé (« deux périphériques dans une commande »). Il supprime les 1,63 cœur du décodage et les 0,88 de x264 qui restent sur un DV5 à 2,1×. Il se fait sur l'i7 de fytroz. Estimation : de ~2,7 cœurs à ~0,1–0,2 (*estimé*).
2. **`tonemap_vaapi`** quand l'essai passe (Ice Lake et plus récents, dont le N100), avec métadonnées de mastering. Sinon, la recette 1. Il faut une machine pour l'essayer.
3. **AMD** : le Vulkan RADV dans l'image, pour libplacebo, en suivant le modèle de `mesa-vulkan-intel` (nom exact du paquet Alpine à vérifier). La course de fytroz le prend sans autre changement.
4. **NVIDIA** : `-hwaccel cuda`, puis `scale_cuda`, puis `h264_nvenc`, avec libplacebo sur le Vulkan NVIDIA. **Un risque à lever d'abord** : les bibliothèques du pilote NVIDIA sont compilées pour glibc alors que l'image est Alpine (musl), et rien ne dit que le FFmpeg d'Alpine a `cuvid` et `scale_cuda`. Il faudra peut-être une variante d'image Debian.
5. **ARM** :
   - Pi 4 : `h264_v4l2m2m`, à essayer ;
   - Pi 5 : pas d'encodeur H.264 matériel ;
   - RK3588 : demande un fork de FFmpeg.

   Pour l'ARM, le plan est surtout de bien régler le CPU (preset rapide, plafond de barreau) et de privilégier la recopie.
6. **QSV** : sous Linux, VAAPI couvre les mêmes circuits Intel. On ne garde qu'un seul chemin à maintenir, VAAPI, et `auto` ne propose plus QSV.

Chaque chemin arrive avec son essai et son banc dans le registre (phase 1). Le planificateur le prend sans autre changement.

### Phase 7 — Visibilité pour l'administrateur

- Une page **Transcodage** dans l'administration :
  - le profil détecté : CPU, GPU, chemins actifs et inactifs avec leur raison (le verdict des essais de fytroz, aujourd'hui seulement au journal) ;
  - la capacité estimée (« environ N flux 1080p, N flux 4K HDR ») ;
  - les sessions en cours, avec leur recette, leur vitesse et leur coût ;
  - un bouton **Remesurer**.

  C'est de l'UI : les textes sont en FR et en EN.
- `server/README.md` documente les forçages comme des forçages, plus comme des réglages.

### Phase 8 — Recette

- **Machines** : les trois de la phase 0, plus un N100 ou un Pi si possible.
- **Appareils** : une Apple TV HD (l'appareil de référence de fytroz), un téléviseur LG et un téléphone Android.
- **Vérification** : les critères du §1, et la comparaison avec la ligne de base.
- **Ensuite** : version de test, puis prod.

## 6. Ordre, dépendances, qui fait quoi

| Phase | Dépend de | Proposé pour |
|---|---|---|
| Lot rapide : threads, gel, journal, compose | rien | tsuky |
| Lot rapide : HDR10 par libplacebo sur le circuit | rien | fytroz (machine Intel) |
| Décision sur le défaut de `VIDEO_ENCODER` (§2) | phase 0 | tsuky et fytroz ensemble |
| 0 Mesurer | rien | les deux : fytroz a la machine Intel, tsuky la prod |
| 1 Profil | 0 | tsuky, avec une relecture de fytroz (on déplace ses essais) |
| 2 Planificateur | 1 | tsuky |
| 3 Admission | 2 | tsuky |
| 4 Tenue des barreaux et Auto | 2 côté serveur ; `chooseAutoSource` sans la tenue peut commencer tout de suite | tsuky (serveur et client) |
| 5 Rétroaction | 3 | tsuky |
| 6 Chemins GPU | 1 (registre d'essais) ; la recette 6.1 peut commencer avant, dans `hardware_filters.go` | fytroz, qui a le matériel et connaît ces fichiers |
| 7 Administration | 1, 3 | l'un ou l'autre |

Une fois la phase 1 posée, la phase 6 avance en parallèle des phases 2 à 5 : le registre d'essais est leur seule interface commune. Pour éviter les conflits, la phase 1 déplace les essais de fytroz **avant** que la phase 6 n'en ajoute.

## 7. Estimation de ce que ça donne

Cœurs occupés en moyenne pendant la lecture, sur une machine de 4 cœurs du calibre de celle de fytroz. Le bridage à 32 s ramène la charge moyenne au coût.

| Cas | Aujourd'hui, sans GPU | Aujourd'hui, iGPU Intel¹ | Après le plan, sans GPU | Après le plan, iGPU Intel |
|---|---|---|---|---|
| Recopie | < 0,1 | < 0,1 | < 0,1 | < 0,1 |
| 1080p H.264 → 720p | ~0,6 | ~0,1–0,2 | ~0,4 (`superfast` si besoin) | ~0,1 |
| 1080p HEVC → 1080p H.264 (Apple TV HD) | ~1,3 | ~0,1–0,2 | ~1,0 | ~0,1 |
| 4K HDR10 → 1080p | 3,44 (*mesuré*, 1,1×) | ~0,8–1 (zscale sur le CPU) ; non mesuré | ~2,9 et ≥ 1,3× (`superfast`), sinon l'Auto ouvre en 720p | ~0,1–0,2 |
| 4K DV5 → 1080p | 9,06 (*mesuré*, 0,39×) | ~2,7 (2,1× *mesuré* sur l'i7) | l'Auto ouvre en 720p ; le 1080p reste choisissable, marqué « peut saccader » | ~0,1–0,2 |
| 8 pistes audio TrueHD | quelques dixièmes de cœur | idem | 2 pistes | 2 pistes |

¹ Avec `/dev/dri` passé et `VIDEO_ENCODER=auto`, comme chez fytroz. Sans la variable, seule la ligne DV5 change : le Vulkan est choisi sans elle. Sans `/dev/dri`, le compose actuel donne la colonne « sans GPU ».

Hors les valeurs marquées *mesuré*, tout est *estimé* : la phase 0 remplacera ces estimations. Le plus gros gain sans GPU ne vient pas de la vitesse : **le serveur ne s'engage plus dans ce qu'il ne tient pas**, et c'est ce qui supprime les saccades qui touchent toutes les sessions. Fytroz l'a montré : alléger les filtres logiciels rapporte au plus 9 %.

## 8. Risques

- **Bancs trompeurs** (source synthétique trop facile, machine froide) : la phase 5 corrige, et on garde une marge de 1,5×. Le cas de l'i7 à 99 °C montre que la marge sert.
- **Pilotes GPU instables** : chaque recette a son repli, et celle qui tue des sessions est retirée. C'est le modèle de fytroz, généralisé.
- **Mauvais diagnostic** : deux jours perdus chez fytroz parce que le journal ne nommait pas la chaîne. Le critère 10 et la page d'administration y répondent.
- **Qualité d'image** : passer de x264 au matériel, ou de zscale à libplacebo, change l'image. La règle ne le fait que faute de marge, et l'administration montre la recette choisie. Les couleurs sont comparées à la phase 0.
- **Conteneur sans quota visible, ou partagé** avec d'autres services (Unraid) : la rétroaction voit la vitesse réelle, et `MAX_TRANSCODES` reste un plafond forcé.
- **Conflits entre les deux branches** : la phase 1 déplace du code que fytroz vient d'écrire. Elle se fait en un seul changement, relu par fytroz, avant que la phase 6 commence.
- **Taille des fichiers** (ADR-0052) : `ffmpeg.go` (769 lignes) et `handler.go` sont près de 800. On extrait avant d'ajouter.
