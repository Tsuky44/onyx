# Le serveur mesure sa machine, et un planificateur choisit la recette de chaque session

- **Statut :** accepté, phases 1 et 2 du plan [transcodage adaptatif](../transcodage-adaptatif.md).
  **Écrit sans les machines** : les tests couvrent l'inventaire sur des contenus fictifs, le banc
  sur des mesures simulées, et le planificateur sur cinq machines fictives. Aucun profil n'a encore
  été mesuré sur la prod, l'i7 de fytroz ou un petit serveur.
- **Date :** 2026-11-25
- **Portée :** `server/streaming/capacity/` (nouveau : `inventory.go`, `cost.go`, `profile.go`,
  `registry.go`, `measure.go`, `profiler.go`, `planner.go`), `capacity/bench/measure.go`
  (`MeasureBackground`) ; dans `server/streaming/` : `capacity_profile.go`,
  `capacity_candidates.go`, `handler_pipeline.go`, `pipeline_render.go` (nouveaux), `ffmpeg.go`,
  `encoder.go`, `encoder_hevc.go`, `hardware_filters.go`, `vulkan_device.go`, `tonemap_dovi.go`,
  `cores.go`, `pipeline_log.go`, `handler.go` ; `server/main.go`, `server/README.md`.
- **Contredit l'ADR-0023 §1.** Le défaut de l'encodeur n'est plus « libx264 tant que l'opérateur
  n'a rien posé » : sans `VIDEO_ENCODER`, la mesure choisit. **S'écarte de l'ADR de fytroz**
  [la chaîne VAAPI ne ramène plus le 4K en mémoire](2026-11-25-fytroz-la-chaine-vaapi-ne-ramene-plus-le-4k-en-memoire.md),
  qui réaffirmait ce §1 (« rien ne change sans l'opérateur »). Décision de Tsuky du 2026-11-25
  (§0.1 du plan). L'ADR Vulkan de fytroz avait déjà franchi ce pas pour le tone mapping.
- **Prolonge** les ADR de fytroz sur VAAPI et Vulkan, dont les essais entrent dans le registre, et
  l'ADR [session remplacée gelée et threads réels](2026-11-25-tsuky-session-remplacee-gelee-et-threads-reels.md),
  dont les threads viennent maintenant de la recette.

## Contexte

Les réglages du transcodage ont été pensés pour la prod, un Xeon sans GPU : libx264 `veryfast`,
seize threads, `ultrafast` en 2160p. Ailleurs, ils font l'inverse de ce qu'il faut. Sur 4 cœurs sans
circuit, un 4K HDR10 vers 1080p coûte 3,44 cœurs et tient 1,1× (mesuré par fytroz) ; sur un N100,
la chaîne VAAPI ferait le même travail pour moins d'un cœur, mais ne tourne que si l'opérateur pose
`VIDEO_ENCODER=h264_vaapi`.

Trois choix se font au démarrage, chacun à sa façon : l'encodeur (`detectVideoEncoder`, le premier
qui marche avec `auto`), la chaîne VAAPI (`detectHardwareFilters`) et le périphérique de libplacebo
(`chooseVulkanDevice`, le plus rapide par une course). Seul le dernier est choisi par la mesure, et
tous les trois relancent leurs FFmpeg à chaque démarrage. Aucun ne sait ce que coûte une session.

## Décision

### 1. Un profil matériel, mesuré une fois

Le paquet `capacity` ne dépend pas de `streaming` ; c'est `streaming` qui lui décrit ses encodeurs
et ses filtres, et qui rend la recette en arguments.

- **Inventaire** (`ReadInventory`), sans rien lancer de lourd : cœurs (`GOMAXPROCS`), mémoire (cgroup
  v2, v1, puis `/proc/meminfo`), architecture et modèle du processeur, `/dev/dri/renderD*`,
  `/dev/nvidia*`, et ce que FFmpeg dit de lui-même (version, encodeurs, filtres, `hwaccels`). Les
  fichiers se lisent sous une racine `fs.FS` injectée : les tests décrivent un N100 bridé sans en
  avoir un.
