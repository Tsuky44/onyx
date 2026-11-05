# Recette sur Apple TV : lecteur natif

À passer sur une vraie Apple TV 4K (le simulateur n'a aucun décodeur matériel et prend toujours la
route logicielle). Réglages > Lecture > Lecteur Apple TV : **Natif**. Décisions : ADR-0105 (lecteur et
parité), ADR-0106 (transcodage), ADR-0107 (sous-titres image) ; étude : `spike-native-tv-player.md` ;
inventaire : `native-tv-parity.md`. Cocher chaque ligne ; une ligne ratée devient une issue.

## Lecture
- [ ] Un film H.264 ou HEVC SDR démarre dans le lecteur tvOS (barre de transport, panneau d'infos
  avec titre, synopsis et affiche).
- [ ] La reprise repart à la bonne position ; la progression remonte au serveur.
- [ ] Vitesse, format d'image et qualité (Auto, Direct, échelle) : la coche suit, l'effet est visible.
- [ ] Les secondes lignes s'affichent dans la barre : « Le fichier tel quel », « S'adapte à la
  connexion » puis « Auto · 1080p », la description de chaque format d'image, le codec et les canaux
  de chaque piste audio. Un menu ouvert ne se referme pas tout seul pendant la lecture.
- [ ] Un seul menu Vitesse (celui d'Onyx), pas de bouton image dans l'image.
- [ ] Le panneau d'infos ne propose plus « Lire depuis le début » ; « Épisode précédent » et
  « Épisode suivant » y sont sur un épisode et ouvrent le bon épisode.

## Transport et gestes
- [ ] Pause et lecture au bouton central, au Centre de contrôle et à l'app Remote de l'iPhone :
  l'état tient, la progression suit. Aucun `transport` parasite au chargement, à un changement
  d'audio ou de qualité, au remplissage du tampon ni à la fin de l'épisode (journal
  `Lecteur natif`).
- [ ] Sauts de 10 s, balayage au trackpad : la lecture repart au bon endroit.
- [ ] Chapitres : un fichier avec chapitres montre le panneau Chapitres d'AVKit (titres, ou
  « Chapitre N ») et les graduations sur la barre, en Direct Play comme en HLS ; un saut de chapitre
  tombe au début du chapitre.
- [ ] Minuterie de veille depuis le menu natif : 15 minutes, puis « reste … » qui décompte ; « À la
  fin de l'épisode » et « Après N épisodes » sur une série ; « Désactivée » l'arrête ; l'échéance met
  en pause et l'annonce s'affiche.
- [ ] « Vous regardez encore ? » ne tombe pas quand on s'est servi de la télécommande pendant les
  épisodes ; sans aucun geste, il tombe après le nombre d'épisodes réglé.

## Épisodes et questions
- [ ] Épisode suivant au générique : la proposition réduit l'image dans un coin, montre l'image,
  le titre, le compte à rebours qui se vide, « Lire » et « Plus tard ». « Lire » enchaîne ; à zéro,
  l'enchaînement se fait seul.
- [ ] « Plus tard » : la proposition part, le compte à rebours ne repart pas, l'action « Épisode
  suivant » reste ; un changement d'audio ou de qualité ne la repropose pas. Menu sur la
  proposition ne ferme pas le lecteur.
- [ ] Minuterie « À la fin de l'épisode » active : la proposition apparaît sans compte à rebours.
- [ ] Un geste de la télécommande pendant le compte à rebours le gèle (l'anneau disparaît).
- [ ] Les questions arrivent en alertes, Menu vaut la réponse indiquée : « Vous regardez encore ? »
  (Continuer, Quitter), langue manquante au lancement et à l'épisode suivant (Continuer, Attendre,
  Fermer), saison suivante (Demander : annonce « Demande envoyée » ; Épisode suivant ; Non merci),
  épisode à venir, lecture reprise sur un autre appareil (Reprendre ici, Quitter).
