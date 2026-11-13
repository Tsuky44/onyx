# ADR-0127 — Le propriétaire d'une liste invite des comptes à la remplir

- **Statut :** accepté
- **Date :** 2026-11-13
- **Portée :** le serveur (`server/watchlists/members.go`, `server/handlers/watch_list_members.go`,
  migration 30, capacité `watch_list_members` dans `server/handlers/ping.go`,
  `contract/watch_list*.json`) et l'app (`app/lib/models/watch_list.dart`,
  `app/lib/providers/watch_lists_provider.dart`, `app/lib/services/api/watch_lists.dart`,
  `app/lib/widgets/global/watch_list_members_sheet.dart`, `app/lib/screens/lists/`).

## Contexte

L'ADR-0070 a écarté « partager avec des comptes choisis » : rien ne le demandait, et une table de
destinataires se rajoute sans toucher aux listes existantes. La demande est là, et elle va plus
loin que lire : composer une liste à plusieurs — « Soirée ciné », « Films de Noël » — où chacun
peut ajouter un film ou une série.

## Décision

1. **Un invité est un compte à qui le propriétaire donne le droit d'écrire.** La table
   `watch_list_members (list_id, user_id, added_at)` le porte, supprimée avec la liste ou avec le
   compte. Un invité ajoute et retire des titres, rien d'autre : renommer, partager, supprimer et
   inviter restent au propriétaire.
2. **L'invitation ouvre aussi la lecture.** Une liste privée est lisible par ses invités ; elle
   apparaît dans le groupe `shared` de `GET /api/lists`, avec `can_edit: true`. Une liste partagée
   avec tous (ADR-0070) reste en lecture seule pour qui n'est pas invité : `is_shared` dit qui
   peut lire, les invités disent qui peut écrire. Pour qui n'a aucun droit sur une liste privée,
   rien ne change : 404.
3. **Seules les listes `custom` s'invitent.** « À regarder plus tard » est le carnet personnel du
   compte ; on ne s'invite pas soi-même.
4. **Qui retire quoi.** Le propriétaire retire n'importe quel invité ; un invité ne retire que
   lui-même, c'est-à-dire qu'il quitte la liste. Un invité retire n'importe quel titre : la liste
   est commune, et le serveur ne retient pas qui a ajouté quoi.
5. **Choisir qui inviter.** `GET /api/list-people` renvoie les autres comptes du serveur (id, nom,
   avatar) à tout compte connecté. Les comptes se voient déjà par le nom des propriétaires de
   listes partagées ; rien d'autre n'est exposé (pas de droits, pas de date de connexion).
6. **Bornes.** 50 invités par liste : qui peut écrire dans une liste doit rester une poignée de
   personnes.
7. **Routes.** `PUT /api/lists/:id/members/:user` invite (idempotent, renvoie les invités),
   `DELETE /api/lists/:id/members/:user` retire ou quitte, et `GET /api/lists/:id` renvoie
   `members`. La capacité `watch_list_members` sur `/api/ping` : l'app ne montre pas « Inviter » à
   un serveur plus ancien (ADR-0051).
8. **Dans l'app,** la feuille « Ajouter à une liste » propose aussi les listes où l'on est invité
   (avec le nom de leur propriétaire), et l'écran d'une liste montre « Inviter » à son
   propriétaire, « Retirer des titres » à tout compte qui peut écrire, « Quitter la liste » à un
   invité.

## Alternatives écartées

- **Ouvrir en écriture toute liste partagée.** N'importe qui pourrait vider une liste : le partage
  à tous reste une vitrine.
- **Des rôles (lecteur, éditeur, administrateur).** Une liste n'a qu'un enjeu ; propriétaire et
  invités suffisent.
- **Mémoriser qui a ajouté chaque titre.** Utile, mais la demande est d'ajouter ; une colonne
  `added_by` se rajoute sans toucher à ce qui est ici.

## Conséquences

- Supprimer un compte retire ses invitations ; supprimer une liste retire ses invités.
- Un propriétaire qui rend privée une liste partagée ne coupe pas ses invités : retirer l'invité
  est le seul geste qui retire l'accès.
- Avec plusieurs serveurs (ADR-0013), les invités sont ceux du serveur actif.
