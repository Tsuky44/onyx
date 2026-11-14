# ADR-0129 — Sur l'Apple TV, la recherche est l'écran du système, et toute recherche montre aussi les titres que le serveur n'a pas

- **Statut :** accepté. Le code natif est compilé par la CI de l'Apple TV et vérifié ici au
  compilateur Swift contre des bouchons d'UIKit ; **il n'a pas encore été vu sur une Apple TV**, et
  ce qui tient au moteur de focus de tvOS ne se voit que là (tableau « À vérifier sur l'appareil »).
- **Date :** 2026-11-14
- **Portée :** `app/tvos/Runner/SystemSearch*.swift` et `AppDelegate.swift` (l'hôte natif),
  `services/tv_system_search.dart` (le canal), `screens/search/tv_system_search_screen.dart` (la
  page hôte), `screens/search/search_shelves.dart`, `services/unavailable_titles_search.dart`,
  `widgets/global/unavailable_badge.dart`, `screens/search/tv_search_screen.dart`,
  `screens/library/search_results_screen.dart`, `widgets/global/tv_poster_wall.dart`,
  `screens/requests/widgets/request_media_card.dart`.
- **Contredit** l'[ADR-0126](0126-la-recherche-d-un-televiseur-ouvre-le-clavier-du-systeme-et-range-ses-resultats-par-rayons.md)
  sur deux points, parce que l'utilisateur le demande maintenant : sur l'Apple TV le clavier n'est
  plus celui qui couvre l'écran mais le clavier en ligne de tvOS, que l'ADR-0126 écartait « à faire
  si l'utilisateur le demande » (son point 1) ; et la recherche n'est plus seulement celle du
  catalogue chargé, elle interroge aussi le catalogue de demandes (son point 8). Le reste de
  l'ADR-0126 tient : c'est la recherche des autres téléviseurs, et le repli de l'Apple TV.
- **Prolonge** l'[ADR-0105](0105-lecteur-natif-sur-apple-tv.md) et
  l'[ADR-0120](0120-sous-l-ecran-natif-d-apple-tv-flutter-reste-le-cerveau.md) : un écran natif
  présenté par-dessus Flutter, qui reste le cerveau.

## Contexte

Deux demandes de l'utilisateur, sur Apple TV, capture de la recherche de YouTube à l'appui :

- « refais le truc recherche, quand on clique sur la loupe je veux arriver là, je veux la même
  recherche que YouTube : on a le clavier, ou on peut utiliser l'iPhone pour noter, ou sinon Siri,
  et on a les résultats ici » ;
- « si on cherche un média qui n'est pas disponible sur le serveur il doit quand même apparaître,
  mais avec un signe distinctif, trouve une idée cohérente avec le site ».

La recherche d'un téléviseur (ADR-0126) ouvrait le clavier du système en plein écran : on ne voyait
les résultats qu'une fois le clavier refermé. Et aucune recherche de l'app ne sortait de la
bibliothèque : un titre absent donnait « Aucun résultat », alors que l'onglet Demandes sait le
trouver et le demander.

L'écran de la capture est celui de tvOS : `UISearchController` dans un
`UISearchContainerViewController`. Le champ, le clavier en ligne, la dictée (bouton micro
maintenu) et le clavier qu'un iPhone propose n'existent que là. Flutter ne peut pas les dessiner,
et un clavier dessiné par l'app a déjà été refusé (ADR-0126).

## Décision

### 1. Sur l'Apple TV, la loupe présente l'écran de recherche du système

**L'écran entier est natif, affiches comprises**, présenté par-dessus Flutter
(`.overFullScreen`, comme le lecteur). Le moteur de focus d'UIKit va du clavier aux affiches et
remonte ; le clavier sort par le haut quand on descend dans la grille. Le montage est celui de la
session WWDC20 « Discover search suggestions for Apple TV » : un contrôleur à nous, qui prend le
`UISearchContainerViewController` pour enfant.

**Dart reste le cerveau**, par le canal `onyx/tv_search` :

| Sens | Message | Rôle |
|---|---|---|
| Dart → hôte | `present` | montre l'écran, avec son texte d'invite, les couleurs de l'app et un premier contenu ; répond vrai une fois l'écran devant |
| Dart → hôte | `update` | remplace les rayons sous le clavier |
| Dart → hôte | `hide` / `show` | retire l'écran sans l'oublier, puis le rend |
| Dart → hôte | `close` | le ferme pour de bon |
| hôte → Dart | `query` | le texte du champ a changé : tapé, dicté, saisi depuis un iPhone |
| hôte → Dart | `select` | l'affiche d'identifiant donné a été choisie |
| hôte → Dart | `closed` | l'écran a été quitté par Retour |

L'hôte ne connaît ni la bibliothèque ni le serveur. Il n'écrit aucun texte et n'invente aucune
couleur : Dart les envoie, déjà traduits, sous leur nom d'`AppColors`.

**La page Flutter derrière (`TvSystemSearchScreen`) ne dessine rien.** Elle cherche à chaque
`query` et envoie les rayons. Elle n'a rien de focalisable : tant que l'écran du système est
devant, la télécommande est à lui (le pavé de la Siri Remote reste transmis à Flutter, où il ne
trouve rien à déplacer).

**Une fiche s'ouvre par-dessus cette page.** L'écran du système se retire dès que la fiche la
recouvre et revient quand elle la rend, par le seul état de la route (`ModalRoute.isCurrent`).
C'est le même écran qui revient, gardé en mémoire : son texte, ses affiches, son défilement, et
le focus sur l'affiche qu'on avait choisie.

**Retour referme la recherche.** Le geste est pris par l'hôte, qui prévient Dart ; Dart dépile sa
page et la loupe retrouve le focus. Trois chemins mènent au même état, pour qu'on ne reste jamais
devant une page vide : le geste de l'hôte, un retrait de l'écran par UIKit lui-même, et une touche
Retour arrivée jusqu'à Flutter (qui dépile la page, laquelle ferme l'écran).

**Si l'hôte ne montre pas l'écran, la page devient la recherche de l'ADR-0126.** Android TV et le
web des téléviseurs LG la gardent : le clavier en ligne n'existe que sur tvOS.

**Le dessin est celui de l'app**, aux mesures du mur d'affiches de Flutter (`TvPosterWall`, 1280 de
large) agrandies une fois et demie : six affiches par ligne, coins de 18, l'affiche focalisée qui
grandit de 10 % depuis son pied avec son ombre pour seul signe (ADR-0118), Manrope lue dans les
ressources de Flutter. Sous chaque affiche, son titre et son année : il n'y a pas de cartouche
natif.

### 2. Toute recherche montre aussi les titres que le serveur n'a pas

**Un dernier rayon, « Pas sur le serveur · n »**, après « Films » et « Séries ». Le mot est déjà
celui des listes et des épisodes absents.

**Le signe est celui que l'app donne déjà aux titres absents** (titres similaires, filmographies,
listes) : l'affiche voilée (`AppColors.unavailableTint`) sous la pastille de verre « Indispo »
(`UnavailableBadge`, sortie de `media_detail_widgets.dart` pour être partagée). Quand une demande
court déjà, la pastille dit « Demandé », du jaune des demandes en cours.

