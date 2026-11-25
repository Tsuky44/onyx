# Transcodage calé sur le serveur — plan

- **Statut :** plan, rien n'est commencé. Une ADR sera écrite à la phase 2 (`docs/adr/AAAA-MM-JJ-tsuky-profil-materiel-et-planificateur.md`).
- **Date :** 2026-11-25
- **Prérequis :** la branche `fytroz` dans `beta` puis `tsuky` resynchronisée. Tsuky fait la fusion avant le début de la refonte. Le plan s'appuie sur ses quatre commits du 2026-11-25 (`hardware_filters.go`, `vulkan_device.go`) et sur ses mesures.
- **Prolonge :** ADR-0022 (échelle de débits), ADR-0056 et ADR-0065 (qualité automatique), ADR-0060 (Dolby Vision 5), les deux ADR de fytroz du 2026-11-25.
- **Contredira :** ADR-0023 §1 (le défaut de l'encodeur ne sera plus « libx264 sauf demande », il sera mesuré), ADR-0033 (`MAX_TRANSCODES` ne comptera plus des sessions, mais un budget).
- **Sources lues :** `server/streaming/` (`ffmpeg.go`, `encoder.go`, `encoder_hevc.go`, `plan.go`, `quality.go`, `session.go`, `manager.go`, `handler.go`, `workspace.go`, `previews.go`, `tonemap_dovi.go`), la branche `origin/fytroz`, `app/lib/screens/player/hooks/player_controller_auto.dart`, `app/lib/services/api/playback.dart`. Chaque chiffre est marqué *mesuré* (avec sa source) ou *estimé*.

## 1. Pourquoi

Le transcodage est réglé pour une machine : le Xeon double socket de la prod, sans GPU.

| Réglage | Valeur | Pensé pour |
|---|---|---|
| Encodeur | libx264 tant que `VIDEO_ENCODER` n'est pas posé | un hôte sans GPU où x264 est plus rapide que le circuit |
| Preset x264 | `veryfast` jusqu'en 1080p, `ultrafast` en 4K | des cœurs en abondance |
| Threads par session | 16, fixe (`maxEncoderThreads`) | un socket de Xeon |
| Sessions simultanées | `max(NumCPU/2, 4)`, une recopie compte comme un encodage | beaucoup de cœurs |
| Pistes audio publiées | jusqu'à 8, toutes encodées en continu | un CPU qui ne les sent pas |
| Barreaux proposés | toute l'échelle jusqu'à la résolution du fichier | un serveur qui tient la 4K en encodage |

Sur toute autre machine, ces réglages font l'inverse de ce qu'il faut. Le cas vu chez fytroz : un i7-10700K avec iGPU tenait 0,6× sur un 4K Dolby Vision, threads à 91 %, 99 °C. Un encodeur sous 1× ne prend jamais ses 32 s d'avance, n'est donc jamais mis en pause, et sature le serveur toute la lecture.

**Ce qu'on veut au bout :** le serveur sait ce que sa machine tient. Il en déduit seul l'encodeur, la chaîne de filtres, le preset et le nombre de sessions, avec ou sans GPU, d'un Raspberry Pi à un Xeon. Les variables d'environnement restent des forçages, plus des réglages nécessaires.

**Le menu Qualité du lecteur reste au spectateur.** Toute l'échelle reste affichée et choisissable, comme aujourd'hui (ADR-0056 §1 : un choix dans le menu retire la main à l'Auto). Ce que le serveur sait de sa machine sert à trois choses seulement :

- **choisir la recette** d'une qualité donnée (encodeur, preset, chaîne de filtres) : invisible, la qualité livrée est celle demandée ;
- **guider l'Auto** : barreau d'ouverture, descente quand le serveur ne suit pas ;
- **prévenir** : un barreau que le serveur ne tiendra probablement pas est marqué dans le menu (« saccades probables sur ce serveur »), pas retiré.

Le serveur ne baisse jamais de lui-même une qualité choisie à la main.

**Critères de réussite** (vérifiés à la phase 8) :

1. Aucune session n'est acceptée si le serveur prévoit qu'elle tiendra moins de 1,3× la vitesse de lecture.
2. Une session qui passe sous 1× plus de 20 s déclenche une action (preset plus rapide à la reprise suivante ; en Auto, barreau plus bas ; en manuel, un avertissement), jamais un serveur saturé jusqu'à la fin sans que personne le sache.
3. Sans aucune variable posée, un serveur avec `/dev/dri` encode sur le GPU s'il y est plus rapide, et sur le CPU sinon.
4. Avec un iGPU Intel : un transcodage SDR coûte moins de 0,2 cœur, un HDR10 4K → 1080p moins de 0,3 cœur.
5. Sans GPU, 4 cœurs : un 4K HDR10 → 1080p tient au moins 1,3×. Sinon l'Auto ouvre plus bas, et le barreau est marqué dans le menu avant d'être lancé.
6. La mesure du premier démarrage dure moins de 20 s et ne bloque pas l'ouverture du serveur. Les démarrages suivants ne mesurent rien.
7. Un barreau choisi dans le menu est toujours celui qui est livré.
8. En Auto, le Direct Play est pris chaque fois que l'appareil décode le fichier et que la ligne le porte, et la recopie passe avant tout transcodage (§4).
9. En Auto, la lecture n'est jamais plus bas que ce que permettent à la fois l'appareil, la ligne et le serveur. Quand une contrainte se lève (ligne remesurée, serveur libéré), l'Auto remonte dans les délais de l'ADR-0056.

## 2. Ce qu'on sait déjà (mesures de fytroz)

4 cœurs sans GPU, FFmpeg 6.1, 4K HEVC 10 bits PQ → 1080p H.264. Coût en cœurs occupés par seconde de film (*mesuré*) :

| Étape | Coût |
|---|---|
| Décodage HEVC 4K | 1,63 |
| Mise à l'échelle (swscale) | 0,17 |
| Tone mapping zscale | 0,76 |
| libx264 `veryfast` | 0,88 |
| **Total HDR10** | **3,44 → 1,1×** |
| Total Dolby Vision 5 (libplacebo sur lavapipe) | 9,06 → 0,39× |

Sur l'i7-10700K avec UHD 630 : le DV5 passe à 2,1× une fois libplacebo sur le circuit (*mesuré*), et zscale seul tient 3,58× en 1080p (*mesuré*).

Leçon de fytroz, reprise ici : deux jours perdus parce que le journal ne disait pas quelle chaîne tournait. **Chaque session journalisera son pipeline complet** (décodage, filtres, tone mapping, encodeur, preset, périphérique).

## 3. Architecture

Trois modules *deep*, chacun avec une interface étroite, dans un sous-package `server/streaming/capacity/` :

```
            démarrage                         /start                        pendant la lecture
               │                                 │                                 │
        ┌──────▼──────┐   profil   ┌─────────────▼────────────┐   réservation  ┌───▼──────────┐
        │   Profiler  ├───────────►│ Planner (PlanPipeline)   ├───────────────►│  Scheduler   │
        │ inventaire  │            │ candidats → coût → choix │                │ budget, gel, │
        │ + bancs     │◄───────────┤                          │◄───────────────┤ rétroaction  │
        └─────────────┘ correction └──────────────────────────┘  vitesse réelle└──────────────┘
```

- **`Profile`** : ce que la machine sait faire et à quel prix. Construit par le `Profiler`, persisté, corrigé par la rétroaction.
- **`Pipeline`** : la recette d'une session (décodage, mise à l'échelle, tone mapping, encodeur, preset, threads, périphériques). `PlanPipeline(source, barreau, caps, profil, charge)` la choisit. `BuildFFmpegArgs` ne fait plus que la rendre en arguments.
- **`Scheduler`** : réserve le coût prévu de chaque session sur chaque ressource, refuse ou dégrade quand le budget manque, gèle ce qui ne sert plus, et renvoie la vitesse réelle au profil.

Les ressources comptées : **CPU** (en cœurs), **décodeur du GPU**, **encodeur du GPU**, **calcul du GPU** (Vulkan, filtres), **RAM**, **disque** de l'espace de travail.

## 4. La règle de l'Auto

En Auto, le lecteur livre **toujours la meilleure image possible**. Ce qui la limite, ce sont quatre choses : le fichier, l'appareil, la ligne et le serveur. Aucune n'est supposée : chacune est lue ou mesurée.

### Les entrées

| Contrainte | D'où elle vient | Ce qu'elle borne |
|---|---|---|
| **Fichier** | les pistes (`handlers/playback.go`) : codecs, résolution, HDR/DV, débit (`source_bitrate_bps`), audio | le plafond : on n'invente pas de pixels (ADR-0022) |
| **Appareil** | `PlaybackCapabilities` : ce que la puce décode en matériel, la résolution qu'elle affiche (`directPlayVideo`), HDR, Dolby Vision, canaux audio | ce qui peut se lire tel quel, et la résolution utile (rien au-dessus de l'écran) |
| **Ligne** | la mesure des ADR-0056 et 0065, jamais une supposition | le **débit** |
| **Serveur** | la tenue de chaque barreau et la marge du moment (phases 3 à 5) | la **résolution** et le HDR gardé, car le coût d'un encodage suit les pixels, presque pas le débit |

