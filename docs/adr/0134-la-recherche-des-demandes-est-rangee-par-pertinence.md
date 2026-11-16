# ADR-0134 — La recherche des demandes est rangée par pertinence, pas dans l'ordre de TMDB

- **Statut** : acceptée
- **Date** : 2026-11-16
- **Portée** : `server/handlers/request_search_rank.go`, `server/handlers/tmdb_requests.go`
  (`TmdbRequestCatalog`, `tmdbCatalogRow`), la route `GET /api/requests/catalog?query=`, donc l'écran
  des demandes et les titres absents de la recherche (`services/unavailable_titles_search.dart`)

## Contexte

La recherche du catalogue de demandes renvoyait les résultats de `/search/multi` (ou `movie`, `tv`)
dans l'ordre de TMDB. TMDB range surtout par correspondance du texte : taper « bat » sortait
« Bat Masterson », une série de 1958 dont le titre contient le mot exact, avant « Batman », que l'on
cherche presque toujours. La notoriété du titre ne comptait presque pas, et un titre connu pouvait
tomber en deuxième ou troisième page.

## Décision

- **Le serveur reclasse.** Pour les pages 1 à 3, il lit les trois premières pages de TMDB (en
  parallèle, dans le cache de dix minutes du catalogue), retire les personnes et les doublons, range
  les titres par score, puis découpe la liste en trois pages. Les pages suivantes sont celles de
  TMDB, telles quelles : chaque titre sort une fois, et l'on ne cherche pas plus loin le titre voulu.
- **Le score** est le poids de la meilleure correspondance, sur le titre traduit ou le titre
  original, multiplié par `1 + ln(1 + popularité) + 0,3 × ln(1 + votes)`. Les poids suivent l'échelle
  de `searchMatchRank` de l'app : titre exact 1, début du titre 0,85, début d'un mot 0,7, tous les
  mots 0,6, n'importe où 0,4, sans espaces 0,35. Un titre que TMDB a trouvé autrement (titre
  alternatif) pèse 0,3. Le logarithme tasse les écarts : la notoriété départage des correspondances
  proches, elle n'écrase pas un titre exact. Les votes retiennent un classique que la popularité de
  la semaine a oublié.
- **Une seule source pour le texte.** `foldSearchText` et `searchMatchRank` reprennent
  `foldForSearch` et `searchMatchRank` de l'app (minuscules, accents, ponctuation) ; un changement
  d'un côté se reporte de l'autre.
- **Écartés.** Un second moteur (Trakt, TheTVDB) aurait demandé une clé de plus et une deuxième
  identité des titres, alors que le défaut venait de l'ordre et non de ce que TMDB trouve. Un tri
  côté app n'aurait vu qu'une page à la fois.

## Conséquences

- La première page d'une recherche coûte trois appels TMDB au lieu d'un. Ils partent ensemble, sans
  attendre que la page 1 donne le nombre de pages : on attend le plus lent des trois, à peine plus
  qu'un seul. Les pages 2 et 3 sortent ensuite du cache.
- Si la page 2 ou 3 échoue, le serveur reclasse ce qu'il a reçu et le journalise ; tant que l'échec
  dure, les pages 1 à 3 se découpent autrement, ce qui peut faire sauter ou répéter un titre au
  défilement.
- Le contrat de `/api/requests/catalog` ne change pas : seul l'ordre des résultats change.