- **Registre unique des essais** (`Registry`), sur le contrat du Vulkan de fytroz : essai, course ou
  banc, choix, retrait quand une session meurt, forçage par variable, ligne de journal. Les essais
  restent écrits dans leurs fichiers (`encoderRuns`, `resolveHardwareFilters`,
  `measureVulkanDevice`) ; leurs verdicts vont dans le profil. Les globaux de fytroz
  (`resolvedEncoder`, `hardwareFiltersOK`, `vulkanChosen`, `libplaceboOK`) sont **alimentés** par le
  profil au démarrage, et `libplaceboUsable` le **lit** une fois prêt, pour que le rendu fasse ce que
  le planificateur a prévu. `noteHardwareSessionDied` et `noteVulkanSessionDied` retirent aussi la
  recette du profil, qui garde la raison et l'écrit.
- **Banc** (`MeasureCosts`) : une seconde de 1080p par étape, en priorité basse, jamais pendant une
  session. Décodage H.264 et HEVC 10 bits, sur le processeur et par VAAPI ; swscale et
  `scale_vaapi` ; zscale et libplacebo sur le périphérique retenu ; libx264 `veryfast`,
  `superfast`, `ultrafast` ; chaque encodeur du circuit qui a passé son essai. Le coût est par
  mégapixel·image et par ressource : **CPU** (cœurs, temps processeur moins une ligne de base),
  **décodeur**, **encodeur** et **calcul** du circuit (occupation estimée par le temps écoulé moins
  la ligne de base, rapporté aux images). Ce que le banc ne mesure pas prend une table de référence
  tirée des chiffres de fytroz, ramenée à la vitesse des cœurs par l'étalon x264 `veryfast`, et
  marquée estimée.
- **Cache** : `capacity-profile.json` dans le dossier de la base. Son empreinte : modèle du
  processeur, architecture, cœurs, mémoire, nœuds de périphérique, version de FFmpeg, version du
  serveur, version du profil, et les forçages (`VIDEO_ENCODER`, `HARDWARE_FILTERS`, `VULKAN_DEVICE`,
  `VAAPI_DEVICE`). Un démarrage avec un cache valide ne relance aucun essai, ni VAAPI ni la course
  Vulkan (critère 6). `Handler.Remeasure()` refait tout, pour la future page d'administration.
- **Démarrage** : avec un cache, les choix en sont relus. Sans cache, les trois choix se font
  exactement comme avant, de façon synchrone, et le registre reprend leurs verdicts ; puis la mesure
  tourne en goroutine (`safego`). Tant qu'elle n'a pas fini, le serveur se comporte comme avant.

### 2. La mesure décide de l'encodeur (§0.1)

Sans `VIDEO_ENCODER`, libx264, libx265 et chaque encodeur du circuit que FFmpeg a compilé **et**
dont le périphérique existe sont essayés ; tous ceux qui tournent deviennent des candidats.
`VIDEO_ENCODER` (y compris `libx264` et `auto`), `HARDWARE_FILTERS`, `VULKAN_DEVICE` et
`MAX_TRANSCODES` gardent leur sens et passent avant la mesure : avec un encodeur forcé, il est le
seul candidat, libx264 seulement en repli pour ce qu'il ne sait pas faire.

### 3. Un planificateur par session

`capacity.PlanPipeline(job, profil, charge)` rend un `Pipeline` : décodage, mise à l'échelle,
tone mapping, encodeur, preset, threads, coût prévu par ressource, vitesse prévue, verdict.

- **La recopie reste décidée avant**, par `PlanVideo`, sans changement.
- **Les recettes** sont celles que le rendu sait lancer : x264 à chaque preset, chaque encodeur
  candidat, la chaîne VAAPI quand les conditions de `usesHardwareFilters` tiennent. Une commande n'a
  qu'un périphérique de filtres : un encodeur à envoi ne prend jamais un profil 5 tone mappé par
  libplacebo (le pipeline à deux périphériques est la phase 6).
- **La vitesse** est, sur chaque ressource, la part libre divisée par le coût, et le minimum sur
  toutes.