Le dernier point est ce qui manque aujourd'hui. **La ligne borne le débit, le serveur borne la résolution.** Les deux se combinent au lieu de se confondre. Aujourd'hui, quand c'est le serveur qui ne suit pas (`encoderBehind`), l'Auto ne fait rien, à raison : descendre en débit ne soulage pas un encodeur.

### L'ordre de préférence

Le premier choix possible gagne :

1. **Direct Play.** L'appareil décode tout en matériel (conteneur, image, son) et la ligne porte le débit du fichier. Une ligne pas encore mesurée ne l'interdit pas : la lecture démarre en Direct Play, comme aujourd'hui (ADR-0065). Le serveur ne fait rien, et l'image est l'originale.
2. **Recopie** (l'image passe telle quelle, seuls le conteneur et parfois le son changent). Cas typiques : un MKV ou un son DTS que l'appareil ne lit pas, un navigateur. Le client envoie `remux=1` quand la ligne porte le fichier, ce qui lève le plafond de 12 Mbit/s (`COPY_BITRATE_CEILING_MBPS`). Aucun client ne l'envoie aujourd'hui. Le coût serveur est presque nul, et l'image reste l'originale.
3. **Transcodage au plus haut** :
   - **résolution** = la plus haute qui respecte à la fois la source, l'écran de l'appareil et la tenue `ok` du serveur ;
   - à cette résolution, **le plus haut débit** qui tient sous 80 % de la ligne (ADR-0056) ;
   - si aucun débit de cette résolution ne passe sur la ligne, on descend en résolution : une image plus fine qui coupe ne vaut rien ;
   - **le HDR est gardé** (`encode=hevc`, ADR-0106) quand l'appareil l'affiche et que le serveur tient le HEVC à ce barreau ; sinon il est tone mappé. Aucun client n'envoie `encode=hevc` aujourd'hui.
4. **Rien ne passe** : le barreau le plus bas, avec un message qui dit qui limite (« connexion lente » ou « serveur occupé », FR/EN).

### Remonter

L'Auto ne reste pas en bas une fois la cause partie :

- **ligne** : la remontée sur mesure de l'ADR-0056 §4, sans changement ;
- **serveur** : quand de la marge revient (une session se termine), `/health` annonce le barreau plus haut que le serveur tient maintenant (`suggested_quality`, phase 5). L'Auto y passe par une session préparée, sans coupure (ADR-0056) ;
- **retour au Direct Play ou à la recopie** dès qu'une mesure de la ligne montre qu'elle porte le fichier.

Les délais et l'hystérésis restent ceux de l'ADR-0056, pour éviter un va-et-vient.

### Où vit la décision

- **Côté client**, dans une seule fonction pure : `chooseAutoSource(fichier, appareil, ligne, serveur)`, qui rend `directPlay`, `copy` ou `transcode(barreau, hdr)`. La ligne n'est connue que du client, comme dans l'ADR-0056.
- Elle remplace les choix aujourd'hui dispersés, qui appellent chacun `qualityForSourceHeight` de leur côté :
  - `serverQualityForUndecodableVideo` (`direct_play_video_gate.dart`) ;
  - `player_controller_direct_play_gate.dart` ;
  - `player_controller_dolby_vision.dart` ;
  - `player_controller_rescue.dart` ;
  - `player_controller_tracks.dart` ;
  - `auto_quality.dart`.

  Un guard test interdit ensuite de choisir une source ailleurs.
- **Le serveur donne les faits** (tenue des barreaux, marge, suggestion), pas la décision.
- **Testée en table**, avec une ligne par cas réel :
  - Apple TV HD + 4K HEVC HDR ;
  - webOS + MKV DTS ;
  - Android 4K HDR sur une ligne à 5 Mbit/s ;
  - serveur 4 cœurs sans GPU occupé ;
  - iGPU libre ;
  - ligne pas encore mesurée.
- **En manuel, rien de tout ça ne s'applique** (§1).

## 5. Phases

### Phase 0 — Mesurer avant de changer

- Un banc reproductible : `server/streaming/capacity/bench/` génère ses sources avec FFmpeg (1080p H.264 SDR, 1080p HEVC 10 bits, 4K HEVC 10 bits HDR10), plus un vrai extrait DV5 fourni à la main (impossible à synthétiser).
- Le journal de chaque session dit son pipeline complet, sa vitesse et son temps CPU réel (`ProcessState.SysUsage()` à la sortie, `/proc/<pid>/stat` pendant).
- Ligne de base sur trois machines : la prod (Xeon), l'i7-10700K + UHD 630 de fytroz, et une machine 4 cœurs bridée (`docker --cpus=4` sur la prod, sans `/dev/dri`).

**Sortie :** un tableau coût par étape et par machine dans ce document, et la ligne de base de chaque critère du §1.

### Phase 1 — Le profil matériel

**Inventaire** (sans rien lancer de lourd) :
- cœurs réellement disponibles : `runtime.GOMAXPROCS(0)`, qui suit le quota cgroup du conteneur depuis Go 1.25 (`go.mod` est en 1.27). `runtime.NumCPU()`, utilisé aujourd'hui, ignore un `--cpus` Docker ;
- RAM disponible (limite cgroup, sinon `/proc/meminfo`) ;
- architecture, modèle du processeur ;
- périphériques : `/dev/dri/renderD*`, `/dev/nvidia*`, Vulkan (déjà listé par `vulkan_device.go`) ;
- FFmpeg : version, encodeurs, filtres, `hwaccels`.

**Essais de fonctionnement** : on regroupe dans un registre unique ceux qui existent déjà (`encoderRuns`, `detectHardwareFilters`, `chooseVulkanDevice`, `libplaceboUsable`) et on y ajoute ceux qui manquent. Chaque essai a le même contrat : une commande, un verdict, une raison au journal.

**Bancs** : quelques secondes par étape, en priorité basse, sur les sources de la phase 0. Pour chaque chemin qui marche, on mesure son débit en images par seconde, converti en coût par seconde de film :

| Étape | Variantes mesurées |
|---|---|
| Décodage | H.264 1080p, HEVC 10 bits 4K ; CPU, et chaque `hwaccel` qui marche |
| Mise à l'échelle | swscale, `scale_vaapi`/`scale_cuda` |
| Tone mapping | zscale, libplacebo sur chaque périphérique Vulkan, `tonemap_vaapi` |
| Encodage 1080p et 720p | libx264 `veryfast`/`superfast`/`ultrafast`, chaque encodeur matériel |

On extrapole le reste (autres résolutions au prorata des pixels, *estimé*), puis la rétroaction corrige (phase 5).

**Cache** : le profil est écrit dans `data/` (JSON), avec une empreinte : modèle CPU, quota, périphériques, version de FFmpeg, version des pilotes, version du profil. On remesure si l'empreinte change, ou sur demande de l'administrateur. Un démarrage normal ne mesure rien.

**Démarrage non bloquant** : tant que le profil n'est pas prêt, on garde le comportement actuel. Les bancs ne tournent jamais pendant une session.

**Forçages** : `VIDEO_ENCODER`, `HARDWARE_FILTERS`, `VULKAN_DEVICE` et `MAX_TRANSCODES` gardent leur sens et passent avant la mesure.

**Sortie :** `Profile` testé en table avec des profils fictifs (Pi 4, N100, i7 + UHD 630, Xeon sans GPU, carte NVIDIA). Aucun changement de comportement à cette phase.

### Phase 2 — Le planificateur de pipeline

- `PlanVideo` garde sa décision copier ou encoder (la recopie reste toujours le premier choix). Si l'image doit être encodée, `PlanPipeline` **énumère les recettes valides** : {décodage CPU ou GPU} × {mise à l'échelle CPU ou GPU} × {aucun tone mapping, zscale, libplacebo@périphérique, `tonemap_vaapi`} × {x264 et son preset, encodeur matériel}.
- Chaque recette a un coût prévu par ressource, tiré du profil.
- **Règle de choix** :
  1. éliminer ce qui ne tient pas 1,5× avec la charge actuelle (1,5× pour qu'une session repartie de zéro après un seek reprenne de l'avance) ;
  2. parmi le reste, s'il y a de la marge, prendre la meilleure image : x264 `veryfast` plutôt que le matériel, comme l'ADR-0023 l'avait mesuré sur le Xeon ;
  3. sans marge, prendre la recette qui épargne la ressource la plus rare.

  Ça généralise le « choisir par la mesure » de fytroz (périphérique Vulkan) à tout le pipeline.
