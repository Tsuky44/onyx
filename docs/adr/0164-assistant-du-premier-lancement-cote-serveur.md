# ADR-0164 — L'assistant du premier lancement : explorateur confiné à /media, test TMDB, état d'installation et verrou des demandes

- **Statut :** accepté, à la demande de l'utilisateur (2026-11-20 : refaire le premier lancement en
  assistant guidé — compte propriétaire, bibliothèques choisies dans un explorateur, clé TMDB
  testable, service de demandes testable). Vérifié par les tests du serveur (Docker, `golang:1.27`),
  **pas encore lancé sur un serveur neuf**. Cette ADR ne couvre que le serveur : l'écran de l'app
  fait l'objet de la sienne.
- **Date :** 2026-11-20
- **Portée :** `server/libraries/browse.go` (nouveau : `Browse`), `server/handlers/fs_browse.go`,
  `server/tmdb/tmdb.go` (`CheckKey`), `server/handlers/settings_tmdb_check.go`,
  `server/handlers/setup.go`, `server/config/settings.go` (`setup_completed`,
  `CheckRequestServiceNeedsTMDB`), `server/handlers/settings.go`, `server/database/migrations.go`
  (migration 32), `server/handlers/ping.go` (capacité `setup_wizard`), `server/main.go`,
  `server/i18n/en.go`, `contract/fs_browse.json`, `contract/setup_state.json`,
  `contract/tmdb_key_test.json`, `contract/ping.json`, `server/README.md`.
- **Précise** l'ADR-0155 : les chemins ne se tapent plus à la main, et `GET /api/libraries/folders`
  (premier niveau de `/media`) n'est plus la seule aide au choix d'un dossier.

## Contexte

Un serveur neuf démarre sans bibliothèque ni clé TMDB (ADR-0058, ADR-0155). L'ADR-0155 propose les
sous-dossiers de `/media` qu'aucune bibliothèque ne couvre, mais seulement ceux du premier niveau :
un disque rangé en `/media/Films/Action` obligeait encore à taper le chemin, et une faute de frappe
ne se disait qu'à l'enregistrement.

Deux autres réglages ne se vérifiaient qu'à l'usage. Une clé TMDB fausse, ou un conteneur sans accès
à Internet, se voyaient à l'écran des demandes resté vide. Et un service de demandes (MediaHub,
Overseerr, Jellyseerr) s'enregistrait sans clé TMDB, alors que le catalogue, les fiches et les
épisodes des demandes viennent de TMDB **pour les trois services** (`TmdbRequestCatalog`,
`TmdbRequestDetails` et `TmdbRequestSeasonEpisodes` répondent 503 sans clé ; ADR-0134, ADR-0135) :
le service ne recevait que des demandes qu'aucun écran ne pouvait émettre. Aucun des trois n'y
échappe, le verrou les couvre donc tous.

## Décision

1. **Un explorateur confiné à la racine des médias** : `GET /api/fs/browse?path=` (`manage_settings`,
   à côté de `/api/libraries/folders`). Sans `path`, la racine, `libraries.MediaRoot()` (`/media`, ou
   `MEDIA_ROOT`). Le serveur ne sort **jamais** de cette racine :
   - un segment `..` est refusé tel quel (400), avant tout nettoyage ; le chemin nettoyé doit être
     la racine ou un de ses descendants, par composants entiers (`/media-autre` n'est pas sous
     `/media`) ; un octet nul est refusé ; un chemin relatif est hors racine (400) ;
   - un dossier absent ou qui n'en est pas un répond 404 ;
   - les liens symboliques de dossiers sont **suivis**, comme `SuggestFolders` : un partage monté
     par un lien sous `/media` reste un dossier de médias. Le confinement est donc lexical : les
     chemins rendus (`path`, `parent`, `breadcrumb`) restent ceux de `/media`, jamais ceux de la
     cible du lien, et la cible, demandée par son propre chemin, est hors racine (400). Un lien
     posé par l'administrateur de l'hôte montre ce qu'il désigne : c'est le but du lien.
   La réponse porte `root`, `path`, `parent` (`null` à la racine), `breadcrumb`, `folders`
   (`name`, `path`, `kind` deviné par `GuessKind`, `covered`, `video_count`, `video_count_capped`),
   `readable` et `empty_root`. `covered` reprend la règle de `SuggestFolders` (la fonction `covers`
   leur est commune). Les dossiers cachés sont ignorés ; la liste est alphabétique, bornée à 500.
   - **Comptage des vidéos borné** : 4 niveaux (Série/Saison/épisode tient dedans), 2 000 entrées par
     dossier, 400 ms par dossier et 2 s au total, en parallèle (4 à la fois) ; `video_count_capped`
     dit que le chiffre est un minimum. Un délai dépassé se dit « coupé », jamais « vide ». Il sert à
     rassurer (« ce dossier contient bien des films »), pas à compter ; la profondeur borne aussi
     une boucle de liens. L'indexeur définit les extensions vidéo (`IsVideoFile`) ; il importe
     `libraries`, qui reçoit donc le test en paramètre.
   - **`empty_root`** : la racine est absente, illisible ou sans sous-dossier. Ce n'est pas une
     erreur (200 avec `readable: false`) : c'est le diagnostic « montez votre dossier dans le
     compose » que l'assistant doit pouvoir afficher avant la première bibliothèque.
