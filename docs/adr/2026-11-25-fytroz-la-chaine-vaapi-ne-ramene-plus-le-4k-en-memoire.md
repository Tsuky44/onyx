# La chaîne VAAPI ne ramène plus le 4K en mémoire

- **Statut :** accepté, **écrit sans le matériel**, puis vu actif sur un i7-10700K le 2026-11-25 :
  `vaapi decodes HEVC 10-bit` et `hardware filters on (vaapi)` au journal. **Son gain n'est pas
  mesuré** : la mesure qui l'a motivé était mal attribuée (voir « Ce qui était faux »).
- **Date :** 2026-11-25
- **Portée :** `server/streaming/hardware_filters.go` (nouveau), `ffmpeg.go` (`BuildFFmpegArgs`,
  `videoFilterChain`, `TranscodeOptions.HardwareFilters`), `encoder.go` (`VideoEncoder.surface`),
  `session.go` (`watch`), `handler.go`, `server/main.go`, `server/README.md`.
- **Prolonge** l'[ADR-0023](0023-encodeur-materiel-optionnel.md), dont la section « VAAPI »
  laissait la mise à l'échelle et le tone mapping sur le processeur « sans la machine pour
  l'essayer ». **Contredit l'ADR-0023** sur son §3 : avec `h264_vaapi`, le graphe de filtres n'est
  plus le même que celui des autres encodeurs.

## Contexte

Demande : lire un 4K HEVC sur une Apple TV HD sans que le serveur sature. Depuis l'ADR du
2026-11-23, cette Apple TV demande le fichier en H.264 1080p, puisque sa puce ne décode pas le
HEVC. Le serveur est un i7-10700K sous Unraid, `/dev/dri` passé au conteneur, `VIDEO_ENCODER=auto`.

C'est la première fois que le chemin VAAPI tourne sur un vrai circuit Intel. Le journal dit :

- `Streaming: video encoder h264_vaapi (hardware=true)` : l'essai du démarrage passe ;
- sur une source 3840×2160 HEVC HDR10 à 19,1 Mbit/s, `1080p encodé à 0.7× la vitesse de lecture`,
  puis la même valeur en `1080p-20m` et en `1080p-10m` ;
- le tableau de bord montre tous les threads vers 91 %, 99 °C, et encore 87 °C à 26 % de charge
  une fois la lecture arrêtée.

Un encodeur sous 1,0× ne prend jamais ses 32 s d'avance, donc n'est jamais mis en pause : le
serveur reste saturé toute la lecture, et le lecteur attend ses segments. Que le débit du barreau
ne change rien dit que l'encodeur n'est pas le goulot.

Mesuré sur 4 cœurs sans circuit vidéo, FFmpeg 6.1, 20 s de 4K HEVC 10 bits PQ à 40 Mbit/s vers
1080p, en cœur-secondes par seconde de film :

| Étape | Coût | Part |
|---|---|---|
| Décodage HEVC 4K | 1,63 | 47 % |
| Mise à l'échelle (swscale bilinéaire) | 0,17 | 5 % |
| Tone mapping (zscale, Hable) | 0,76 | 22 % |
| Encodage libx264 `veryfast` | 0,88 | 26 % |

Cette machine tient donc 1,1× tout en logiciel, et 1,27× quand les images arrivent en P010 comme
après un décodage matériel. Ce qui a été essayé pour alléger le logiciel ne change pas l'ordre de
grandeur : tone mapping en deux zscale au lieu de trois (4 % du total), mise à l'échelle par
zscale (9 %), filtre de boucle du décodeur sauté (3 %, image dégradée), table 3D `lut3d` à la
place de zscale (plus lent, les conversions de swscale coûtent plus que zscale).

## Décision

1. **Avec un encodeur qui a une surface (`h264_vaapi`), l'image reste sur le circuit.** Le
   décodage est nommé (`-hwaccel vaapi -hwaccel_output_format vaapi`) au lieu de `-hwaccel auto`,
   qui ramenait chaque image en mémoire en 4K avant le premier filtre. La mise à l'échelle passe
   par `scale_vaapi`.
2. **Une source SDR ne redescend plus.** `…,hwupload,scale_vaapi=…:format=nv12`, puis l'encodeur.
3. **Une source HDR redescend une fois, à la taille du barreau**, pour le tone mapping de
   toujours (`hdrToSDRFilter`), puis remonte : `scale_vaapi=…:format=p010le,hwdownload,
   format=p010le,<zscale>,format=nv12,hwupload`.
4. **La tête de la chaîne prend les deux sortes d'images** (`format=nv12|p010le|vaapi,hwupload`).
   Une source que le circuit ne décode pas est décodée en logiciel et envoyée, au lieu de tuer la
   session.
