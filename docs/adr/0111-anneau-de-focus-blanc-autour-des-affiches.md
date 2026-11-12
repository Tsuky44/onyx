# ADR-0111 — L'anneau de focus est blanc, et entoure les affiches au lieu de les border

- **Remplacée sur téléviseur, pour les affiches,** par l'[ADR-0118](0118-le-style-de-salon-du-televiseur.md)
  le 2026-11-12 : l'affiche focalisée se soulève sans anneau (l'anneau reste en mode léger, et partout
  ailleurs que sur les affiches).
- **Statut :** accepté
- **Date :** 2026-11-10
- **Portée :** le dessin du focus télécommande et clavier : `tv/tv_focus_ring.dart` (`TvFocusRing`),
  `TvDpadFocusable` et `TvLegacyFocusable`, `AppTheme._focusSide`, `PosterLift` et
  `PosterHoverOverlay` (`widgets/global/poster_card.dart`), `PosterCard.railRoom` et les rangées qui
  la réservent (`MediaRow`, `PosterRail`). Amende l'ADR-0008 sur la couleur de l'anneau, pas sur sa
  règle (le chrome affiché a toujours une commande sélectionnée).

## Contexte

Le focus se dessinait en bleu d'accent (`AppColors.accent`) : 3 px plus un halo flouté sur les
cartes, 3 px **à l'intérieur** de l'affiche sur les rangées de l'accueil. Retour de l'utilisateur :
l'effet « n'est pas beau » et, sur l'accueil, les contours bleus des affiches sont « coupés en haut
et en bas ».

La coupure avait deux causes qui s'additionnaient :

- l'affiche grandissait **deux fois** : `TvFocusable` agrandissait toute la carte de 5 % autour de
  son centre, puis `PosterLift` soulevait l'affiche de 4 px de chaque côté ;
- la rangée ne réservait de la place qu'au-dessus (`liftHeadroom`, 10 px), rien en dessous, et son
  `ListView` coupe tout ce qui dépasse.

Le bleu, lui, se confondait avec ce qui est déjà bleu dans l'interface (boutons pleins, sélection,
progression), et dans l'affiche il mangeait l'image sur ses bords.

## Décision

1. **Un seul anneau**, `TvFocusRing` : un trait blanc (`AppColors.focus`) de 2,5 px qui épouse
   l'arrondi, allumé en fondu (`AppMotion.focus`), éteint net. Plus de halo. Les deux systèmes de
   focus le posent, et les bords de focus du thème (`_focusSide`, `chipSide`) et des cartes qui
   dessinent le leur prennent la même couleur.
2. **Sur une affiche, l'anneau est à l'extérieur**, détaché du bord par un jour de 2,5 px
   (`outset`) : l'image reste entière. `PosterLift` le trace, pour qu'il suive le soulèvement.
3. **Un seul agrandissement par affiche** : `PosterCard` et `ContinueWatchingCard` passent
   `focusScale: 1.0`, seul `PosterLift` soulève. Sur téléviseur, l'affiche grandit depuis son pied
   (`PosterLift.tvAnchor`) : l'anneau ne descend pas sur le titre.
4. **Les rangées réservent la place** que donne `PosterCard.railRoom` : 18 px au-dessus et 7 px en
   dessous sur téléviseur, inchangée ailleurs (10 px au-dessus).

## Conséquences

- L'accent bleu reste pour ce qui est choisi ou actif (sélection, progression, boutons pleins), plus
  pour « où est la télécommande ». Le commentaire d'en-tête d'`AppColors` (« blue focus
  sparingly ») ne décrit plus le focus.
- Les rangées d'affiches sont un peu plus hautes sur téléviseur (15 px). Une nouvelle rangée
  horizontale d'affiches doit réserver `PosterCard.railRoom`, sinon son anneau est coupé.
- Un anneau `outset` dépasse de `TvFocusRing.reach` : il ne sert qu'où la place est réservée. Les
  autres focusables gardent l'anneau intérieur, qui ne déborde jamais.
- Le remplissage bleu de la barre de progression et des boutons du lecteur au focus n'est pas
  touché : ce n'est pas un anneau, et l'ADR-0008 le règle.
- Épinglé par `test/poster_focus_ring_test.dart` et `test/tv_focus_ring_test.dart`.
