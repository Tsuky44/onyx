# ADR-0112 — Sur téléviseur, la commande focalisée se remplit de blanc

- **Statut :** accepté
- **Date :** 2026-11-10
- **Portée :** le focus des boutons à la télécommande : `theme/focus_fill.dart` (`FocusFill`),
  `AppTheme.focusRinged` et les thèmes de boutons d'`AppTheme`, `HeroPill`
  (`widgets/global/detail_hero.dart`), et le trait de `TvFocusRing`. Complète l'ADR-0111.

## Contexte

L'ADR-0111 a rendu l'anneau de focus blanc. Sur les affiches, c'est réussi. Sur les boutons, non :
retour de l'utilisateur, sur « Reprendre » à l'accueil « ça fait blanc sur blanc, on comprend pas ».
Le bouton principal est blanc, et un anneau blanc posé sur son bord disparaît. Sur les boutons de
verre, l'anneau restait un filet qu'il fallait chercher. La consigne : que ce soit utilisable par
quelqu'un qui n'a jamais vu l'app, et que ça fasse pro.

Un anneau ne peut pas contraster avec tous les fonds à la fois (bouton blanc, verre, image claire
d'un bandeau). Les interfaces de salon (l'app TV d'Apple, les lecteurs du commerce) font autrement :
au repos, toutes les commandes sont en verre, et celle qui a le focus devient pleine et blanche.

## Décision

1. **Sur téléviseur, une commande focalisée se remplit de blanc (`FocusFill.fill`), et son texte et
   son icône passent au noir (`FocusFill.ink`).** `FocusFill.wrap` enveloppe les couleurs d'un
   `ButtonStyle` sans les remplacer : tous les autres états gardent les leurs. `AppTheme.focusRinged`
   l'applique, donc tous les boutons du thème (plein, contour, texte, icône, rempli) et chaque style
   local qui passe par lui. `HeroPill` fait de même.
2. **Sur téléviseur, le bouton blanc au repos passe au verre (`FocusFill.glass`, blanc à 20 %).**
   Ainsi, la seule commande blanche à l'écran est celle qui a le focus. Ailleurs, il reste blanc.
3. **Hors téléviseur, rien ne change** : le focus clavier garde l'anneau de l'ADR-0111.
4. **L'anneau des cartes (`TvFocusRing`) prend un second trait** : un filet sombre juste dans le
   blanc, qui le détache d'un fond clair. Un anneau intérieur ajoute aussi un voile blanc à 8 % sur
   la carte. L'anneau extérieur d'une affiche n'a pas ce voile, qui resterait sur l'image.

## Conséquences

- Sur téléviseur, le bouton principal d'un écran (« Reprendre », « Lecture », « Valider ») n'est plus
  blanc au repos. C'est voulu : le blanc ne veut plus dire qu'une chose, « ici ».
- Un bouton dont le style local fixe `backgroundColor` sans passer par `AppTheme.focusRinged` perd
  le remplissage et ne garde que l'anneau. Un nouveau bouton passe donc par le thème ou par
  `focusRinged`.
- Le remplissage bleu des commandes du lecteur et de sa barre de progression (ADR-0008) n'est pas
  touché.
- Épinglé par `test/focus_fill_test.dart`.
