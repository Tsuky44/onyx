# « Mes stats » : les statistiques de chaque compte, dans une entrée à elles

- **Statut :** accepté
- **Date :** 2026-11-26
- **Portée :**
  - Serveur : `handlers/stats.go` (extrait d'`activity.go`), `handlers/stats_personal.go`, `handlers/stats_personal_titles.go`, `handlers/stats_personal_test.go`, `indexer/genres.go`, `indexer/genres_test.go`, `indexer/manual_match.go`, `database/migrations.go` (migration 33), `main.go`, `codeguard/size_test.go`, `server/README.md`.
  - App : `models/personal_stats.dart`, `models/server_activity.dart`, `services/api/activity.dart`, `l10n/tmdb_genres.dart`, `l10n/locale_formats.dart`, `l10n/en.dart`, `screens/settings/settings_sections.dart`, `screens/settings/settings_categories.dart`, `screens/settings/pages/my_stats_page.dart`, `screens/settings/pages/account_page.dart`, `screens/settings/pages/stats_page.dart`, `screens/settings/widgets/stats_charts.dart`, `screens/settings/widgets/my_stats/`, `test/my_stats_page_test.dart`, `test/my_stats_insights_test.dart`, `test/settings_screen_test.dart`, `test/settings_navigation_map_test.dart`.
- **Contredit l'[ADR-0071](0071-parametres-regroupes-en-neuf-entrees.md)** et l'[ADR-0100](0100-parametres-ranges-par-portee.md) sur le plafond d'entrées : dix au plus (au lieu de neuf), six pour un membre (au lieu de cinq).

## Contexte

1. Un compte sans droit d'administration ne voyait de son visionnage que quatre tuiles et trois titres, en tête de *Mon compte › Profil*. Les graphiques (par jour, par heure, classements) n'existaient que dans *Activité › Statistiques*, réservé à `manage_users`.
2. `GET /api/me/stats` existait déjà (`RequireAuth`) et calculait les mêmes chiffres que la page du serveur pour le seul compte appelant ; seule l'app ne les montrait pas.
3. Ce qui intéresse quelqu'un sur son propre visionnage n'est pas ce qui intéresse un administrateur : la méthode de lecture (Direct Play, transcodage) ou la version de l'application ne lui disent rien ; ses séries en cours, ses habitudes, ses genres, ses records, si.
4. Les genres ne sont pas en base : le serveur les lit chez TMDB à l'ouverture d'une fiche et ne les garde que six heures en mémoire (`indexer/catalog.go`).

## Décision

1. **Une entrée « Mes stats » dans « Mon espace »**, juste sous *Mon compte*, visible de tous. Pas un onglet de *Mon compte* : celui-ci gère le compte (sécurité, appareils, partage), alors que les statistiques se consultent. Le bloc de statistiques quitte *Profil*.
2. **`GET /api/me/stats` gagne `personal`**, absent de `/api/admin/stats` : période d'avant, jours d'affilée (sur tout l'historique), grille jour × heure, plus longue séance, plus gros marathon, avancement des séries (épisodes vus selon la progression du serveur, saison 0 exclue), films à finir, durée moyenne des films, décennies de sortie, genres, appareils (par nom d'appareil), totaux depuis l'arrivée et titre le plus revu. `all=1` couvre tout l'historique (dix ans au plus).
3. **Ce que l'app peut déduire des séries déjà envoyées ne passe pas par le serveur** : jour record, séance moyenne, créneau préféré, part d'après minuit (`my_stats_insights.dart`, fonctions pures).
4. **Les genres sont stockés par identifiant TMDB** dans `media_genres`, rempli par une tâche de fond (`indexer.RunGenreFiller`) par lots de 40, hors du scan, qui rattrape seule une bibliothèque existante. L'identifiant ne dépend pas de la langue : l'app le nomme en français ou en anglais (`l10n/tmdb_genres.dart`). Les genres doubles des séries (« Sci-Fi & Fantasy »…) sont repliés sur ceux des films au calcul, pour qu'un film et une série du même genre se retrouvent. `medias.genres_checked_at` évite de redemander une fiche déjà lue ; un `rematch` le remet à zéro.
5. **Rien de technique** : pas de méthode de lecture, pas de version d'application, pas de qualité de flux.
6. Les graphiques communs aux deux pages (par jour, par heure, lignes à barre) passent dans `widgets/stats_charts.dart`. Au-delà de trois mois, le graphique par jour regroupe par semaine, puis par mois.

## Conséquences

- La navigation d'un administrateur passe à dix entrées, celle d'un membre à six ; `settings_screen_test.dart` épingle le nouveau plafond.
- Un serveur plus ancien n'envoie pas `personal` : la page garde les chiffres communs, le graphique par heure et les titres, sans planter.
- « Mes genres » reste vide quelques minutes après la mise à jour du serveur, le temps que la tâche de fond lise les fiches (une requête TMDB toutes les 250 ms) ; la page le dit.
- Épinglé par `stats_personal_test.go` (chaque statistique, sur une base semée, et l'absence de `personal` côté administration), `genres_test.go` (une fiche lue une fois, un échec réessayé), `my_stats_insights_test.dart`, `my_stats_page_test.dart` (contenu, « Depuis le début », serveur ancien, cibles nommées sur téléphone).
