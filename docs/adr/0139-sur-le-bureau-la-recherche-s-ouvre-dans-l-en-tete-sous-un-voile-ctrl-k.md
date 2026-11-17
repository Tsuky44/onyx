# ADR-0139 — Sur le bureau, la recherche s'ouvre dans l'en-tête, sous un voile (Ctrl K)

- **Statut :** accepté. Testé en widget (`desktop_search_test.dart`, `desktop_search_grid_test.dart`,
  `library_tabs_layout_test.dart`). Une première version a été essayée par l'utilisateur sous
  Windows ; **la version avec le volet à gauche n'a pas encore été regardée dans l'app lancée**.
- **Date :** 2026-11-17
- **Portée :** le bureau seulement. `app/lib/screens/shell/desktop_header_search.dart`,
  `app/lib/screens/shell/shell_desktop_header.dart`, `app/lib/screens/search/desktop/`,
  `app/lib/main.dart` (les raccourcis), `PosterCard.highlight`, `LibrarySpotlight.backdropUrl`. Le téléphone et le téléviseur
  gardent leur recherche (`GlassCatalogSearch`, `SearchResultsScreen`, ADR-0126, ADR-0129).

## Contexte

Sur le bureau, la recherche était un champ de 280 px collé à droite de l'en-tête. Au premier
caractère, une page opaque (`SearchResultsScreen.followingHeader`) recouvrait l'écran, avec une
barre « Recherche » et une flèche retour de Material sous l'en-tête de verre. La recherche avait
l'air d'une page étrangère à l'app. Rien n'était prévu pour le clavier : pas de raccourci pour
l'ouvrir, pas de flèches pour choisir un titre. Champ vide, la page ne montrait qu'une icône.

L'utilisateur a demandé une recherche « mieux intégrée sur le PC ». Il a choisi, parmi quatre
maquettes, une synthèse : le geste rapide d'une palette (Ctrl K, Entrée), la grille d'affiches et
les filtres dans l'en-tête, l'aperçu d'un panneau latéral. Il a écarté un onglet « Rechercher ».
Après l'essai, il a demandé l'aperçu à gauche, avec le dessin du volet de la télévision.

## Décision

1. **Le champ de l'en-tête ouvre la recherche.** Un clic, Ctrl K (⌘ K sur Mac) ou « / » le
   focalisent. L'en-tête efface alors ses onglets et fait glisser le champ au centre en
   l'élargissant (620 px au plus). Un rappel de la page quittée (« ‹ Accueil ») prend la place des
   onglets et y ramène d'un clic.
2. **Un voile, pas une page.** `DesktopSearchRoute` n'est pas opaque : la page d'avant reste
   dessous, floutée puis assombrie (`AppColors.searchVeil`). En mode léger, le voile est presque
   opaque et sans flou. Échap le relève, et on retrouve la page telle qu'on l'avait laissée.
3. **Le champ garde le focus du début à la fin.** Bas fait entrer les flèches dans la grille, et
   Haut depuis la première ligne les rend au champ. Entrée ouvre la fiche du titre sélectionné,
   Ctrl + Entrée lance le film. Le premier titre est sélectionné d'emblée (soulevé, sans anneau) :
   taper puis Entrée suffit pour un titre connu. On corrige sa frappe à tout moment. La sélection
   vit dans `DesktopSearchController`, partagé par le champ et la grille. Les cartes la montrent
   par `PosterCard.highlight`.
4. **Les flèches passent par les actions du champ.** Le `TextField` de Flutter déclare ses actions
   remplaçables (`Action.overridable`). Le champ de l'en-tête remplace celle des flèches verticales
   (déclarée sous `DirectionalCaretMovementIntent`), celle des flèches horizontales et
   `DismissIntent`. Aucun `Shortcuts` ni gestionnaire de touches n'est ajouté (ADR-0110).
5. **Ctrl K et « / » sont des raccourcis de `MaterialApp`**, joints à ceux qui existent dans
   `main.dart`. L'action ne fait rien tant que le champ du bureau ne s'est pas inscrit
   (`DesktopSearchHotkey`). Sur un téléviseur ou un téléphone, la touche passe son chemin. Dans un
   champ de saisie, « / » reste un caractère.
6. **La feuille** (`DesktopSearchSheet`) montre, champ vide, les recherches récentes du profil et
   les derniers ajouts. Sinon, elle montre des pastilles (Tout, Films, Séries, Pas sur le serveur,
   avec leurs décomptes), la grille de la bibliothèque puis celle des titres absents (ADR-0129).
   À gauche, à partir de 1100 px de large, le titre sélectionné (sous le pointeur ou les flèches)
   se présente comme dans le volet d'une bibliothèque sur téléviseur (`LibrarySpotlight`,
   ADR-0123) : image de fond, logo ou titre, métadonnées, résumé. Le volet s'efface vers la
   transparence plutôt que vers la couleur du fond, qui laissait une couture sur le voile. Un titre
   absent du serveur y passe avec l'image que le catalogue de demandes connaît déjà.
7. **Aucune touche dessinée.** Une première version peignait « Ctrl K » dans le champ, les touches
   sur les boutons d'un aperçu et une légende des flèches. À l'essai, l'utilisateur les a trouvées
   laides. Le raccourci se dit dans l'infobulle du champ, au survol.
8. **Recherches récentes** : six au plus, par serveur et par profil (`RecentSearches`). Une
   recherche n'y entre que si elle a servi, c'est-à-dire si un titre a été ouvert ou lancé depuis
   ses résultats.

## Conséquences

- `GlassCatalogSearch` perd son mode `staysAbovePages` : il ne sert plus qu'au téléphone et au
  téléviseur. `SearchResultsScreen.followingHeader` n'a plus d'appelant. Il est laissé en place
  (page du téléphone), et son retrait se fera à part.
- La feuille étant transparente, la page dessous continue d'être peinte. Le flou coûte une passe
  par image sur tout l'écran : c'est pour cela que le mode léger le retire.
- Le défilement qui ramène la carte sélectionnée à l'écran est celui d'une sélection sans focus,
  propre au bureau. Il ne double pas celui de dpad, qui n'existe que sur téléviseur.
- Pour une série, Ctrl + Entrée ouvre la fiche : lancer « l'épisode suivant » depuis la recherche
  demanderait de connaître la reprise de la série, que le catalogue ne porte pas.
