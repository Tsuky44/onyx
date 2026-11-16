# ADR-0129 — Un invité peut remplir une liste, ou seulement la voir

- **Statut :** accepté
- **Date :** 2026-11-14
- **Portée :** le serveur (`server/watchlists/members.go`, `server/watchlists/watchlists.go`,
  `server/watchlists/read.go`, `server/handlers/watch_list_members.go`, migration 31, capacité
  `watch_list_member_roles` dans `server/handlers/ping.go`, `contract/watch_list*.json`) et l'app
  (`app/lib/models/watch_list.dart`, `app/lib/services/api/watch_lists.dart`,
  `app/lib/providers/watch_lists_provider.dart`, `app/lib/widgets/global/watch_list_members_sheet.dart`,
  `app/lib/screens/lists/list_detail_screen.dart`).

## Contexte

L'ADR-0127 a fait de l'invité un compte qui remplit la liste, et du partage (`is_shared`) une
vitrine pour tout le serveur. Il manquait le cas du milieu : montrer une liste privée à une ou
deux personnes, sans leur donner le droit d'y toucher. On veut pouvoir composer « Soirée ciné »
à deux, la montrer à un troisième, ou la montrer à tout le monde.

## Décision

1. **Un invité a un rôle.** `watch_list_members.role` vaut `editor` (il ajoute et retire des
   titres) ou `viewer` (il la voit, même privée). Les invitations d'avant la migration 31 restent
   `editor` : c'est ce qu'elles donnaient.
2. **Qui lit, qui écrit.** Lisent : le propriétaire, ses invités quel que soit leur rôle, et tout
   le serveur si `is_shared`. Écrivent : le propriétaire et les invités `editor`. Un `viewer` qui
   écrit reçoit `403` (il voit la liste), comme un compte qui lit une liste partagée.
3. **Une liste dit au compte ce qu'il y est.** `can_edit` dit s'il peut la remplir, `is_member`
   s'il y est invité, pour la remplir ou la voir : c'est ce qui montre « Quitter la liste ».
   `member_count` compte tous les invités. Chaque invité de `members` porte son `role`.
4. **`PUT /api/lists/:id/members/:user`** accepte le corps facultatif `{"role": "viewer"}` ou
   `{"role": "editor"}`. Sans corps, c'est `editor` : une app d'avant les rôles invite comme
   avant. Inviter un invité change son rôle, sans le compter deux fois dans la borne de 50.
5. **La capacité `watch_list_member_roles`** sur `/api/ping`. L'app n'envoie de rôle et ne
   propose « Peut voir » qu'à un serveur qui l'annonce : un serveur plus ancien ignorerait le
   corps et donnerait le droit d'écrire à qui ne devait que voir.
6. **Dans l'app,** le bouton « Inviter » devient « Partager ». Sa feuille réunit les deux
   gestes : l'interrupteur « Tout le serveur peut la voir » (`is_shared`) et, pour chaque compte,
   « Aucun accès », « Peut voir » ou « Peut ajouter des titres ». Les choix se déplient sous la
   personne, en liste verticale : un seul élément focalisable par ligne, que le D-pad parcourt
   sans détour. L'écran de la liste distingue « Remplie avec » et « Partagée avec ».

Contredit l'ADR-0127, qui écartait « des rôles (lecteur, éditeur, administrateur) » parce
qu'une liste n'avait qu'un enjeu : montrer à quelques-uns sans tout montrer en est un second.
On s'arrête à deux rôles ; gérer la liste (renommer, partager, inviter, supprimer) reste au seul
propriétaire.

## Alternatives écartées

- **Une seconde table de lecteurs.** Deux tables pour un même couple (liste, compte) laisseraient
  un compte à la fois lecteur et éditeur ; une colonne garde une seule vérité.
- **Des cases « voir » et « ajouter » indépendantes.** « Ajouter sans voir » n'a pas de sens ;
  trois états exclusifs disent tout.

## Conséquences

- Rendre privée une liste partagée ne coupe ni ses éditeurs ni ses lecteurs : retirer l'invité
  reste le seul geste qui retire l'accès (ADR-0127).
- Passer un éditeur en lecteur garde les titres qu'il a ajoutés : le serveur ne retient pas qui
  a ajouté quoi.
