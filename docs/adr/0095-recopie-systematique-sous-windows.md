# ADR-0095 — Recopie systématique du décodage matériel sous Windows

- **Statut :** accepté
- **Date :** 2026-10-30
- **Portée :** `app/lib/screens/player/hardware_decoding.dart`,
  `app/lib/screens/player/playback/mpv_playback_session.dart`

## Contexte

L'ADR-0019 a ouvert le décodage `d3d11va` sans copie sous Windows, puis l'a limité aux images de
1440 lignes et plus après une bande verte en bas d'un épisode 1080p (point 4). La bande est revenue,
signalée par un utilisateur sur « certains fichiers », fichier inconnu. Deux trous restaient :

- au-dessus de 1440 lignes (4K, scope), le seul garde-fou était un rognage de 8 lignes, dont
  l'ADR-0019 dit déjà qu'il ne couvre pas une bande de plusieurs dizaines de lignes ;
- sous 1440 lignes, la bascule vers la copie n'a lieu qu'après la première image : les premières
  images, et toute lecture où `hwdec-current` ou les dimensions arrivent mal, restaient sans copie.

La cause exacte n'a jamais été reproduite. Elle tient à la surface du décodeur, plus grande que
l'image, que mpv lit sans copie.

## Décision

Sous Windows, `hwdec` vaut toujours `auto-copy-safe` : décodage matériel, image recopiée, quel que
soit le fichier. La recopie ne sort que l'image utile, donc toute cette famille de défauts disparaît.
Le rognage `zeroCopyEdgeCrop`, la bascule `windowsZeroCopyUnwanted` et le rattrapage logiciel →
copie propre à Windows sont retirés : ils n'ont plus rien à rattraper.

Contredit l'ADR-0019 (points 3 et 4) parce qu'une image juste passe avant le gain processeur.

## Ce que font les autres lecteurs

- **mpv seul** (sortie `d3d11`) : `d3d11va` n'y est pas sans copie par défaut
  (`d3d11va-zero-copy=no`). Il recopie sur le GPU (`CopySubresourceRegion`) la seule zone utile
  vers une texture à la taille de l'image : pas de remplissage, et pas de passage par la mémoire
  vive.
- **L'interop `d3d11-egl`**, celle que l'ADR-0019 a débloquée pour media_kit, n'a pas cette étape :
  elle enveloppe la texture du décodeur à sa taille complète (`texdesc.Width/Height`), remplissage
  compris. mpv la désactivait d'ailleurs sous ANGLE, et c'est notre correctif binaire qui l'ouvre.
- **VLC** a eu la même ligne verte avec Direct3D11 (2016-2018) et l'a corrigée en retirant le
  remplissage des textures qu'il dessine et en rognant à l'affichage.
- **Jellyfin Media Player** (mpv) est passé en 1.6.0 au décodage matériel avec recopie par défaut,
  jugé fiable pour la quasi-totalité des utilisateurs et moins sujet aux défauts de couleur.
- **Plex HTPC** (mpv) utilise `d3d11-egl` sans copie depuis 2021 ; son forum a des signalements
  d'images teintées de vert sous Windows.

La voie qui garderait le gain de l'ADR-0019 sans la bande verte est celle de mpv seul : une copie
GPU → GPU de la zone utile dans l'interop `d3d11-egl`. Elle demande de recompiler libmpv, ce que
l'ADR-0019 a écarté ; à rouvrir si la charge processeur en 4K devient un problème.

## Conséquences

- Un 4K HDR coûte de nouveau la recopie (~24 Mo par image, ADR-0019) : charge processeur plus
  élevée sur ces fichiers. Le correctif de libmpv de l'ADR-0019 devait rester en place pour le jour où le
  sans-copie reviendrait ; il a été retiré avec le passage au libmpv officiel (ADR-0158, phase 1,
  voir la dernière révision).
- Le réglage « copie » et le réglage « auto » donnent la même valeur sous Windows.

## Révision du 2026-11-19 — les voies sans copie étudiées, la recopie reste

Relu dans le source de mpv (master) : `hwdec_d3d11egl.c`, notre interop, déclare à ANGLE la
texture du décodeur à sa taille complète (`texdesc.Width/Height`) et compte sur le recadrage des
coordonnées. `hwdec_d3d11va.c`, celui de mpv seul, recopie la zone utile (`D3D11_BOX` aux
dimensions de l'image) avec `CopySubresourceRegion1` quand `d3d11va-zero-copy=no`. C'est cette
étape qui manque à notre chemin.

Voies étudiées pour retrouver le sans-copie, toutes écartées :

- **La fenêtre mpv de l'ADR-0061 pour toutes les lectures** : bonne pour le HDR et le Dolby Vision,
  mais elle coûte la réutilisation du moteur, casse les animations (zoom d'entrée, fondus) et
  repose sur deux fenêtres synchronisées et une fonction Windows non documentée. Trop fragile pour
  le cas général.
- **Un libmpv construit par nous**, avec la recopie GPU de la zone utile ajoutée à
  `hwdec_d3d11egl.c` : solide, mais c'est une chaîne de build Windows (MinGW, FFmpeg, libplacebo) à
  maintenir en permanence.
- **`dxva2-egl`**, présent dans mpv sans correctif : il rogne bien (`StretchRect` aux dimensions de
  l'image), mais il convertit en RVB 8 bits par le pilote (plus de 10 bits ni de HDR, une matrice de
  couleurs laissée au pilote) et attend jusqu'à 8 ms par image sur le fil de rendu.

La recopie reste donc la valeur de Windows. Elle ne coûte qu'en 4K HDR. Les saccades et le
décalage du son signalés le même jour venaient du relais local (ADR-0036), pas d'elle. Seule voie
gardée ouverte, sans rien à maintenir : proposer la recopie de la zone utile à mpv lui-même. Une
fois fusionnée, les builds de shinchiro l'apporteront au prochain changement de `LIBMPV`.

## Révision du 2026-11-19 (2) — la recopie n'est plus que le chemin « Ancien » et le repli

Le sans-copie est revenu par le rendu D3D11 de libmpv 0.42.0 ([ADR-0158](0158-libmpv-officiel-et-rendu-d3d11-sous-windows.md), phase 2). La recopie `d3d11va-copy` (`auto-copy-safe`) reste, mais ne sert plus qu'à deux cas :

- le rendu **Ancien** (ANGLE), que l'utilisateur peut choisir dans le réglage « Rendu vidéo » ;
- le **repli automatique** : quand le rendu D3D11 ne montre rien ou perd son périphérique, la lecture passe sur ANGLE, et la machine retient l'échec par adaptateur et pilote.

Le défaut de tous les utilisateurs Windows est désormais **Automatique** : D3D11 → ANGLE → logiciel. Ce qui est dit plus haut de « la valeur de Windows » vaut pour ANGLE seulement. `HardwareDecoding` décide selon le chemin retenu : D3D11 → `auto-safe`, ANGLE ou chemin inconnu → `auto-copy-safe`.

Le correctif binaire de libmpv n'existe plus (phase 1) : la recopie n'a plus rien à garder en réserve.

Le statut reste « accepté » pour le rendu Ancien. Il ne sera revu que si l'ADR-0158 est acceptée.
