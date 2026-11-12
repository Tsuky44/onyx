# ADR-0115 — Le stockage se gère aussi depuis l'administration d'Onyx

- **Statut :** accepté
- **Date :** 2026-11-12
- **Portée :** `server/handlers/admin_storage.go`, `server/handlers/mediahub_storage_details.go`
  (`current_episode`), les routes `GET /api/admin/storage`, `GET|DELETE /api/admin/storage/:id`,
  `app/lib/screens/settings/pages/storage_*.dart`, l'onglet Paramètres → Bibliothèque → Stockage.
  Prolonge l'ADR-0114.

## Contexte

Faire de la place demandait d'ouvrir MediaHub. L'administrateur veut le faire depuis l'app : voir ce
que pèse chaque titre, qui l'a demandé et quand, qui le regarde et où il en est, depuis combien de
temps personne ne l'a lancé, et supprimer un film, une série entière ou une seule saison.

## Décision

- **Un seul gestionnaire, deux portes.** Le détail et la suppression sont les handlers de l'ADR-0114,
  enregistrés une deuxième fois derrière une session Onyx. Seule la liste a son handler, qui ajoute à
  celle de MediaHub l'affiche et les demandes.
- **Le droit est `delete_media`**, pour les trois routes : la page n'a de sens que pour qui peut
  supprimer, et elle montre l'activité de tous les comptes. L'onglet n'apparaît qu'avec ce droit.
- **Les demandes viennent de MediaHub**, lues au nom de l'administrateur (`scope=all`) et rapprochées
  par `tmdb_id` et type (`tv` ↔ `show`). Onyx ne garde pas de copie : MediaHub reste la source. Sans
  réponse en 6 s, ou sans MediaHub, la liste part sans elles et le dit (`requests_available`), plutôt
  que d'afficher « personne ne l'a demandé ».
- **Supprimer, c'est supprimer partout.** Effacer les fichiers sans prévenir le gestionnaire ne
  sert à rien : sorraa (ou Radarr/Sonarr) suit toujours le titre et le retélécharge. La suppression
  de l'administration (`AdminDeleteStorage`) fait donc, dans cet ordre :
  1. `indexer.CheckDeletable` : un titre qu'Onyx refusera (`409`, fichier hors bibliothèque) ne
     doit pas d'abord disparaître ailleurs ;
  2. `POST /library/removals` chez MediaHub, au nom de l'administrateur : MediaHub retire le titre,
     ou la seule saison, du gestionnaire choisi pour ce type, *sans* ses fichiers (sorraa les
     mettrait dans sa corbeille, qui ne libère rien), et supprime ses demandes ;
  3. l'effacement des fichiers par Onyx.

  Si MediaHub échoue, est trop ancien (`404`) ou refuse, Onyx ne supprime rien (`502`, message qui
  le dit). Sans MediaHub configuré, Onyx efface seulement ses fichiers. Le gestionnaire de stockage
  de MediaHub passe par le même service (`lib/services/media-forget.ts`), qui sait désormais aussi
  retirer de sorraa.
- **« Où il en est »** : chaque compte d'une série reçoit `current_episode`, l'épisode qu'il a lu en
  dernier, avec sa position. Le champ est en plus : MediaHub l'ignore.
- **« Pas regardé depuis »** se mesure depuis la dernière lecture, ou depuis l'ajout pour un titre
  jamais lancé : un film arrivé hier n'est pas oublié. Le tri et les filtres se font dans l'app, sur
  la liste complète, comme MediaHub le fait déjà.

## Conséquences

- Un compte qui a `delete_media` peut effacer des fichiers du disque depuis l'app, dans les seules
  bibliothèques de films et de séries (même garde que l'ADR-0114, `409` ailleurs).
- La liste attend MediaHub jusqu'à 6 s quand il est lent ; le disque, lui, répond tout de suite.
- La suppression attend MediaHub jusqu'à 60 s (Sonarr relit toutes ses séries pour en trouver une
  par TMDB) ; l'app lui laisse 90 s.
- Un MediaHub sans `/library/removals` bloque la suppression depuis Onyx tant qu'il n'est pas mis à
  jour : c'est voulu, une suppression à moitié ne fait pas de place.
