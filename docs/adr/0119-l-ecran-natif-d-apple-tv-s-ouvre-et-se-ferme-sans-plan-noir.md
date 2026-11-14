# ADR-0119 — L'écran natif d'Apple TV s'ouvre et se ferme sans plan noir

- **Statut :** remplacée par l'[ADR-0133](0133-pas-de-lecteur-natif-sur-l-apple-tv.md) (lecteur natif retiré le 2026-11-14). Avant : accepté. Le Dart est testé ; le Swift est compilé par la CI et **n'a pas été vu sur une
  vraie Apple TV** (le simulateur prend la route logicielle, où l'écran natif ne se présente pas).
- **Date :** 2026-11-12
- **Portée :** `packages/onyx_player_apple/darwin/.../NativePlayerPresenter.swift` (et sa copie
  `tvos/`), `app/tvos/Runner/AppDelegate.swift`,
  `app/lib/screens/player/playback/native_tv_presenter.dart`, `native_tv_screen.dart`,
  `aether_playback_session.dart`, `app/lib/screens/player/player_screen_native_tv.dart`.
- **Complète** l'[ADR-0105](0105-lecteur-natif-sur-apple-tv.md). Ne contredit aucune ADR.

## Contexte

Retour de l'utilisateur sur le lecteur « Natif » : pas assez fluide, et des défauts au lancement. Une
relecture du présentateur, des sources d'AetherEngine 7.42 et du chemin Dart a trouvé quatre causes,
toutes lues dans le code :

- **Présenté trop tôt.** L'écran natif partait dès `_isInitialized`, avant que le moteur ait un
  `AVPlayer` : AVKit montrait un plan noir sans roue pendant que la source s'ouvrait. Sur une source
  qui finit en route logicielle, il s'ouvrait pour se refermer aussitôt, retiré pour tout le film.
- **Présenté pendant une fermeture.** À l'épisode suivant, l'écran du précédent se ferme encore
  (`dismiss(animated:)`) quand le nouveau se présente. UIKit refuse une présentation pendant une
  fermeture, sans rien lever ni toujours appeler la complétion : écran noir, son joué, ou natif
  retiré pour l'épisode.
- **Fermé en série.** Menu n'était dit à Dart qu'à la *fin* de la transition d'AVKit. Dart
  enregistrait alors la progression (une requête au serveur) puis dépilait l'écran : un noir entre le
  lecteur et la fiche, puis une à trois secondes de focus vide.
- **Session audio activée au lancement de l'app.** `AppDelegate` appelait `setActive(true)` : la
  route audio se fige sur ce que le HDMI annonce à cet instant (la stéréo, liaison au repos), et un
  film en 5.1 est ensuite mixé en stéréo (AetherEngine, issue #24).

## Décision

1. **La première présentation attend le lecteur du moteur.** `NativeTvScreen.hasNativePlayer` (route
   `loopback` ou `remoteBypass`) est passé à `NativeTvPresenter.sync` ; sans lui, rien n'est
   présenté et la roue de démarrage d'Onyx reste. Au plus `playerPatience` (4 s), après quoi il se
   présente comme avant. Un écran déjà présenté n'attend rien : entre deux rechargements le moteur n'a
   pas de lecteur, et il ne doit pas se fermer.
2. **Une présentation attend la fin d'une fermeture en cours** : tant que le contrôleur qui présente
   en a un autre `isBeingDismissed`, elle se reporte de 100 ms, 30 fois au plus, avec la spec la plus
   récente.
3. **Menu est dit à Dart au début de la transition**
   (`playerViewControllerWillBeginDismissalTransition`) : la progression s'enregistre et l'écran se
   dépile pendant qu'AVKit se retire. La fin de la transition fait le ménage et redemande le focus
   (`setNeedsFocusUpdate`). Une fermeture demandée pendant celle de Menu ne relance pas un `dismiss`.
4. **`AppDelegate` ne fait que déclarer la catégorie** : c'est l'écran de lecture qui active la
   session, au moment où tvOS négocie la route.
5. **L'affiche du panneau d'infos se réencode hors du fil principal**, et un JPEG passe tel quel.

## Conséquences

- **À confirmer à l'appareil :** l'ouverture sans plan noir, l'enchaînement d'épisodes, la sortie par
  Menu (plus de noir, focus rendu tout de suite), et le 5.1 sur un ampli ou une barre de son.
- **Pas fait, et pourquoi :**
  - *Reprise d'un film transcodé et sous-titres texte en HLS* gardent l'interface Onyx (règle de
    repli de l'ADR-0105). Les lever demande une playlist VOD complète côté serveur, donc l'accord de
    l'utilisateur.
  - *Vignettes au balayage* : AetherEngine sait servir une playlist I-frame
    (`LoadOptions.serveIFramePlaylist`), incompatible avec la connexion tenue que le plugin active
    pour tout fichier brut. À essayer sur appareil, pas à l'aveugle.
  - *Image de fond pendant le chargement*, *genre et année dans le panneau d'infos*, *« Depuis le
    début » pour un film* : demandent de nouveaux champs au contrat Pigeon.
- Épinglé par `test/native_tv_presenter_test.dart` (l'attente du lecteur) ; le Swift n'a pas de test.
