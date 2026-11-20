# ADR-0157 — Sous Windows, les contrôles de la fenêtre vivent dans l'en-tête de verre

- **Statut :** accepté, à la demande de l'utilisateur (2026-11-19). Il a choisi la proposition D
  parmi plusieurs maquettes (« ouais la D j'aime bien »), après avoir écarté une capsule de verre
  (« ça ira pas dans le thème ») et des boutons collés au compte (« ça casse un peu »).
  Vérifié en test, **pas encore vu dans l'app lancée sous Windows**.
- **Date :** 2026-11-19
- **Portée :** `widgets/global/window_caption_buttons.dart` (nouveau : `WindowCaptionButtons`),
  `utils/window_frame_state.dart` (nouveau), `utils/window_controls_io.dart` et
  `utils/window_controls_web.dart` (`WindowControls.frameState`), `desktop_window.dart`
  (`WindowCaptionBar`, `DesktopCaptionSlot`, `WindowCaptionHost`, `windowCaptionHosted`),
  `screens/shell/shell_desktop_header.dart`, `main.dart`, `theme/app_colors.dart`
  (`windowClose`).

## Contexte

Sous Windows, la barre native est masquée et remplacée par une barre maison : une bande de 28 px
en `AppColors.surface`, plus claire que le fond de l'app, posée au-dessus de tout, avec trois
pastilles de couleur façon macOS (orange, vert, rouge). Elle découpait le haut de la fenêtre d'une
bande grise, ne ressemblait à aucune fenêtre de Windows, et prenait 28 px au-dessus d'un en-tête
de verre qui a déjà de la place libre au bout de sa rangée.

## Décision

1. **Les symboles de Windows 11, à la forme de l'en-tête** (`WindowCaptionButtons`) : réduire,
   agrandir ou restaurer, fermer, dans l'ordre de Windows et tracés comme lui (traits d'un pixel).
   Les boutons ont la hauteur et l'arrondi du champ Rechercher (34 px, 40 de large). Au repos,
   seuls les symboles sont posés sur le verre. Au survol, ils prennent le voile du champ (10 % de
   blanc), et Fermer prend le rouge de Windows (`AppColors.windowClose`, `#C42B1C`). Quand la
   fenêtre est au second plan, les symboles s'éteignent.
2. **Sur la coquille, l'en-tête les porte** : au bout de la rangée, après un trait vertical qui
   les sépare du compte. La marge de droite de l'en-tête passe de 28 à 12 px, pour que Fermer
   reste près du coin. Le vide du verre déplace la fenêtre, et un double-clic l'agrandit (le
   `WindowDragArea` que macOS avait déjà).
3. **La bande du haut ne reste qu'en repli** (`DesktopCaptionSlot`), là où aucun en-tête ne
   porte les contrôles : écrans de connexion, fenêtre trop étroite pour l'en-tête de verre, page
   opaque poussée sur le navigateur racine (« Qui regarde ? »). Elle prend le fond de l'app et non
   plus une surface plus claire. Dans le lecteur, elle sort toujours au contact du bord haut
   (`CaptionBarPeek`), posée sur un dégradé sombre au lieu d'un fond plein.
4. **« L'en-tête est à l'écran » se lit à `TickerMode`** (`WindowCaptionHost`). Une page opaque
   par-dessus met la coquille hors scène, et la bande revient. Un menu ou un panneau la laisse en
   scène, et l'en-tête reste visible derrière son voile. Le compte change après l'image : le
   modifier pendant la construction reconstruirait un ancêtre déjà construit.
5. **L'état de la fenêtre suit ses événements** (`WindowControls.frameState`, via le
   `WindowListener` de window_manager) et n'est plus relu seulement après nos clics. Win + Haut,
   un double-clic ou un glissement contre le bord de l'écran agrandissent aussi la fenêtre, et
   « Restaurer » doit alors suivre.

## Conséquences

- Sur la coquille, l'app gagne 28 px en hauteur, et le haut de la fenêtre n'a plus de bande grise.
- Le premier écran de la coquille montre la bande pendant une image, le temps que l'en-tête la
  réclame. Pousser « Qui regarde ? » la fait réapparaître à la fin de la transition, ce qui
  descend la page de 28 px.
- Sous un menu ou un panneau (route surgissante), le voile de la route couvre aussi les contrôles
  de l'en-tête : il faut fermer le menu avant de réduire la fenêtre.
- macOS ne change pas : ses feux restent natifs.
- `WindowControlPills` disparaît. `test/window_caption_buttons_test.dart` épingle l'ordre, la
  hauteur alignée sur Rechercher, le rouge de Fermer, « Restaurer » et le retrait de la bande sous
  un en-tête à l'écran.
