# ADR-0107 — Sous-titres image sur l'écran natif d'Apple TV : une couche UIKit côté plugin

- **Statut :** accepté, réalisé — compilé pour le simulateur tvOS et testé en Dart. **Jamais vu sur une
  vraie Apple TV** : le simulateur prend toujours la route logicielle, où l'écran natif ne se présente pas.
- **Date :** 2026-11-05
- **Portée :** `packages/onyx_player_apple/darwin/.../NativeBitmapSubtitles.swift` (nouveau),
  `NativePlayerPresenter.swift`, `PlayerHost.swift` (`setVideoFit`), `pigeons/messages.dart`
  (`OnyxAppleNativeReason.bitmapSubtitles`), `app/lib/screens/player/playback/native_tv_fallback.dart`,
  `native_tv_presenter.dart`.
- **Complète** [ADR-0105](0105-lecteur-natif-sur-apple-tv.md), dont la règle de repli rendait l'interface
  Flutter à toute piste image (PGS, VobSub, DVB) en Direct Play.

## Contexte

AVKit ne peint que le groupe `legible` de l'item, et une piste image n'en a pas de vraie. Choisir une piste
PGS faisait donc quitter l'écran natif (`NativeTvFallback.bitmapSubtitles`), alors qu'une bonne part des remux
Blu-ray n'a que des PGS.

Ce qu'AetherEngine fait déjà sur la route native (7.42, lu dans ses sources) :

- il décode la piste image choisie comme sur les autres routes : `subtitleCues` porte des `.image(SubtitleImage)`,
  un `CGImage` placé en pixels de son canevas ;
- avec `prepareNativeSubtitles`, il ajoute à chaque piste image (hors direct) une rendition texte remplie par OCR
  (Vision), placée après toutes les autres. C'est elle que `setNativeSubtitleRendering(true)` sélectionne quand la
  piste image est active. Le README du moteur la réserve à PiP et AirPlay : « fullscreen keeps the pixel-accurate
  overlay ».

## Décision

1. **Les images restent côté Swift.** `NativeBitmapSubtitles` lit `engine.subtitleCues` et l'horloge source,
   garde les répliques actives (`ActiveCues`, le même filtre que pour Dart) et pose leurs `CGImage` dans une vue
   ajoutée au `contentOverlayView` d'AVKit, entre l'image et la barre de transport. Rien ne passe par Dart : un
   PNG par réplique pour une interface Flutter qui n'est plus montée ne servait à rien.
2. **Le cadre se calcule.** `videoBounds` n'existe pas sur tvOS. Le cadre vidéo vient de la taille codée, du
   rapport de pixel et du `videoGravity`. Le canevas s'aligne sur la largeur et se centre en hauteur (conseil du
   moteur pour un rip recadré), ses pixels gardent le rapport de ceux de la vidéo (DVD anamorphosé).
3. **Le format d'image atteint AVKit.** `engine.videoGravity` ne règle que les calques du moteur, pas celui
   d'`AVPlayerViewController`. `setVideoFit` le recopie désormais sur le contrôleur et sur la couche des
   sous-titres, qui suivent ainsi le même cadrage que l'image.
4. **La rendition OCR sert au menu, pas à l'écran.** Tant qu'une piste image est active, une
   `AVPlayerItemLegibleOutput` à `suppressesPlayerRendering` est posée sur l'item courant : la piste reste cochée
   dans le menu Sous-titres d'AVKit, mais AVKit ne peint pas son texte reconnu par-dessus l'image.
5. **Le menu Sous-titres d'AVKit liste les pistes image** (leurs renditions OCR). Un choix y est reconnu par le
   nom de la rendition (`engine.nativeSubtitleTracks`) : les dernières renditions sont les pistes image, dans
   l'ordre du moteur. Il remonte en `subtitleSelected`, puis `selectInternalSubtitle`, donc la mémoire des pistes.
   Sans piste active, `systemCaptionRequest` ne donne que la langue : la piste texte de cette langue passe avant
   l'image, qui ne répond que seule dans sa langue.
6. **Repli.** Si la couche ne peut pas se poser (pas de `contentOverlayView`) alors qu'une piste image est
   active, le natif répond `unavailable/bitmapSubtitles` et se ferme. Ce refus ne retire pas l'écran natif : la
   règle de repli garde Flutter tant qu'une piste image est choisie, et le natif revient avec une piste texte.

## Conséquences

- Une piste image en Direct Play garde l'écran natif. `NativeTvFallback.bitmapSubtitles` ne sert plus qu'au
  refus ci-dessus.
- Le moteur fait tourner son OCR tant qu'une piste image est choisie, même si rien ne l'affiche : un coût CPU
  accepté pour avoir la piste dans le menu d'AVKit.
- Les sous-titres image ne remontent pas quand la barre de transport apparaît ; une réplique en bas peut passer
  dessous. À revoir avec `willTransitionToVisibilityOfTransportBar`, que le lot Swift de la parité branchera.
- Une couche de toast (Regarder ensemble) se posera au-dessus de celle-ci dans le même `contentOverlayView`.
- À confirmer à l'appareil : la suppression du rendu `legible` sous `AVPlayerViewController`, la place des PGS
  (rip recadré, DVD 16:9), le choix d'une piste PGS dans le menu d'AVKit avec et sans piste active, le format
  d'image (Original, Remplir) sur l'image et sur les sous-titres.
