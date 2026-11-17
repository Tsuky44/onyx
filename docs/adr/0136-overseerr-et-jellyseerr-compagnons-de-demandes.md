# ADR-0136 — Overseerr et Jellyseerr se branchent comme compagnons de demandes

- **Statut :** accepté
- **Date :** 2026-11-17
- **Portée :** `server/mediahub/service.go`, `server/mediahub/seerr*.go`, le réglage
  `request_service` (`server/config/settings.go`), `server/handlers/mediahub.go`,
  `server/handlers/mediahub_link.go`, `server/handlers/mediahub_moderation.go`, la capacité
  `request_services`, `contract/seerr/`, et côté app `models/request_service.dart` et
  `screens/settings/pages/integrations_page.dart`. Prolonge les ADR-0089, 0102, 0115 et 0128.

## Contexte

Le service de demandes d'Onyx était MediaHub, ou OnyxHub tant qu'il dure (ADR-0089). Beaucoup
d'installations ont déjà Overseerr ou Jellyseerr devant Radarr et Sonarr, avec leurs comptes, leurs
quotas et leurs règles d'approbation : leur demander d'installer MediaHub en plus pour demander
depuis Onyx n'a pas de sens.

Overseerr et Jellyseerr partagent une même API (celle de Seerr, `/api/v1`), très différente de
celle de MediaHub : une clé d'administrateur dans `X-Api-Key`, `X-Api-User` pour agir au nom d'un de
leurs comptes, des demandes sans titre ni affiche, pas de lot de disponibilités, pas d'évènements
signés, pas de recherche interactive, et aucun moyen pour eux d'appeler Onyx.

## Décision

- **Le service se choisit, il ne se devine pas.** Un réglage `request_service` (`mediahub`,
  `overseerr`, `jellyseerr` ; repli `REQUEST_SERVICE`, puis `mediahub`) dit qui est à l'adresse.
  `mediahub_url` et `mediahub_api_key` gardent leur nom : MediaHub (`PUT /link`) et les apps déjà
  installées les écrivent encore. Un `PUT /api/settings` qui ne parle pas du service le garde ; une
  valeur inconnue est refusée (`400`) avant toute écriture. MediaHub et OnyxHub se distinguent
  toujours par sonde ; Overseerr et Jellyseerr ne se sondent pas.
- **Un troisième dialecte derrière le même client.** `mediahub.Client` reçoit le service et parle
  `DialectSeerr` : les handlers appellent les mêmes méthodes (`Availability`, `Requests`, `Feed`,
  `Moderate`, `Access`, `Progress`, `ForgetMedia`) et l'app reçoit les mêmes formats (les lots de
  `contract/requests_mine.json`). Rien ne change dans les écrans de demandes.
- **Le compte Seerr est celui qui porte le nom du compte Onyx** (nom local, nom affiché, nom Plex ou
  Jellyfin, ou adresse, sans tenir compte de la casse). Onyx agit alors en son nom
  (`X-Api-User`) : Seerr applique ses droits, ses quotas et son approbation automatique. **Sans
  homonyme, le compte agit par le compte de la clé** : il peut demander tout de suite, et partage
  ses demandes (« Mes demandes ») avec les autres comptes sans homonyme. `linked: false` le dit à
  l'app, et le test de liaison à l'administrateur. Les comptes de Seerr se relisent toutes les
  cinq minutes.
- **Onyx borne ce que l'app propose.** `GET /api/requests/access` ne rend « toutes les demandes »,
  la modération et la suppression qu'à qui a `manage_settings`, le droit qu'exigent déjà ces routes
  (ADR-0089). Sans cette borne, un compte sans homonyme hériterait à l'écran des droits
  d'administrateur du compte de la clé.
- **Ce que Seerr ne donne pas, Onyx le lit sur la fiche.** `GET /movie/:id` et `GET /tv/:id` portent
  le titre, l'affiche, l'état, les demandes et les téléchargements d'un titre. Une fiche se retient
  30 s (une page du catalogue se lit en six appels à la fois, puis de mémoire), le titre et
  l'affiche un jour. Le suivi d'un téléchargement vient de la file de Radarr/Sonarr que Seerr
  relève ; l'import n'y est pas.
- **Les statuts se traduisent une fois**, dans `seerr_requests.go` et `seerr_media.go` : la
  décision de la demande d'abord (en attente, refusée), puis ce que le titre ou la saison est
  devenu. Overseerr laisse « approuvée » une demande dont le titre est arrivé ; une série arrivée en
  partie se lit saison par saison sur sa fiche. La bibliothèque d'Onyx garde le dernier mot
  (ADR-0084).
- **Les refus arrivent en français.** Seerr répond `{ message }` en anglais ; les refus qu'un
  compte rencontre (quota, déjà demandé, titre bloqué, droit manquant) sont traduits dans la forme
  que l'app affiche (`{ error }`). Son `202` « plus aucune saison à demander » devient un `409`, et
  son `401` un `403`, que l'app ne prend pas pour une session Onyx expirée.
- **Supprimer partout** (ADR-0115, 0128) : pour un film ou une série entière, Onyx demande à Seerr
  de le retirer de Radarr ou Sonarr avec ses fichiers (`DELETE /media/:id/file`), puis d'oublier la
  fiche et ses demandes (`DELETE /media/:id`), avant d'effacer ce qui reste. Un Overseerr sans la
  première route, ou un titre que Radarr n'a pas, n'empêche rien.
- **La clé de Seerr n'ouvre rien chez Onyx.** Les routes que MediaHub appelle avec la clé
  d'intégration (évènements, annuaire, stockage, rachat d'un code, ADR-0090, 0102, 0114) la refusent
  tant que le service est Overseerr ou Jellyseerr : ils n'appellent jamais Onyx, et leur clé
  n'a pas à valoir un droit d'effacer des fichiers ici.
- **L'app propose le choix quand le serveur l'annonce** (capacité `request_services`) : trois
  capsules dans Paramètres → Services. Changer de service demande de coller sa clé ; celle de
  l'ancien ne se garde pas en silence. Un serveur d'avant ne voit que MediaHub et ne reçoit pas le
  réglage.

## Conséquences

- Un compte Onyx sans homonyme demande avec les droits du compte de la clé, donc sans approbation
  si ce compte est administrateur de Seerr. C'est le droit `request_media` d'Onyx qui décide alors
  qui peut demander ; créer chez Seerr un compte du même nom rend à chacun ses demandes, ses quotas
  et son approbation. Comme avec MediaHub, le nom est le seul lien : un nom choisi à l'inscription
  peut être celui d'un compte Seerr.
- Pas d'évènements : un titre arrivé se voit quand la fiche retenue expire (30 s) et quand le
  moniteur d'Onyx indexe le fichier, pas à l'instant de l'import.
- Pas de recherche interactive, pas de motif de refus (Seerr n'en garde pas), pas de « Ouvrir
  MediaHub », pas de gestionnaire de stockage côté compagnon : `501`, ou bouton absent.
- Une saison seule ne se retire pas de Sonarr par Seerr : Onyx efface ses fichiers, Sonarr la suit
  encore et peut la retélécharger.
- L'administrateur sans homonyme n'est pas notifié des demandes des autres comptes sans homonyme :
  elles sont, pour Seerr, les siennes.
- La première lecture d'une longue liste de demandes paie une fiche par titre, six à la fois.
- `contract/seerr/` est écrit d'après le code de Seerr, pas copié d'une instance : un champ qui
  change chez eux ne casse aucun test ici.
