# ADR-0128 — Le gestionnaire efface les fichiers, Onyx nettoie ce qui reste

- **Statut :** accepté
- **Date :** 2026-11-13
- **Portée :** `server/indexer/media_delete.go`, `server/indexer/media_delete_writable*.go`,
  `server/handlers/mediahub_storage.go` (`MediaHubCheckDeletableStorage`),
  `server/handlers/admin_storage_delete.go`, la route
  `GET /api/integrations/mediahub/storage/:id/deletable`, `docker-compose.prod.yml`.
  Contredit en partie l'ADR-0114 et l'ADR-0115. Côté sorraa : son ADR 0031.

## Contexte

Le gestionnaire de stockage de MediaHub retirait le titre de sorraa *sans* ses fichiers (sorraa les
aurait mis dans sa corbeille, qui ne libère rien), puis demandait à Onyx de les effacer. Le modèle de
`docker-compose.prod.yml` monte pourtant Films et Séries en lecture seule (`:ro`) : `os.Remove`
échouait *après* le retrait de sorraa. Le titre n'était plus suivi par personne et ses fichiers
restaient sur le disque, avec le message « Onyx n'a pas pu supprimer tous les fichiers ».

## Décision

- **Le gestionnaire efface les fichiers.** MediaHub demande à sorraa (ou Radarr/Sonarr) de retirer
  le titre *avec* ses fichiers, depuis son propre gestionnaire comme depuis l'administration
  d'Onyx (`POST /library/removals`). sorraa les supprime définitivement, sans corbeille (son
  ADR 0031) : c'est lui qui écrit sur le disque, il en a les droits.
- **Onyx nettoie ce qui reste.** Il efface ensuite les fichiers encore là (titre qu'aucun
  gestionnaire ne suit, ou que l'administrateur a gardé chez lui), le dossier vidé de ses vidéos,
  et oublie le titre. Un fichier déjà absent compte comme supprimé, comme avant.
- **Onyx vérifie qu'il peut écrire avant de toucher à quoi que ce soit.** `indexer.DeleteMedia`
  demande au noyau (`access(2)`, Linux et macOS) si le dossier de chaque fichier encore présent est
  inscriptible ; sinon `409` qui nomme le dossier et la cause (`:ro`, PUID/PGID), rien n'est
  supprimé. Sous Windows, la vérification est sautée (ACL).
- **`indexer.CheckDeletable` ne regarde pas le disque** : l'administration l'appelle avant MediaHub,
  quand le gestionnaire va encore effacer les fichiers. `indexer.CheckErasable` le regarde, et sert
  la nouvelle route `GET …/storage/:id/deletable` (`204` ou l'erreur de la suppression) : MediaHub
  l'appelle quand l'administrateur garde le titre chez le gestionnaire, avant de supprimer les
  demandes. Un Onyx sans cette route ne bloque rien (MediaHub reçoit un 404 en texte brut).

## Conséquences

- Un Onyx monté en `:ro` peut faire de la place, tant qu'un gestionnaire suit le titre.
- Retirer un titre d'un gestionnaire ne se rattrape plus par sa corbeille : la suppression est
  définitive.
- Un titre qu'aucun gestionnaire ne suit, sur un disque en lecture seule, ne peut pas être effacé :
  Onyx le dit, ses demandes MediaHub sont déjà parties.
