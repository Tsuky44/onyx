# ADR-0135 — La recherche des demandes complète les titres connus, depuis l'export quotidien de TMDB

- **Statut** : acceptée
- **Date** : 2026-11-16
- **Portée** : `server/titleindex/` (nouveau paquet), `server/handlers/request_search_rank.go`,
  `server/handlers/request_title_index.go`, `server/main.go`, le fichier `title-index.db` à côté de
  la base du serveur. Prolonge l'ADR-0134.

## Contexte

L'ADR-0134 reclasse les résultats de TMDB par pertinence. Ça ne suffisait pas : la recherche de TMDB
cherche des **mots entiers**. Avec « bat », ses 10 000 résultats sont Bat★21, Black Bat, The Bat…
et aucun Batman. On ne peut pas faire remonter un titre que TMDB ne renvoie pas.

TMDB publie chaque jour, sans clé, la liste de tous ses films et séries
(`files.tmdb.org/p/exports/movie_ids_MM_DD_YYYY.json.gz` et `tv_series_ids_…`) : l'identifiant, le
titre original et la popularité, soit environ 1,45 million de lignes et 33 Mo compressés. Ses
conditions limitent le cache à 6 mois (§1.C) ; ces fichiers sont faits pour être téléchargés.

## Décision

- **Un index des titres connus**, dans `title-index.db`, une base SQLite à part à côté de celle du
  serveur : c'est un cache refait chaque jour, il n'a rien à faire dans les sauvegardes et on peut le
  supprimer sans rien perdre. Une table FTS5 indexe le titre passé par `Fold` (minuscules, sans
  accents) par début de mot, avec les préfixes de 2 et 3 lettres précalculés.
- **Seulement les titres un minimum connus** : films de popularité ≥ 1, séries ≥ 2, ni adultes ni
  simples vidéos. Seuils choisis avec Mathis sur l'export du 15/11/2026 : « Les Visiteurs » est à
  4,3, « Pride and Prejudice » (BBC) à 2,1 ; en dessous, surtout des titres que personne ne cherche.
  Il reste environ 92 000 titres, 11 Mo sur disque, indexés en 4 s.
- **Mise à jour** : `titleindex.Refresher.Run`, deux minutes après le démarrage puis chaque heure,
  télécharge l'export du jour (publié vers 8 h UTC ; avant 9 h, celui de la veille) s'il ne l'a pas
  déjà. Films et séries entrent dans la même transaction : un téléchargement coupé laisse l'index de
  la veille. Sans clé TMDB, rien n'est téléchargé, puisque le catalogue de demandes ne sert pas.
- **Dans la recherche** : pour les pages 1 à 3, l'index donne les 10 titres qui commencent le mieux
  par la requête (chaque mot tapé est un début de mot du titre, « dark kni » trouve The Dark Knight),
  le serveur lit leur fiche TMDB dans la langue du compte (titre traduit, affiche ; un jour en cache)
  en même temps que les trois pages de recherche, et les ajoute à la liste avant le classement de
  l'ADR-0134. Un titre suggéré que TMDB a aussi trouvé ne sort qu'une fois.
- **Le classement s'affine** : un article de tête (« the », « le », « la », « les »…) ne compte plus
  pour juger qu'un titre commence par la requête (« The Batman » commence par « bat ») ; la
  popularité d'une série est divisée par 3 pour la ramener à l'échelle des films (The Office, série,
  est à 1 740 quand The Dark Knight est à 83). `Fold` et `MatchRank` vivent dans `titleindex`, seule
  source côté serveur ; ils restent alignés sur `utils/search_match.dart` de l'app.
- **Écartés.** Copier toute la base de TMDB par l'API (titres traduits, affiches) : 1,4 million
  d'appels par serveur, contraire à l'esprit de ses conditions (bande passante excessive, dérivés).
  Les suggestions d'IMDb : une API non officielle, sans garantie. Trakt : une clé de plus, et rien
  ne montre qu'il complète mieux.

## Conséquences

- Chaque serveur télécharge environ 33 Mo par jour et garde 11 Mo sur disque. La mémoire n'en garde
  rien : la lecture est en flux, et l'index est sur disque.
- L'export n'a que les **titres originaux** : un titre français que l'on commence à taper
  (« le seigneur des a… ») n'est pas complété par l'index ; il reste trouvé par TMDB une fois les mots
  entiers tapés. Les titres traduits demanderaient un appel par titre : à reconsidérer si le manque
  se fait sentir.
- Une recherche nouvelle coûte jusqu'à 13 appels TMDB (3 pages, 10 fiches), en parallèle et en
  cache : les fiches reviennent d'une lettre à l'autre.
- Un index absent, vide (premier démarrage) ou en panne laisse la recherche à TMDB seul, comme avant.
- Le contrat de `/api/requests/catalog` ne change pas.
