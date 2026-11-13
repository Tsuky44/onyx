# ADR-0123 — La bibliothèque d'un téléviseur présente le titre focalisé en tête

- **Statut :** accepté, **amendé le 2026-11-13 par
  l'[ADR-0125](0125-la-bibliotheque-d-un-televiseur-pose-la-fiche-a-gauche-et-la-grille-a-droite.md)** :
  après l'essai, la fiche passe dans un volet à gauche et la grille défile à droite sur toute la
  hauteur. Les points 1, 2, 7 et 8 ci-dessous décrivent la première mise en page ; les points 3 à 6
  tiennent.
- **Date :** 2026-11-12
- **Portée :** `screens/library/library_screen.dart`, `screens/library/widgets/library_tv_view.dart`
  (`LibraryTvView`), `screens/library/widgets/library_spotlight.dart` (`LibrarySpotlight`),
  `screens/library/widgets/catalog_header.dart` (`CatalogSortCapsule`), `widgets/global/media_card.dart`
  et `poster_card.dart` (`scrollAlignment`, `showDetails`).
- **Prolonge** l'[ADR-0118](0118-le-style-de-salon-du-televiseur.md) (six affiches par rangée, affiche
  soulevée) et l'[ADR-0058](0058-bibliotheques-nommees.md)
  (un seul écran pour toutes les bibliothèques).

## Contexte

Retour de l'utilisateur sur Apple TV : « l'affichage de la bibliothèque de séries et de films : il y en
a trop, et quand on défile ça fait trop rempli, trop compact ».

Mesuré sur la page d'un téléviseur (1280 × 720) : sept affiches de 157 px par ligne, 14 px entre elles
dans les deux sens, aucun titre. Une fois la page défilée, l'écran porte trois rangées pleines et le
bord de deux autres, une vingtaine d'affiches que rien ne hiérarchise. La grille est celle du bureau
(`AppLayout.posterGridDelegate`), pensée pour une souris à 60 cm.

Trois maquettes ont été proposées : **A**, la même grille aérée (six par ligne, deux rangées, le titre
sous l'affiche focalisée) ; **B**, la fiche du titre focalisé en tête et une seule rangée dessous ;
**C**, des rayons par genre comme l'accueil. L'utilisateur a choisi B.

## Décision

**Sur téléviseur, une bibliothèque montre la fiche du titre que la télécommande désigne, et une rangée
d'affiches dessous** (`LibraryTvView`). Hors téléviseur, la grille et son en-tête ne changent pas.

1. **La grille.** Six affiches par ligne, 24 px entre elles : la taille d'une rangée de l'accueil
   (177 × 266 px). L'écran en montre une rangée et 52 px de la suivante. 32 px entre deux rangées.
2. **Elle défile rangée par rangée.** L'affiche focalisée se pose toujours à la même hauteur, 30 px
   sous le bord de la grille (la place de son soulèvement), par le `scrollAlignment` de `TvFocusable`
   que `PosterCard` expose désormais. L'écart entre rangées (32) dépasse ces 30 px : la rangée du dessus
   est sortie tout entière, sans filet d'affiches au bord.
3. **La fiche ne défile pas** (`LibrarySpotlight`) : le nom de la bibliothèque et son nombre de titres
   en surtitre, le logo du titre ou son nom, une ligne de métadonnées (année, durée ou saisons, note,
   deux genres), trois lignes de résumé, et l'image de fond du titre derrière, fondue vers la page.
4. **Deux sources, deux temps.** Ce que la liste de la bibliothèque porte déjà (titre, année, durée,
   résumé) s'écrit à l'instant où le focus arrive. Le reste (image de fond, logo, genres, note) vient de
   la fiche du catalogue (`MediaDetailsCache`), demandée 220 ms après que le focus s'est posé :
   traverser une rangée ne demande pas une fiche par affiche. C'est la fiche que `DetailPrefetch`
   réchauffe déjà pour la page du titre, à la même adresse d'image et à la même largeur de décodage :
   aucune requête ni aucun décodage de plus qu'avant.
5. **Rien ne clignote sous un focus qui court.** Le titre change sans fondu (deux titres superposés ne
   se lisent pas) ; le logo ne remplace le titre qu'une fois décodé ; l'image de fond du titre
   précédent reste jusqu'à ce que la suivante soit prête, puis les deux se fondent. La place du titre
   est fixe : le logo qui arrive ne décale ni les métadonnées ni le résumé.
6. **Le cartouche posé sur l'affiche focalisée disparaît** (`MediaCard.showDetails`) : la fiche dit
   déjà le titre, le type et le résumé.
7. **Le tri est une capsule** à droite au-dessus de la grille (`CatalogSortCapsule`), un bouton du
   thème qui ouvre le même menu. Le `PopupMenuButton` de l'en-tête commun n'a pas d'état focalisé à
   lui. Choisir un tri rend le focus à la capsule, ramène la grille en haut et la fiche à la première
   affiche.
8. **Le chargement a déjà cette forme** : le nom de la bibliothèque à la place du titre, douze cases
   grises à la place des affiches, pas de tri (il serait la seule cible sous l'en-tête). L'erreur et
   la bibliothèque vide gardent la page commune.

### Écarté

- **A, la grille aérée.** Plus simple, mais elle garde un mur d'affiches sans contexte ; l'utilisateur
  ne l'a pas retenue.
- **C, les rayons par genre.** Les genres ne sont pas envoyés avec la liste d'une bibliothèque : il
  faudrait modifier le serveur. À reprendre si c'est demandé.
- **Demander la fiche de chaque affiche survolée.** Une lancée du pavé traverse dix affiches en une
  demi-seconde.
- **Faire défiler la grille soi-même** (`Scrollable.ensureVisible` depuis l'écran) : un second
  défilement par pas, ce que `no_parallel_focus_system_test` interdit. L'alignement passe par
  `TvFocusable`.

## Conséquences

- **On voit six affiches à la fois au lieu d'une vingtaine.** Parcourir une grande bibliothèque
  demande plus de pas ; le tri A → Z et la recherche restent les raccourcis.
- **Android TV et le web des téléviseurs LG** prennent le même écran (`TvScope`).
- **Sous dpad** (drapeau `ONYX_TV_NAV`), l'affiche est ramenée « au plus près » et non à hauteur fixe :
  dpad ne connaît que le centre et le plus près (`TvNavTheme.alignmentFor`).
- **Sans réseau ou sans fiche**, la fiche garde le titre, l'année, la durée et le résumé, sans image.
- Épinglé par `test/library_tv_view_test.dart` (les deux systèmes de navigation) et
  `test/library_screen_tv_test.dart`.