- [ ] Deux questions de suite (langue puis saison suivante) : la seconde s'affiche après la première.

## Panneau d'infos
- [ ] Onglet **Épisodes** : saisons en boutons, épisodes en cartes avec image, durée et
  avancement ; l'épisode en cours est marqué et prend le focus ; changer de saison recharge la liste ;
  choisir un épisode l'ouvre.
- [ ] Onglet **Regarder ensemble** : « Démarrer une séance » montre le code, les participants
  (« Hôte », « (vous) ») et « Quitter la séance ».
- [ ] Onglet **Stats** : chemin de lecture, codecs, décodeurs, images par seconde, images perdues,
  débits, format vidéo, sortie audio et conteneur, mis à jour chaque seconde.
- [ ] Le focus entre dans chaque onglet et y reste pendant les mises à jour (compte à rebours,
  annonce).

## Regarder ensemble à deux appareils
Une Apple TV en Natif, un second appareil (iPhone, Android ou web) dans la même séance :
- [ ] Pause et lecture à la télécommande : le second appareil suit, et la pause tient (la séance ne
  relance pas l'Apple TV).
- [ ] Saut de 10 s et balayage : le second appareil suit ; même chose en HLS (qualité transcodée).
- [ ] Une pause, un saut et un changement de vitesse sur le second appareil : l'Apple TV suit.
- [ ] Les annonces (« alex a mis en pause », attente d'un participant) apparaissent en haut de
  l'image, sous la barre de transport, au-dessus des sous-titres image.
- [ ] La séance change de média : l'Apple TV ouvre le nouveau dans le lecteur natif.

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

## Transcodage des sources sans décodeur matériel (ADR-0106)
Pour chacun : VC-1, MPEG-2 entrelacé, AV1 (SDR, puis HDR10 sur une Apple TV sans décodeur AV1),
H.264 10 bits (Hi10P), un H.264 entrelacé :
- [ ] Lancé du début : l'écran natif apparaît, en HLS (journal `HLS … depuis 0s`,
  `engine.videoRoute == .remoteBypass`), image propre (pas de peigne sur l'entrelacé), son correct.
- [ ] L'AV1 HDR10 garde le HDR (téléviseur en HDR10) ; les autres restent en SDR.
- [ ] Une recherche dans la partie déjà encodée reste dans le natif ; une recherche loin devant
  reconstruit la session et rend l'interface Onyx (repli `hlsOffset`), sans couper la lecture.
- [ ] Changer de langue audio rouvre la session sur la bonne langue.
- [ ] Une reprise (40 min) : l'interface Onyx, à la bonne position (repli `hlsOffset`).

## Sous-titres image (ADR-0107)
- [ ] PGS d'un remux en Direct Play : image nette, bien placée, sans texte OCR par-dessus.
- [ ] Rip recadré (canevas 1920×1080 sur une image 1920×800) et VobSub d'un DVD 16:9 : bien placés.
- [ ] Choisir une piste PGS dans le menu AVKit, sans piste active puis avec une piste texte active ;
  « Désactivé » ; la mémoire de série la reprend à l'épisode suivant.
- [ ] Format d'image Original puis Remplir : l'image et les PGS suivent.
- [ ] Barre de transport visible : noter si les PGS passent sous la barre (pas encore remontés).
- [ ] Une piste PGS en HLS : incrustée dans l'image, le natif tient.

## Repli sur l'interface Flutter
- [ ] Un film en codec logiciel dont la session transcodée échoue (serveur arrêté pendant
  l'ouverture) : le fichier s'ouvre tel quel dans l'interface Onyx, jamais de roue AVKit.
- [ ] Une piste texte en lecture HLS (qualité transcodée) : sous-titre peint par Flutter ; repasser
  sur « Désactivé » rend l'écran natif.
- [ ] Démarrage bloqué : l'interface Onyx avec « Réessayer ».
- [ ] Réglage sur **Onyx** : le lecteur Flutter, comme avant.
