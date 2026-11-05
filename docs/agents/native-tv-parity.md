# Parité du lecteur natif Apple TV : inventaire et feuille de route

Date : 2026-11-05. Point de départ : ADR-0105 (commits `714e65d5` à `0b87b7b2`), `NativePlayerPresenter.swift`,
`native_tv_presenter.dart`, `player_screen_native_tv.dart`.

But : sur Apple TV, l'`AVPlayerViewController` doit faire tout ce que fait l'interface Onyx. `PlayerScreen` reste le
cerveau. Swift n'applique que la dernière spec reçue et remonte les gestes de l'utilisateur.

Ce document sert de feuille de route :

1. une session pose le contrat Pigeon (section 3) ;
2. deux sessions travaillent ensuite en parallèle, l'une sur le lot Swift, l'autre sur le lot Dart (section 4).

**Vérification des APIs.** Toutes les APIs AVKit citées ont été lues dans les en-têtes du SDK installé
(`AppleTVOS27.0.sdk`, `AVKit.framework/Headers`). Leur présence sur tvOS est donc établie. Ce que le simulateur ne
peut pas montrer reste marqué **« à confirmer à l'appareil »** : il prend toujours la route logicielle (spike, Q1). Deux
APIs UIKit restent **« à confirmer à la compilation »** : `UIMenuElement.subtitle` et `UIMenuOptionsSingleSelection`,
déclarées `ios(15.0)` sans mention de tvOS.

## 1. Ce qu'il faut savoir avant de lire le tableau

Sept constats changent le plan. Les cinq premiers sont des défauts du natif actuel, à corriger avant d'ajouter quoi que
ce soit.

1. **Les gestes d'AVKit contournent Dart.** Plusieurs gestes vont droit à l'`AVPlayer`, sans passer par
   `_togglePlayPause` ni `_seekTo` (`player_screen_flow.dart`) :
   - lecture et pause ;
   - sauts de 10 s, balayage du trackpad ;
   - saut de chapitre ;
   - « Lire depuis le début », l'`infoViewActions` par défaut ;
   - commandes du Centre de contrôle ou de l'app Remote.

   Trois conséquences :
   - **Regarder ensemble** : la pause locale n'est jamais annoncée. La séance croit qu'on lit encore et recale le
     lecteur, donc **la pause est annulée**. De même, une recherche locale est ramenée à la position de la séance.
   - **« Vous regardez encore ? »** et le gel des comptes à rebours ne voient aucune activité. `StillWatching` écoute
     les touches à la racine Flutter, que UIKit ne lui transmet plus. La question tombe donc à tort après N épisodes, et
     les comptes à rebours ne se gèlent jamais.
   - **HLS** : une recherche hors de ce que la session a encodé doit reconstruire la session
     (`seekToAbsoluteSeconds`), et AVKit ne le sait pas.
2. **AVKit a son propre menu Vitesse.** Sur tvOS 16 et plus, `AVPlayerViewController.speeds` vaut
   `systemDefaultSpeeds` par défaut, et l'en-tête dit qu'une liste vide masque ce menu. Aujourd'hui, il double donc le
   menu Vitesse d'Onyx, et il règle `AVPlayer.defaultRate` sans le moteur ni le facteur de vitesse de la séance. Il faut
   le masquer avec `speeds = []`.
3. **L'image dans l'image est autorisée par défaut.** `allowsPictureInPicturePlayback` vaut `YES` par défaut (en-tête,
   tvOS 14). Onyx ne la propose pas sur Apple TV, et le cycle de vie de `PlayerScreen` n'y est pas préparé. Il faut la
   mettre à `false`.
4. **Ce qui est posé sur l'item se perd.** Le moteur remplace l'item à chaque rechargement (audio, qualité : spike, Q2)
   et ne rejoue que `externalMetadata`. Tout ce qui vit sur l'`AVPlayerItem` doit être reposé à chaque
   `engine.$currentAVPlayerItem` :
   - `navigationMarkerGroups` (nom Swift de `navigationMarkersGroups`) ;
   - `nextContentProposal` ;
   - `interstitialTimeRanges`.
5. **En HLS, la barre d'AVKit est fausse.** Une session HLS commence à `_hlsStartOffset`
   (`player_controller_hls.dart`), et sa timeline repart de 0. Une reprise à 40 min affiche donc 0:00 sur la durée
   restante, et la recherche avant ce point est impossible. Tant que le serveur ne sert pas une timeline complète, il
   faut un repli vers Onyx dès que l'offset est non nul. Ce point est à valider avec le chantier transcodage.
6. **Onyx n'affiche aucune statistique à l'écran.** `PlaybackStatsCollector` mesure pendant la lecture, mais le résumé
   ne part qu'avec le journal (Réglages › Journaux de lecture). Un onglet Stats natif serait donc un ajout, pas une
   parité. Il est prévu parce qu'il est demandé.
