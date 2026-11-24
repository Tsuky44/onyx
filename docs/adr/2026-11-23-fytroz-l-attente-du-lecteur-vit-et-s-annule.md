# ADR 2026-11-23 (fytroz) : L'attente du lecteur vit toujours, et s'annule d'un geste

- **Statut :** accepté. Le Dart est analysé et testé. **Rien n'a été regardé sur une vraie Apple TV**
  (voir « À vérifier ») : la cause de l'anneau figé est lue dans le code, pas mesurée.
- **Date :** 2026-11-23
- **Portée :** `screens/player/widgets/onyx/onyx_loading_ring.dart`,
  `widgets/player_status_panels.dart` (`PlayerLoadingSpinner`, `playerAwaitsPicture`),
  `hooks/use_player_exit.dart` (nouveau, `PlayerExit`),
  `player_screen.dart`, `player_screen_chrome.dart` (`_awaitingPicture`, `_buildLoadingRing`),
  `player_screen_flow.dart` (`_leavePlayer`, `_syncProgressOnExit`), `theme/app_motion.dart`
  (`waitTurn`, `waitBreath`).
- **Contredit** le point 3 de l'[ADR-0140](0140-l-attente-du-lecteur-prend-la-place-de-la-lecture.md)
  et pose une exception à l'[ADR-0101](0101-le-mode-leger-reconnait-les-ordinateurs-modestes.md).

## Contexte

Retour d'usage sur Apple TV, dont une Apple TV HD : « Le truc de chargement ne tourne pas, fais en
sorte de régler ça et de faire une belle annulation quand ça tourne. » La dictée avait écrit
« annulation » pour « animation », ce que l'utilisateur a précisé le 2026-11-24 : la demande était
un anneau qui tourne, et bien.

À la lecture du code :

- **L'anneau était immobile par construction.** `OnyxLoadingRing` arrêtait son animation sous
  `AppMotion.reduced(context) || LiteScope.of(context)` (ADR-0140, point 3). Or une Apple TV HD est
  en mode léger d'office (`LiteMode.isModestHardware`, modèle `AppleTV5,`), et toute Apple TV l'est
  si on l'a choisi, ou accepté quand l'app l'a proposé (ADR-0141). Les autres attentes de l'app
  (`LoadingView`, le cercle de Material) tournent en mode léger : seule celle du lecteur se figeait,
  devant un écran noir, là où l'on attend le plus longtemps.
- **Deux anneaux au démarrage.** L'écran en posait un pour la première image et un pour le tampon ;
  entre l'appel de lecture et la première image, le moteur se dit aussi « en tampon », et les deux
  étaient là, décalés. Immobiles, ils se confondaient ; en mouvement, on aurait vu deux têtes.
- **Quitter pendant une attente attendait le serveur.** `_leavePlayer` envoyait la dernière position
  et ne dépilait l'écran qu'à la réponse : écran figé si le serveur tarde, ce qui est justement la
  raison d'une attente. Un second Retour dépilait alors le lecteur, puis, la réponse venue, l'écran
  d'en dessous.
- **Rien n'arrêtait ce qui était en vol.** Le contrôleur ne s'arrête qu'à `_disposed`, posé à la
  destruction de l'écran, après la réponse du serveur et le fondu de sortie. Une session HLS
  demandée avant le Retour (changement de qualité, saut, repli en transcodage) s'ouvrait donc après
  lui, par `session.open(…, play: true)` : du son sans image.

## Décision

1. **L'anneau vit toujours.** Le mode léger et « réduire les animations » changent sa façon de
   vivre, pas le fait qu'il vive.
   - Là où le verre ne floute pas (`glassBlurs` : mode léger, web), il tourne encore et son ombre
     floue devient un halo plat de deux traits. C'est le flou, refait à chaque image, qui coûte à
     une puce A8, pas un arc de 52 points.
   - Sous « réduire les animations » du système, il ne tourne plus : il respire, par l'opacité
     seule (`AppMotion.waitBreath`).
   - Il arrive en fondu, pour qu'un tampon vide d'un quart de seconde ne clignote pas.
   - Le dessin écoute l'animation (`repaint:`) : rien n'est reconstruit, un `RepaintBoundary`
     l'isole, et son opacité passe par l'alpha des traits, sans `saveLayer`.

   *Contredit l'ADR-0140 (point 3) parce qu'*un anneau d'attente immobile se lit comme un plantage,
   et que sur l'appareil visé il l'était toujours. L'ADR-0101 voulait qu'une animation sans fin
   s'arrête en mode léger parce qu'elle redessine sa zone tant que l'écran reste ouvert ; celle-ci
   ne dure que le temps d'attendre, quand rien d'autre ne se dessine, et s'allège au lieu de
   s'arrêter. `repeating_animations_respect_lite_mode_test.dart` porte l'exception, avec sa raison.
