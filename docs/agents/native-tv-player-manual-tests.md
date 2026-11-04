# Recette sur Apple TV : lecteur natif

À passer sur une vraie Apple TV 4K (le simulateur n'a aucun décodeur matériel et prend toujours la
route logicielle). Réglages > Lecture > Lecteur Apple TV : **Natif**. Décision : ADR-0105 ; étude :
`spike-native-tv-player.md`. Cocher chaque ligne ; une ligne ratée devient une issue.

## Lecture
- [ ] Un film H.264 ou HEVC SDR démarre dans le lecteur tvOS (barre de transport, panneau d'infos
  avec titre, synopsis et affiche).
- [ ] La reprise repart à la bonne position ; la progression remonte au serveur.
- [ ] Vitesse, format d'image et qualité (Auto, Direct, échelle) : la coche suit, l'effet est visible.

## Audio
- [ ] Le menu **Audio** (menu personnalisé de la barre) liste les langues du serveur ; changer de
  langue relance sans repasser par Flutter et la coche suit.

## Sous-titres
- [ ] Les pistes texte d'un MKV apparaissent dans le menu Sous-titres d'AVKit (journal moteur
  `native subtitles: prepare=true … textTracks=N`).
- [ ] Choisir une piste (sans piste active, puis avec une active) : elle s'affiche, tient, et la
  mémoire de série la reprend à l'épisode suivant. « Désactivé » coupe et se mémorise.
- [ ] Changer d'audio ou de qualité : le sous-titre tient, pas de double sous-titre.

## Actions contextuelles
- [ ] « Passer l'intro » apparaît pendant l'intro seulement et saute le segment.
- [ ] « Épisode suivant » apparaît au générique seulement et enchaîne : nouvel `AVPlayer`, pas de
  retour au SDR si le suivant est HDR.

## Menu et focus
- [ ] Menu sur la télécommande ferme le lecteur natif et revient à l'écran précédent de Flutter.
- [ ] Focus au retour : il reste vide 1 à 3 s ; noter si un appui est perdu pendant ce temps, puis
  qu'une flèche déplace bien le focus.

## HDR et Dolby Vision (protocole de la Q4 du spike)
Réglages tvOS : Format SDR 4K, Adapter le contenu à la plage dynamique et à la fréquence d'images
activés ; téléviseur HDR10 et Dolby Vision. Pour un remux HDR10, un Dolby Vision 8.1, un Dolby
Vision 5 :
- [ ] Le téléviseur bascule (bandeau HDR10 ou Dolby Vision) ; journal `DisplayCriteria … apply` sans
  `-11868` ni `-15628` ; `engine.videoRoute == .loopback`.
- [ ] Menu rend le SDR ; l'épisode suivant ne repasse pas par le SDR.
- [ ] Match Content désactivé : image convertie en SDR, sans écran noir.

## Repli sur l'interface Flutter
- [ ] Un film en codec logiciel (VC-1, MPEG-2, H.264 10 bits) : l'interface Onyx apparaît, image et
  son corrects, jamais de roue AVKit.
- [ ] Une piste PGS choisie dans Onyx : l'écran Flutter revient sans couper la lecture ; repasser
  en texte rend l'écran natif.
- [ ] Une piste texte en lecture HLS (qualité transcodée) : sous-titre peint par Flutter.
- [ ] Réglage sur **Onyx** : le lecteur Flutter, comme avant.
