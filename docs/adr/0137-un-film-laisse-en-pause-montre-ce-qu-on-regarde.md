# ADR-0137 — Un film laissé en pause montre ce qu'on regarde

- **Statut :** accepté. Regardé sur ordinateur (épisode) ; logo, image de l'épisode suivant et note
  ajoutés après ce premier essai, **pas encore regardés** ; Android TV, Apple TV et LG non plus.
- **Date :** 2026-11-17
- **Portée :** `screens/player/hooks/use_pause_info.dart` (`PauseInfoWatch`),
  `screens/player/pause_info_content.dart` (`PauseInfoContent`),
  `screens/player/widgets/pause_info_overlay.dart` (`PauseInfoOverlay`),
  `screens/player/player_screen_pause_info.dart`, `screens/player/player_key_routing.dart`
  (`pauseInfoShown`), `screens/player/player_screen_remote.dart`,
  `screens/player/player_screen_chrome.dart`, `screens/player/player_screen_flow.dart`,
  `screens/player/widgets/onyx/onyx_chrome_theme.dart` (`pauseInfoSideScrim`,
  `pauseInfoBottomScrim`).

## Contexte

Demande de l'utilisateur : « quand je mets pause sur un média et que je reste en pause assez
longtemps, sur PC ou télé, qu'il y ait un peu comme à la Netflix le résumé du média par-dessus, en
transparence ». Quatre maquettes ont été faites ; il a gardé les deux en voile cinéma (film,
épisode) pour tous les écrans, et écarté le panneau de verre et la variante télé à boutons.

Ses règles : « cette affiche apparaît 5 secondes après une pause, et si je mets pause mais que je
bouge pour ouvrir un menu, alors elle ne s'affiche pas. C'est vraiment quand je mets pause et que
je ne fais rien de plus » ; « sur la télé on a juste à appuyer sur OK pour relancer ».

## Décision

1. **Cinq secondes de calme, tant que la pause dure.** `PauseInfoWatch` s'arme quand quelqu'un
   met pause (`_togglePlayPause`, d'où viennent le bouton, Espace, la touche du casque et un clic
   sur l'image), et monte l'écran au bout de **5 s sans geste**. Chaque geste (souris, doigt,
   touche, menu, barre) le retire s'il est affiché et **relance les 5 s** : l'écran revient dès que
   la souris s'arrête, autant de fois que la pause dure. Hors pause, il ne guette rien. Les gestes
   passent par un seul point, `_noteUserActivity`, qui arrête aussi les comptes à rebours de
   l'intro et de l'épisode suivant.
   *Révisé après le premier essai* : au départ, un geste annulait l'écran pour toute la pause.
   L'utilisateur devait garder la souris immobile dès la pause ; il a demandé que l'écran revienne
   quand la souris s'arrête.
2. **Le geste qui met pause n'en est pas un de plus.** Le clic qui met pause réveille aussi le
   chrome, qui signale une activité juste après : cela ne fait que relancer l'attente.
3. **Rien d'autre ne tient l'écran.** Relu au bout des 5 s : toujours en pause, pas de menu ni de
   volet d'onglets, pas de page de fin, de question « Vous regardez encore ? », de cadenas, de
   lecture passée sur un autre appareil ni d'image dans l'image. Sinon, l'attente repart pour
   5 s : l'écran monte une fois le menu fermé, sans qu'il faille remettre pause.
4. **Pas sur un téléphone ni une tablette** : l'écran est dans la main, et le résumé n'aurait pas
   la place de se lire par-dessus le film.
5. **Le chrome s'efface sous l'écran**, et la télécommande quitte la barre avec lui. **OK relance la
   lecture** (`routePlayerKey`, `pauseInfoShown`), Espace aussi, un clic sur l'image aussi (l'écran
   ne prend aucun geste). Une autre touche, la souris qui bouge ou **Retour** retirent seulement
   l'écran et rendent le chrome : la vidéo reste en pause, et Retour ne quitte pas le film.
6. **Ce qui s'affiche vient de ce que le lecteur sait déjà** (`PauseInfoContent`), sans requête de
   plus : la fiche en cache du logo-titre (celle du film, ou celle de la série pour un épisode), et
   le logo que le chrome affiche déjà (`_mediaLogoUrl`).
   Film : « Vous regardez », son **logo** (le titre écrit tant qu'il charge, ou s'il n'en a pas),
   année, deux genres, durée, note TMDB, accroche, résumé, réalisation, trois premiers rôles.
   Épisode : le **logo de la série**, « Saison 2 · Épisode 5 », le titre et le résumé de
   l'épisode, sa date de diffusion, la **note de la série**, la carte de l'épisode suivant avec
   **son image** (16:9, `posterUrl` de l'épisode). Les deux : le temps
   restant, l'heure de fin si l'on reprend maintenant, la progression, et la touche qui reprend
   (« OK » sur un téléviseur, « Espace » ailleurs).
7. **Un voile plat, pas de verre.** Dense à gauche pour le texte, il laisse la droite de l'image
   visible ; aucun flou (ADR-0048, `player_glass_guard_test.dart`). Il entre en fondu
   (`AppMotion.emphasis`, conservé sous « réduire les animations »). Sur un téléviseur, la couche
   passe par `PlayerTvScale.layer`, comme le chrome.

## Conséquences

- Les badges techniques des maquettes (4K, HDR, langue et sous-titres en cours) ne sont pas
  affichés : ils demanderaient de lire les pistes du moteur, ce qui sort de « ce que le lecteur
  sait déjà ». À ajouter si l'écran en manque.
- Un épisode affiche la note de la série : le serveur ne connaît pas de note par épisode
  (seule la fiche TMDB de la série la porte). Demandé par l'utilisateur au premier essai, pour un
  écran plus complet.
- Une pause venue d'ailleurs (la séance « Regarder ensemble », un autre appareil, la minuterie de
  veille) ne monte pas l'écran : ce n'est pas « j'ai mis pause et je suis parti ».
- Tests : `pause_info_watch_test.dart` (le compte à rebours, ce qui le relance, le retour de
  l'écran quand la souris s'arrête),
  `pause_info_content_test.dart` (ce que dit l'écran, et qu'il laisse passer un clic),
  `player_key_routing_test.dart` (OK relance devant l'écran).
