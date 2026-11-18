# ADR-0147 — Un épisode manquant arrête l'enchaînement et pose la question

- **Statut :** accepté. Demandé par l'utilisateur le 2026-11-18 : « quand il manque un ep entre les
  deux ça le dise avant de passer et que ça demande quoi faire ». Vérifié en test, **pas encore vu
  dans le lecteur**.
- **Date :** 2026-11-18
- **Portée :** `server/handlers/next_up.go` (`describeSkippedEpisode`, champ `missing_count` de
  `upcoming_episode`), `contract/next_episode.json`, `models/episode_navigation.dart`
  (`UpcomingEpisode.missingCount`), `screens/player/hooks/use_episode_navigation.dart`,
  `screens/player/player_screen_flow.dart`, `screens/player/widgets/upcoming_episode_overlay.dart`,
  `screens/player/widgets/end_card_chrome.dart`.

## Contexte

`GET /api/episodes/:id/next` rendait le premier épisode de la saison dont le numéro dépasse celui
qu'on regarde. Avec les épisodes 2 et 4 sur le serveur, la fin du 2 enchaînait sur le 4 sans rien
dire : on sautait le 3 sans le savoir. Le trou avant une saison suivante passait déjà par la carte
« épisode pas encore disponible » ; le trou au milieu d'une saison, non.

## Décision

1. **Le serveur signale le trou.** Quand l'épisode suivant détenu n'est pas le numéro d'après, la
   réponse garde `episode` (on peut toujours y aller) et ajoute `upcoming_episode` pour le premier
   épisode manquant, avec `missing_count`, le nombre d'épisodes sautés. Quand TMDB connaît la
   saison, il tranche : un trou qu'il ne liste pas n'en est pas un (numérotation différente).
   Sans TMDB, la numérotation locale fait foi — une fausse alerte coûte un appui, un saut silencieux
   coûte un épisode.
2. **Le lecteur demande.** La carte existante prend le générique, sans compte à rebours :
   « ÉPISODE 3 MANQUANT » (ou « 2 ÉPISODES MANQUANTS AVANT LE SUIVANT »), le titre et le résumé
   TMDB, et deux choix : « Passer à l'épisode 4 » ou « Fermer ».
3. **« Fermer » veut dire « ne saute pas ».** Plus de compte à rebours ni de page « épisode
   suivant » après, et la fin du fichier quitte le lecteur au lieu d'enchaîner. Le bouton
   « Épisode suivant » du chrome reste pour qui change d'avis. Cela vaut aussi pour le trou avant
   une saison suivante, qui relançait le compte à rebours.

## Conséquences

- Un fichier double (S01E02E03 indexé comme épisode 2) ferait croire au manque du 3 quand TMDB
  liste le 3 : l'indexeur ne connaît pas les épisodes doubles. On accepte la question en trop.
