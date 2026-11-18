# ADR-0141 — Les saccades proposent le mode léger, sans l'imposer

- **Statut :** accepté. Testé en unitaire et en widget (`lite_mode_test.dart`,
  `lite_mode_suggestion_test.dart`). **Pas encore regardé sur une vraie Apple TV ni un vrai
  téléviseur Android.**
- **Date :** 2026-11-18
- **Portée :** `app/lib/theme/lite_mode.dart`, `app/lib/theme/frame_budget_watch.dart`,
  `app/lib/widgets/global/lite_mode_suggestion.dart`, la tuile du réglage
  (`settings/widgets/lite_mode_tile.dart`). Contredit en partie l'ADR-0086.

## Contexte

L'ADR-0086 donnait deux déclencheurs au mode léger en « Auto » : le matériel (Apple TV HD, téléviseur
LG, moins de 2,5 Go de mémoire…) et la mesure des images. Une fenêtre de 120 images dont 30 %
dépassaient le budget d'une image (16,7 ms à 60 Hz) suffisait : le mode léger s'activait en pleine
session, sans rien dire, et la mesure était gardée pour tous les démarrages suivants.

Sur une Apple TV 4K, que le matériel laisse complète, le mode léger finissait quand même actif. Le
retour d'usage : « les Apple TV 4K, je suis sûr que ça fonctionne super bien ». À la lecture du code,
la mesure se trompait de trois façons :

- **Elle tournait pendant un film.** L'écran d'un téléviseur passe alors à la fréquence du film
  (24 Hz), et sur tvOS le temps de dessin d'une image compte l'attente de l'écran. Le budget, calculé
  une fois au démarrage à 60 Hz, était dépassé par presque chaque image, sur une machine rapide.
- **Le budget n'avait aucune marge.** Une milliseconde de trop comptait comme une saccade, qu'on ne
  voit pourtant pas.
- **Un seul verdict, pour toujours.** Une fenêtre lente au retour du lecteur, et l'appareil était
  rangé parmi les faibles jusqu'à ce que quelqu'un aille dans les réglages.

Le mode léger a aussi un coût que la mesure ne voit pas : il retire le mouvement et le flou à quelqu'un
qui ne l'a pas demandé, et le chemin léger est moins essayé que le chemin complet (le dos de l'affiche
retournée s'y peignait en miroir).

## Décision

1. **Le matériel décide toujours seul** pour les appareils connus comme faibles (règles de l'ADR-0086
   inchangées) : sur une Apple TV HD ou un téléviseur LG, l'interface complète rame dès la première
   image.
2. **La mesure ne fait plus que proposer.** Des saccades lèvent `LiteMode.suggestion`, et
   `LiteModeSuggestion` pose une fenêtre (`OnyxDialog`) : « Passer en mode léger » (le bouton
   principal, qui a le focus) ou « Garder l'interface complète ». Une fenêtre et pas un bandeau : un
   bandeau ne prend pas le focus, la télécommande ne pourrait pas y répondre.
   - Accepter règle la préférence sur « Activé », visible comme telle dans les réglages.
   - Refuser est gardé (`lite_mode_suggestion_declined`) : la question ne revient pas. Choisir
     « Auto » de nouveau dans les réglages oublie le refus.
   - Retour ou clic à côté ne garde rien ; la question attend le prochain démarrage.
3. **La mesure est fiabilisée :**
   - elle se tait pendant un film (`PlayerPresence`) et quand l'app n'est pas au premier plan, puis
     attend 3 s après la pause (affiches redécodées, écran qui repasse à 60 Hz) ;
   - une image n'est lente qu'au-delà d'une fois et demie son budget ;
   - le budget suit la fréquence actuelle de l'écran ; une fréquence de cinéma (< 30 Hz) se juge à
     60 Hz, la cadence des pages ;
   - il faut deux fenêtres lentes, pas une.
4. **L'ancienne mesure est effacée** au démarrage (`lite_mode_measured_slow`) : les appareils qu'elle
   avait rangés en mode léger retrouvent l'interface complète, et la question leur sera posée s'ils
   saccadent vraiment.

## Conséquences

- Une Apple TV 4K, un téléviseur Android haut de gamme ou un ordinateur ordinaire gardent l'interface
  complète, sauf si leur utilisateur choisit le contraire.
- Un appareil réellement faible que le matériel ne reconnaît pas (un Raspberry Pi à 4 Go) rame
  jusqu'à la question, au lieu de basculer seul. C'est le prix d'un choix laissé à l'utilisateur.
- La raison « l'interface saccadait » disparaît du réglage : un mode léger actif l'est par le matériel
  ou par choix.

## À vérifier

- Sur une Apple TV 4K : lire un film en entier, revenir à l'accueil, et vérifier qu'aucune question
  n'apparaît et que le réglage reste « Auto » / « Inactif ».
- Sur un appareil réellement lent : que la question arrive bien, hors du lecteur, et que la
  télécommande y réponde.
