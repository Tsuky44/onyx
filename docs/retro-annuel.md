# Rétro 2026 : plan de construction

- **Auteur :** tsuky, 2026-11-26
- **Maquette :** `design-plans/onyx-wrapped-maquette.html` (story, accueil, sources des chiffres)
- **Décision :** [ADR 2026-11-26-tsuky-retro-annuel](adr/2026-11-26-tsuky-retro-annuel.md)
- **Échéance :** visible le **1er décembre 2026**, donc serveur et apps publiés au plus tard le **30 novembre**.

## 0. Ce qui est décidé

| Sujet | Décision |
|---|---|
| Contenu | Dix écrans : ouverture, heures, n°1, top 5, heure, mois, moments, écrans, serveur, carte. |
| Période comptée | Du 1er janvier au 30 novembre inclus, dans le fuseau de l'appareil. |
| Visibilité | Du 1er décembre au 15 janvier, sur l'horloge du serveur. |
| Seuil | 5 h de lecture sur la période. En dessous, rien sur l'accueil. |
| Classement | Affiché à tous, sans réglage (total, rang, titre le plus vu ; jamais qui a vu quoi). |
| Textes | FR et EN, aucun accord de genre. Les profils ont des noms neutres. |
| Partage | La carte finale s'exporte en image : 1080 × 1920 en portrait, 1920 × 1080 en paysage. Ni nom de serveur ni adresse. |
| Accueil | Première diapo du carrousel et anneau sur l'avatar tant que la story n'est pas vue, puis carte « Revoir ». |
| Appareils | Une seule mise en page qui passe en deux colonnes dès que l'écran est plus large que haut : téléphone, tablette, PC, TV, web. |

## 1. Prérequis

« Mes stats » (ADR 2026-11-26-tsuky-statistiques-personnelles) est **en cours sur `tsuky`, pas encore commité**. Le Rétro réutilise ses chargeurs (`computePersonalStats`, `loadMarathon`, `loadWeekdayHour`, `loadDevices`, `statsWindow`) : il commence une fois ce travail commité, pour ne pas écrire dans les mêmes fichiers en même temps.

## 2. Serveur

### 2.1 Une fenêtre fermée

`statsWindow` n'a qu'un début (`since`). Le Rétro a besoin d'une fin : `statsWindow` gagne `until` (vide = jusqu'à maintenant) et `personalQuery.where()` ajoute `AND h.started_at < ?` quand il est posé. « Mes stats » ne change pas de comportement.

Les chiffres sont stables d'eux-mêmes : la fenêtre se ferme le 30 novembre, et l'historique d'avant ne bouge plus. **Pas de table d'instantané**, un `ttlcache` (1 h, 500 entrées) suffit pour ne pas recalculer à chaque ouverture.

### 2.2 Fichiers

| Fichier | Rôle |
|---|---|
| `handlers/retro.go` | Les trois handlers, minces. |
| `handlers/retro_report.go` | `computeRetro(userID, year, offset)` : appelle les chargeurs de « Mes stats » sur la fenêtre fermée, ajoute ce qui est propre au Rétro (§2.3). |
| `handlers/retro_archetype.go` | `chooseArchetype(r RetroReport) string`, fonction pure. |
| `handlers/retro_calendar.go` | `retroCalendar(now) (year int, open bool, endsAt time.Time)`, fonction pure. `ONYX_RETRO_PREVIEW=1` l'ouvre hors saison, pour tester. |
| `handlers/retro_test.go`, `retro_archetype_test.go`, `retro_calendar_test.go` | Voir §5. |
| `database/migrations.go` | Migration suivante : `retro_views`. |
| `handlers/ping.go` | Capacité `retro`. |
| `server/README.md` | Les trois routes. |

### 2.3 Ce que le Rétro calcule en plus de « Mes stats »

Tout vient de `playback_history`, filtré par `watched_seconds >= playbackMinSeconds` comme « Mes stats ».

