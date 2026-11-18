# ADR-0149 — Sur le web, les transitions de page n'animent plus d'opacité

- **Statut :** accepté. Vérifié en test (builder web, lecteur, mouvement réduit). Le gain de
  fluidité n'a **pas été mesuré** au navigateur par une trace de performance (voir Conséquences).
- **Date :** 2026-11-18
- **Portée :** `app/lib/theme/app_page_transitions.dart` (`OnyxPageTransitionsBuilder.cheap`,
  `appPageTransitionsTheme`), `desktop_search_route.dart`, `phone_search.dart`.
- **Prolonge** l'[ADR-0086](0086-mode-leger-pour-les-petits-appareils.md) et le contrat de mouvement (`PROJECT_DESIGN.md` §10).

## Contexte

Le rendu web d'Onyx est CanvasKit. `OnyxPageTransitionsBuilder` enveloppait toute la page dans
un `FadeTransition` : une opacité animée sur un grand arbre force un `saveLayer` plein écran à
chaque image pendant toute la transition, flous du verre compris. C'est le cas le plus lent
de CanvasKit, et la source probable du « ça rame quand j'ouvre une fiche ».

## Décision

- Sur `kIsWeb` (webOS compris : même moteur, appareil plus faible), la page arrive **opaque,
  par un glissé court seul** (`rise`, 180–280 ms de `AppMotion`), sans aucune opacité animée.
  Sous « réduire les animations », elle apparaît d'un coup.
- Sur le web, `appPageTransitionsTheme` donne ce builder à **toutes** les plateformes, iOS
  compris : `TargetPlatform` y reflète l'OS du navigateur, et le glissé Cupertino (ombre sur
  toute la page, geste de bord inexistant en navigateur) est le même coût. La version TV
  (`TvScaledPageTransitionsBuilder`) délègue au builder d'Onyx et en hérite.
- Le **lecteur** garde son fondu seul, jamais de géométrie : règle inchangée.
- Routes maison : la recherche du bureau n'anime plus que le décalage de 10 px sur le web (le
  voile flouté ne se fond plus), la recherche du téléphone apparaît d'un coup. Le menu « Plus »
  et le popover de filtres restent en fondu : petite surface.
- Natif (Android, iOS, desktop, TV) : inchangé.

## Conséquences

- Pendant le glissé, une bande de 2,5 % de la page précédente reste visible en haut ; c'est
  voulu (elle est opaque, rien n'est composé en transparence).
- Mesure à faire : trace de performance d'une ouverture de fiche dans Chrome, avant/après.