**Choisir un titre absent ouvre sa fiche de demande**, où il se demande. Au retour, le catalogue
est relu : « Indispo » devient « Demandé ».

**Les trois recherches de l'app le font**, par le même rangement (`SearchShelves`) : l'écran du
système de l'Apple TV, le mur des autres téléviseurs (`TvSearchScreen`) et la grille du téléphone
et du bureau (`SearchResultsScreen`).

**D'où ils viennent :** la route existante `GET /api/requests/catalog?query=…`, que l'onglet
Demandes interroge déjà (TMDB, lu par le serveur, chaque titre avec son statut). Rien ne change
côté serveur.

- La bibliothèque répond à chaque frappe, sans réseau. Le catalogue est interrogé quand la frappe
  marque une pause de 350 ms, à partir de deux lettres ; la réponse à une recherche déjà quittée
  est jetée. Entre deux réponses, la dernière reste, réduite aux titres qui correspondent encore :
  le rayon ne clignote pas à chaque lettre.
- **Seulement pour un compte qui peut demander** (`canRequestMedia`) : lui montrer un titre absent
  qu'il ne peut pas demander ne mènerait nulle part. Les autres gardent la recherche d'avant.
- **Un titre du catalogue que la bibliothèque détient rejoint ses rayons**, même si son titre ne
  correspondait pas : le catalogue connaît le titre original, pas la recherche locale. On le
  reconnaît à son identifiant TMDB et à son type.
