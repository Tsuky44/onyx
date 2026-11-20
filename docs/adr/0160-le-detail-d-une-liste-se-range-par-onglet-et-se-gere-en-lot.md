# ADR-0160 — Le détail d'une liste se range par onglet et se gère en lot

- **Statut :** accepté
- **Date :** 2026-11-19
- **Portée :** le serveur (`server/watchlists/progress.go`, `server/watchlists/read.go`,
  `server/models/watch_list.go`, `contract/watch_list.json`,
  `contract/watch_list_item.json`) et l'app (`app/lib/models/watch_list.dart`,
  `app/lib/providers/watch_lists_provider.dart`, `app/lib/screens/lists/list_detail_screen.dart`,
  `app/lib/screens/lists/list_detail_view.dart`, `app/lib/screens/lists/widgets/`).
  Complète les ADR-0070 et 0159 ; n'en contredit aucun point.

## Contexte

Le détail d'une liste n'avait que l'affiche de chaque titre, un mode « Retirer des
titres » qu'on traversait un titre à la fois, et jusqu'à cinq boutons contour dans
l'en-tête, « Supprimer » compris. On ne pouvait ni ne savait rien filtrer (ce qu'on
a vu, ce qu'il faut demander), ni déplacer un titre d'une liste à une autre, ni
lancer le prochain titre depuis la liste. L'ADR-0159 a donné aux résumés la
progression de la liste ; le détail, lui, ne disait pas titre par titre ce qui est vu.

## Décision

1. **Le serveur dit ce qui est vu, titre par titre.** Chaque élément du détail porte
   `watched` : le calcul de l'ADR-0159 (film terminé, série dont chaque épisode présent
   l'est), réutilisé sans le dupliquer. Il vaut faux pour un titre que le serveur n'a
   pas, et pour tout élément renvoyé par une écriture (seul le détail le remplit).
   L'app ne le recalcule pas : `percentWatched` ne dit rien d'une série.
2. **Des onglets et un tri, côté app.** Tous / À voir / Vus / À demander rangent les
   éléments déjà reçus (`list_detail_view.dart`, pur et testé) ; le tri (récents, plus
   anciens, titre, année) aussi. Un onglet sans titre disparaît, sauf « Tous » et
   celui qui est ouvert. Rien de ceci n'ajoute d'appel au serveur.
3. **Une seule action principale, le reste dans « ⋯ ».** L'en-tête lance le prochain
   titre (`next_item`, ADR-0159) et propose « Partager » ; modifier, sélectionner,
   retirer les titres vus, quitter et supprimer vivent dans un menu dont les lignes
   suivent ce que le compte peut faire (propriétaire, invité qui remplit, lecteur,
   « À regarder plus tard » qui ne se renomme ni ne se supprime).
4. **La sélection remplace « Retirer des titres ».** Un mode où toucher une affiche la
   coche, avec une barre : déplacer vers…, copier vers…, retirer. Le retour la quitte
   avant de fermer la liste. Le clic droit et l'appui long ouvrent le même menu pour
   une seule affiche.
5. **Déplacer et copier ne demandent aucune nouvelle route.** Copier, c'est
   `POST /api/lists/:id/items` pour chaque titre : un titre déjà présent n'est pas
   doublé (ADR-0070 §5), le serveur renvoie l'élément existant. Déplacer copie d'abord,
   puis retire de la liste d'origine **seulement ce qui est bien arrivé**, pour qu'un
   échec ne perde aucun titre. Le résultat dit combien ont échoué.
6. **Un retrait se défait.** Plus de confirmation bloquante : un retrait (d'un titre ou
   d'une sélection) montre pendant six secondes une barre « Annuler » qui remet les
   titres par le même appel qu'une copie. Ils reviennent en tête, avec la date du
   moment : l'ordre d'ajout d'origine n'est pas conservé. La suppression d'une liste
   garde sa confirmation.
7. **Le lot est séquentiel.** Un appel par titre, dans l'ordre, jusqu'à la borne d'une
   liste (1 000) : assez simple pour que chaque échec se compte, et le serveur reste
   le seul à décider. Une route de lot se justifiera si l'usage montre des sélections
   de centaines de titres.

## Alternatives écartées

- **Calculer « vu » dans l'app** à partir de `media.percentWatched` : faux pour une
  série et pour un film proche de la fin (ADR-0159).
- **Un point d'accès « déplacer »** : il dupliquerait l'ajout et la suppression, qui
  portent déjà les droits (propriétaire, invité) et les bornes.
- **Une vue en rangées ou un réordonnancement à la main** : le modèle n'a pas de
  position d'un titre dans sa liste ; cela demanderait une migration et une route.
  Maquetté, pas retenu pour l'instant.

## Conséquences

- Un serveur d'avant cette décision ne renvoie pas `watched` : tous les titres sont
  « non vus », l'onglet Vus reste vide, « À voir » montre tout ce que le serveur a.
- `GET /api/lists/:id` relit la progression de la seule liste ouverte : une requête de
  plus par ouverture, bornée par les 1 000 titres d'une liste.
- « Dupliquer la liste », « Enregistrer dans mes listes » (copier la liste d'un autre
  compte) et « Marquer comme vu » ne sont pas faits : ils demandent chacun une route.