5. **Un essai au démarrage** (`detectHardwareFilters`) écrit une source HEVC Main 10 marquée
   BT.2020 PQ, puis lui fait traverser le périphérique, le décodage, la chaîne et l'encodeur d'une
   session, dans les deux variantes. Un échec garde les filtres logiciels et le journal dit
   pourquoi. Une troisième commande, sans la tête, dit seulement si le circuit décode le HEVC
   10 bits : elle ne décide de rien, elle renseigne.
   La source porte ses marques sur les images (`setparams`) et dans le flux (x265), pas par
   `-color_trc` sur la sortie : le FFmpeg du runner de la CI ignore cette option, et zscale refuse
   une image sans transfert connu. La première version de l'essai aurait donc refusé la variante
   HDR sur un circuit qui marche.
6. **Une session qui meurt avec cette chaîne avant son premier segment la retire** pour tout le
   serveur (`noteHardwareSessionDied`), avec l'erreur de FFmpeg au journal.
7. **`HARDWARE_FILTERS=off`** revient à la chaîne logicielle sans attendre une image du serveur.

Restent sur la chaîne logicielle : le sous-titre incrusté et le désentrelacement (images
logicielles, avant la mise à l'échelle), le Dolby Vision profil 5 (libplacebo, ADR-0060), le HDR
gardé en HEVC, et une source HDR déjà à la taille du barreau.

### Écarté

- **Le tone mapping sur le circuit (`tonemap_vaapi`).** Le README du pilote Intel 26.2.1, celui
  d'Alpine 3.24, ne donne « HDR10 TM » qu'à partir d'Ice Lake : pas sur un Comet Lake. Le filtre
  refuse aussi une source sans métadonnées de mastering. Il resterait à l'écrire pour les circuits
  plus récents, avec une machine pour l'essayer.
- **Alléger la chaîne logicielle.** Les gains mesurés vont de 3 à 9 %.
- **Changer le défaut de `VIDEO_ENCODER`.** L'ADR-0023 §1 tient : rien ne change sans l'opérateur.
- **Brider la cadence de FFmpeg (`-readrate`).** Le travail par seconde de film reste le même ;
  cela ne sauve pas une session sous 1,0×.

## Ce qui était faux

Le 0,7× du contexte ne venait pas de cette chaîne. La liste des processus pendant la lecture l'a
montré : l'épisode est un Dolby Vision profil 5, et sa session passait par `-init_hw_device vulkan`,
libplacebo sur le Vulkan logiciel et libx264, sans jamais toucher à VAAPI. Une fois cette chaîne
déployée, la même lecture a donné 0,6× : rien n'avait changé pour ce fichier. Le remède est dans
[libplacebo prend le périphérique Vulkan le plus rapide](2026-11-25-fytroz-libplacebo-prend-le-peripherique-vulkan-le-plus-rapide.md).

Ce qui a induit en erreur : l'écran de statistiques d'un autre fichier, étiqueté `hdr10`, et la
raison journalisée de la session (« client does not decode hevc, tone mapped »), qui ne dit pas
quel tone mapping est pris. Sur la même machine, le tone mapping zscale seul tient 3,58× en 1080p.

Cette chaîne reste : le circuit décode et met à l'échelle, ce qui évite de ramener 24 Mo par image
4K en mémoire. Mais aucun chiffre ne dit encore ce qu'elle rapporte sur une source HDR10.

## Conséquences

- Sans `VIDEO_ENCODER`, ou avec un autre encodeur que `h264_vaapi`, aucune commande ne change.
- Avec `h264_vaapi`, le démarrage du serveur lance trois à quatre FFmpeg de plus (une source de
  six images, puis les essais), et écrit leur verdict au journal.
- Le tone mapping reste la part du processeur pour une source HDR : 0,76 cœur-seconde par seconde
  de film sur la machine de mesure, sur une image quatre fois plus petite qu'avant.
- La mise à l'échelle du circuit n'est plus le bilinéaire de swscale : l'image peut différer
  légèrement de celle des autres encodeurs.

## À vérifier sur un serveur Intel

1. Au démarrage : `Streaming: hardware filters on (vaapi)`, et la ligne sur le décodage du HEVC
   10 bits.
2. Sur la même source 4K HDR10 : la ligne `encodé à N×` au-dessus de 1, et des threads qui se
   reposent une fois les 32 s d'avance prises.
3. L'image tone mappée a les mêmes couleurs qu'avant (les marques BT.2020 PQ doivent survivre à
   `scale_vaapi` et à `hwdownload`).
4. Une source SDR 4K : aucun filtre logiciel, processeur presque au repos.

Épinglé par `server/streaming/hardware_filters_test.go`.