- **Top 5** : regroupé par série, sinon par film, avec le temps, les épisodes distincts, les fois vu (une lecture d'au moins la moitié du film, même règle que « le plus revu » de « Mes stats », `countsAsViewingSQL`), plus `poster_url` et `media_id` par jointure sur `medias`.
- **Par mois** : 12 totaux.
- **Par heure** : somme des colonnes de `weekday_hour`, déjà calculé.
- **Première séance de l'année** et **séance la plus tardive** (heure de début entre 0 h et 5 h, la plus avancée).
- **Lecture directe** : part de `play_method = 'direct'` (vide compte comme direct, comme `stats.go`). C'est le seul chiffre technique, assumé (voir ADR).
- **Serveur** : membres au-dessus du seuil, heures totales, rang de l'appelant, titre vu par le plus de membres distincts. Une requête `GROUP BY user_id`.
- **Profil** : identifiant choisi par `chooseArchetype`. Le serveur décide, l'app traduit.

Règles du profil, dans l'ordre, le premier qui correspond gagne :

| Identifiant | Règle |
|---|---|
| `marathon` | Au moins 6 épisodes différents d'une même série le même jour (`loadMarathon` de « Mes stats »). |
| `night_owl` | Plus de 40 % du temps entre 22 h et 4 h. |
| `cinephile` | Plus de 60 % du temps sur des films. |
| `explorer` | Plus de 40 titres distincts. |
| `weekend` | Plus de 50 % du temps le samedi et le dimanche. |
| `good_audience` | Par défaut. |

### 2.4 Routes

Toutes en `RequireAuth` : chacun ne lit que son propre Rétro, plus les agrégats du serveur, qui ne nomment personne.

| Route | Réponse |
|---|---|
| `GET /api/me/retro?tz_offset=<minutes>` | Léger, pour l'accueil : `{year, open, eligible, seen, ends_at}`. |
| `GET /api/me/retro/:year?tz_offset=<minutes>` | Le rapport complet. `404` hors saison ou si l'année n'est pas celle en cours. `eligible: false` sous le seuil, sans le reste. |
| `POST /api/me/retro/:year/seen` | `204`. Pose `retro_views(user_id, year, seen_at)`. |

`retro_views` : `user_id`, `year`, `seen_at`, clé `(user_id, year)`, `ON DELETE CASCADE`. « Vu » est côté serveur pour que l'anneau disparaisse sur tous les appareils du compte.

Le rapport a son fichier de contrat (ADR-0051) : `TestAPIContract` le génère, `app/test/api_contract_test.dart` le vérifie.

## 3. App

### 3.1 Données

| Fichier | Rôle |
|---|---|
| `models/retro.dart` | `RetroStatus`, `RetroReport` et ses sous-objets, `fromJson`. Réexporté par `models.dart`. |
| `services/api/retro.dart` | Mixin `RetroApi` : `fetchRetroStatus`, `fetchRetro(year)`, `markRetroSeen(year)`. |
| `providers/retro_provider.dart` | Statut et rapport par compte, compteur de génération, `reset()` au changement de serveur (ajouté à `server_switch_catalog_test.dart`). Ne charge rien si la capacité `retro` manque. |

### 3.2 La story

`screens/retro/` :

| Fichier | Rôle |
|---|---|
| `retro_screen.dart` | Route plein écran. Fond noir, statut et barres système masqués. |
| `hooks/retro_story_controller.dart` | Index, progression, pause, maintien, suivant et précédent. Classe pure qui prend une horloge : testée sans monter l'écran. |
| `widgets/retro_slide_layout.dart` | Portrait : une colonne. Paysage : texte à gauche, visuel à droite. Une seule bascule, sur `constraints.maxWidth > maxHeight`. |
| `slides/retro_*_slide.dart` | Un fichier par écran (dix). Chacun prend le rapport et rend `(texte, visuel)`. |
| `widgets/retro_kinetic_text.dart` | Mots qui montent un à un. |
| `widgets/retro_count_up.dart` | Chiffre qui défile. |
| `widgets/retro_ambient.dart` | Fonds : halos, bandeaux qui défilent, rayons, ondes, points. Un `CustomPainter` par motif, aucune image. |
| `widgets/retro_transition.dart` | Ouverture en cercle depuis le point touché, l'écran précédent qui recule. |
| `widgets/retro_clock_chart.dart`, `retro_months_chart.dart` | Les deux graphiques, peints. |
| `widgets/retro_confetti.dart` | Confettis de la carte finale. |
| `widgets/retro_share_card.dart` | La carte, aussi rendue hors écran pour l'image. |
| `theme/retro_motion.dart` | Les durées et courbes propres au Rétro (voir ADR). |
| `l10n/retro_archetypes.dart` | Identifiant de profil → nom et phrase, FR et EN. |

Commandes :

- **Tactile** : toucher à droite ou à gauche, maintenir pour la pause, glisser vers le bas pour fermer.
- **Souris et clavier** : boutons ‹ › sur les bords, clic à gauche ou à droite, bouton pour fermer. Les flèches du clavier ne sont pas branchées : le dépôt interdit un gestionnaire de touches hors de dpad (`no_parallel_focus_system_test`), et `TvFocusable.onDirection` ne répond que sur un téléviseur. À voir avec la refonte dpad.
- **TV** : Gauche et Droite, OK pour la pause, Retour pour fermer, par `TvFocusable`, sans nouveau système de focus (ADR-0110). Test de focus sur le modèle de `tv_focus_test.dart`.

Les affiches passent par `AppNetworkImage` et `poster_url.dart`. Sans affiche, on garde le dégradé de la maquette.

**Mode léger et réduction des animations** : pas de fonds animés ni de confettis, transitions en fondu court, chiffres affichés directement. Même source que le reste de l'app (`LiteMode`, `AppMotion.move`).

### 3.3 Accueil

- **Carrousel** : `HeroCarousel` accepte une diapo d'en tête qui n'est pas un média. `HeroSlide` devient un type à deux variantes (média, Rétro) plutôt qu'un `Media` factice. Sur TV, son bouton prend le focus d'office (`autofocusPlay`).
- **Carte « Revoir »** : à la place de `SetupHomeCard`, au-dessus de « Reprendre la lecture », une fois la story vue.
- **Anneau** : `ProfileDisc` gagne un paramètre d'anneau, posé par `account_menu.dart` tant que le Rétro n'est pas vu. Le menu du compte gagne « Mon Rétro 2026 » jusqu'au 15 janvier.
- **« Plus tard »** : range la diapo pour la session de l'app. Seule l'ouverture de la story pose « vu » sur le serveur.

### 3.4 Image à partager

`RepaintBoundary` hors écran sur `RetroShareCard`, puis `toImage` en PNG à la taille cible.

| Cible | Action |
|---|---|
| Android, iOS | Feuille de partage du système. Nouvelle dépendance `share_plus`, à justifier dans `pubspec.yaml`. |
| Windows, macOS | Enregistrer dans Téléchargements (`path_provider`), puis toast avec « Ouvrir le dossier ». |
| Web, webOS | Téléchargement du fichier. |
| TV | Pas de bouton : une TV n'a rien vers quoi partager. |

## 4. Textes

Tout passe par `tr()` avec son entrée dans `l10n/en.dart` (ADR-0047), valeurs en argument. Aucune phrase ne qualifie la personne par un mot accordé : « Accro aux marathons », « Oiseau de nuit », « Cinéphile », « Touche-à-tout », « Fidèle du dimanche », « Bon public ». Les mois et les nombres passent par `LocaleFormats`.

## 5. Tests

| Test | Ce qu'il épingle |
|---|---|
| `retro_calendar_test.go` | Fermé le 30 novembre à 23 h 59, ouvert le 1er décembre, encore ouvert le 15 janvier, fermé le 16 ; l'année d'un 10 janvier est l'année d'avant ; `ONYX_RETRO_PREVIEW`. |
| `retro_archetype_test.go` | Une ligne par profil, et l'ordre quand plusieurs règles correspondent. |
| `retro_test.go` | Sur une base semée : la fenêtre exclut décembre, le seuil, top 5 groupé par série, relectures, mois, première et dernière séance, rang et titre du serveur, `seen` posé puis relu, `404` hors saison. |
| `stats_personal_test.go` | « Mes stats » inchangé avec `until` vide. |
| `retro_story_controller_test.dart` | Avance seule, pause au maintien, reprise au relâché, bornes. |
| `retro_screen_test.dart` | Portrait et paysage, serveur sans `retro`, rapport `eligible: false`, réduction des animations. |
| `retro_tv_focus_test.dart` | Gauche, Droite, OK, Retour. |
| `retro_home_test.dart` | Diapo et anneau avant, carte après, rien hors saison ni sous le seuil. |
| `accessibility_labels_test.dart` | Chaque écran a un résumé lisible par un lecteur d'écran. |
| `l10n_coverage_test.dart` | Déjà en place, couvre les nouvelles chaînes. |

Vérification à l'œil, avec `ONYX_RETRO_PREVIEW=1` : téléphone (Pixel 9), Windows, Android TV et le simulateur webOS.

## 6. Phases

Ordre pensé pour l'échéance. Les phases 1 à 4 sont nécessaires le 1er décembre ; la 5 peut sortir en correctif pendant la période, qui court jusqu'au 15 janvier.

| Phase | Contenu | Fin |
|---|---|---|
| 1. Serveur | §2 complet, tests, contrat, README, capacité. | **Fait le 2026-11-26** (non commité) : `go vet` et `go test ./...` verts. Reste l'essai sur une base réelle avec `ONYX_RETRO_PREVIEW=1`. |
| 2. Story | Modèle, provider, écran, dix écrans en portrait et paysage, commandes, TV. Transitions simples. | **Code écrit le 2026-11-26** (non commité) : `flutter analyze` propre, tests du déroulé, du contrat et des dix écrans sur quatre formats verts. Entrée provisoire : « Mon Rétro » dans le menu du compte. Reste : la regarder tourner sur téléphone, PC et TV ; flèches du clavier sur PC (voir §3.2). |
| 3. Mouvement | Texte animé, chiffres, graphiques, fonds, transition en cercle, confettis, mode léger. | **Code écrit le 2026-11-26** (non commité) : une horloge d'entrée par écran (`RetroEntrance`), mots qui montent, chiffres qui défilent, barres et jauges qui poussent, affiches en éventail et retournée, fonds peints sans flou (`RetroAmbientLayer`), cercle depuis le point touché, confettis ; tout s'arrête sous « réduire les animations » et en mode léger. Rendu vérifié en images (téléphone et PC). Reste : la fluidité sur Windows et sur TV. La carte qui s'incline sous la souris n'est pas faite. |
| 4. Accueil | Diapo, carte, anneau, menu du compte, « vu ». | `retro_home_test.dart`, vérifié sur téléphone et PC. |
| 5. Partage | Image et partage par plateforme. | Image ouverte sur chaque cible. |
| 6. Publication | Version de test depuis `tsuky` (Android, Android TV, webOS, Windows, serveur), puis prod avant le 30 novembre. L'Apple (iOS, tvOS) se publie par fytroz. | Serveur de prod à jour le 30 novembre. |

## 7. Encore ouvert

- **Police d'affichage** : la maquette utilise Bricolage Grotesque. L'app embarque déjà Manrope (ADR-0025, démarrage hors ligne). Proposition : Manrope ExtraBold, sans nouvelle police.
- **Publication Apple** : à caler avec fytroz pour qu'iOS et tvOS aient la version avant le 1er décembre.
