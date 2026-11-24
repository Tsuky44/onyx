# ADR-0155 — Un seul docker-compose réglé par .env, et des bibliothèques préremplies

> Précisé par l'ADR-0164 (assistant d'installation).
>
> **Réduit encore le 2026-11-20, à la demande de l'utilisateur** (« un compose le plus simple
> possible ») : `docker-compose.yml` ne porte plus que l'image, le port, `./data` et `./media`
> (une douzaine de lignes), sans variable ni `env_file`. `.env.example` est supprimé ; les
> réglages avancés (`PUID`/`PGID`, `TZ`, `VIDEO_ENCODER`, HTTPS…) se posent dans un bloc
> `environment:` du compose, listés dans `server/README.md`. Les points 1 et 2 de la décision
> ci-dessous ne décrivent plus le fichier ; le serveur du point 3 et la fenêtre du point 4 sont
> inchangés.

- **Statut :** accepté, à la demande de l'utilisateur (2026-11-18 : « refais un compose propre […]
  pour que les utilisateurs aient juste à le prendre et à remplir », puis « préremplir ça en
  fonction de ce qu'on a mis dans la config »). Vérifié par `docker compose config` et en test,
  **pas encore lancé sur un serveur**.
- **Date :** 2026-11-18
- **Portée :** `docker-compose.yml` (réécrit), `.env.example` (nouveau), `.gitignore` (`/.env`),
  `docker-compose.prod.yml` (retiré), `README.md`, `server/README.md`,
  `server/libraries/folders.go` (nouveau : `SuggestFolders`, `GuessKind`, `MediaRoot`),
  `server/handlers/libraries.go` (`ListLibraryFolders`), `server/main.go`
  (`GET /api/libraries/folders`), `contract/library_folders.json`,
  `app/lib/models/media_library.dart` (`LibraryFolder`, `LibraryFolders`),
  `app/lib/services/api/libraries.dart` (`getLibraryFolders`),
  `app/lib/screens/settings/widgets/library_editor_dialog.dart`.
- **Remplace** les deux compose d'avant : `docker-compose.yml` (construction depuis les sources) et
  `docker-compose.prod.yml` (l'image publiée).

## Contexte

Le dépôt avait deux compose presque identiques, l'un construit depuis les sources, l'autre tiré de
ghcr.io, chacun avec ses chemins à remplacer dans le fichier même. Ils posaient encore `MOVIES_DIR`
et `SERIES_DIR`, que le serveur ne lit plus que pour reprendre une base d'avant les bibliothèques
(ADR-0058), et une adresse MediaHub par défaut que la plupart des installations n'ont pas.

Une fois le serveur lancé, créer une bibliothèque demandait de taper le chemin tel que le conteneur
le voit (« /media/Films ») : il fallait relire le compose pour le savoir, et une faute de frappe ne
se disait qu'à l'enregistrement.

## Décision

1. **Un seul `docker-compose.yml`, qui ne se modifie pas.** Il tire l'image publiée
   (`ONYX_VERSION`, `latest` par défaut) ; `build: ./server` y est commenté pour qui construit
   depuis les sources. Les médias de l'hôte (`MEDIA_PATH`, obligatoire) sont montés sous un seul
   dossier, `/media`, en lecture seule sauf `MEDIA_ACCESS=rw`. Les journaux du conteneur tournent
   (10 Mo, trois fichiers). Seuls le transcodage matériel (`devices`) et un second disque se
   décommentent dans le fichier.
2. **Tous les réglages dans `.env`**, copié depuis `.env.example`. `env_file: .env` le passe tel quel
   au serveur : un réglage facultatif s'active en décommentant sa ligne, sans toucher au compose.
   `.env` est ignoré par git (il porte les clés). `MOVIES_DIR`, `SERIES_DIR` et l'adresse MediaHub
   par défaut disparaissent.
3. **Le serveur propose les dossiers montés** : `GET /api/libraries/folders` (`manage_settings`)
   liste les sous-dossiers de `/media` (`MEDIA_ROOT` hors de Docker) qu'aucune bibliothèque ne
   couvre, avec le type que leur nom suggère (« Films », « Movies » ; « Séries », « TV Shows »),
   films d'abord. Un `/media` sans sous-dossier se propose lui-même ; absent ou illisible, la liste
   est vide.
4. **La fenêtre « Nouvelle bibliothèque » se préremplit** avec le premier dossier libre : nom, dossier
   et type. Les autres sont des pastilles sous le champ du dossier. Changer de type fait suivre le
   dossier proposé ; un nom ou un dossier tapé à la main n'est jamais remplacé. Un serveur plus
   ancien répond 404 : rien à proposer, le formulaire reste à remplir à la main.

### Écarté

- **Deux compose, ou un `.env` versionné** : un `.env` rempli dans un clone finit commité avec sa
  clé TMDB.
- **Un montage par bibliothèque (`/media/Films`, `/media/Series`) dans le compose** : il fallait
  l'éditer pour chaque dossier, et ses noms ne collaient pas toujours à ceux du disque.
- **Retirer `platform: linux/amd64`** : l'image des versions n'est publiée que pour amd64
  (ADR-0051).

## Conséquences

- Une installation existante qui passe au nouveau compose doit garder les mêmes chemins dans le
  conteneur : ses bibliothèques sont enregistrées par chemin (`/media/Films`…). Avec un
  `MEDIA_PATH` qui contient `Films/` et `Series/`, rien ne change.
- Le nom du conteneur reste `onyx-server`, celui de l'ancien compose de production.
- Épinglé par `server/libraries/folders_test.go` (le type lu dans le nom, l'ordre, les dossiers
  déjà couverts, le dossier monté seul, l'absence de `/media`),
  `TestLibraryFoldersSuggestWhatIsMountedAndFree` et `app/test/libraries_test.dart` (le
  préremplissage, le type qui fait suivre le dossier, la saisie à la main gardée, le contrat).
