# ADR-0125 — La bibliothèque d'un téléviseur pose la fiche à gauche et la grille à droite

- **Statut :** accepté. Maquette choisie par l'utilisateur parmi trois (2026-11-13, « la 1 est pas
  mal ») ; rendu vérifié sur une capture de l'app à 1280 × 720, pas encore vu sur une Apple TV.
  **Révisé le même jour** : le tri passe en haut à droite (voir « Le tri, en haut à droite »).
- **Date :** 2026-11-13
- **Portée :** `screens/library/widgets/library_tv_view.dart` (`LibraryTvView`),
  `screens/library/widgets/library_spotlight.dart` (`LibrarySpotlight`),
  `screens/library/widgets/catalog_sort_capsule.dart` (`CatalogSortCapsule`),
  `widgets/global/tv_poster_wall.dart` (`TvPosterWall`), `tv/tv_touchpad.dart`
  (`TvTouchpad.isGliding`).
- **Amende** l'[ADR-0123](0123-la-bibliotheque-d-un-televiseur-presente-le-titre-focalise-en-tete.md) :
  ses points 1, 2, 7 et 8 (la mise en page). Ses points 3 à 6 tiennent : ce que la fiche montre, ses
  deux sources, rien qui clignote, pas de cartouche sur l'affiche.

## Contexte

L'ADR-0123 posait la fiche du titre focalisé en tête d'écran et une seule rangée de six affiches
dessous. Retour de l'utilisateur après l'essai sur Apple TV : « on ne voit pas super bien, et quand on
défile c'est pareil, c'est un peu trop brut, c'est bizarre ».

Deux causes, vues dans le code :

- **La grille ne défilait que dans la moitié basse de l'écran**, coupée net sous la fiche. Une rangée
  sortait par une fente et la suivante entrait par le bas : on ne voyait jamais deux rangées entières,
  donc ni d'où l'on venait ni où l'on allait.
- **Un pas du pavé vers le bas défilait en 90 ms.** `TvTouchpad.isGliding` valait pour tout pas donné
  sur des affiches, et `TvFocusScroll.durationFor` prend alors la durée courte, faite pour une rangée
  qui file sous le doigt (un pas toutes les 60 ms). Vers le bas il n'y a qu'un pas par geste, mais la
  page parcourait une rangée entière, près de 300 px, en 90 ms : elle sautait.

Une première maquette (le même écran, défilement ralenti) a été refusée. Trois autres ont suivi :
**1**, la fiche à gauche et la grille à droite ; **2**, la grille plein écran et le titre en bandeau en
bas ; **3**, des rayons comme l'accueil. L'utilisateur a choisi la 1.

## Décision

**Sur téléviseur, la fiche du titre focalisé tient dans un volet fixe à gauche, et la grille défile à
droite sur toute la hauteur de l'écran.**

1. **Le volet.** 48 px de gouttière, 374 px de texte, 48 px avant la grille. La fiche
   (`LibrarySpotlight`) y écrit ce qu'elle écrivait, avec six lignes de résumé au lieu de trois. Son
   image de fond déborde de 170 px sous les premières colonnes et se fond vers la droite et vers le
   bas : elle se voit en haut du volet, le texte se lit sur un fond presque uni.
2. **La grille** (`TvPosterWall`, que la recherche emploie aussi, ADR-0126). Quatre affiches par
   ligne, 24 px entre elles, 28 px entre deux rangées : 172 × 259 px, la taille d'une affiche de
   l'accueil. Elle prend toute la hauteur et passe sous la barre d'onglets, comme les rangées de
   l'accueil : deux rangées entières à l'écran.
3. **Elle défile toujours rangée par rangée** (`TvFocusable.scrollAlignment`) : la rangée focalisée se
   pose sous le tri, avec la place de l'affiche soulevée. Les dernières rangées, elles, restent en bas
   de l'écran : la grille ne finit pas sur un écran aux trois quarts vide.
4. **Un pas vers le haut ou le bas n'est plus une glissade** (`TvTouchpad.isGliding`) : la page défile
   en 200 ms (`AppMotion.standard`) et non en 90. Cela vaut partout, l'accueil compris. Une flèche
   maintenue garde la durée courte : là, les pas se suivent.
5. **Le tri est une capsule de verre en haut à droite**, au-dessus de la grille : voir la section
   suivante.
6. **Le chargement a la même forme** : le nom de la bibliothèque à la place du titre, des cases grises
   dans la grille, pas de tri.

### Le tri, en haut à droite

La première version posait le tri en haut du volet, à gauche. Demande de l'utilisateur le même jour :
« le Récents sur la page films et séries, je veux que ça aille à droite en haut, fais un truc joli ».

- **Une capsule de verre** (`CatalogSortCapsule`, 36 px) calée sur le bord droit de la grille, au ras
  de la barre d'onglets : le dessin de la pilule des onglets (ADR-0117). Du verre au repos, pour se
  lire sur les affiches qui défilent dessous ; blanche à l'encre noire sous la télécommande
  (`FocusFill`, ADR-0112). L'icône du tri, le tri en vigueur, un chevron. Son menu coche le tri en
  vigueur à droite de son nom.
- **La rangée focalisée se pose 58 px sous la marge de l'onglet** : la capsule, 8 px, puis la place de
  l'affiche soulevée. Deux rangées entières tiennent toujours à l'écran ; la troisième ne pointe plus.
  Les rangées déjà vues s'estompent en passant sous la capsule.
- **Elle se rejoint par la géométrie, sans règle à elle.** Haut depuis la dernière colonne y mène, Bas
  en revient ; depuis les autres colonnes, Haut monte aux onglets. En arrivant des onglets, Bas entre
  par la première affiche (`TvFocusMemory.entersAtTop` prend la cible la plus proche du coin
  haut-gauche de la page, et la capsule est à l'autre bout).

### Écarté

- **Le tri en bas du volet**, comme sur la maquette. Aucune affiche n'est sur sa ligne : gauche
  envoyait le focus à l'autre bout de l'écran, et depuis le tri haut et bas tombaient sur une affiche
  prise au hasard de la grille (vu au banc, sur les deux systèmes de navigation).
- **Le tri sur la ligne de la barre d'onglets**, à droite. La place est celle du compte, de l'état de
  l'indexation et du téléchargement de l'app.
- **Deux volets** (`TvRegion.panes`, ADR-0121). Haut et bas ne quittent pas un volet : depuis la
  première rangée, on ne remonterait plus à la barre d'onglets.
- **Faire monter la dernière rangée en haut de l'écran**, comme sous l'ADR-0123. Sur toute la hauteur,
  cela laisse l'écran presque vide en fin de bibliothèque.
- **Ralentir le défilement de la seule bibliothèque.** Le saut venait de la durée courte donnée à tout
  pas vertical du pavé ; il était le même sur l'accueil.

## Conséquences

- **Huit affiches entières à l'écran** au lieu de six, et l'on voit la rangée d'où l'on vient.
- **Android TV et le web des téléviseurs LG** prennent le même écran (`TvScope`). La durée de
  défilement ne change que pour le pavé de la Siri Remote, seul à passer par `TvTouchpad`.
- **Sous dpad** (drapeau `ONYX_TV_NAV`), l'affiche est ramenée « au plus près » et non à hauteur fixe,
  comme sous l'ADR-0123.
- Épinglé par `test/library_tv_view_test.dart` (mise en page, fiche, tri en haut à droite et son
  parcours, les deux systèmes de navigation) et `test/tv_touchpad_test.dart` (« d'une rangée à l'autre,
  le pas n'est pas une glissade »).
