# ADR-0162 — L'affiche d'une série d'une liste dit où l'on en est

- **Statut :** accepté
- **Date :** 2026-11-20
- **Portée :** le serveur (`server/watchlists/progress.go`, `server/watchlists/read.go`,
  `server/models/watch_list.go`, `contract/watch_list.json`, `contract/watch_list_item.json`)
  et l'app (`app/lib/models/watch_list.dart`,
  `app/lib/screens/lists/widgets/list_item_card.dart`). Complète l'ADR-0159 ;
  n'en contredit aucun point.

## Contexte

Dans le détail d'une liste, l'affiche d'un film commencé porte une barre de lecture ;
celle d'une série n'en portait aucune. Une série à moitié vue ressemblait à une série
jamais lancée : rien ne disait combien d'épisodes étaient derrière, ni où reprendre.
L'ADR-0159 l'explique : la fiche d'une série n'a pas de position de lecture, seuls ses
épisodes en ont, et l'app ne doit pas recalculer « vu ».

## Décision

1. **Le serveur calcule, l'app affiche.** Chaque élément **série** du détail d'une liste
   porte quatre champs de plus, relus pour le compte qui lit : `episodes_watched`,
   `episodes_total`, `next_episode_season` et `next_episode_number`. Les épisodes
   comptés sont ceux présents sur le disque, comme pour « vu » (ADR-0159).
2. **Le prochain épisode** est le plus petit couple (saison, épisode) non terminé ; la
   saison est celle de l'épisode, à défaut celle de son dossier. Il vaut 0/0 quand tout
   est vu. Un épisode sans numéro ne se nomme pas : l'app n'affiche alors que la barre.
3. **Le calcul rejoint la requête de `progress`** (un `MIN` en plus dans l'agrégat par
   série) : pas de requête de plus. Les champs sont réservés au détail d'une liste, le
   résumé de `GET /api/lists` ne les porte pas.
4. **Côté app**, une série *commencée et pas finie* (`WatchListItem.isShowInProgress`)
   reçoit une pastille « S2 E5 » en haut à gauche, une barre des épisodes terminés en bas
   (`ProgressPill`) et, au survol, « 3/8 épisodes vus · Prochain : S1 E4 ». Une série
   jamais lancée n'ajoute rien ; une série finie garde sa coche.
5. **Rétrocompatibilité sans capacité.** Les champs sont additifs (`omitempty`) : un
   ancien client les ignore, un nouveau client face à un ancien serveur les lit à 0 et
   garde l'affiche d'avant. Pas de nouvelle entrée dans `/api/ping` (ADR-0051).

## Alternatives écartées

- **Un `percentWatched` côté app.** Faux pour toute série (0), voir l'ADR-0159.
- **Une requête d'épisodes par série à l'ouverture.** Une aller-retour de plus par
  affiche pour une information que l'agrégat existant porte déjà.

## Conséquences

- Une série présente en double sur le disque est comptée sur la ligne rattachée, comme
  dans l'ADR-0159.
- Une série dont les épisodes n'ont ni numéro de saison ni numéro d'épisode a un
  prochain épisode nommé 0/0 : seule la barre s'affiche.
- Les tests : `server/watchlists/progress_test.go`
  (`TestListDetailTellsHowFarTheAccountIsInAShow`), `app/test/list_show_progress_test.dart`,
  et `contract/watch_list*.json` relus par `app/test/api_contract_test.dart`.
