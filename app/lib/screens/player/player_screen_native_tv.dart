part of 'player_screen.dart';

/// L'écran natif d'Apple TV. Quand il est présenté, l'interface Flutter du
/// lecteur se retire (scène vidéo, chrome, gestes, cartes), mais cet écran
/// reste le cerveau : progression, segments, épisode suivant, mémoire des
/// pistes, qualité et séance partagée tournent sur la même session. Voir
/// [NativeTvPresenter].
extension _PlayerNativeTv on _PlayerScreenState {
  bool get _nativeTvShown => _nativeTv?.isShown ?? false;

  /// Le présentateur, là seulement où il servira : un appareil éligible et un
  /// moteur qui a un écran natif.
  NativeTvPresenter? _createNativeTv() {
    if (!isNativeTvPlayerEligible()) return null;
    final screen = _playerController.session.nativeTvScreen;
    if (screen == null) return null;
    return NativeTvPresenter(screen: screen, onIntent: _handleNativeTvIntent);
  }

  /// Ce que seule l'interface Flutter sait montrer. Le natif lui rend la main
  /// le temps qu'il faut, puis la reprend.
  bool get _needsFlutterScreen =>
      _stillWatchingAsked ||
      _endCardVisible ||
      (_episodeNav?.showLaunchLanguageCard ?? false) ||
      _handoff.handedOffTo != null ||
      _startupStalled;

  bool get _nativeTvWanted =>
      _isInitialized &&
      !_isLeaving &&
      !_isDisposing &&
      !_needsFlutterScreen &&
      _nativeTvFallback == null;

  /// Ce que le média demande, relu à chaque construction : une piste image
  /// choisie, ou la route logicielle qui s'installe en cours de film, rendent
  /// l'interface Flutter sans couper la lecture.
  NativeTvFallback? get _nativeTvFallback {
    final controller = _playerController;
    final screen = controller.session.nativeTvScreen;
    return nativeTvFallbackFor(
      refusal: _nativeTv?.refusal,
      softwareRoute: screen?.softwareRoute ?? false,
      subtitle: nativeTvSubtitleKind(
        selectedLang: controller.selectedSubtitleLang,
        serverTracks: controller.mediaTracks?.subtitles,
        engineShowsBitmap: screen?.showsBitmapSubtitle ?? false,
      ),
      streaming: controller.currentQuality != null,
    );
  }

  /// Appelé à chaque construction de l'écran : c'est là que tout changement
  /// d'état arrive. Le présentateur ne passe le pont que si la spec a changé.
  void _scheduleNativeTvSync() {
    if (_nativeTv == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNativeTv());
  }

  void _syncNativeTv() {
    final presenter = _nativeTv;
    if (presenter == null || !mounted) return;
    presenter.sync(wanted: _nativeTvWanted, spec: _nativeTvSpec());
    if (!presenter.isShown) return;
    presenter.syncFit(
      _displayMode.fit,
      _playerController.videoAspectRatio,
      MediaQuery.sizeOf(context),
    );
  }

  NativeTvSpec _nativeTvSpec() {
    final controller = _playerController;
    final nav = _episodeNav;
    final media = _info.media;
    return NativeTvSpecBuilder.build(NativeTvState(
      title: _info.showTitle,
      subtitle: _info.overline,
      posterUrl: detailPosterUrl(
        _info.item?.displayPosterUrl ?? media.posterUrl,
        serverBaseUrl: _apiClient?.baseUrl,
      ),
      overview: media.overview,
      rate: _playbackRate,
      rates: _PlayerScreenState._playbackRates,
      mode: _displayMode,
      quality: NativeTvQuality(
        tiers: PlayerMenuChoices.qualityTiers(controller.mediaTracks),
        current: controller.currentQuality,
        isAuto: controller.isAutoQuality,
        autoAvailable: controller.autoQualityAvailable,
        isLocalPlayback: controller.isLocalPlayback,
      ),
      serverAudio: controller.mediaTracks?.audio,
      selectedAudioIndex: controller.selectedAudioIndex,
      engineAudio: controller.session.audioTracks,
      currentEngineAudio: controller.session.currentAudioTrack,
      skipSegment: (nav?.showSkipIntro ?? false) ? nav!.skipSegment : null,
      // Au générique seulement, comme la pastille de l'interface Onyx : une
      // action contextuelle d'AVKit est faite pour un moment, pas pour tout
      // l'épisode.
      hasNextEpisode:
          nav?.nextEpisode != null && (nav?.showNextEpisodeOutro ?? false),
    ));
  }

  /// Chaque demande du natif passe par le gestionnaire que l'interface Onyx
  /// appelle déjà : la logique (séance partagée, mémoire des pistes, Auto)
  /// n'existe qu'une fois.
  void _handleNativeTvIntent(NativeTvIntent intent) {
    if (_isDisposing || !mounted) return;
    switch (intent) {
      case NativeTvSkipSegment():
        unawaited(_skipIntroFromControl());
      case NativeTvNextEpisode():
        _goToNextEpisode();
      case NativeTvSetRate(:final rate):
        unawaited(_setPlaybackRate(rate));
      case NativeTvSetFit(:final mode):
        _updateDisplayMode(mode);
      case NativeTvSetQuality(auto: true):
        _playerController.chooseAutoQuality();
      case NativeTvSetQuality(:final key):
        unawaited(_playerController.chooseQuality(key));
      case NativeTvSetAudio(:final serverIndex?):
        unawaited(_playerController.switchAudioTrack(serverIndex));
      case NativeTvSetAudio(:final engineTrackId?):
        final track = _playerController.session.audioTracks
            .where((track) => track.id == engineTrackId)
            .firstOrNull;
        if (track != null) {
          unawaited(_playerController.session.setAudioTrack(track));
        }
      case NativeTvSetAudio():
        break;
      case NativeTvSetSubtitle(:final trackId):
        // Le menu AVKit ne liste que les pistes du fichier : le même chemin
        // que le menu Onyx en Direct Play, mémoire des pistes comprise. Le
        // moteur n'a rien adopté de lui-même, c'est ce rappel qui fait tenir
        // le choix.
        final track = nativeTvSubtitleChoice(
            trackId, _playerController.session.subtitleTracks);
        if (track == null || !_playerController.listsEmbeddedSubtitles) {
          debugPrint('Lecteur natif : sous-titre $trackId ignoré');
          break;
        }
        _playerController.selectInternalSubtitle(track);
      case NativeTvClosed():
        // Menu sur la télécommande : le même chemin que Retour, pour que la
        // progression parte et que la séance soit quittée.
        unawaited(_handleBack());
      case NativeTvUnavailable(:final reason):
        debugPrint('Lecteur natif indisponible (${reason?.name}) : '
            'interface Onyx');
        // La lecture continue : seule l'interface revient, chrome compris.
        _keyboardFocusNode.requestFocus();
        _showControlsTransient(byUser: false);
    }
    // Le natif ne coche rien de lui-même : la spec suivante le fait.
    _rebuild();
  }
}
