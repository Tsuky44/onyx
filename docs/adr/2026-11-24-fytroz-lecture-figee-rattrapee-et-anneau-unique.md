# Une lecture figée après sa première image se rattrape, et l'attente n'a qu'un anneau

- **Statut :** accepté. Signalé par l'utilisateur sur une Apple TV (2026-11-24) : « j'ai reculé dans
  la vidéo et ça a freeze, ça charge indéfiniment, après écran noir, obligé de revenir en arrière et
  relancer », et « rends le chargement dans le player plus fluide (l'animation) ». La cause exacte de
  la recherche qui ne se pose pas n'est **pas établie** (pas de journal de l'appareil) ; ce qui est
  établi dans le code, c'est qu'aucun rattrapage n'existait. Couvert par des tests ; **pas encore vu
  sur une Apple TV**.
- **Date :** 2026-11-24
- **Portée :** `screens/player/playback/playback_rescue.dart` (nouveau),
  `hooks/player_controller_rescue.dart` (nouveau), `hooks/player_controller_tracks.dart`
  (`_handleFailure`), `hooks/player_controller_hls.dart` (`seekToAbsoluteSeconds`,
  `seekToAbsolutePosition`), `hooks/use_player_controller.dart`, `player_screen.dart`,
  `player_screen_chrome.dart`, `widgets/player_status_panels.dart` (`PlayerLoadingSpinner`),
  `test/playback_rescue_test.dart`, `test/onyx_player_loading_and_preview_test.dart`.
- **Prolonge** l'[ADR-0140](0140-l-attente-du-lecteur-prend-la-place-de-la-lecture.md) (l'anneau).

## Contexte

Passé la première image, plus rien ne veillait sur la lecture :

- le délai de démarrage est désarmé à la première image, et son écran d'échec ne s'affichait que
  sans première image ;
- `_handleFailure` ne rattrapait qu'une source coupée (`StreamCutRecovery`) : toute autre panne du
  moteur partait au journal, sous un écran noir ;
- AetherEngine retient l'horloge sur la cible d'une recherche qui ne se pose pas et se dit « en
  tampon », sans erreur : l'anneau tournait sans fin.

L'anneau, lui, était monté à deux endroits de l'écran (démarrage, tampon). Au passage de l'un à
l'autre il repartait de zéro, les deux pouvaient se superposer, et chaque attente brève le faisait
claquer à l'écran sans fondu.

## Décision

1. **Une échelle de rattrapage, `PlaybackRescue`** : rouvrir le flux à la seconde visée, puis
   quitter le Direct Play pour le transcodage, puis l'écran d'échec (`StalledStartup`, avec
   « Réessayer »). Une recherche encore en tampon sur sa cible quinze secondes plus tard monte un
   échelon ; une panne annoncée par le moteur le monte tout de suite, et droit au transcodage quand
   il dit ne pas savoir décoder. Une lecture repartie remet l'échelle à zéro.
2. **Elle ne juge pas une ouverture en cours** : avant la première image (le délai de démarrage
   veille), pendant un changement de qualité, un échange de session HLS ou une reprise après
   coupure.
3. **Un seul anneau, qui paraît et s'efface en fondu** (`PlayerLoadingSpinner.visible`, porté par
   `_awaitingPicture`). Il reste monté le temps de sa sortie et garde son tour d'une attente à la
   suivante ; sans attente, il n'est plus monté et ne coûte rien.

### Écarté

- **Transmettre `seekEvents` d'AetherEngine par Pigeon** pour savoir qu'une recherche a échoué :
  plus juste, mais touche le pont natif des trois cibles Apple, sans appareil pour l'essayer. À
  faire si le journal montre que quinze secondes sont trop longues.
- **Un anneau natif (Core Animation)** insensible aux à-coups du fil principal : une vue de
  plateforme par-dessus la vidéo pour un indicateur.
- **Borner l'attente du point de reprise au démarrage** : le démarrage « un peu lent » n'a pas de
  cause mesurée ; la ligne `PLAYER STARTUP` du journal nomme l'étape lente.

## Conséquences

- Une recherche vraiment lente (plus de quinze secondes de tampon sur place) rouvre le flux : au
  pire, un rechargement à la seconde visée.
- Le journal client dit chaque échelon : `Player: lecture figée à Ns — flux rouvert`, `— repli HLS`,
  `— abandon`, et `Player: panne en cours de lecture` passe en erreur.
- Si le fil principal de l'Apple TV se bloque pendant l'ouverture, l'anneau saccade encore : aucune
  animation Flutter n'y échappe.