- **Refactor** : `TranscodeOptions` perd `Encoder`, `HEVCEncoder` et `HardwareFilters` au profit d'un seul `Pipeline`. `ffmpeg.go` fait 769 lignes sur `fytroz`, près de la limite de 800 (ADR-0052). Le rendu du pipeline part donc d'abord dans son propre fichier.
- Le `-threads` vient du pipeline : la part de cœurs réservée, au plus `GOMAXPROCS`. Le 16 fixe disparaît.
- Une ADR décrit le profil, le planificateur et l'écart à l'ADR-0023.

**Sortie :** tests en table, une ligne par couple (machine fictive, cas). Sur le Xeon, la commande produite reste identique à l'actuelle : test de non-régression.

### Phase 3 — Admission et budget

- `MAX_TRANSCODES` (nombre de sessions) laisse la place à un **budget par ressource** :
  - une session réserve son coût prévu ;
  - une recopie ne coûte presque rien ;
  - une session en attente (`standby`) réserve aussi ;
  - une session remplacée est **gelée tout de suite** (SIGSTOP) et rend sa réservation. Elle reste servie pendant ses 30 s de grâce (ADR-0033).
- **Une demande qui dépasse le budget** prend d'abord une recette moins chère, à qualité égale. Ensuite :
  - en **Auto**, le barreau descend ;
  - en **manuel** (le client envoie `manual=1` à `/start`), le barreau demandé est servi tel quel, et la réponse porte un avertissement (`capacity_warning`) que le lecteur affiche (FR/EN).

  Le 503 avec `Retry-After` et une raison lisible (`server_busy`) ne sert qu'à la limite dure, quand le serveur ne peut plus rien ouvrir. C'est le cas aujourd'hui avec `MAX_TRANSCODES`.
