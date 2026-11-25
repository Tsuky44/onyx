# libplacebo prend le périphérique Vulkan le plus rapide du serveur

- **Statut :** accepté, **vu sur un vrai circuit** le 2026-11-25 (i7-10700K, Intel UHD Graphics 630,
  Unraid) : la course a donné 419 ms au circuit contre 856 ms au rendu logiciel, le circuit a été
  retenu, et l'épisode 4K profil 5 qui tenait 0,6× a été encodé à **2,1×** la vitesse de lecture.
  L'utilisateur ne signale plus aucun défaut de lecture sur l'Apple TV HD.
- **Date :** 2026-11-25
- **Portée :** `server/streaming/vulkan_device.go` (nouveau), `tonemap_dovi.go`
  (`libplaceboUsable`, `ResolveToneMapping`), `ffmpeg.go`, `previews.go`, `session.go` (`watch`),
  `handler.go`, `server/main.go`, `server/Dockerfile` (`mesa-vulkan-intel`), `server/README.md`.
- **Prolonge** l'[ADR-0060](0060-dolby-vision-profil-5-sans-decodeur.md), qui installait le Vulkan
  logiciel pour l'hôte sans GPU.

## Contexte

Sur un i7-10700K avec `/dev/dri` passé au conteneur, un épisode 4K en Dolby Vision profil 5 lu
sur une Apple TV HD donnait `encodé à 0.6× la vitesse de lecture`, tous les threads vers 91 %,
100 °C. Deux jours ont été perdus à chercher du côté de VAAPI et de zscale, parce que ce fichier
était pris pour du HDR10.

`ps` et `top -H` dans le conteneur, pendant la lecture, ont tranché :

```
ffmpeg … -init_hw_device vulkan -ss 1536 -i "…S01 E05 [FR+EN] WEBDL-2160p.mkv" …
  -vf scale=…,libplacebo=tonemapping=hable:… -c:v libx264 …
```

avec seize threads `llvmpipe-N` en tête. C'est le chemin de l'ADR-0060 : la couche RPU du profil 5
n'est lue que par libplacebo, et libplacebo veut Vulkan. L'image n'avait que le Vulkan logiciel,
et `-init_hw_device vulkan` prend le périphérique 0.

Reproduit sur 4 cœurs, FFmpeg 6.1, 20 s de 4K HEVC 10 bits vers 1080p :

| Chaîne | Cœur-secondes par seconde de film | Vitesse |
|---|---|---|
| zscale (HDR10), libx264 | 3,44 | 1,10× |
| libplacebo sur lavapipe (profil 5), libx264 | 9,06 | 0,39× |

L'ADR-0060 l'avait mesuré : 30 images par seconde sur seize threads, avec les réglages allégés.
C'est à peine le temps réel sur une machine saine, et en dessous sur une machine qui chauffe.

## Décision

1. **Le pilote Vulkan d'Intel entre dans l'image** (`mesa-vulkan-intel`, x86_64), à côté des pilotes
   VAAPI. Sans `/dev/dri`, il ne trouve aucun périphérique.
2. **Le périphérique est choisi au démarrage, par la mesure** (`chooseVulkanDevice`). FFmpeg écrit
   la liste des périphériques en `verbose` ; chacun fait d'abord tourner le filtre d'une session
   sur deux images 10 bits. Quand plusieurs y arrivent, ils sont chronométrés sur une seconde de
   720p et **le plus rapide est retenu**, le circuit à temps égal. La commande nomme ensuite ce
   périphérique (`-init_hw_device vulkan:N`). Le choix suit donc la machine : un serveur sans
   circuit garde le rendu logiciel et tous ses cœurs sans payer la course, un serveur à beaucoup
   de cœurs dont le circuit serait plus lent garde ses cœurs.
3. **Le journal dit sur quoi le filtre tourne** : `libplacebo renders on <nom> (<type>)`, avec un
   avertissement quand c'est le rendu logiciel.
4. **Une session qui meurt sur le circuit avant son premier segment ramène le serveur au rendu
   logiciel** (`noteVulkanSessionDied`).
5. **`VULKAN_DEVICE`** nomme le périphérique (un index, ou un morceau de son nom) ; `llvmpipe`
   revient au rendu logiciel.
6. **Le choix se fait au démarrage** (`ResolveToneMapping`), plus au premier film en profil 5.

Les aperçus de la barre de lecture prennent le même périphérique.

### Écarté

- **Préférer le circuit par principe.** C'était la première version. Un circuit n'est pas plus
  rapide parce qu'il est un circuit (l'ADR-0023 l'a mesuré pour l'encodage) : la course coûte une
  seconde au démarrage des seuls serveurs qui ont le choix.
- **Décoder aussi sur le circuit pour ces sessions.** Deux périphériques dans une commande
  (VAAPI pour décoder, Vulkan pour filtrer) demandent de nommer celui des filtres ; à faire une
  fois ce premier pas vu sur une machine. Le décodage reste logiciel, l'encodage reste libx264.
- **Le pilote Vulkan d'AMD.** Même raisonnement que pour VAAPI, mais personne pour l'essayer.
- **Se passer de libplacebo.** Sans la RPU, un profil 5 sort rose et vert (ADR-0060).

## Conséquences

- Une image plus lourde du poids de `mesa-vulkan-intel`.
- Le démarrage lance deux ou trois FFmpeg de plus, et la course quand deux périphériques
  marchent : 0,8 s de rendu logiciel mesuré sur 4 cœurs.
- Sur un hôte sans GPU, rien ne change : même périphérique, même coût.
- Le coût qui reste pour un profil 5 sur un serveur Intel : décodage 4K, mise à l'échelle et
  libx264 sur les cœurs, soit ce que coûte déjà un HDR10 sans circuit, moins le tone mapping.

## Vu sur un serveur Intel

Journal du démarrage, puis de la même lecture qu'au contexte :

```
Streaming: libplacebo on Intel(R) UHD Graphics 630 (CML GT2) (integrated): 419ms for the timed run
Streaming: libplacebo on llvmpipe (LLVM 22.1.3, 256 bits) (software): 856ms for the timed run
Streaming: libplacebo renders on Intel(R) UHD Graphics 630 (CML GT2) (integrated)
Session …: 1080p encodé à 2.1× la vitesse de lecture
```

À 2,1×, l'encodeur prend ses 32 s d'avance et le serveur le met en pause : les cœurs se
reposent entre deux salves au lieu de rester saturés. Les couleurs n'ont pas été comparées image par
image au rendu logiciel ; aucune dominante n'a été signalée.

Épinglé par `server/streaming/vulkan_device_test.go`.