7. **`apply()` réaffecte tout à chaque spec** (menus, actions, métadonnées). Avec des mises à jour plus fréquentes
   (toast, compte à rebours, panneaux), réaffecter `transportBarCustomMenuItems` pourrait fermer un menu ouvert (à
   confirmer à l'appareil). Le lot Swift doit donc appliquer par morceaux et ne toucher que ce qui a changé.

## 2. Tableau de parité

Légende de l'état :

- **déjà fait** : livré avec l'ADR-0105 ;
- **partiel** : livré, mais avec un défaut ou un manque ;
- **à faire** ;
- **repli** : le natif rend la main à Flutter, ce qui est voulu ou temporaire ;
- **impossible** ;
- **sans objet** : la fonction n'existe pas sur Apple TV ;
- **chantier en cours** : une autre session s'en occupe.

### 2.1 Transport et temps

| Fonction | Code Onyx | État natif | Moyen prévu | Remarque |
|---|---|---|---|---|
| Lecture / pause (OK, bouton central) | `player_screen_flow.dart` (`_togglePlayPause`), `onyx_controls_layer.dart` (`_buildTransport`) | partiel | comportement natif d'AVKit + événement `transport` | Le geste marche, mais rien ne remonte : séance, `_wantsPlayback`, `StillWatching`. Voir §1.1. |
| Reculer / avancer de 10 s (flèches, clic sur les bords) | `player_key_routing.dart` (`PlayerKeyRemoteSeek`), `player_screen_remote.dart` (`_remoteSeekStep`) | partiel | comportement natif + délégué `willResumePlaybackAfterUserNavigatedFromTime` → `userSeeked` | Même défaut. |
| Barre de progression, balayage au trackpad (ADR-0039) | `widgets/onyx/onyx_progress_bar.dart`, `player_screen_remote.dart` (`_handleTouchpadMove`), `playback/remote_seek.dart` | partiel | comportement natif + `userSeeked` | |
| Recherche HLS hors de la fenêtre encodée | `hooks/player_controller_hls.dart` (`seekToAbsoluteSeconds`) | à faire | délégué `timeToSeekAfterUserNavigatedFromTime` → `seekRequested` quand `interceptSeeks` | Le natif rend `oldTime` et Dart cherche. Un saut visuel est possible (à confirmer à l'appareil). |
| Timeline absolue en HLS (offset de session) | `hooks/player_controller_hls.dart` (`_hlsStartOffset`) | à faire (repli) | repli Onyx tant que l'offset est non nul | Voir §1.5. Une timeline complète côté serveur relève du chantier transcodage. |
| Vignettes de la barre | `playback/timeline_previews.dart` | impossible | — | AVKit ne tire ses vignettes que d'une playlist I-frame HLS, et aucune API publique n'en accepte d'autres. Une playlist I-frame servie par le moteur sur la route loopback reste possible côté AetherEngine (à confirmer). |
| Graduations des chapitres sur la barre | `onyx_controls_layer.dart` (`chapterMarks`) | à faire | `navigationMarkerGroups` (voir Chapitres) | Rendu à confirmer à l'appareil. |
| Retour visuel d'un saut | `widgets/seek_feedback_overlay.dart` | déjà fait | comportement natif | |
| Roue de chargement, voile pendant un changement de qualité | `player_screen.dart` (`PlayerLoadingSpinner`, voile `isSwitchingQuality`) | déjà fait | comportement natif (roue d'AVKit) | Le moteur garde le même `AVPlayer` à un changement de qualité. |
| Le chrome se cache, le focus suit la télécommande | `player_screen_remote.dart` (`_ensureRemoteInChrome`, `_leaveControlBar`), `chrome_auto_hide.dart` | déjà fait | comportement natif | |
| Retour / Menu | `player_screen_remote.dart` (`_handleBack`) | déjà fait | délégué `playerViewControllerDidEndDismissalTransition` → `dismissed/userDismissed` | Le focus vide une à trois secondes reste à confirmer à l'appareil. |
| OK chrome caché presse « Passer » | `player_key_routing.dart` (`PlayerKeySkipIntro`) | déjà fait | comportement natif de `contextualActions` | Le bouton prend le focus (à confirmer à l'appareil). |
| Raccourcis clavier (K, J, L, F, M, N, 0–9, ?) | `player_shortcuts.dart` | sans objet | — | Déjà coupés sur téléviseur (`player_key_routing.dart`). |
| Touche média « avance rapide » = épisode suivant | `hooks/use_player_media_keys.dart`, `player_screen_remote.dart` (`_handleMediaFastForward`) | à faire (facultatif) | `MPRemoteCommandCenter.nextTrackCommand` | AVKit enregistre déjà ses commandes. Ne l'ajouter que si un essai à l'appareil montre qu'il n'y a pas de conflit. |
| Now Playing (Centre de contrôle, app Remote de l'iPhone) | `services/macos_now_playing.dart` (macOS seulement) | déjà fait | `externalMetadata` publié en Now Playing par AVKit (`updatesNowPlayingInfoCenter` n'existe pas sur tvOS) | Ces commandes vont droit à l'`AVPlayer` : elles passent par l'événement `transport`. |
| Écran gardé allumé | `playback/screen_awake.dart` | déjà fait | comportement natif (`AVPlayer.preventsDisplaySleepDuringVideoPlayback`) | |

### 2.2 Identité et informations

| Fonction | Code Onyx | État natif | Moyen prévu | Remarque |
|---|---|---|---|---|
| Titre, surtitre (`S1:E3 - …`, année) | `onyx_controls_layer.dart` (`_buildBrand`), `player_media_info.dart` | déjà fait | `externalMetadata` (titre, `iTunesMetadataTrackSubTitle`) | |
| Logo du titre | `onyx_controls_layer.dart` (`logoUrl`) | impossible | — | AVKit n'affiche qu'un texte de titre. |
| Synopsis, affiche dans le panneau Infos | — (pas dans le chrome Onyx) | déjà fait | `externalMetadata` (description, artwork) | |

### 2.3 Menus de réglages

| Fonction | Code Onyx | État natif | Moyen prévu | Remarque |
|---|---|---|---|---|
| Qualité : Auto, le fichier tel quel, l'échelle | `onyx_settings_menu.dart` (`_buildQuality`), `hooks/use_auto_quality.dart` | partiel | `transportBarCustomMenuItems` (menu `quality`) | Il manque les secondes lignes « Le fichier tel quel », « S'adapte à la connexion », « Couleurs incorrectes sur cet appareil » et la valeur « Auto · 1080p » : `OnyxAppleNativeOption.detail` → `UIMenuElement.subtitle` (à confirmer à la compilation, puis à l'appareil pour le rendu). |
| Audio | `onyx_settings_menu.dart` (`_buildAudio`), `hooks/player_controller_tracks.dart` | partiel | `transportBarCustomMenuItems` (menu `audio`) | Seule la seconde ligne manque : codec et canaux, via `splitTrackLabel(...).$2` → `detail`. |
| Sous-titres texte en Direct Play | `onyx_settings_menu.dart` (`_buildSubtitles`), `playback/series_track_memory.dart` | déjà fait | menu Sous-titres natif d'AVKit (groupe `legible`) + `subtitleSelected` | Étape 4 de l'ADR-0105. |
| Sous-titres texte en HLS (servis à part, peints par Flutter, ADR-0031) | `playback/live_subtitles.dart`, `playback/subtitle_overlay.dart` | repli (`overlaySubtitles`) | `contentOverlayView`, la même couche que les sous-titres image | À aligner sur le chantier des sous-titres image : même vue, mêmes répliques poussées par Dart. Le menu passe alors par `transportBarCustomMenuItems` (menu `subtitles`, qu'`OnyxAppleNativeMenu` prévoit déjà). |
| Sous-titres image (PGS, VobSub) | `playback/subtitle_bitmap_overlay.dart` | chantier en cours | `contentOverlayView` | Aujourd'hui en repli (`bitmapSubtitles`). |
| Vitesse de lecture | `onyx_settings_menu.dart` (`_buildSpeed`) | partiel | `transportBarCustomMenuItems` (menu `speed`) + `speeds = []` | Le menu Vitesse d'AVKit fait doublon. Voir §1.2. |
| Affichage : Original, Remplir la hauteur, Remplir | `onyx_settings_menu.dart` (`_buildDisplay`), `video_display_mode.dart` | partiel | `transportBarCustomMenuItems` (menu `fit`) + `videoGravity` | Il manque la description de chaque mode (`mode.description` → `detail`). |
| Zoom au pincement, indice de zoom | `pinch_zoom_fit.dart`, `widgets/video_zoom_hint.dart` | sans objet | — | Réservé aux appareils tenus en main (`_handheld`). Ce n'est donc pas une perte sur Apple TV, contrairement à ce que dit l'ADR. |
| Minuterie de veille (durées, « À la fin de l'épisode », « Après N épisodes », « reste … ») | `playback/sleep_timer.dart`, `onyx_settings_menu.dart` (`_buildSleep`) | à faire | `transportBarCustomMenuItems` (menu `sleep`) | Le contrat actuel suffit, plus `detail` pour « reste 12 min ». L'échéance met en pause côté Dart, ce qui marche déjà en natif. |
| Chapitres (liste, saut) | `onyx_settings_menu.dart` (`_buildChapters`), `hooks/use_episode_navigation.dart` (`chapters`) | à faire | `AVPlayerItem.navigationMarkerGroups`, à reposer sur chaque item | Panneau Chapitres natif, à confirmer à l'appareil. Si AVKit ne l'affiche pas hors HLS, prévoir un menu `chapters` dans `transportBarCustomMenuItems`. Un saut de chapitre est une navigation de l'utilisateur, donc il remonte en `userSeeked`. |
| Délai audio ou sous-titres | — | sans objet | — | N'existe pas dans Onyx. |
| Style des sous-titres | — | déjà fait | comportement natif (réglages d'accessibilité tvOS) | Onyx n'a pas de réglage de style. AVKit applique celui du système. |

### 2.4 Segments et épisodes

| Fonction | Code Onyx | État natif | Moyen prévu | Remarque |
|---|---|---|---|---|
| Passer l'intro, passer le récap | `widgets/onyx/onyx_skip_intro_button.dart`, `playback/skip_segments.dart` | déjà fait | `contextualActions` (`skipSegment`) | |
| Saut automatique avec compte à rebours | `hooks/use_episode_navigation.dart` (`introAutoSkipCountdown`, `_startIntroAutoSkip`) | partiel | `contextualActions` (libellé fixe) + événement `userActivity` | Le saut se fait (Dart), mais la pastille qui se remplit n'existe pas, et rien ne gèle le compte à rebours. Réécrire `contextualActions` chaque seconde est déconseillé (focus). |
| Marqueurs de segments sur la barre | — | impossible (écarté) | ~~`AVInterstitialTimeRange`~~ | L'en-tête le dit : une plage interstitielle est repliée en un point de la barre. L'intro disparaîtrait de la durée affichée. |
| Épisode suivant au générique, compte à rebours, « Annuler » | `widgets/next_episode_overlay.dart`, `hooks/use_episode_navigation.dart` (`_startOutroAutoPlay`, `cancelAutoPlay`) | partiel | `AVContentProposal` + sous-classe d'`AVContentProposalViewController` | Aujourd'hui, une action contextuelle sans compte à rebours ; l'enchaînement se fait quand même (Dart). Voir le détail sous ce tableau. |
| Pas de compte à rebours si la minuterie s'arrête après cet épisode | `player_screen.dart` (`SleepTimer.instance.stopsAfterThisEpisode`) | à faire | `nextUp.countdownSeconds` nul | Décidé côté Dart. |
| Épisode précédent, épisode suivant (boutons de transport) | `onyx_controls_layer.dart` (`onSkipPrevious`, `onSkipNext`), `hooks/use_episodes_panel.dart` (épisode précédent) | à faire | `infoViewActions` (deux au plus, d'après l'en-tête) | Remplace « Lire depuis le début », qui contournerait Dart. Une liste vide le retire aussi. |
| Panneau des épisodes (saisons, liste, ouvrir un épisode) | `widgets/player_episodes_panel.dart`, `hooks/use_episodes_panel.dart` | à faire | `customInfoViewControllers`, onglet « Épisodes » | Panneau générique (§3) : saisons en onglets, épisodes en lignes. |
| Carte « saison suivante » (la demander) | `widgets/next_season_overlay.dart` | repli (`_needsFlutterScreen`) | question native (`UIAlertController` présenté sur l'`AVPlayerViewController`) | Une sous-classe d'`AVContentProposalViewController` peut réduire l'image comme la carte Onyx, mais une seule proposition existe par item. La question est plus simple. |
| Carte « épisode pas encore sorti » | `widgets/upcoming_episode_overlay.dart` | repli | question native | |
| Question de langue (épisode suivant ou lancement sans la langue suivie) | `widgets/language_gap_overlay.dart`, `playback/audio_language_gap.dart` | repli | question native | |
| « Vous regardez encore ? » | `widgets/still_watching_prompt.dart`, `playback/still_watching.dart` | repli | question native + `userActivity` | Sans `userActivity`, le compte d'épisodes est faux (§1.1). |
| Lecture reprise sur un autre appareil | `hooks/use_playback_handoff.dart`, `widgets/player_status_panels.dart` (`PlayingElsewhere`) | repli | question native | |
| Démarrage bloqué (« Réessayer ») | `widgets/player_status_panels.dart` (`StalledStartup`) | repli (définitif) | repli Onyx | Arrive avant la première image ou pendant un rechargement. L'interface Flutter est déjà là pour ça. |
| Retour après une TV éteinte (`PlayerAwayGuard`) | `playback/away_from_screen.dart` | déjà fait | — (Dart, par le moteur) | Une recherche ordinaire, faite par Dart. |

**Épisode suivant, en détail :**

- Swift pose `item.nextContentProposal` quand `spec.nextUp` arrive, avec `contentTimeForTransition` = `transitionMs`.
- Le délégué `shouldPresentContentProposal` ne répond vrai que si `spec.nextUp` est non nul.
- La proposition présentée affiche le compte à rebours de Dart (`countdownSeconds`). Elle **n'utilise pas**
  `dateOfAutomaticAcceptance` : Dart reste seul maître de l'enchaînement, avec la question de langue et la minuterie.
- « Lire » renvoie `action/nextEpisode`.
- « Plus tard » appelle `dismissContentProposal(for: .defer)`, puis renvoie `action/cancelAutoPlay`. **Pas `.reject`** :
  d'après l'en-tête, `.reject` ferme le lecteur.
- Présenter une proposition dont l'heure est déjà passée est à confirmer à l'appareil. À défaut, poser `transitionMs` =
  le temps courant de l'item + 0,5 s.

### 2.5 Regarder ensemble

| Fonction | Code Onyx | État natif | Moyen prévu | Remarque |
|---|---|---|---|---|
| Panneau : démarrer une séance, code, participants, hôte, quitter | `widgets/watch_party_overlay.dart` (`WatchPartyPanel`), `hooks/use_player_watch_party.dart` (`start`, `leave`) | à faire | `customInfoViewControllers`, onglet « Regarder ensemble » | Panneau générique : texte, code, lignes des participants, actions. « Copier » est sans objet sur TV. |
| Annonces (« alex a mis en pause »), attente d'un participant | `widgets/watch_party_overlay.dart` (`WatchPartyToast`), `use_player_watch_party.dart` (`notice`, `waitingMessage`) | à faire | `contentOverlayView` (`spec.toast`) | Non interactif, au-dessus de l'image et sous les contrôles. |
| La séance pilote le lecteur (lecture, pause, recherche, vitesse) | `services/watch_party.dart`, `use_player_watch_party.dart` (`applyPlaying`, `applySeek`, `applyRateFactor`) | déjà fait | — (passe par le moteur) | AVKit reflète l'`AVPlayer`. |
| Les gestes locaux sont annoncés à la séance | `player_screen_flow.dart` (`_seekTo`, `_togglePlayPause`) | à faire (régression) | événements `transport`, `userSeeked`, `seekRequested` → mêmes chemins | Priorité 1 (§1.1). |
| La séance change de média | `use_player_watch_party.dart` (`openMedia`) | déjà fait | — | Nouvel écran, donc `dismissNative` puis `presentNative`, comme l'épisode suivant. À vérifier à l'appareil. |
| Rejoindre une séance, invitations | menu du compte (hors lecteur) | sans objet | — | |

### 2.6 Session, réseau, journaux (Dart, sans interface)

| Fonction | Code Onyx | État natif | Moyen prévu | Remarque |
|---|---|---|---|---|
| Envoi de la progression | `hooks/playback_reporter.dart` | déjà fait | — | Tourne sur la session. |
| Mémoire des pistes par série | `playback/series_track_memory.dart` | déjà fait | — | |
| Qualité Auto (descente, confiance) | `playback/auto_quality.dart`, `auto_descent.dart`, `auto_trust.dart` | déjà fait | — | |
| Reprise après coupure du flux, relais | `playback/stream_cut_recovery.dart`, `relay_trigger.dart` | déjà fait | — | Un rechargement garde l'`AVPlayer`. |
| Journal de lecture et statistiques résumées (ADR-0026) | `playback/playback_stats.dart`, `engineLog` | déjà fait | — | |
| Adapter l'écran au film (HDR, cadence), décodage matériel | `display_frame_rate.dart`, `hardware_decoding.dart` | déjà fait | `appliesPreferredDisplayCriteriaAutomatically = false`, le moteur écrit les critères | HDR et Dolby Vision à confirmer à l'appareil (spike, Q4). |
| Codecs sans décodeur matériel (route logicielle) | `native_tv_fallback.dart` (`softwareRoute`) | chantier en cours | repli Onyx en attendant | Transcodage serveur. |
| Refus du natif, échec de présentation | `native_tv_fallback.dart`, `native_tv_presenter.dart` (`_refusal`) | déjà fait | repli Onyx | |

### 2.7 Statistiques et fonctions propres aux autres appareils

| Fonction | Code Onyx | État natif | Moyen prévu | Remarque |
|---|---|---|---|---|
| Statistiques à l'écran | — (absent d'Onyx) | à faire (ajout) | `customInfoViewControllers`, onglet « Stats » | Swift lit le moteur chaque seconde tant que l'onglet est visible, avec la fonction qui sert `stats()`. Dart ne fournit que les libellés. |
| Image dans l'image | `PictureInPictureBridge.swift` (iPhone, iPad) | sans objet | `allowsPictureInPicturePlayback = false` | Voir §1.3. |
| Volume, muet, luminosité, plein écran, verrouillage, PiP d'ordinateur, double tap | `onyx_brightness_slider.dart`, `player_screen_lock.dart`, `desktop_pip_overlay.dart`, `player_tap_zones.dart` | sans objet | — | Déjà absents du chrome TV. |

## 3. Extension du contrat Pigeon

Fichier : `packages/onyx_player_apple/pigeons/messages.dart`. Puis :

```
dart run pigeon --input pigeons/messages.dart
dart run tool/sync_tvos.dart
```

Tous les textes restent traduits côté Dart. Les listes sont requises et valent `[]` quand elles sont vides, pour que
l'égalité Pigeon (`updateNative` seulement si la spec change) reste simple.

### 3.1 Champs ajoutés aux types existants

```dart
class OnyxAppleNativeOption {
  // … id, label, selected inchangés …

  /// Seconde ligne, déjà traduite (`UIMenuElement.subtitle`) : le codec d'une
  /// piste, « reste 12 min » d'une minuterie, l'avertissement Dolby Vision.
  final String? detail;
}

class OnyxAppleNativeSpec {
  // … title, subtitle, posterUrl, overview, menus, actions inchangés …

  /// `AVPlayerItem.navigationMarkerGroups`, reposé sur chaque nouvel item.
  final List<OnyxAppleNativeChapter> chapters;

  /// `infoViewActions` (deux au plus) : épisode précédent, épisode suivant.
  /// Vide, AVKit n'en montre aucune : pas de « Lire depuis le début », qui
  /// chercherait sans Dart.
  final List<OnyxAppleNativeAction> infoActions;

  /// L'épisode suivant proposé au générique (`AVContentProposal`), ou null.
  final OnyxAppleNativeNextUp? nextUp;

  /// La question à poser par-dessus le lecteur (`UIAlertController`), ou null.
  final OnyxAppleNativePrompt? prompt;

  /// Les onglets ajoutés au panneau d'infos (`customInfoViewControllers`),
  /// dans l'ordre : Épisodes, Regarder ensemble, Stats.
  final List<OnyxAppleNativePanel> panels;

  /// Une annonce en haut de l'image (`contentOverlayView`), ou null pour la
  /// retirer. Regarder ensemble l'utilise.
  final String? toast;

  /// Le natif retient les recherches de l'utilisateur au lieu de les
  /// appliquer, et les remonte en `seekRequested` : Dart décide (HLS, où
  /// une recherche peut reconstruire la session).
  final bool interceptSeeks;
}

class OnyxAppleNativeEvent {
  // … playerId, kind, actionId, menuId, optionId, trackId, reason inchangés …

  /// `transport` : l'état demandé dans AVKit.
  final bool? playing;

  /// `transport`, `userSeeked`, `seekRequested` : la position en temps de
  /// l'item (millisecondes).
  final int? positionMs;

  /// `userSeeked` : d'où l'utilisateur est parti.
  final int? fromPositionMs;

  /// `panelRowSelected`, `panelTabSelected`.
  final String? panelId;

  /// `panelRowSelected`.
  final String? rowId;
}
```

### 3.2 Nouveaux types

```dart
/// Un chapitre, pour `AVPlayerItem.navigationMarkerGroups`
/// (`AVTimedMetadataGroup` : titre et plage).
class OnyxAppleNativeChapter {
  OnyxAppleNativeChapter({
    required this.title,
    required this.startMs,
    required this.endMs,
  });

  /// Déjà traduit (« Chapitre 3 » quand le fichier n'a pas de titre).
  final String title;
  final int startMs;
  final int endMs;
}

/// L'épisode suivant, proposé par une sous-classe
/// d'`AVContentProposalViewController`. Dart reste maître de l'enchaînement :
/// le natif n'accepte jamais de lui-même.
class OnyxAppleNativeNextUp {
  OnyxAppleNativeNextUp({
    required this.title,
    required this.transitionMs,
    required this.playLabel,
    required this.laterLabel,
    this.subtitle,
    this.imageUrl,
    this.countdownSeconds,
  });

  /// « S1:E4 · Le titre ».
  final String title;
  final String? subtitle;

  /// L'image de l'épisode, en URL absolue avec son ticket.
  final String? imageUrl;

  /// `contentTimeForTransition` : le début du générique, en temps de l'item.
  final int transitionMs;

  /// Les secondes qui restent avant que Dart n'enchaîne, ou null sans compte
  /// à rebours (gelé, annulé, minuterie de veille).
  final int? countdownSeconds;

  /// « Lire » → action `nextEpisode` ; « Plus tard » → action
  /// `cancelAutoPlay`, après `dismissContentProposal(for: .defer)`.
  final String playLabel;
  final String laterLabel;
}

/// Une question posée par-dessus le lecteur natif : « Vous regardez
/// encore ? », langue manquante, saison suivante, épisode à venir, lecture
/// reprise ailleurs.
class OnyxAppleNativePrompt {
  OnyxAppleNativePrompt({
    required this.id,
    required this.title,
    required this.actions,
    required this.cancelActionId,
    this.message,
  });

  /// Stable d'une spec à l'autre : la même question n'est pas reposée.
  final String id;
  final String title;
  final String? message;

  /// Dans l'ordre d'affichage ; la première est l'action préférée.
  final List<OnyxAppleNativeAction> actions;

  /// L'action que vaut Menu (la touche Retour de la télécommande), rendue en
  /// `action`. Elle doit être l'une de [actions].
  final String cancelActionId;
}

/// Une ligne d'un panneau : un épisode, un participant, une statistique.
class OnyxAppleNativePanelRow {
  OnyxAppleNativePanelRow({
    required this.id,
    required this.title,
    required this.selected,
    required this.selectable,
    this.subtitle,
    this.detail,
    this.imageUrl,
    this.progress,
  });

  final String id;
  final String title;
  final String? subtitle;

  /// À droite : une durée, « Hôte », une valeur de statistique.
  final String? detail;
  final String? imageUrl;

  /// Avancement de 0 à 1, pour un épisode commencé.
  final double? progress;

  /// L'épisode qui joue : marqué, et le focus y entre.
  final bool selected;

  /// Faux pour une ligne d'information (participant, statistique).
  final bool selectable;
}

/// Un onglet du panneau d'infos d'AVKit (`customInfoViewControllers`).
///
/// Un seul modèle pour Épisodes, Regarder ensemble et Stats : Swift a un seul
/// contrôleur à écrire.
class OnyxAppleNativePanel {
  OnyxAppleNativePanel({
    required this.id,
    required this.title,
    required this.tabs,
    required this.rows,
    required this.actions,
    required this.loading,
    this.message,
  });

  /// `episodes`, `watchParty`, `stats` : rendu dans les événements.
  final String id;

  /// Le titre de l'onglet (`UIViewController.title`).
  final String title;

  /// Un paragraphe au-dessus des lignes : l'explication et le code de la
  /// séance, une erreur.
  final String? message;

  /// Les saisons : un choix rendu en `panelTabSelected` (`optionId`).
  final List<OnyxAppleNativeOption> tabs;

  /// Pour `stats`, les lignes ne portent que l'identifiant de la mesure
  /// (`route`, `videoCodec`, `videoDecoder`, `audioDecoder`, `observedFps`,
  /// `containerFps`, `droppedFrames`, `averageBitrateMbps`, `videoBitrate`,
  /// `videoFormat`, `audioDelivery`, `container`) et son libellé : Swift
  /// remplit `detail` lui-même, chaque seconde, tant que l'onglet est
  /// visible.
  final List<OnyxAppleNativePanelRow> rows;

  /// Les boutons sous les lignes (« Démarrer une séance », « Quitter la
  /// séance »), rendus en `action`.
  final List<OnyxAppleNativeAction> actions;
  final bool loading;
}
```

### 3.3 Nouveaux types d'événements

Ajouts à `OnyxAppleNativeEventKind`, après `unavailable` (l'ordre des valeurs existantes ne bouge pas) :

```dart
  /// Lecture ou pause demandée dans AVKit (télécommande, Centre de contrôle,
  /// app Remote) : `playing`, `positionMs`. Jamais pour une demande de Dart.
  transport,

  /// L'utilisateur a déplacé la lecture dans AVKit (saut de 10 s, balayage,
  /// chapitre), déjà appliqué : `fromPositionMs`, `positionMs`.
  userSeeked,

  /// La même chose, retenue parce que `interceptSeeks` : Dart doit chercher
  /// `positionMs`.
  seekRequested,

  /// Une ligne choisie dans un panneau : `panelId`, `rowId`.
  panelRowSelected,

  /// Un onglet choisi dans un panneau (une saison) : `panelId`, `optionId`.
  panelTabSelected,

  /// Quelqu'un se sert de la télécommande : la barre de transport apparaît,
  /// un menu, une action ou une navigation. Au plus un toutes les 5 s.
  userActivity,
```

### 3.4 Identifiants que Dart ajoute à `NativeTvIds`

| Où | Identifiants |
|---|---|
| Menus | `sleep` (options `off`, `episodes:<n>`, `minutes:<n>`) ; `chapters` (repli, options `chapter:<id>`) ; `subtitles` (sous-titres HLS, plus tard) |
| Actions | `previousEpisode`, `cancelAutoPlay` ; `watchParty.start`, `watchParty.leave` |
| Questions | `stillWatching`, `languageGap`, `launchLanguageGap`, `nextSeason`, `upcomingEpisode`, `playingElsewhere` |
| Réponses | `<question>.<réponse>` : `stillWatching.continue`, `stillWatching.leave`, `languageGap.continue`, `languageGap.wait`, `languageGap.dismiss`, `nextSeason.request`, `nextSeason.playNext`, `nextSeason.dismiss`, `upcomingEpisode.playNext`, `upcomingEpisode.dismiss`, `playingElsewhere.resume`, `playingElsewhere.leave` |
| Panneaux | `episodes` (lignes `episode:<id>`, onglets `season:<id>`) ; `watchParty` (lignes `member:<id>`) ; `stats` |

### 3.5 Ce que la session du contrat livre en plus

Les nouveaux champs requis cassent la construction de la spec. La session du contrat :

- remplit donc `NativeTvSpecBuilder.build` avec des valeurs vides (`[]`, `null`, `false`) ;
- ajoute à `nativeTvIntentOf` des branches qui rendent `null` pour les nouveaux types d'événements ;
- ajoute à `NativePlayerPresenter.swift` un `default` qui ignore les champs inconnus.

Le dépôt reste ainsi vert, et les deux lots partent du même commit. Elle relance enfin
`app/test/onyx_player_apple_sources_test.dart`, qui vérifie la copie `tvos/`.

## 4. Découpage en deux lots indépendants

Les deux lots ne partagent aucun fichier. Ils ne dépendent l'un de l'autre que par le contrat généré. Dans chaque lot,
l'ordre est une priorité : P1 corrige les défauts du §1, P2 et P3 ajoutent des fonctions.

### 4.1 Lot Swift

**Fichiers :**

- `packages/onyx_player_apple/darwin/onyx_player_apple/Sources/onyx_player_apple/NativePlayerPresenter.swift` ;
- nouveaux fichiers voisins, tous sous `#if os(tvOS)` :
  - `NativeInfoPanelController.swift` ;
  - `NativeNextUpProposalController.swift` ;
  - `NativeOverlayView.swift` ;
- `PlayerHost.swift`, pour la marque « demandé par Dart » et l'extraction des stats ;
- la copie `tvos/`, par `dart run tool/sync_tvos.dart`.

**P1 : défauts**

1. `speeds = []` et `allowsPictureInPicturePlayback = false` à la création du contrôleur.
2. `apply(spec)` par morceaux : ne réaffecter `transportBarCustomMenuItems`, `contextualActions`, `infoViewActions`,
   `customInfoViewControllers` et la proposition que si la partie correspondante de la spec a changé.
3. `transport` : observer `AVPlayer.rateDidChangeNotification`. Ignorer les changements que Dart vient de demander :
   `PlayerHost` arme une marque sur `play`, `pause`, `setRate` et `seekTo`, puis le présentateur la consomme. Ignorer
   aussi l'attente du tampon (`timeControlStatus == .waitingToPlayAtSpecifiedRate`). La distinction moteur ou
   utilisateur est à confirmer à l'appareil, et `AVPlayerRateDidChangeReasonKey` (tvOS 15) peut aider.
4. `userSeeked` par `playerViewController(_:willResumePlaybackAfterUserNavigatedFrom:to:)`. Quand `interceptSeeks` est
   vrai, utiliser à la place `playerViewController(_:timeToSeekAfterUserNavigatedFrom:to:)`, qui rend `oldTime` et
   émet `seekRequested`.
5. Reposer sur chaque `engine.$currentAVPlayerItem` tout ce qui vit sur l'item : `navigationMarkerGroups` et
   `nextContentProposal` (§1.4).

**P2**

6. `OnyxAppleNativeOption.detail` → `UIAction.subtitle` (à confirmer à la compilation). `UIMenu` avec `.singleSelection`
   pour les menus cochés (à confirmer à la compilation).
7. `userActivity` : délégué `playerViewController(_:willTransitionToVisibilityOfTransportBar:with:)` quand la barre
   apparaît, plus chaque menu, action et navigation. Une fois toutes les 5 s au plus.
8. Chapitres : `AVTimedMetadataGroup` (titre `commonIdentifierTitle`, plage `startMs`–`endMs`) dans un
   `AVNavigationMarkersGroup` sans titre. Le rendu est à confirmer à l'appareil.
9. `infoActions` → `infoViewActions`. Une liste vide retire « Lire depuis le début ».
10. `prompt` → `UIAlertController` présenté par l'`AVPlayerViewController`. L'action `cancelActionId` porte le style
    `.cancel`, donc Menu la déclenche. La question n'est reprise que si son `id` change, et elle est retirée quand
    `prompt` devient nul.

**P3**

11. `NativeOverlayView` dans `contentOverlayView` : le toast en haut au centre, avec fondu à l'apparition et au
    retrait. Il réserve sa place sous la future couche des sous-titres image, à voir avec ce chantier.
12. `NativeNextUpProposalController`, une sous-classe d'`AVContentProposalViewController` :
    - image, titre, compte à rebours et deux boutons ;
    - `preferredPlayerViewFrame` réduit l'image dans un coin ;
    - « Plus tard » appelle `.defer`, jamais `.reject` ;
    - délégués `shouldPresentContentProposal`, `didAcceptContentProposal` et `didRejectContentProposal` ;
    - le compte à rebours est mis à jour en place, sans nouvelle présentation.
13. `NativeInfoPanelController`, un seul contrôleur pour un `OnyxAppleNativePanel` :
    - onglets, paragraphe, lignes focalisables (`UICollectionView`), boutons ;
    - `preferredContentSize` fixe ;
    - mise à jour en place, sans recréer le contrôleur ni perdre le focus ;
    - le panneau `stats` lit le moteur chaque seconde entre `viewWillAppear` et `viewDidDisappear`, avec la fonction
      extraite de `PlayerHost.stats`.

À confirmer à l'appareil pour ce lot :

- rendu des secondes lignes dans la barre de transport ;
- panneau Chapitres hors HLS ;
- présentation d'une proposition dont l'heure est passée ;
- focus dans un onglet personnalisé ;
- aucun `transport` parasite sur un rechargement.

### 4.2 Lot Dart

**Fichiers :**

- `app/lib/screens/player/playback/native_tv_presenter.dart` : `NativeTvState`, `NativeTvSpecBuilder`, `NativeTvIds`,
  `NativeTvIntent` et `nativeTvIntentOf` ;
- `app/lib/screens/player/player_screen_native_tv.dart` : collecte de l'état, `_handleNativeTvIntent`,
  `_needsFlutterScreen` ;
- `app/lib/screens/player/playback/native_tv_fallback.dart` : règle HLS ;
- `app/lib/screens/player/playback/aether_playback_session.dart` (`_AetherNativeTvScreen`), seulement si un champ
  d'événement doit être traduit ;
- `app/lib/l10n/en.dart` ;
- les tests `app/test/native_tv_presenter_test.dart` et `app/test/native_tv_fallback_test.dart`.

**P1 : défauts**

1. `NativeTvTransport(playing, position)` passe par le chemin de `_togglePlayPause`, sans rappeler le moteur :
   - annonce à la séance (`party.sendPlaying`) ;
   - `_wantsPlayback` ;
   - `StillWatching.instance.noteActivity()`.

   `NativeTvUserSeeked(position)` annonce de même `party.sendSeek`. `NativeTvSeekRequested(position)` appelle
   `_seekTo`. La position est en temps de l'item : la convertir en absolu par le contrôleur.
2. `interceptSeeks` = la lecture passe par une session HLS (`controller.currentQuality != null`).
3. Repli `hlsOffset` dans `nativeTvFallbackFor`, tant que `_hlsStartOffset > 0` (§1.5). À valider avec le chantier
   transcodage.
4. `NativeTvUserActivity` appelle `StillWatching.instance.noteActivity()` et `_episodeNav?.onUserActivity()`, ce qui gèle
   les deux comptes à rebours.

**P2**

5. `detail` dans les menus Qualité, Audio et Affichage, avec les mêmes textes que `onyx_settings_menu.dart`.
6. Menu `sleep` (`SleepTimer.choices`, `episodeChoices` devant un épisode, « reste … »), branché sur `SleepTimer.start`,
   `startEpisodes` et `cancel`.
7. `chapters` depuis `_episodeNav.chapters`. La fin d'un chapitre est le début du suivant, ou la durée pour le dernier.
8. `infoActions` : « Épisode précédent » (`_episodesPanel.previousEpisode`) et « Épisode suivant » (`nav.nextEpisode`).
9. Questions natives : `prompt` construit depuis `_stillWatchingAsked`, `nav.showLaunchLanguageCard`,
   `nav.showLanguageGapCard`, `nav.showNextSeasonCard`, `nav.showUpcomingEpisodeCard` et `_handoff.handedOffTo`.
   Chaque réponse passe par le gestionnaire qu'Onyx appelle déjà :
   - `_confirmStillWatching`, `_leavePlayer` ;
   - `_continueInOfferedLanguage`, `_waitForAudioLanguage`, `_dismissEndCard` ;
   - `_requestNextSeason` ;
   - `_handoff.resumeHere`.

   Ces cas sortent alors de `_needsFlutterScreen`, où il ne reste que `_startupStalled`.

**P3**

10. `nextUp` depuis `nav.nextEpisode`, `nav.outroCountdownSeconds`, `nav.outroAutoPlayActive`, `outroAutoPlayFrozen` et
    `SleepTimer.instance.stopsAfterThisEpisode`. `NativeTvCancelAutoPlay` appelle `nav.cancelAutoPlay()`. L'action
    contextuelle `nextEpisode` reste après un « Plus tard ».
11. Panneau `episodes` depuis `_episodesPanel`. Le premier affichage déclenche le chargement (`_openEpisodesPanel` sans
    l'interface). `panelTabSelected` appelle `selectSeason`, et `panelRowSelected` appelle `_navigateToEpisode`.
12. Panneau `watchParty` depuis `_party.party`, avec les textes de `watch_party_overlay.dart`. Les actions appellent
    `start` et `leave`. `toast` = `party?.waitingMessage ?? (_party.noticeVisible ? _party.notice : null)`.
13. Panneau `stats` : libellés seulement (§3.2).
14. Traductions anglaises de chaque nouveau texte dans `en.dart`. Tests du constructeur de spec et de la traduction des
    événements, sans moteur.

## 5. Recette à ajouter

Ajouter à `docs/agents/native-tv-player-manual-tests.md`, une fois les lots livrés :

- en séance partagée, pause et saut à la télécommande, avec le second appareil qui suit ;
- « Vous regardez encore ? » qui ne tombe pas quand on s'est servi de la télécommande ;
- minuterie de veille depuis le menu natif ;
- chapitres ;
- proposition d'épisode suivant avec compte à rebours, puis « Plus tard » ;
- onglets Épisodes, Regarder ensemble et Stats ;
- pas de menu Vitesse en double, pas de bouton PiP ;
- reprise HLS à 40 min : repli vers Onyx tant que la timeline serveur n'est pas complète.