- **Aperçus** : la passe de fond ne tourne que sur le budget libre et se met en pause dès qu'un encodage en a besoin.
- **Audio** : le nombre de pistes publiées est plafonné selon le profil (8 sur une grosse machine, 2 sur une petite : la piste choisie et la VO). Le changement de langue rare relance alors une session.
- **Disque** : le budget de l'espace de travail suit le débit des sessions, la garde actuelle `HLS_MIN_FREE_MB` reste.

**Sortie :** tests du scheduler (accepter, dégrader, refuser, geler), et un test qui ouvre deux sessions trop lourdes : la seconde est dégradée, pas acceptée en saturant la première.

### Phase 4 — Tenue des barreaux et nouvel Auto

- `QualityLadderFor(sourceHeight)` garde toute l'échelle. Il prend aussi le profil et la source, et donne à chaque barreau une **tenue prévue** (`ok`, `limite`, `trop_lourd`). Exemples de `trop_lourd` : la 4K en encodage sur un 4 cœurs sans GPU, ou un DV5 en 1080p sur lavapipe. Aucun barreau n'est retiré.
- La réponse des pistes (`handlers/playback.go`) porte cette tenue. C'est un changement de contrat : fichier `contract/`, modèle Dart et `api_contract_test.dart` dans le même changement (ADR-0051), plus une capacité dans `handlers/ping.go`.
- **Menu Qualité** : un barreau `trop_lourd` reste choisissable, avec une mention discrète (« peut saccader sur ce serveur », FR/EN). Un serveur plus ancien n'envoie rien : le menu reste celui d'aujourd'hui.
- **Auto** : `chooseAutoSource` et la règle du §4. Le client envoie `remux=1`, `encode=hevc` et `manual=1` quand ils s'appliquent. Les choix dispersés sont remplacés et un guard test l'épingle. Une ADR prolonge l'ADR-0056 : préférence Direct Play → recopie → transcodage, et la ligne qui borne le débit pendant que le serveur borne la résolution.
- **Sortie :** les tests en table du §4, au vert. Sur un serveur plus ancien (sans tenue), l'Auto se comporte comme aujourd'hui.

