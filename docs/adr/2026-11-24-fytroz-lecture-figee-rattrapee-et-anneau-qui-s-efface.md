# Une lecture figée après sa première image se rattrape, et l'anneau d'attente s'efface

- **Statut :** accepté. Signalé par l'utilisateur sur une Apple TV (2026-11-24) : « j'ai reculé dans
  la vidéo et ça a freeze, ça charge indéfiniment, après écran noir, obligé de revenir en arrière et
  relancer », et « rends le chargement dans le player plus fluide (l'animation) ». La cause de la
  recherche qui ne se pose pas n'est **pas établie** (pas de journal de l'appareil) ; ce qui est
  établi dans le code, c'est qu'aucun rattrapage n'existait. Couvert par des tests ; **pas encore vu
  sur une Apple TV**.
- **Date :** 2026-11-24
- **Portée :** `screens/player/playback/playback_rescue.dart` (nouveau),
  `hooks/player_controller_rescue.dart` (nouveau), `hooks/player_controller_tracks.dart`
  (`_handleFailure`), `hooks/player_controller_hls.dart` (`seekToAbsoluteSeconds`,
  `seekToAbsolutePosition`), `hooks/use_player_controller.dart`, `player_screen.dart`,
  `player_screen_chrome.dart` (`_awaitingPicture`), `widgets/player_status_panels.dart`
  (`PlayerLoadingSpinner.visible`), `widgets/onyx/onyx_loading_ring.dart` (`present`, `onGone`),
  `test/playback_rescue_test.dart`, `test/onyx_player_loading_and_preview_test.dart`.
- **Prolonge** l'[ADR du 2026-11-23](2026-11-23-fytroz-l-attente-du-lecteur-vit-et-s-annule.md)
  (l'anneau vit toujours, un seul anneau).

## Contexte

Passé la première image, plus rien ne veillait sur la lecture :

- le délai de démarrage est désarmé à la première image, et son écran d'échec ne s'affichait que
  sans première image ;
- `_handleFailure` ne rattrapait qu'une source coupée (`StreamCutRecovery`) : toute autre panne du
  moteur partait au journal, sous un écran noir ;
- AetherEngine retient l'horloge sur la cible d'une recherche qui ne se pose pas et se dit « en
  tampon », sans erreur : l'anneau tournait sans fin.

L'anneau, depuis l'ADR du 2026-11-23, tourne toujours et arrive en fondu. Mais l'écran le démontait
net dès que l'attente cessait : il disparaissait d'un coup, et repartait du haut, fondu d'arrivée
compris, à l'attente suivante. Dans la suite de tampons courts qui suit une recherche, cela se lit
comme une saccade.

## Décision

1. **Une échelle de rattrapage, `PlaybackRescue`** : rouvrir le flux à la seconde visée, puis
   quitter le Direct Play pour le transcodage, puis l'écran d'échec (`StalledStartup`, avec
   « Réessayer »). Une recherche encore en tampon sur sa cible quinze secondes plus tard monte un
   échelon ; une panne annoncée par le moteur le monte tout de suite, et droit au transcodage quand
   il dit ne pas savoir décoder. Une lecture repartie remet l'échelle à zéro.
2. **Elle ne juge pas une ouverture en cours** : avant la première image (le délai de démarrage
   veille), pendant un changement de qualité, un échange de session HLS ou une reprise après
   coupure. La réouverture respecte l'intention de lecture (`wantsPlay`).
3. **L'anneau part comme il arrive.** L'écran le pose toujours et dit seulement s'il attend
   (`PlayerLoadingSpinner.visible`) : l'anneau s'efface par l'alpha de ses traits, sans cesser de
   tourner, puis se démonte (`OnyxLoadingRing.present`, `onGone`). Une attente qui reprend avant la
   fin du fondu retrouve le même anneau, sur son tour. Sans attente, rien ne tourne.
4. **Pas d'anneau sur l'écran d'échec d'une lecture figée**, comme sur celui d'un démarrage au
   délai dépassé.

### Écarté

- **Transmettre `seekEvents` d'AetherEngine par Pigeon** pour savoir qu'une recherche a échoué :
  plus juste, mais touche le pont natif des trois cibles Apple, sans appareil pour l'essayer. À
  faire si le journal montre que quinze secondes sont trop longues.
- **Un anneau natif (Core Animation)** insensible aux à-coups du fil principal : une vue de
  plateforme par-dessus la vidéo pour un indicateur.

## Conséquences

- Une recherche vraiment lente (plus de quinze secondes de tampon sur place) rouvre le flux : au
  pire, un rechargement à la seconde visée.
- Le journal client dit chaque échelon : `Player: lecture figée à Ns — flux rouvert`, `— repli HLS`,
  `— abandon`, et `Player: panne en cours de lecture` passe en erreur.
- Si le fil principal de l'Apple TV se bloque pendant l'ouverture (`AetherPlayer` est `@MainActor`),
  l'anneau saccade encore : aucune animation Flutter n'y échappe, et cet ADR ne le règle pas.
- Épinglé par `playback_rescue_test.dart` et `onyx_player_loading_and_preview_test.dart` (« il part
  en fondu, et garde son tour si l'attente reprend »). `player_wait_guard_test.dart` tient
  toujours : l'anneau n'est posé qu'une fois.

## À vérifier

- Sur une Apple TV : un retour en arrière qui fige rouvre le flux au bout de quinze secondes, et
  le journal dit quel échelon a rendu l'image.
- L'anneau pendant une recherche : une seule apparition, sans claquement entre deux tampons.
