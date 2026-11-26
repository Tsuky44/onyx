# Sélecteur de serveurs en cartes toujours accessible et serveurs pairs proposés

- **Statut :** accepté
- **Date :** 2026-11-25
- **Portée :**
  - Serveur : `handlers/federation.go`, `handlers/federation_admin.go` (`ListSuggestedPeerServers`), `handlers/ping.go` (`CapabilitySuggestedPeers`), `main.go` (`GET /api/peers/suggested`), `handlers/federation_test.go`, `server/README.md`.
  - App : `models/server_capabilities.dart`, `models/server_account.dart` (`SuggestedPeerServer`), `services/api/peers.dart`, `services/api_client.dart`, `screens/settings/servers_support.dart` (`loadSuggestedServers`), `screens/settings/add_server_screen.dart`, `screens/auth/widgets/server_choice_card.dart`, `screens/auth/server_switcher_screen.dart`, `widgets/global/account_menu_panel.dart`, `widgets/global/account_menu.dart`, `l10n/en.dart`, `test/account_menu_test.dart`, `test/server_switcher_screen_test.dart`.
- **Contredit l'ADR-0013** sur le masquage du sélecteur quand l'appareil n'a qu'un seul serveur et sur les entrées « Passer sur {0} » dans le menu du compte. Prolonge l'[ADR-0017](0017-serveurs-lies-et-progression-entre-serveurs.md).

## Contexte

1. L'[ADR-0013](0013-plusieurs-serveurs-et-demandes-d-acces.md) n'affichait le changement de serveur dans le menu du compte qu'à partir de deux serveurs enregistrés (« Passer sur {nom} »), obligeant à passer par *Paramètres → Serveurs* pour ajouter ou configurer un serveur.
2. Une première version à deux boutons (`+ Ajouter` et `Configurer les serveurs`) exposait deux interfaces distinctes pour gérer et ajouter des serveurs.
3. Les paires de serveurs mutuellement acceptées par les administrateurs (`peer_servers` avec `local_approved = 1 AND remote_approved = 1`, ADR-0017) n'étaient visibles que sur `/api/peers` (réservé aux administrateurs) : un utilisateur qui ajoutait un serveur ne les voyait donc pas proposés de base.

## Décision

1. **`Gérer les serveurs` est toujours présent dans le menu du compte**, juste sous `Gérer les profils`, et remplace les lignes `Passer sur {0}`.
2. **Une seule interface de cartes (`ServerSwitcherScreen`)**, calquée sur `UserChoiceScreen` :
   - en mode normal : bascule au toucher d'un serveur (ou `UserChoiceScreen` s'il a plusieurs profils), une unique carte `+ Ajouter` ouvrant `AddServerScreen`, et un bouton `Gérer les serveurs` ;
   - en mode gestion (`_editing`, bouton `Terminé`) : gestion des serveurs sur la même grille (serveur principal, renommage, liaison/dissociation, retrait de l'appareil) et demandes d'accès en attente.
3. **Propositions automatiques dans `AddServerScreen`** : `GET /api/peers/suggested` (authentifié, capacité `suggested_peers`) expose aux utilisateurs connectés les seuls serveurs mutuellement acceptés (`server_id`, `name`, `url`, sans secret ni état interne). `loadSuggestedServers` fusionne ces serveurs pairs avec les comptes déjà liés sur un autre appareil (`serversNotOnThisDevice`) et les propose en haut d'`AddServerScreen` pour préremplir l'adresse en un tap.

## Conséquences

- Une seule entrée et un seul parcours d'ajout/gestion de serveurs depuis le menu du compte, cohérent avec les profils.
- Les serveurs partenaires mutuellement validés par les administrateurs sont découverts automatiquement lors de l'ajout.
- Épinglé par `federation_test.go`, `account_menu_test.dart` et `server_switcher_screen_test.dart`.
