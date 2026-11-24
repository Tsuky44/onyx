# Sur un téléviseur, le bandeau défile comme au bureau et reste l'entrée de l'accueil

- **Statut :** accepté. Demandé par l'utilisateur sur une photo d'Apple TV (2026-11-24) : « règle le
  problème d'UI », « mets le même truc qui défile que sur PC, là c'est pas totalement pareil »,
  « quand on descend de la barre de nav ça va pas sur Reprendre ». Couvert par des tests de widget ;
  **pas encore vu sur une Apple TV**.
- **Date :** 2026-11-24
- **Portée :** `widgets/global/hero_carousel.dart`, `widgets/global/hero/hero_actions.dart`
  (`HeroPlayButton`), `tv/nav/tv_slide_edges.dart`, `tv/nav/tv_region.dart` (`TvRegion.slide`,
  ancien système), `tv/tv_focus_memory.dart` (`addLead`), `test/hero_series_slide_test.dart`,
  `test/shell_navigation_map_test.dart`.
- **Contredit** l'[ADR-0154](0154-le-bandeau-d-une-serie-lance-son-episode-et-fait-defiler-ses-images.md)
  sur un point (« le téléviseur garde ses traits immobiles ») parce que le bandeau d'un téléviseur
  ne défilait alors jamais. Le fond fixe et les boutons du téléviseur (ADR-0112) ne changent pas.

## Contexte

Trois défauts sur l'accueil d'une Apple TV :

- **« S15 E1 » ne se lisait pas.** Le numéro d'épisode du bouton était teint du noir de la page, à
  55 %. Juste sur le bouton blanc du bureau ; sur un téléviseur, le bouton au repos est en verre et
  son texte blanc (ADR-0112) : du noir sur du gris.
- **Le bandeau ne défilait pas.** Le focus suspendait le défilement comme le survol d'une souris,
  et la télécommande ouvre l'accueil avec le focus sur « Reprendre » : le bandeau restait sur sa
  première diapositive, sous des traits figés, pleins.
- **Bas depuis la barre n'arrivait pas sur « Reprendre ».** Les boutons du bandeau sont des boutons
  de Material : ils n'entraient pas dans la mémoire de la page (`TvFocusMemory`), que seuls les
  `TvFocusable` alimentent. Après un passage par une rangée, Bas depuis la barre rendait la carte
  de la rangée. Et Haut depuis une carte du milieu d'une rangée saute le bandeau pour la barre.

## Décision

1. **Le numéro d'épisode prend l'encre du bouton**, éclaircie (`HeroPlayButton.codeOpacity`) : il
   suit le repos, le focus et le bouton désactivé sans rien savoir du téléviseur.
2. **Sur un téléviseur, le focus ne retient plus le bandeau** (`_heldByFocus`). Il défile sous la
   télécommande, et le bouton de la diapositive qui arrive prend le focus de celle qui part. Une
   télécommande partie dans une rangée pendant que la page tourne y reste.
3. **Le trait de la diapositive se remplit sur un téléviseur**, sauf en mode léger, qui garde ses
   traits immobiles : c'est le mode léger (ADR-0086) qui dit qu'une box ne tient pas une animation
   continue, pas le fait d'être un téléviseur.
4. **La diapositive est l'entrée de sa page tant qu'elle est à l'écran** (ancien système,
   `TvFocusMemoryState.addLead`, posé par `TvRegion.slide`). Bas depuis la barre arrive sur son
   premier bouton. Page défilée plus bas (Retour depuis une rangée profonde), la mémoire reprend
   la main. Sous dpad, l'entrée de `TvRegion.slide` tenait déjà cette promesse.

### Écarté

- **Faire entrer tout bouton de Material dans la mémoire** (écouter `FocusManager` dans chaque
  zone) : ne répare pas le cas où Haut saute le bandeau, et touche toutes les pages d'un système
  en cours de retrait (ADR-0110).
- **Le fond vivant sur un téléviseur** : pas demandé, et son coût sur une box n'est pas mesuré.

## Conséquences

- Sur un téléviseur, une diapositive peut tourner pendant qu'on s'apprête à appuyer sur OK, comme
  sur les bandeaux des apps de salon du commerce. « Réduire les animations » arrête le défilement.
- Une flèche gauche ou droite relance le temps de la diapositive (`_onPageChanged`).
- Épinglé par `hero_series_slide_test` (groupe « sur un téléviseur ») et
  `shell_navigation_map_test` (« redescendre de la barre ramène au bandeau, pas à la rangée »).

## À vérifier dans l'app

| Quoi | Pourquoi ici seulement |
| --- | --- |
| Le focus qui suit la diapositive sur une vraie Apple TV | Le pavé et l'en-tête réels. |
| Le remplissage du trait à 4K | La fluidité dépend du GPU. |
