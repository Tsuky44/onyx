# ADR-0166 — L'app de bureau fige son mouvement sans le focus et rend ses images cachées

- **Statut :** accepté. Demandé par l'utilisateur (2026-11-23) : « faire en sorte que les animations
  soient arrêtées si l'app n'est pas au premier plan, et réduire ce que l'app prend en CPU et en
  RAM ». Couvert par `test/background_motion_gate_test.dart`, `test/idle_hold_test.dart` et
  `test/reachability_sleeps_when_hidden_test.dart`. Mesuré sous Windows (voir « Mesure »).
- **Date :** 2026-11-23
- **Portée :** `widgets/global/background_motion_gate.dart` (nouveau), `utils/on_screen.dart`
  (`AppForeground.focused`), `services/player_presence.dart` (`open` observable),
  `services/background_memory_trim.dart` (nouveau), `main.dart`. Étendue le même jour (phase 1 du
  plan RAM/CPU) : `utils/idle_hold.dart` (nouveau) et `PlayerEnginePool`, `AppImageCache.configure`,
  `ServerReachability`, `scripts/perf/measure-windows.ps1` (nouveau).

## Contexte

Une partie existait : `AppForeground` coupe les sondages et les carrousels quand la fenêtre est
cachée, `ShellTabStack` suspend les animations d'un onglet caché par `TickerMode`. Restaient deux
trous.

1. **Une fenêtre sans le focus est `inactive`, pas `hidden`.** `AppForeground.visible` la compte
   comme vue (cas voulu : une partie regardée sur un second écran), et Flutter y dessine chaque
   image. Derrière un navigateur, les squelettes, la pastille « en cours », le compte à rebours et
   le carrousel de l'accueil continuaient de faire tourner le processeur et le GPU.
2. **Le cache d'images décodées monte à 300 Mo sur bureau** (`AppImageCache.configure`) et n'est
   jamais rendu : une app réduite des heures gardait ces affiches.

## Décision

1. **`BackgroundMotionGate`**, posé une fois au-dessus du `Navigator` : un `TickerMode` qui passe à
   faux quand `AppForeground.focused` l'est (état `resumed` seulement), sur bureau. Tous les
   `AnimationController` de l'app s'arrêtent d'un coup, sans toucher un widget. Comme
   `OnScreenState` lit `TickerMode`, les sondages des écrans qui l'utilisent (tableau de bord,
   demandes, serveurs, bannière de lecture à distance) se mettent en pause avec.
   Exceptions : un lecteur ouvert (`PlayerPresence.open` : le chrome se fond et se cache pendant
   qu'on regarde le film dans une autre fenêtre, figé à mi-fondu il resterait sur l'image), et tout
   ce qui n'est pas un ordinateur (sur téléphone, `inactive` veut dire fenêtre partagée ou boîte
   système, l'app est bien regardée).
2. **`BackgroundMemoryTrim`** : après 45 s sans que l'app soit visible (réduite, cachée), vide le
   cache d'images décodées. Les fichiers restent sur disque ; seul le décodage est à refaire au
   retour, ce qui coûte un éclair de vignette. Le délai évite de vider pour un aller-retour rapide.

3. **Le moteur du lecteur ne reste prêt que deux minutes** (`PlayerEnginePool.idleLimit`, tenu par
   `IdleHold`). Il était préparé trois secondes après le lancement et rendu après chaque film, puis
   gardé toute la session : contexte libmpv, fils de décodage et, après un film, surfaces vidéo.
   Passé le délai sans lecture, il est détruit ; la lecture suivante en construit un neuf, ce qui
   coûte une fraction de seconde. Deux minutes couvrent l'épisode suivant choisi à la main et le
   film lancé juste après l'ouverture.
4. **Le cache d'images décodées du bureau descend de 300 à 150 Mo** (et de 2000 à 1500 entrées).
   Les images étant décodées à la taille de leur place (ADR-0087), 150 Mo tiennent encore plusieurs
   grilles et une fiche ; les 150 Mo de plus ne servaient qu'à éviter un éclair de vignette sur un
   retour lointain.
5. **`ServerReachability` ne sonde plus une app cachée.** Elle se réveillait toutes les 45 s même
   réduite. Un appel qui échoue pendant ce temps (battement d'un film qui joue fenêtre réduite)
   déclenche toujours sa vérification, et le retour au premier plan sonde aussitôt
   (`test/reachability_sleeps_when_hidden_test.dart`).
6. **La mesure se fait par `scripts/perf/measure-windows.ps1`**, sur une build release lancée avec
   `STORE_BUILD=true` : mémoire privée, ensemble de travail et part du CPU de la machine, chaque
   seconde, sur trois scénarios automatiques (accueil, arrière-plan sans focus, réduite) et trois
   guidés (`-Guided` : défilement, lecture, après lecture). `-Baseline` compare à une série
   précédente. Les sorties vont dans `perf-out/`, ignoré par git.

## Mesure

`scripts/perf/measure-windows.ps1`, builds release `STORE_BUILD=true` de HEAD (64ed99e1) puis de ce
changement, lancées l'une après l'autre sur le même PC (16 processeurs logiques), serveur connecté,
45 s d'échauffement puis 60 s par scénario. CPU en part de toute la machine.

| Scénario | CPU avant | CPU après | Mémoire privée avant | après |
|---|---|---|---|---|
| Accueil, au premier plan | 0,42 % | 0,44 % | 497 Mo | 497 Mo |
| Fenêtre sans le focus | 0,46 % | 0,10 % | 500 Mo | 431 Mo |
| Fenêtre réduite | 0,32 % | 0,02 % | 509 Mo | 435 Mo |

- La mémoire chute d'environ 65 Mo et de 30 fils deux minutes après le lancement : c'est le moteur
  mpv préparé d'avance qui est détruit (point 3).
- Le vidage des images après 45 s cachée ne se voit pas dans la mémoire privée à l'accueil : le
  cache y est encore petit. Son effet est à mesurer après avoir parcouru plusieurs bibliothèques.
- L'accueil au premier plan, au repos, prend encore environ 7 % d'un cœur : ce qui s'y réveille
  sans rien montrer reste à trouver (phase 3 du plan).

## Conséquences

- Les services qui écoutent leur propre `AppLifecycleListener` (invitations de watch party,
  disponibilité du serveur) ne changent pas : elles continuent de recevoir leurs événements
  fenêtre derrière.
- Une animation en cours quand la fenêtre perd le focus reste à mi-course et repart au retour. Un
  `await controller.forward()` lancé pendant ce temps attend le retour du focus, comme pour un
  onglet caché.
- **Écarté :** couper aussi les sondages réseau d'un lecteur ouvert sans focus (le serveur doit
  continuer de recevoir les battements de lecture). **Écarté :** figer un `TickerMode` par widget
  décoratif, six à sept sites à tenir à jour contre un seul interrupteur.
- **Écarté en phase 1 :** remplacer la minuterie de 16 ms de `MpvWindowHost`. Sous Windows, cette
  fenêtre ne sert qu'aux Dolby Vision profil 5 (`MpvNativeView`), le gain ne vaut pas le risque de
  voir la vidéo décalée.
- **Le préchauffage au lancement ne sert plus qu'à un film lancé dans les deux minutes.** Le déplacer
  vers une intention de lecture (ouverture d'une fiche) est la phase 2 du plan.
- **Reste à faire :** mesurer le gain, et décider si `AppForeground.visible` doit lui aussi exclure
  `inactive` sur bureau pour les sondages qui ne passent pas par `OnScreenState`.
