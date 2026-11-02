# ADR-0101 — Le mode léger reconnaît les ordinateurs modestes

- **Statut :** accepté. Prolonge l'ADR-0086.
- **Date :** 2026-11-02
- **Portée :** `theme/lite_mode.dart`, `theme/frame_budget_watch.dart`, `utils/app_platform*.dart`,
  `poster_launch_route.dart`, la page Tableau de bord et la page Statistiques des réglages, la recherche
  du catalogue.

## Contexte

Le mode léger (ADR-0086) a été pensé pour les téléviseurs et les boîtiers. Un ordinateur n'y entrait
jamais par le matériel : `isModestHardware` répondait faux hors Android, iOS et tvOS. Un PC avec un
Pentium et sans processeur graphique (Flutter dessine alors l'interface sur le processeur) ne le recevait
que par la mesure des images, dix secondes après le démarrage, soit le temps de ramer à l'ouverture.

Par ailleurs, quelques animations ignoraient le mode : le zoom de lancement depuis « Reprendre »
(`pushPosterLaunch` ne lisait que le réglage système), la pulsation « EN DIRECT » du tableau de bord (sans
fin), les barres animées des statistiques et l'élargissement du champ de recherche.

## Décision

- **Sur ordinateur, deux processeurs logiques ou moins** (Pentium ou Celeron double cœur sans
  hyper-threading) suffisent à activer le mode léger. `AppPlatform.processorCount` donne le nombre ; le
  navigateur répond 0, « inconnu », qui ne décide rien. La mémoire ne décide toujours pas sur ordinateur.
- **La mesure des images arrive plus tôt** : échauffement de 5 s (au lieu de 10) et fenêtre de 120 images
  (au lieu de 180). Un Pentium à quatre fils ou un portable sur puce intégrée datée passe par là.
- **Les animations qui y échappaient** passent par `AppMotion.reduced` / `AppMotion.move` : le zoom de
  lancement, la pulsation « EN DIRECT », les barres et jauges des statistiques et du tableau de bord, la
  largeur du champ de recherche.
- **Une animation sans fin doit le demander** : `test/repeating_animations_respect_lite_mode_test.dart`
  refuse un `.repeat(` dans un fichier qui ne lit ni `AppMotion.reduced` ni `LiteScope`.

- **Hors mode léger, moins de calques au repos** : les affiches n'ont plus d'ombre tant qu'elles ne sont
  pas pointées (une ombre transparente restait une ombre floutée à dessiner), l'affiche pointée a son
  propre calque pour que l'ombre animée ne la fasse pas redessiner, et un épisode disponible n'est plus
  enveloppé d'un filtre neutre (`test/no_idle_compositing_layer_test.dart`).

## Conséquences

- Un ordinateur modeste reçoit l'interface plate dès la première image ; les autres, après la mesure.
- Un ordinateur à deux processeurs logiques mais bien doté en graphique est tout de même allégé ; le
  réglage « Mode léger » (Désactivé) le lui rend.
- Cet ADR n'a pas été mesuré sur un vrai Pentium sans GPU : voir « À vérifier ».

## À vérifier

- Sur un PC Windows à Pentium sans GPU, en build de production : le journal dit `LiteMode: actif`, le
  défilement de l'accueil et le focus suivent la souris et le clavier, et le zoom de « Reprendre » est
  remplacé par une ouverture directe.
- Que la fenêtre de 120 images ne bascule pas par erreur un ordinateur ordinaire pendant le chargement
  de l'accueil.
