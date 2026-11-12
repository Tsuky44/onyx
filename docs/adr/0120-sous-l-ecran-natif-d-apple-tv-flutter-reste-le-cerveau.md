# ADR-0120 — Sous l'écran natif d'Apple TV, Flutter doit rester le cerveau

- **Statut :** accepté. Le Dart est testé ; le Swift est compilé par la CI. Écrit d'après le premier
  essai de l'utilisateur sur une vraie Apple TV (version 1.1.41) et la lecture du code : **les causes
  sont déduites, pas observées**, et se confirment au prochain essai.
- **Date :** 2026-11-12
- **Portée :** `packages/onyx_player_apple/` (`pigeons/messages.dart`, `NativePlayerPresenter.swift`,
  `NativeInfoPanelController.swift`, `NativeOverlayView.swift`, `AetherPlayer.swift`,
  `PlayerHost.swift`),
  `app/lib/screens/player/playback/native_tv_presenter.dart`, `native_tv_panels.dart`,
  `native_tv_spec.dart`, `app/lib/screens/player/player_screen_native_tv.dart`,
  `player_screen_remote.dart`, `hooks/use_player_controller.dart`.
- **Complète** l'[ADR-0105](0105-lecteur-natif-sur-apple-tv.md) et
  l'[ADR-0119](0119-l-ecran-natif-d-apple-tv-s-ouvre-et-se-ferme-sans-plan-noir.md).

## Contexte

Trois retours après l'essai du lecteur Natif : l'épisode suivant s'ouvre en pause ; il n'y a ni
« Passer l'intro » ni proposition au générique ; le panneau « Regarder ensemble » est « un peu vide ».

L'ADR-0105 repose sur une promesse : `PlayerScreen` reste le cerveau et renvoie une spec à chaque
changement d'état. Or il ne la renvoie qu'en se **reconstruisant** (`_scheduleNativeTvSync`, appelé
dans `build`, puis un rappel de fin d'image). Un `AVPlayerViewController` se présente par défaut en
plein écran : UIKit retire alors de la hiérarchie la vue de celui qui présente, et
`FlutterViewController`, à `viewDidDisappear`, met le moteur Flutter en pause (`AppLifecycleState.paused`,
plus aucune image). Dart continue de tourner, mais rien ne se reconstruit : la spec envoyée à la
présentation est la dernière. « Passer l'intro », l'épisode suivant au générique, les menus cochés, la
liste des épisodes chargée après coup n'arrivent jamais. `hasFirstFrame`, posé dans un rappel de fin
d'image, peut aussi ne jamais venir, et tout ce qui l'attend avec lui.

## Décision

1. **L'écran natif se présente par-dessus Flutter sans retirer sa vue**
   (`modalPresentationStyle = .overFullScreen`). Flutter garde son cycle de vie et ses images ; sous
   AVKit, l'écran du lecteur ne dessine qu'un fond noir.
2. **Le présentateur rappelle l'écran quatre fois par seconde tant que le natif est présenté**
   (`NativeTvPresenter.onResync`), pour qu'il relise son état et renvoie sa spec si elle a changé. La
   promesse tient ainsi même si Flutter ne dessinait plus. Le minuteur vit dans le présentateur, pas
   dans l'écran : il ne dépend d'aucune image.
3. **La première image ne s'attend pas quand Flutter ne dessine pas** : `_maybeMarkFirstFrame` pose
   `hasFirstFrame` tout de suite si `framesEnabled` est faux. Il n'y a alors ni image à attendre ni
   texture à protéger.
4. **Après s'être présenté, l'écran natif relance la lecture si Dart la veut et que l'`AVPlayer` est
   en pause** (`AetherPlayer.resumeIfWanted`), tout de suite puis une seconde plus tard. À l'épisode
   suivant, l'écran du précédent finit de se fermer pendant que le nouveau lecteur démarre, et AVKit,
   en partant, met en pause ce qui joue. Pas au-delà d'une seconde : une pause qui arrive ensuite est
   celle de la télécommande.
5. **Les actions portent un symbole** (`OnyxAppleNativeAction.icon`) : « Passer l'intro », « Épisode
   suivant », « Épisode précédent ».
6. **« Regarder ensemble » a une colonne de présentation.** Trois champs de plus au panneau
   (`headline`, `eyebrow`, `rowsTitle`) et un à la ligne (`badge`). Hors séance : le titre, une phrase,
   le bouton plein, et à droite les trois étapes numérotées. En séance : le code en chasse fixe, très
   grand, sous « Code de la séance », le bouton pour quitter, et à droite les participants avec leur
   initiale. Avant, un paragraphe et un bouton au bout de la ligne, sur un panneau large comme l'écran.
7. **Sous l'écran natif, le doigt sur le pavé n'est plus lu par le lecteur Flutter**
   (`_handleTouchpadMove`) : la barre d'AVKit le suit déjà.
8. **Le logo du titre en haut à gauche, avec la barre de transport** (demandé le même jour : « comme
   sur l'autre lecteur »). `OnyxAppleNativeSpec.logoUrl` porte le logo que le chrome d'Onyx montre déjà
   (`_mediaLogoUrl` : celui de la série pour un épisode). `NativeOverlayView` le pose dans le
   `contentOverlayView`, à 80 pt des bords, 96 pt de haut, et le montre dans les animations coordonnées
   d'AVKit (`willTransitionToVisibilityOfTransportBar`) : il apparaît et s'efface avec la barre.
   L'ADR-0105 rangeait « le logo du titre » parmi l'impossible : AVKit n'a pas de place pour lui dans sa
   barre, mais la couche de contenu, elle, est à nous.

## Conséquences

- **À confirmer à l'appareil**, dans l'ordre : « Passer l'intro » apparaît pendant l'intro et
  « Épisode suivant » au générique ; l'épisode suivant démarre seul ; les menus se cochent après un
  choix ; l'onglet Épisodes se remplit ; le nouveau panneau « Regarder ensemble ».
- **Si `.overFullScreen` posait un souci à l'écran** (la vue de Flutter visible pendant une
  transition, le focus qui ne revient pas), le point 2 suffit à tenir la promesse : la ligne se retire
  sans rien casser d'autre.
- Le contrat Pigeon gagne six champs facultatifs ; `Messages.g.swift` et `messages.g.dart` sont
  régénérés (Pigeon 28.1.0), `tvos/` recopié.
- Épinglé par `test/native_tv_presenter_test.dart` (le rappel, les symboles) et
  `test/native_tv_parity_test.dart` (le panneau). Le Swift n'a pas de test.