### Phase 5 — Rétroaction en continu

- Chaque session rapporte sa vitesse réelle et son temps CPU au profil. Une correction lissée par classe de recette remplace l'estimation du banc : les vrais fichiers sont plus durs que les sources synthétiques, et une machine qui chauffe ralentit (le cas à 99 °C).
- **Session sous 1×** pendant plus de 20 s hors démarrage : la recette suivante pour ce fichier est plus légère (preset, puis barreau). La réponse de `/health` gagne un `suggested_quality`. Aujourd'hui le client voit `encoderBehind` mais ne fait rien, par choix, car ce n'est pas la ligne (`player_controller_auto.dart`) ; avec la suggestion du serveur, **l'Auto** peut changer de barreau sans accuser la ligne. **En manuel**, la suggestion n'est qu'un message, et le spectateur garde son barreau. Ça étend l'ADR-0056 et demande une ADR courte.
- Une recette qui fait mourir des sessions est retirée du profil, comme fytroz l'a fait pour la chaîne VAAPI et pour Vulkan, mais en généralisé.

### Phase 6 — Les chemins GPU qui manquent

Par ordre d'intérêt pour les petits serveurs :

1. **Intel et AMD, HDR entièrement sur le circuit** : `tonemap_vaapi` quand l'essai passe (Ice Lake et plus récents, dont le N100) ; sinon décodage VAAPI → `hwmap` vers Vulkan → libplacebo → `hwmap` retour → `h264_vaapi`, pour le HDR10 comme pour le DV5. Sinon la chaîne hybride de fytroz reste le repli. C'est ce qui fait passer le HDR de ~0,8–2,7 cœurs à ~0,1–0,2 (*estimé*). Fytroz l'a explicitement remis à plus tard.
2. **AMD** : le Vulkan RADV dans l'image, pour libplacebo (nom exact du paquet Alpine à vérifier).
3. **NVIDIA** : `-hwaccel cuda` + `scale_cuda` + `h264_nvenc`, avec libplacebo sur le Vulkan NVIDIA. **Risque à lever d'abord** : les bibliothèques du pilote NVIDIA sont compilées pour glibc et l'image est Alpine (musl), et rien ne dit que le FFmpeg d'Alpine a `cuvid`/`scale_cuda`. Il faudra peut-être une variante d'image Debian.
4. **ARM** :
   - Pi 4 : `h264_v4l2m2m`, à essayer ;
   - Pi 5 : pas d'encodeur H.264 matériel ;
   - RK3588 : demande un fork de FFmpeg.

   Le plan pour l'ARM est surtout de bien régler le CPU (preset rapide, plafond de barreau) et de privilégier la recopie.