- Un catalogue en panne (clé TMDB absente, serveur injoignable) ne se dit pas : la recherche reste
  celle de la bibliothèque.

### Écarté

- **Le clavier du système au-dessus de résultats dessinés par Flutter.** Il aurait fallu rendre le
  focus d'un monde à l'autre à chaque passage du clavier aux affiches : deux moteurs de focus pour
  un seul geste, impossible à essayer sans appareil. Un écran entièrement natif n'a qu'un moteur
  de focus, celui pour lequel `UISearchController` est fait.
- **Les suggestions du clavier** (`searchSuggestions`, les pastilles sous le clavier de YouTube).
  Elles complètent une requête dans un index immense ; ici les affiches arrivent à chaque lettre
  et en tiennent lieu.
- **Garder la progression fine et le cartouche de l'affiche** (résumé, compteur d'épisodes). L'écran
  natif montre la barre d'un film en cours et la coche d'un titre vu ; le reste est sur la fiche.
- **Une route de recherche à part sur le serveur.** Celle du catalogue de demandes rend déjà ce
  qu'il faut, statut compris.
- **Montrer les titres absents à un compte qui ne peut pas demander.** Voir plus haut.
- **Tout envoyer à l'écran natif.** Une lettre seule ramène presque toute une bibliothèque : un
  rayon s'arrête à 120 affiches, et son titre dit le vrai compte.

## Conséquences

- **Du Swift entre dans l'hôte de l'Apple TV** (trois fichiers, `tvos/Runner/SystemSearch*.swift`),
  que seul Xcode compile : la CI de l'Apple TV, pas `flutter test`. Un fichier Swift ajouté à
  `tvos/Runner` doit l'être aussi au projet Xcode, sinon il est ignoré sans rien dire.
- **Les titres absents demandent une requête par recherche**, pour les comptes qui peuvent
  demander. Elle part après la pause et ne retarde pas les résultats de la bibliothèque.
- **Android TV et les téléviseurs LG** gardent le clavier en plein écran de l'ADR-0126, et gagnent
  le rayon des titres absents.
- Épinglé par :
  - `test/tv_system_search_screen_test.dart` (la page hôte, face à un hôte simulé : présentation,
    frappe, rayons, pastilles, limite d'un rayon, fiche qui recouvre puis rend, Retour par les
    deux chemins, repli ; les deux systèmes de navigation) ;
  - `test/tv_system_search_host_test.dart` (lit les sources Swift : le projet Xcode les compile
    toutes, et les deux bouts du canal parlent des mêmes messages et des mêmes champs) ;
  - `test/unavailable_titles_search_test.dart` et `test/search_shelves_test.dart` (quand le
    catalogue est interrogé, et comment une recherche se range) ;
  - `test/search_unavailable_shelf_test.dart` (le rayon des absents sur un téléviseur et sur le
    bureau, son signe, la télécommande qui y descend, la fiche de demande).

### À vérifier sur l'appareil

Ce que ni un test ni le compilateur ne disent, et où regarder si ce n'est pas ça :

| Ce qu'on attend | Si ce n'est pas ça |
|---|---|
| Le clavier en tête, les affiches visibles dessous ; Bas descend du clavier à la première ligne | la place que tvOS donne aux résultats : `SystemSearchResultsController` (`contentInsetAdjustmentBehavior`, marges de sécurité) |
| Le clavier sort par le haut quand on descend, revient quand on remonte | `setContentScrollView` sur l'écran des résultats, et `searchControllerObservedScrollView` que le SDK 27 déprécie à son profit : les deux sont posés, pour les deux générations de tvOS |
| Au retour d'une fiche, le focus est sur l'affiche quittée, sinon sur le clavier avec les affiches intactes dessous | `SystemSearchScreen.focusResults` et `returnsToResults` |
| Retour ferme la recherche d'un seul appui, clavier ou affiches | `SystemSearchScreen` : le geste `menuPressed`, et `pressesEnded` quand l'appui arrive par la chaîne de réponse |
| Titres en Manrope | `SystemSearchFont` (chemin des ressources de Flutter dans l'app) |
| Six affiches par ligne, l'affiche soulevée ne touche ni le titre du rayon ni la ligne du dessus | `SystemSearchMetrics` |