- **La règle** : éliminer ce qui tient moins de 1,5× ; avec de la marge, la meilleure image (x264 au
  preset du barreau d'abord, le circuit entre `superfast` et `ultrafast`) ; sans marge, la recette
  qui laisse le plus de sa ressource la plus tendue. Une recette « a de la marge » quand, son coût
  payé, elle laisse au moins un quart de chaque ressource qu'elle utilise. Si rien ne tient 1,5×, la
  plus rapide est rendue avec son verdict (`ok`, `limite` entre 1,0 et 1,5×, `trop_lourd`) : la
  phase 3 décidera quoi en faire.
- **La charge** est un paramètre (`capacity.Load`), nulle dans cette phase.

### 4. Le rendu

`TranscodeOptions` **garde** `Encoder`, `HEVCEncoder` et `HardwareFilters`, alimentés par le
pipeline (`withPipeline`), et gagne un champ `Pipeline` qui porte la recette et ce qui n'avait pas
de champ : le preset et les threads de libx264 (`encodeTarget`). Les vingt-cinq tests de fytroz qui
construisent des options VAAPI restent ainsi inchangés, ce qui prouve qu'ils ne sont pas affaiblis ;
les retirer aurait obligé à les réécrire autour d'un `Pipeline`. Le rendu vidéo part de `ffmpeg.go`
dans `pipeline_render.go`, la planification de `/start` dans `handler_pipeline.go` (ADR-0052).

### Écarté

- **Préférer le circuit dès qu'il tourne.** Le Mac de l'ADR-0023 le dément : le circuit coûte
  quatorze fois moins de CPU mais va deux fois moins vite, et l'image de x264 est meilleure à débit
  égal. Le circuit ne gagne que faute de marge.
- **Un preset plus lent que celui du barreau.** Le planificateur ne descend jamais sous le preset
  du barreau : la 2160p reste en `ultrafast`, choisi pour qu'une session repartie de zéro y tienne.
  C'est aussi ce qui garde la commande du Xeon identique.
- **Relire tous les globaux depuis le profil.** `SelectedVideoEncoder` et `HardwareFiltersUsable`
  sont résolus une fois par processus et lus avant que le profil existe ; le planificateur ne s'en
  sert plus une fois le profil prêt. Seul `libplaceboUsable`, que le rendu consulte à chaque session,
  lit le profil.
- **Mesurer libx265.** Deux fois plus lent que libx264, il aurait coûté plusieurs secondes de la
  mesure ; il prend la référence (2,1 × x264 `veryfast`), marquée estimée.

## Conséquences

- Sur la prod sans GPU et au repos, la commande ne change pas : le test
  `TestPlanner_XeonWithoutGPUKeepsTodaysCommand` le prouve sur les cas de `ffmpeg_test.go` et ceux
  qu'il ne couvre pas (profil 5, HDR gardé, désentrelacement, 60 i/s). Avec
  `VIDEO_ENCODER=h264_vaapi` et la chaîne utilisable, la commande reste celle de fytroz
  (`TestPlanner_ForcedVAAPIKeepsFytrozCommand`).
- Sans variable, un serveur avec `/dev/dri` peut encoder sur le circuit **quand x264 n'y tient pas
  1,5× avec marge** (le N100 sur un 4K HDR10). Au repos, un i7 à seize threads garde x264 : le
  critère 4 du plan (moins de 0,2 cœur par session sur un iGPU) ne sera tenu que sous charge, quand
  la phase 3 passera une charge non nulle. À trancher à la phase 8 si l'on veut épargner le CPU même
  au repos.
- Le premier démarrage d'une nouvelle version lance la mesure : une quinzaine de FFmpeg d'une
  seconde de film, en priorité basse.
- Le modèle de vitesse suppose qu'une session peut prendre tous les cœurs libres. Sur un Xeon à deux
  sockets, c'est optimiste ; la rétroaction (phase 5) corrigera le profil avec la vitesse réelle.
- Un retrait (chaîne VAAPI, circuit Vulkan) est maintenant écrit dans le cache : il survit au
  redémarrage, jusqu'à `Remeasure()` ou un changement d'empreinte.

## À vérifier sur une vraie machine

1. Prod : `Streaming: profil matériel prêt en N s` avec N < 20, puis, au redémarrage, `profil
   matériel lu du cache`, sans aucune ligne d'essai VAAPI ou Vulkan.
2. Les coûts du cache comparés au tableau du §2 du plan (x264 `veryfast` vers 0,018 cœur-seconde par
   mégapixel·image sur 4 cœurs).
3. i7 de fytroz sans variable : `encodeurs candidats libx264, h264_vaapi, …`, et la recette d'un 4K
   HDR10 vers 1080p (`recette décodage=…`) avec sa vitesse prévue, à comparer à la vitesse réelle de
   la session.
4. Un N100 ou un petit serveur : la chaîne VAAPI prise sans `VIDEO_ENCODER` sur un 4K HDR10.
