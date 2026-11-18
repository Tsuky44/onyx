# ADR-0151 — Sur le web, les images se décodent à leur taille et la molette glisse

- **Statut :** accepté. Vérifié en test unitaire/widget ; mesures navigateur : voir « Vérification ».
- **Date :** 2026-11-18
- **Portée :** `widgets/global/app_network_image.dart`, `widgets/global/smooth_wheel_scroll.dart`
  (nouveau), `main.dart` (`AppScrollBehavior.buildScrollbar`), `pubspec.yaml`.

## Contexte

La version web est saccadée. Trois causes, traitées ici : (1) `cached_network_image` 4.0.3 utilise sur
le web `ImageRenderMethodForWeb.HtmlImage`, qui passe par `createImageCodecFromUrl` et **ignore
`memCacheWidth`** : chaque affiche est décodée à sa taille source, même quand `AppNetworkImage`
demande 256 px ; (2) Flutter web avance la molette d'un cran entier (~100 px) sans inertie ; (3) des
animations en boucle (squelettes, points « en direct ») repeignent à chaque image.

## Décision

1. **Images : `HttpGet` sur le web.** `AppNetworkImage.webRenderMethod` vaut `HttpGet`, passé au
   widget et à `providerFor` (donc au préchauffage : même clé de cache). Les octets sont téléchargés
   puis décodés par Flutter, qui applique `ResizeImage`. Il n'y a pas de cache disque côté web
   (`imageCacheManager` est nul) : c'est le cache HTTP du navigateur qui sert de magasin, comme avant.
   Aucun en-tête d'authentification n'est ajouté, donc pas de requête préliminaire CORS. Le paquet
   `cached_network_image_platform_interface` devient une dépendance directe, seulement pour nommer
   l'énumération.
2. **Molette : `SmoothWheelScroll`**, dans son propre fichier, branché dans `buildScrollbar`.
   Flutter garde la décision (quelle zone défile, jusqu'où) : son gestionnaire passe toujours en
   premier et saute d'un cran. Le widget écoute la notification de ce saut, **rembobine dans une
   micro-tâche, avant tout rendu**, et fait glisser la position vers la cible (lissage exponentiel,
   τ = 85 ms) ; les crans rapides s'additionnent dans la même cible. Il ne touche pas : au trackpad
   (deltas fractionnaires ou < 40), avec Ctrl/Cmd/Maj (zoom de grille, zoom navigateur), au clic
   molette, ni hors du web.
3. **Animations en boucle.** Elles utilisent déjà `vsync: this`, donc `TickerMode` les coupe quand
   une route les recouvre, et les listes paresseuses ne construisent pas ce qui est hors écran. On
   ajoute les `RepaintBoundary` qui manquaient (squelette, point « en direct » du tableau de bord,
   pastille de `MediaCountdown`).

## Conséquences

- Écart au choix initial de ne pas toucher l'ordre des gestionnaires : on ne peut pas devancer celui
  de Flutter depuis `buildScrollbar` (il est enregistré plus profondément), d'où le rembobinage.
- Le seuil trackpad/molette est heuristique : une molette à deltas fractionnaires garde le défilement
  par crans de Flutter.
- Si `cached_network_image` change de version, relire `HttpGet` : il passe par
  `cacheManager.getFileStream`, sans disque sur le web.
