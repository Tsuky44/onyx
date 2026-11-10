# ADR-0114 — MediaHub gère le stockage d'Onyx

- **Statut :** accepté
- **Date :** 2026-11-10
- **Portée :** `server/handlers/mediahub_storage*.go`, `server/indexer/media_delete.go`, les routes
  `GET /api/integrations/mediahub/storage`, `GET|DELETE /api/integrations/mediahub/storage/:id`, la
  capacité `mediahub_storage`. Prolonge l'ADR-0102 et s'en écarte sur un point.

## Contexte

Le gestionnaire de stockage de MediaHub (Stats → Stockage) liste films et séries par taille, dit quand
ils ont été regardés pour la dernière fois et par qui, et supprime ce qui ne sert plus, avec ou sans
Radarr et Sonarr. Il ne savait le faire qu'avec Emby : sur une installation où Onyx est la
médiathèque, il appelait encore l'adresse d'Emby et échouait (`getaddrinfo ENOTFOUND`).

## Décision

- **Les mêmes données qu'Emby.** `GET /storage` rend en une fois films et séries : taille en octets
  (`file_size` de l'indexeur ; une série additionne ses épisodes qui ont un fichier), date d'ajout,
  dernière lecture tous comptes confondus (progression ou historique, la plus récente). MediaHub trie,
  filtre et pagine lui-même, comme il le fait déjà avec l'index d'Emby. `GET /storage/:id` donne les
  saisons et l'activité de chaque compte.
- **Supprimer, c'est supprimer du disque**, comme `DELETE /Items` d'Emby : les fichiers vidéo, puis
  chaque dossier qui ne contient plus aucune vidéo (affiches, `.nfo`, sous-titres posés à côté),
  jamais la racine d'une bibliothèque, puis les lignes du catalogue. Un fichier déjà absent (Radarr ou
  Sonarr l'ont supprimé juste avant) compte comme supprimé.
- **Seulement dans les bibliothèques de films et de séries.** Un média dont un fichier n'est sous
  aucune d'elles est refusé (`409`) : la clé ne peut pas faire effacer un fichier ailleurs.
- **Contredit l'ADR-0102 (« Pas d'écriture large ») parce que** la suppression est la raison d'être du
  gestionnaire de stockage, et qu'un deuxième secret pour une seule route n'ajouterait rien : la clé
  reste un secret d'administrateur, posé à la main des deux côtés.

## Conséquences

- Une fuite de la clé permet désormais de supprimer des médias des bibliothèques, en plus de ce
  qu'elle exposait déjà. Les routes restent limitées comme un sondage (`PollLimiter`).
- Un disque monté en lecture seule fait échouer la suppression (`500`) : les fichiers déjà partis
  quittent le catalogue, les autres y restent.
- Les lignes de `playback_history` gardent leur titre (`media_id` passe à `NULL`) : les statistiques
  d'Onyx survivent à la suppression.
