# ADR-0159 — La vue large des listes montre la progression, que le serveur calcule

- **Statut :** accepté
- **Date :** 2026-11-19
- **Portée :** le serveur (`server/watchlists/progress.go`, `server/watchlists/read.go`,
  `server/models/watch_list.go`, `contract/watch_list.json`, `contract/watch_lists.json`) et
  l'app (`app/lib/models/watch_list.dart`, `app/lib/screens/lists/lists_screen.dart`,
  `app/lib/screens/lists/lists_overview_wide.dart`, `app/lib/screens/lists/widgets/`).
  Complète l'ADR-0070 ; n'en contredit aucun point.

## Contexte

L'onglet Listes de la grande fenêtre (proposition « E » : encart « À regarder plus
tard », cartes à bandeau d'affiches, listes partagées au second plan) doit dire où
l'on en est de chaque liste : combien de titres vus, combien le serveur en a, lequel
regarder ensuite. `GET /api/lists` ne portait que `item_count` et quatre affiches.
La progression existait seulement dans le détail d'une liste, titre par titre
(`media.current_position_seconds`, `is_finished`), et **pas pour une série** : la fiche
d'une série n'a pas de position de lecture, seuls ses épisodes en ont. Un
`percentWatched` côté app aurait donné 0 pour toute série, et « vu » pour un film
arrêté à 94 % alors que le serveur ne le tient pas pour terminé.

## Décision

1. **Le serveur calcule, l'app affiche.** Chaque résumé de liste porte trois champs
   de plus, relus pour le compte qui lit (la liste d'un autre se lit avec sa propre
   progression) : `watched_count`, `on_server_count` et `next_item`.
2. **Ce qu'est « vu ».** Un film est vu quand sa progression est terminée
   (`is_finished`). Une série est vue quand chacun de ses épisodes présents sur le
   disque l'est ; les épisodes sans fichier (emplacements TMDB) ne comptent pas, comme
   dans `loadShowWatchStats`. Une série sans épisode indexé n'est jamais vue.
3. **Sur le serveur** (`on_server_count`) : les titres rattachés à une fiche. L'app en
   déduit « à demander » = `item_count − on_server_count`.
4. **Le prochain titre** (`next_item`) est le premier titre **du serveur** non vu, dans
   l'ordre d'ajout (le plus ancien ajout d'abord, à l'inverse de la liste affichée).
   Un titre à demander n'est jamais proposé : on ne le lance pas. Absent quand tout ce
   que le serveur a est vu. L'objet est réduit (id d'élément, `media_id`,
   `media_type`, titre, affiche, date) : de quoi l'afficher et lancer la lecture.
5. **Rétrocompatibilité sans capacité.** Les champs sont ajoutés, aucun n'est
   renommé : un ancien client les ignore. Un nouveau client face à un ancien serveur
   les lit absents (`null`) et retombe sur les vignettes d'avant, sans barre
   (`WatchList.hasProgress`). Pas de nouvelle entrée dans `/api/ping` (ADR-0051).
6. **Côté app.** À partir de la largeur « large » (`AppLayout.isWide`, 900 px) et hors
   télévision, `ListsScreen` pose `wideListsSlivers` à la place des deux grilles de
   vignettes. Le téléphone, la tablette étroite et la télévision gardent
   `WatchListTile`. « Lire » ouvre `PlayLink.routeFor` (ADR-0091) : le film à sa
   position, la série à l'épisode à reprendre.
7. **Bornes.** La progression se calcule en trois requêtes pour toutes les listes de
   la page (titres, films terminés, épisodes des séries), les identifiants passant par
   lots de 500 ; la page des listes des autres reste bornée à 500 (ADR-0070).

## Alternatives écartées

- **Lire la progression dans le détail de chaque liste.** Une requête par carte, pour
  une page qui en montre une douzaine ; le résumé existe justement pour la page.
- **Calculer « vu » dans l'app avec `percentWatched`.** Faux pour les séries (0), et
  une seconde définition de « vu » à côté de celle du serveur.
- **Une capacité `watch_list_progress`.** Les champs sont additifs et l'app se
  dégrade sans eux : une capacité n'ajouterait qu'un aller-retour au lancement.

## Conséquences

- `GET /api/lists` fait trois requêtes de plus, une fois par chargement de la page
  (et par `Create` / `Update`, qui relisent le résumé de la liste touchée).
- Une série présente en double sur le disque (deux dossiers) est comptée sur la ligne
  rattachée, la plus ancienne : la progression des séries dédoublonnées pour
  l'affichage (`ShowDisplayGroupKey`) n'est pas sommée ici. À reprendre si le cas se
  rencontre.
- Le titre de `next_item` est celui de la fiche, non traduit (ADR-0049) : le résumé ne
  porte pas la couche de traduction des fiches du détail.
- Un titre ajouté mais dont l'élément n'est lu que par `tmdb_id` (pas de `media_id`)
  compte comme « sur le serveur » dès que la fiche existe, comme dans le détail.
- Les tests : `server/watchlists/progress_test.go` (films, séries, épisode manquant,
  compte qui lit), `contract/watch_lists.json` relu par
  `app/test/api_contract_test.dart`, `app/test/lists_overview_wide_test.dart` (calcul
  des lignes, rendu large et téléphone).
