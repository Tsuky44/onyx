# Le Rétro de fin d'année : une story calculée par le serveur, visible six semaines

- **Statut :** proposé
- **Date :** 2026-11-26
- **Portée :**
  - Serveur : `handlers/retro.go`, `handlers/retro_report.go`, `handlers/retro_archetype.go`, `handlers/retro_calendar.go`, `handlers/stats.go` (`statsWindow.until`), `handlers/stats_personal.go`, `handlers/ping.go`, `database/migrations.go` (`retro_views`), `server/README.md`.
  - App : `models/retro.dart`, `services/api/retro.dart`, `providers/retro_provider.dart`, `screens/retro/`, `theme/retro_motion.dart`, `l10n/retro_archetypes.dart`, `utils/hero_slides.dart`, `widgets/global/hero_carousel.dart`, `widgets/global/profile_disc.dart`, `widgets/global/account_menu.dart`, `screens/home/home_screen.dart`, `l10n/en.dart`.
- **Plan :** [docs/retro-annuel.md](../retro-annuel.md). **Maquette :** `design-plans/onyx-wrapped-maquette.html`.
- **S'écarte de `PROJECT_DESIGN.md` §10** (durées de 180 à 280 ms, une seule courbe) pour la seule story du Rétro, et de l'ADR « Mes stats » §5 (« rien de technique ») pour un chiffre : la part de lecture directe.

## Contexte

1. Chaque membre d'un serveur doit recevoir en fin d'année une story personnelle sur ce qu'il a regardé, avec une carte à partager.
2. « Mes stats » (`GET /api/me/stats`, `personal`) calcule déjà la plupart des chiffres : grille jour × heure, marathon, plus longue séance, appareils. Sa période n'a qu'un début.
3. Onyx ne connaît pas le genre de ses membres.
4. Un Rétro qui se recalcule chaque jour donnerait des chiffres différents d'un jour à l'autre, et une carte partagée qui ne correspond plus à ce que voient les autres.

## Décision

1. **Le serveur calcule tout**, y compris le profil (`chooseArchetype`, fonction pure). L'app affiche et traduit. Les chargeurs de « Mes stats » sont réutilisés sur une fenêtre fermée : `statsWindow` gagne une fin (`until`), vide pour « Mes stats ».
2. **Période comptée : 1er janvier au 30 novembre. Visible : 1er décembre au 15 janvier.** La fenêtre étant fermée, les chiffres ne bougent plus sans table d'instantané. Un cache en mémoire borné évite de recalculer à chaque ouverture.
3. **« Vu » est stocké côté serveur** (`retro_views`), pour que l'accueil change sur tous les appareils du compte.
4. **Seuil de 5 h** : en dessous, rien n'apparaît.
5. **Le classement entre membres est affiché à tous**, sans réglage. Il ne montre que des agrégats : total, rang, titre vu par le plus de membres. Jamais qui a regardé quoi.
6. **Une seule mise en page**, qui passe en deux colonnes quand l'écran est plus large que haut. Pas de variante par plateforme. *Révisé le 2026-11-26* : sur PC, deux colonnes centrées laissaient une bande au milieu de l'écran et des vides autour. Un écran peut donc poser lui-même sa scène (`RetroSlide.compose`) contre les bords, et un fond sous ses animations (`RetroSlide.backdrop`). C'est toujours la forme de l'écran qui décide, jamais la plateforme. Les quatre premiers écrans le font : mur d'affiches, chiffre géant, affiche en fond, podium (`design-plans/onyx-retro-pc-propositions.html`).
7. **Le mouvement du Rétro a ses propres jetons** (`theme/retro_motion.dart`) : transitions de 600 à 1 000 ms, plusieurs courbes, fonds animés en continu. C'est un moment de fête, pas une navigation. Le reste de l'app garde `AppMotion`. Le mode léger et la réduction des animations ramènent le Rétro à des fondus courts.
8. ~~**La part de lecture directe reste**, présentée comme une nouvelle du serveur (« ton serveur a eu une année tranquille »), pas comme une mesure technique.~~ *Révisé le 2026-11-26* : l'écran « Tes écrans » (appareil le plus utilisé, lecture directe) est retiré à la demande de tsuky ; la story passe à neuf écrans et la carte de fin montre les séances à la place de l'écran. Le serveur envoie toujours `devices` et `direct_percent` : l'API reste stable, l'app ne les lit plus.
9. **Aucun texte accordé** : les profils ont des noms neutres par eux-mêmes.
10. **Le Rétro tutoie** (« ton année », « ta place »), comme la maquette validée : c'est une story qu'on se raconte et qu'on partage. Le reste de l'app continue de vouvoyer. En anglais, la fonctionnalité s'appelle « Recap ».
11. **Le n°1 s'affiche par son logo** (TMDB), lu dans la fiche du titre par `MediaDetailsCache` à l'ouverture du Rétro, trois secondes au plus. Le rapport du serveur ne le porte pas : le logo vient du catalogue en direct, pas de la base, et la fiche est souvent déjà en cache. Sans logo, le titre s'écrit. La couleur de l'affiche teinte l'écran : l'affiche décodée sur dix pixels puis étirée, sans flou calculé.
13. **L'image de récap est un ticket de séance** au nom du membre, aux couleurs de son profil (`widgets/retro_recap_ticket.dart`). Dessinée à taille fixe (360 × 640, 9:16) sans lire l'écran autour, pour se rendre pareil dans la story et hors écran en 1080 × 1920. Le dernier écran la montre telle qu'elle partira. Choisie parmi trois pistes (`design-plans/onyx-retro-pc-propositions-2.html`).
14. **Le partage passe par `share_plus`** (13.3), la seule dépendance ajoutée pour le Rétro : le menu de partage du système sur Android, iPhone, iPad et Mac, et dans un navigateur (qui télécharge l'image s'il ne sait pas partager). Sur Windows et Linux, l'image s'enregistre dans Téléchargements par `path_provider` : on l'envoie ensuite d'où l'on veut. Aucun téléviseur ne propose le partage. L'image est rendue hors écran (`utils/widget_image.dart`), pas capturée à l'écran : elle sort pareille quel que soit l'état de l'animation. `share_plus` ne déclare pas tvOS : flutter-tvos ne l'embarque pas (garde `tvos_plugins_linkable_test`). Il tire `url_launcher_windows` et `url_launcher_linux`, et ajoute un plugin natif au build Windows. Pas encore construit pour Android, iPhone ni Windows : à vérifier à la première version de test.
12. **Pas d'écran blanc** : le top 5 reste le seul écran clair, mais sur un papier tamisé (`#D6D0C4`). Le temps passé quitte le bleu de la marque en plein cadre pour un bleu nuit éclairé de halos. Les deux éblouissaient sur un grand écran.

## Conséquences

- Un serveur sans la capacité `retro` ne montre rien : l'app ne demande pas le statut.
- Les tests ne peuvent pas attendre décembre : `ONYX_RETRO_PREVIEW=1` ouvre le Rétro hors saison.
- Après le 15 janvier, rien ne reste sur l'accueil ; `retro_views` garde une ligne par compte et par an, négligeable.
- Le Rétro 2027 se fera sans code nouveau : l'année se déduit de la date (`retroCalendar`).
- Épinglé par `retro_calendar_test.go`, `retro_archetype_test.go`, `retro_test.go`, `retro_story_controller_test.dart`, `retro_screen_test.dart`, `retro_tv_focus_test.dart`, `retro_home_test.dart`.
