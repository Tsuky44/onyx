# ADR-0127 — La lecture d'un autre appareil s'annonce en notification, et se reprend en maintenant Lecture

- **Statut :** accepté. Maquette validée par l'utilisateur (2026-11-13, piste A : « celle-là elle est
  vraiment bien »), puis étendue le même jour : « mets-le sur tout sauf téléphone », et une forme à
  elle pour le téléphone (« la 1 bis est parfaite »). Rendu vérifié sur des captures de l'app ; pas
  encore vu sur un appareil, et **l'appui maintenu n'a pas été essayé avec une vraie télécommande**.
- **Date :** 2026-11-13
- **Portée :** `widgets/global/remote_playback_notice.dart` (`RemotePlaybackNotice`),
  `widgets/global/remote_playback_banner.dart` (`RemotePlaybackBanner.notice`, `_onHoldKey`),
  `screens/home/home_screen.dart`. Retire `widgets/global/remote_playback_tv_card.dart`.

## Contexte

Quand le compte lit quelque chose sur un autre appareil, l'accueil le propose : « Lecture en cours sur
… », et de quoi reprendre ici à la même seconde (`server/handlers/playback_handoff.go`).

Sur téléviseur c'était une grande carte posée dans la page, sous le film à la une, avec un bouton bleu
« Reprendre ». Elle tenait 1040 px de large et poussait toutes les rangées de 180 px vers le bas. Un
simple appui sur lecture/pause reprenait : la touche qu'on presse sans y penser lançait une lecture.
Ailleurs, une carte opaque en bas de l'écran.

Demande de l'utilisateur, sur Apple TV : « améliore ça avec un petit design comme Apple ; pour lancer
il faut qu'on reste appuyé sur play ; il faut aussi mettre un petit texte pour que ce soit facilement
compréhensible ». Trois maquettes : **A**, une notification en haut à droite ; **B**, une pilule en bas
de l'écran ; **C**, la carte dans la page, redessinée. L'utilisateur a choisi A.

## Décision

**La lecture d'un autre appareil est une notification de verre en haut à droite de l'accueil**
(`RemotePlaybackNotice`), sous le compte, comme celles de tvOS. Elle ne déplace rien. Sur un téléphone,
elle est en bas de l'écran, sous une forme ramassée (point 7).

1. **Ce qu'elle dit.** L'affiche, « EN LECTURE SUR » et le nom de l'appareil, le titre, l'épisode et le
   temps restant, la progression. Puis, sous un filet, une ligne qui dit toujours quoi faire.
2. **Avec une télécommande, on maintient lecture/pause** (`RemotePlaybackBanner.hold`). L'anneau
   autour de la touche se remplit pendant l'appui, 900 ms, et le texte passe de « Maintenir pour
   reprendre ici » à « Continuez d'appuyer… ». Au bout, la lecture reprend. **Un appui court ne fait
   rien** : relâcher ramène l'anneau à zéro, et reprendre l'appui repart de zéro.
3. **Un relâchement suivi d'un nouvel appui dans les 40 ms est le même appui** : la télécommande du
   simulateur Apple TV coupe un appui tenu en « enfoncé, relâché, ré-enfoncé », comme pour OK
   (`TvFocusable`).
4. **Sur Apple TV, elle ne prend pas le focus.** La Siri Remote a toujours la touche ; rien d'autre ne
   reprend.
5. **Sur les autres téléviseurs, elle prend aussi le focus** (`selectable`) : toutes les télécommandes
   n'ont pas de touche lecture/pause. Bas depuis le compte y mène, OK reprend, et la ligne dit alors
   « OK pour reprendre ici ».
6. **À la souris** (ordinateur, tablette, web) : un clic sur la notification reprend, la croix
   l'écarte. La ligne dit « Reprendre ici ».
7. **Sur un téléphone, la même notification, ramassée, en bas de l'écran** (`compact`) : il n'a ni
   télécommande ni coin libre en haut à droite. Une seule hauteur, à la largeur de l'écran : le bouton
   lecture est à droite du titre, il n'y a pas de ligne de texte dessous, toucher la carte reprend et
   la croix du coin l'écarte. Maquette « 1 bis », validée le 2026-11-13 après une première piste où
   la ligne « Toucher pour reprendre ici » alourdissait la carte.
8. **Elle reste tant que l'autre appareil lit.** Le sondage de dix secondes et la relecture de la
   position au moment de reprendre ne changent pas.

### Écarté

- **B, la pilule en bas de l'écran.** Posée sur les rangées, là où l'on regarde les affiches.
- **C, la carte dans la page.** Plus basse, mais elle décale toujours les rangées.
- **Garder l'appui simple sur lecture/pause.** C'est ce que l'utilisateur ne voulait plus : une lecture
  partait d'un geste machinal.
- **Une notification focalisable sur Apple TV.** Un élément en surimpression n'est sur le chemin
  d'aucune rangée ; c'est pour cela que la carte d'avant était dans la page. La touche maintenue s'en
  passe.

## Conséquences

- **Si la Siri Remote n'envoie pas l'appui et le relâchement de lecture/pause séparément**, l'anneau ne
  se remplira pas et rien ne reprendra depuis la notification. La rangée « Reprendre la lecture » de
  l'accueil propose toujours le titre. À vérifier au premier essai sur appareil.
- **Android TV et le web des téléviseurs LG** changent aussi : la carte dans la page disparaît au
  profit de la notification, focalisable.
- **L'ordinateur et la tablette** perdent la carte du bas pour la notification du haut ; **le
  téléphone** garde la sienne en bas, redessinée.
- La carte opaque au bouton bleu (`_card`) et la carte de la page d'un téléviseur
  (`RemotePlaybackTvCard`) disparaissent : il n'y a plus qu'un dessin, sous deux formes.
- Épinglé par `test/remote_playback_notice_test.dart` : Apple TV (ni focus ni appui court, appui tenu,
  appui coupé), autre téléviseur (focus et OK), souris (clic et croix), téléphone (une hauteur, toucher
  et croix), sur les deux systèmes de navigation.