2. **Le test de la clé TMDB** : `POST /api/settings/tmdb/test` (`manage_settings`), calqué sur
   `TestMediaHubLink`. Corps `{"tmdb_api_key"}` facultatif (vide : la clé en place). Le paquet `tmdb`
   gagne `CheckKey(ctx, client, key)`, seul appel qui prend une clé explicite : il demande la route
   légère `/configuration` et garde la protection du paquet, la clé est retirée de toute erreur
   (ADR-0050). Réponse `200` `{"ok", "reason", "message"}` : `invalid_key` sur un 401 de TMDB,
   `unreachable` sur une erreur réseau, DNS, un délai (8 s) ou un 5xx (le serveur n'a pas pu juger la
   clé, et ne dit pas qu'elle est fausse), `no_key` sans clé. Message traduit (FR/EN) dans la langue
   de la requête. La clé n'est jamais renvoyée ni journalisée.
3. **L'état de l'installation** : `GET /api/setup/state` (`manage_settings`) rend
   `{"completed", "libraries": {"count", "done"}, "tmdb": {"done"}, "requests": {"done", "available"}}`.
   Tout se **calcule depuis les données** (une bibliothèque, une clé TMDB, une adresse et une clé de
   service de demandes), sans drapeau, sauf `completed` : le réglage `setup_completed` de
   `app_settings`, posé par `POST /api/setup/complete` (204, idempotent) et que rien ne retire.
   `requests.available` vaut vrai quand une clé TMDB existe (enregistrée ou `TMDB_API_KEY`). Ce
   réglage n'est pas un champ de `PUT /api/settings`. Capacité `setup_wizard` sur `/api/ping`, pour
   qu'un serveur plus ancien (404) se distingue sans appel.
4. **Migration 32** : sur une base qui a déjà au moins une bibliothèque, `setup_completed` est posé
   (`INSERT OR IGNORE … WHERE EXISTS (SELECT 1 FROM libraries)`). Les installations existantes, y
   compris celles dont la migration 22 vient de reprendre `MOVIES_DIR` et `SERIES_DIR`, ne voient
   jamais l'assistant. Un serveur neuf, sans bibliothèque, le garde ouvert.
5. **Le verrou des demandes sans TMDB** : `PUT /api/settings` répond 409 (`writeJSONError`, message
   traduit) quand il met en place ou change le service de demandes (`request_service`,
   `mediahub_url`, `mediahub_api_key`) sans qu'une clé TMDB existe une fois la requête appliquée :
   celle de la même requête compte, ainsi que celle déjà enregistrée ou de l'environnement ; effacer
   la clé dans la même requête ne la compte plus. Refusé **avant toute écriture**.
   - Ne sont jamais bloqués : rejouer les valeurs déjà en place, les effacer, un réglage sans
     rapport — une configuration déjà en place n'est jamais touchée, même si la clé TMDB a disparu.
   - Le verrou est dans le handler du formulaire (`config.CheckRequestServiceNeedsTMDB`), pas dans
     `ApplyUpdate` : MediaHub réécrit son adresse et sa clé par la clé d'intégration
     (`PUT /api/integrations/mediahub/link`, ADR-0102), parle d'un service déjà en place et ne doit
     pas être refusé.

### Écarté

- **Laisser taper un chemin libre, ou monter au-dessus de `/media`** : un administrateur de l'app
  verrait tout le disque du conteneur. La racine est la seule porte.
- **Résoudre les liens symboliques et refuser ceux qui sortent de la racine** : cela casse le partage
  réseau monté par un lien sous `/media`, que `SuggestFolders` suit déjà.
- **Un drapeau par étape de l'assistant** : il divergerait de la réalité dès qu'un réglage se fait
  ailleurs (compose, ancien écran de réglages, MediaHub). Seul `completed` en est un.
- **Verrouiller dans `ApplyUpdate`** : voir le point 5.

## Conséquences

- L'app peut descendre dans `/media` dossier par dossier, voir ce qui est déjà pris et combien de
  vidéos s'y trouvent, et diagnostiquer un dossier non monté, sans que le serveur n'expose rien
  au-dessus de sa racine.
- Une clé TMDB et une adresse de compagnon se testent depuis le serveur, qui est seul à savoir s'il
  joint TMDB ou le compagnon.
- Un service de demandes ne s'enregistre plus sans clé TMDB depuis le formulaire des réglages. Une
  app d'avant l'assistant qui enregistre un service sans clé reçoit un 409 : son message d'erreur
  s'affiche comme n'importe quelle autre erreur de réglage.
- `contract/ping.json` gagne la capacité `setup_wizard` (ajout, rien n'est retiré).
- Un seul `video_count` ne sait pas dire « beaucoup » au-delà des bornes : un dossier de plus de
  2 000 entrées s'affiche avec `video_count_capped`.
