# Calendrier des sorties : données du serveur et suivi des séries

- **Statut :** accepté
- **Date :** 2026-11-27
- **Portée :**
  - Serveur : `server/calendar/` (cœur pur), `handlers/calendar.go`, `handlers/calendar_sources.go`, `handlers/calendar_tmdb.go`, migration 35 `calendar_follows`, capacité `calendar` (`handlers/ping.go`), `contract/calendar.json`, `TMDBEpisodeSummary.Type`.
  - App : `models/calendar_feed.dart`, `services/api/calendar.dart`, `providers/calendar_provider.dart`, `screens/calendar/calendar_entry_launch.dart`, `main.dart`, `screens/home/home_screen.dart`.
- **Suit :** `2026-11-27-tsuky-calendrier-sorties-ui.md` (l'UI et le seam `CalendarProvider` en mémoire).

## Contexte

1. L'UI du calendrier « À venir » tournait sur des données factices dans `CalendarProvider`.
2. Le calendrier ne doit montrer que ce qui concerne le compte : jamais « toutes les sorties du monde ».
3. Les demandes ne vivent pas dans Onyx : elles sont chez le compagnon (MediaHub, Overseerr, Jellyseerr, ADR-0136).
4. TMDB ne donne qu'un « prochain épisode » par série sur `/tv/:id` ; les dates des suivants sont dans `/tv/:id/season/:n`.

## Décision

1. **Le serveur décide qui figure au calendrier, et pourquoi** (`calendar.Source`), par ordre de priorité :
   - `followed` : suivie à la main (bouton « Suivre ») ;
   - `watching` : un épisode lancé par le compte dans les 365 derniers jours (100 séries au plus) ;
   - `request` : une demande du compte au compagnon, refus exclus, séries et films ;
   - `server` : une série de la bibliothèque qui a reçu un épisode ces 180 derniers jours (60 au plus).
   Une série retirée (`DELETE`) disparaît quelle que soit sa raison et ne revient pas d'elle-même ; `PUT` la remet en suivi manuel.
2. **Stockage** : table `calendar_follows (user_id, tmdb_id, followed)`. Clé TMDB, parce qu'une série demandée n'est pas encore dans la bibliothèque. Seuls les choix explicites sont stockés : les raisons automatiques se recalculent à chaque lecture.
3. **Un cœur pur** `server/calendar` (`Merge`, `Build`, `Followed`, `PickRelease`) reçoit les intérêts, les choix, les programmes et la présence en bibliothèque. Il ne lit ni la base ni TMDB, et se teste en tables.
4. **Programmes TMDB** : fiche `/tv/:id`, puis les épisodes de 3 saisons au plus (celle du prochain épisode, celle du dernier, une saison annoncée datée). Cache 3 h par série et 6 h par film, 2048 entrées par langue, 6 appels en parallèle. Un calendrier attend TMDB 6 s au plus : ce qui arrive après remplit le cache pour le chargement suivant. Un échec n'est pas mis en cache.
5. **Films** : la sortie retenue est celle qui permet de voir le film chez soi (numérique, puis physique, puis salle), dans le pays de la langue, sinon aux États-Unis, sinon la date générale.
6. **« Disponible »** se lit dans la bibliothèque (épisode présent avec fichier) : `ready` et `episode_media_id`.
7. **App** : `CalendarProvider` garde l'interface que les écrans utilisaient. Il relit `GET /api/calendar`, applique « Suivre / Ne plus suivre » tout de suite, puis relit la réponse du serveur, qui fait foi ; un refus remet l'état d'avant. La fenêtre chargée (mois précédent → +180 j) s'élargit quand la navigation en sort. Un toucher sur une sortie ouvre la fiche de la bibliothèque, ou la fiche de demande si le serveur n'a pas le titre.

## Conséquences

- Un serveur sans la capacité `calendar` laisse le provider vide (`available` faux) : la rangée de l'accueil se masque.
- Le premier chargement d'un compte peut coûter jusqu'à ~180 appels TMDB (60 séries × fiche + 2 saisons) ; les suivants sortent du cache. Les bornes de l'étape 1 sont là pour ça.
- Une série en pause depuis plus de six mois, que personne ne suit ni n'a demandée, n'apparaît pas à son retour : il faut la suivre. C'est le prix de « pas toutes les sorties du monde ».
- TMDB ne donne pas l'heure de diffusion : `timeLabel` reste vide, et « Ce soir » ne s'affiche pas.