2. **Un seul anneau**, posé sous `_awaitingPicture` (`playerAwaitsPicture`), et pas sur le panneau
   d'un démarrage qui a dépassé son délai. Une première image n'est pas un film qui joue : le
   moteur d'Apple peut l'annoncer avant que la lecture ne parte. Passé la première image, c'est
   donc le moteur seul qui dit l'attente, que le démarrage soit fini ou non.
3. **Quitter pendant une attente n'attend rien** (`PlayerExit`, `playerExitCannotWait` : une
   attente, ou un démarrage inachevé, première image ou pas). Dans l'ordre : annuler ce que le
   contrôleur a en vol (`cancelStreams` : il s'arrête à son prochain point de contrôle, la session
   HLS et le ticket sont rendus tout de suite), arrêter le moteur, dépiler, et laisser la position
   partir derrière. Devant un film qui joue, l'ordre d'avant est gardé (la position, puis l'écran) :
   l'accueil qu'on rejoint relit le serveur. Dans les deux cas la sortie n'a lieu qu'une fois, et un
   échec ne la retient pas. Le fondu de sortie est celui de la page, qui part maintenant dans le
   geste.

### Écarté

- **Un bouton « Annuler » sous l'anneau d'un téléviseur**, après quatre secondes sans image. Livré
  le 2026-11-23 sur la lecture « annulation » de la demande, retiré le lendemain : elle disait
  « animation ». Retour quitte déjà tout de suite pendant une attente (point 3), et une capsule de
  plus sous l'anneau prenait la télécommande à qui ne l'avait pas demandée.
- **Dépiler d'abord dans tous les cas.** L'écran d'où l'on vient relit le serveur à la sortie du
  lecteur : devant un film qui joue, il relirait la position d'il y a cinq secondes, ou un épisode
  pas encore marqué vu.

## Conséquences

- En mode léger, une animation sans fin tourne pendant l'attente du lecteur. C'est voulu ; son coût
  sur une puce A8 reste à mesurer.
- Un lancement annulé avant sa première image envoie encore sa position de reprise au serveur, comme
  avant (`PlaybackReporter.finish`), alors qu'il n'a rien lu.
- Deux gardes du contrôleur manquent encore, hors de la portée de cet ADR : `startPlayback` relance
  le battement après ses `await` sans relire `_disposed`, et `switchToDirectPlay` ouvre avec
  `play: true` sans le relire non plus. La destruction de l'écran, qui suit maintenant le Retour
  d'un fondu, les arrête.
- Épinglé par `onyx_player_loading_and_preview_test.dart` (l'anneau vit), `player_exit_test.dart`
  (la sortie) et `player_wait_guard_test.dart` (l'écran passe bien par ces règles : il ne se monte
  pas en test).

## À vérifier

- Sur une Apple TV HD : l'anneau tourne sans à-coup pendant toute l'ouverture d'un fichier, et le
  journal dit bien `LiteMode: actif`. S'il se fige encore, la cause est ailleurs (fil principal
  occupé par le moteur) et cet ADR ne la règle pas.
- Avec « Réduire les animations » de tvOS : l'anneau respire.
- Menu pendant un lancement, un changement de qualité et un tampon vide : l'écran part tout de
  suite, aucun son ne suit, et le serveur ne garde ni session HLS ni lecture « en cours ».
- Que Menu arrive bien en `popRoute` : une touche Retour (Échap, B d'une manette) lecteur garé ne
  quitte toujours pas le lecteur (`player_screen_remote.dart`, dernière marche de `PlayerKeyBack`),
  ce que le banc de test fait, lui.
