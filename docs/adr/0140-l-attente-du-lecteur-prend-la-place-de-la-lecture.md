# ADR-0140 — L'attente du lecteur prend la place de lecture/pause, et un bouton sans piste disparaît

- **Statut :** accepté. Demandé par l'utilisateur sur des captures d'iPhone (2026-11-18) ; rendu
  vérifié sur des images du chrome en 844 × 390, **pas encore vu sur un iPhone**. Le point 3
  (anneau immobile en mode léger) est contredit par
  l'[ADR du 2026-11-23](2026-11-23-fytroz-l-attente-du-lecteur-vit-et-s-annule.md).
- **Date :** 2026-11-18
- **Portée :** `screens/player/widgets/onyx/onyx_loading_ring.dart` (nouveau),
  `widgets/player_status_panels.dart` (`PlayerLoadingSpinner`), `onyx_handheld_chrome.dart`,
  `onyx_controls_layer.dart` (`isLoading`, `hasSubtitles`), `onyx_controls_rows.dart`,
  `onyx_progress_bar.dart`, `onyx_chrome_theme.dart` (`handheldCentreAt`),
  `hooks/player_controller_subtitle_offer.dart` (nouveau, `hasSubtitleTracks`),
  `player_screen.dart`, `player_screen_chrome.dart`.
- **Prolonge** l'[ADR-0139](0139-un-seul-arrangement-du-lecteur-sur-tous-les-ecrans.md).

## Contexte

Trois défauts relevés sur un iPhone avec la version de l'ADR-0139 :

- **La vignette de la barre ne partait plus.** Après un glissé du doigt sur la barre, l'image et
  le temps visés restaient au-dessus d'elle. Seule la sortie d'une souris les effaçait ; un doigt
  ne « sort » jamais.
- **Le bouton des sous-titres ouvrait un menu vide** (« Aucune piste disponible ») sur un épisode
  sans sous-titres.
- **Le cercle d'attente était bleu et mal placé** : le bleu Material de 2020, au milieu de
  l'écran, alors que lecture/pause est à 42 % de la hauteur. Il se posait sous le bouton au lieu
  de le remplacer. « Pas fou, et pas centré. »

## Décision

1. **Un doigt qui quitte la barre emporte la vignette** (`_setDrag`) : à la fin d'un glissé,
   sauf sous une souris, qui survole encore la barre et dont la sortie s'en charge.
2. **Sans sous-titre à choisir, pas de bouton des sous-titres**, dans les trois arrangements.
   `PlayerController.hasSubtitleTracks` lit la même liste que le menu : celle du fichier en Direct
   Play, celle du serveur sinon ; « Désactivés » n'en est pas un. L'écran se reconstruit à chaque
   apparition du chrome, donc un sous-titre qui arrive en cours de lecture fait revenir le bouton.
3. **L'attente est un anneau blanc** (`OnyxLoadingRing`) : un trait fin, une traîne qui s'efface,
   une tête ronde, posé sur une ombre douce pour se lire sur un ciel comme sur le noir du
   démarrage. Il tourne une fois par `AppMotion.sweep` ; sous « réduire les animations » et en
   mode léger il reste immobile (ADR-0101).
4. **Sur un écran tenu en main, l'anneau prend la place de lecture/pause** : il se pose à
   `OnyxChromeTheme.handheldCentreAt`, le milieu du bouton, et le bouton s'efface sans quitter sa
   place ni sa cible (on peut toujours mettre en pause pendant l'attente). Ailleurs, où rien n'est
   au milieu de l'image, il est au centre de l'écran, à l'échelle du lecteur sur un téléviseur.

### Écarté

- **Griser le bouton des sous-titres** au lieu de le retirer. Un bouton qui ne fait rien prend une
  place de la rangée et un pas de télécommande.
- **Dessiner l'anneau dans le chrome.** Il disparaîtrait avec lui, alors qu'une attente doit se
  voir même chrome masqué ; l'écran le pose donc toujours, et le chrome lui laisse la place.

## Conséquences

- Le raccourci clavier des sous-titres ouvre toujours le menu, posé sans repère quand le bouton
  est absent.
- Épinglé par `test/onyx_player_loading_and_preview_test.dart` (la vignette après le doigt et sous
  la souris, le bouton absent sans piste, l'anneau à la place du bouton, immobile sous « réduire
  les animations »).