5. **QSV** : sous Linux, VAAPI couvre les mêmes circuits Intel. On ne garde qu'un seul chemin à maintenir, VAAPI, et QSV n'est plus proposé par `auto`.

Chaque chemin arrive avec son essai de fonctionnement et son banc (phase 1). Le planificateur le prend sans autre changement.

### Phase 7 — Visibilité pour l'administrateur

- Une page **Transcodage** dans l'administration :
  - le profil détecté (CPU, GPU, chemins actifs et inactifs avec leur raison) ;
  - la capacité estimée (« environ N flux 1080p, N flux 4K HDR ») ;
  - les sessions en cours avec leur recette, leur vitesse et leur coût ;
  - un bouton **Remesurer**.

  C'est de l'UI, donc les textes sont en FR et en EN.
- `docker-compose.yml` : les lignes `/dev/dri` (et NVIDIA) en commentaire, prêtes à décommenter. `server/README.md` documente les forçages.

### Phase 8 — Recette

Sur les trois machines de la phase 0, plus un N100 ou un Pi si possible, et sur une Apple TV HD, un téléviseur LG et un téléphone Android : les critères du §1, et la comparaison avec la ligne de base. Ensuite, version de test, puis prod.

## 6. Ordre, dépendances, qui fait quoi

| Phase | Dépend de | Proposé pour |
|---|---|---|
| Lot rapide (threads ← `GOMAXPROCS`, gel des sessions remplacées, `/dev/dri` commenté dans le compose) | rien | tsuky, tout de suite : ne touche pas aux fichiers de fytroz |
| 0 Mesurer | fusion de `fytroz` | les deux : fytroz a la machine Intel |
| 1 Profil | 0 | tsuky |
| 2 Planificateur | 1 | tsuky |
| 3 Admission | 2 | tsuky |
| 4 Tenue des barreaux et Auto | 2 (côté serveur) ; `chooseAutoSource` sans la tenue peut commencer tout de suite | tsuky (serveur et client) |
| 5 Rétroaction | 3 | tsuky |
| 6 Chemins GPU | 1 (registre d'essais) | fytroz, qui a le matériel et connaît `hardware_filters.go` |
| 7 Administration | 1, 3 | l'un ou l'autre |

Les phases 6 et 2 à 5 avancent en parallèle une fois la phase 1 posée, car le registre d'essais est leur seule interface commune.

## 7. Estimation de ce que ça donne

Cœurs occupés en moyenne pendant la lecture (le bridage à 32 s ramène la charge moyenne au coût). Sur une machine de 4 cœurs du calibre de celle de fytroz :

| Cas | Aujourd'hui sans GPU | Après le plan, sans GPU | Après le plan, iGPU Intel |
|---|---|---|---|
| Recopie | < 0,1 | < 0,1 | < 0,1 |
| 1080p H.264 → 720p | ~0,6 | ~0,4 (`superfast` si besoin) | ~0,1 |
| 1080p HEVC → 1080p H.264 (Apple TV HD) | ~1,3 | ~1,0 | ~0,1 |
| 4K HDR10 → 1080p | 3,44 (*mesuré*, 1,1×) | ~2,9, ≥ 1,3× (`superfast`) ; sinon l'Auto ouvre en 720p | ~0,1–0,2 |
| 4K DV5 → 1080p | 9,06 (*mesuré*, 0,39×) | l'Auto ouvre en 720p ; 1080p reste choisissable, marqué « peut saccader » | ~0,1–0,2 |
| 8 pistes audio TrueHD | quelques dixièmes de cœur | 2 pistes | 2 pistes |

Hors les deux valeurs mesurées, tout est *estimé* ; la phase 0 remplacera ces estimations. Le plus gros gain sans GPU ne vient pas de la vitesse : **le serveur ne s'engage plus dans ce qu'il ne tient pas**, et c'est ce qui supprime les saccades générales.

## 8. Risques

- **Bancs trompeurs** (source synthétique trop facile, machine froide) : la phase 5 corrige, et on garde 1,5× de marge.
- **Pilotes GPU instables** : chaque recette a son repli, et celle qui tue des sessions est retirée (modèle de fytroz).
- **Qualité d'image** : passer de x264 au matériel change l'image. La règle ne le fait que faute de marge, et l'administration montre la recette choisie.
- **Conteneur sans quota visible ou partagé** avec d'autres services (Unraid) : la rétroaction voit la vitesse réelle, et `MAX_TRANSCODES` reste un plafond forcé.
- **Taille des fichiers** (ADR-0052) : `ffmpeg.go` et `handler.go` sont près de 800 lignes. On extrait avant d'ajouter.
