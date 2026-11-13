# ADR-0125 — La bibliothèque d'un téléviseur pose la fiche à gauche et la grille à droite

- **Statut :** accepté. Maquette choisie par l'utilisateur parmi trois (2026-11-13, « la 1 est pas
  mal ») ; rendu vérifié sur une capture de l'app à 1280 × 720, pas encore vu sur une Apple TV.
- **Date :** 2026-11-13
- **Portée :** `screens/library/widgets/library_tv_view.dart` (`LibraryTvView`),
  `screens/library/widgets/library_spotlight.dart` (`LibrarySpotlight`), `tv/tv_touchpad.dart`
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
2. **La grille.** Quatre affiches par ligne, 24 px entre elles, 28 px entre deux rangées : 172 × 259 px,
   la taille d'une affiche de l'accueil. Elle prend toute la hauteur et passe sous la barre d'onglets,
   comme les rangées de l'accueil : deux rangées entières à l'écran, et la troisième pointe.
3. **Elle défile toujours rangée par rangée** (`TvFocusable.scrollAlignment`) : la rangée focalisée se
   pose 16 px sous la barre d'onglets, la place de l'affiche soulevée. Les dernières rangées, elles,
   restent en bas de l'écran : la grille ne finit pas sur un écran aux trois quarts vide.
4. **Un pas vers le haut ou le bas n'est plus une glissade** (`TvTouchpad.isGliding`) : la page défile
   en 200 ms (`AppMotion.standard`) et non en 90. Cela vaut partout, l'accueil compris. Une flèche
   maintenue garde la durée courte : là, les pas se suivent.
5. **Le tri est en haut du volet, à la hauteur de la rangée focalisée.** Gauche depuis la première
   colonne y mène, droite ou bas ramène à l'affiche quittée, haut monte aux onglets : le focus part
   dans le sens de la flèche. Le passage est explicite (`TvRegion.slide`, `onEdge`) et le tri est hors
   du parcours géométrique (`descendantsAreTraversable: false`) : sous la barre d'onglets, Bas entre
   dans la grille, jamais sur le bouton posé à sa gauche.
6. **Un geste qui court le long de la rangée s'arrête à son bord.** Gauche ne mène au tri que si
   l'affiche de la première colonne a gardé le focus 300 ms (`LibraryTvView.rest`), plus que l'écart
   entre deux pas d'une lancée (220 ms) ou d'une flèche maintenue. Arrivé d'une autre rangée, le focus
   n'attend pas.
7. **Le chargement a la même forme** : le nom de la bibliothèque à la place du titre, des cases grises
   dans la grille, pas de tri.

### Écarté

- **Le tri en bas du volet**, comme sur la maquette. Aucune affiche n'est sur sa ligne : gauche
  envoyait le focus à l'autre bout de l'écran, et depuis le tri haut et bas tombaient sur une affiche
  prise au hasard de la grille (vu au banc, sur les deux systèmes de navigation). En haut, à la hauteur
  de la rangée focalisée, chaque flèche va où elle pointe.
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
- Épinglé par `test/library_tv_view_test.dart` (mise en page, fiche, passage grille ↔ tri, les deux
  systèmes de navigation) et `test/tv_touchpad_test.dart` (« d'une rangée à l'autre, le pas n'est pas
  une glissade »).
