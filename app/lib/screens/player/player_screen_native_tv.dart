part of 'player_screen.dart';

/// L'écran natif d'Apple TV. Quand il est présenté, l'interface Flutter du
/// lecteur se retire (scène vidéo, chrome, gestes, cartes), mais cet écran
/// reste le cerveau : progression, segments, épisode suivant, mémoire des
/// pistes, qualité et séance partagée tournent sur la même session. Voir
/// [NativeTvPresenter] et `docs/agents/native-tv-parity.md`.
extension _PlayerNativeTv on _PlayerScreenState {
  bool get _nativeTvShown => _nativeTv?.isShown ?? false;

  /// Le présentateur, là seulement où il servira : un appareil éligible et un
  /// moteur qui a un écran natif.
  NativeTvPresenter? _createNativeTv() {
    if (!isNativeTvPlayerEligible()) return null;
    final screen = _playerController.session.nativeTvScreen;
    if (screen == null) return null;
    return NativeTvPresenter(
      screen: screen,
      onIntent: _handleNativeTvIntent,
      onResync: () {
        if (mounted && !_isDisposing) _syncNativeTv();
      },
    );
  }

  /// Ce que seule l'interface Flutter sait montrer : un démarrage bloqué,
  /// avec « Réessayer » et le journal. Les questions et les cartes de fin
  /// passent par des alertes natives ([NativeTvQuestion]).
  bool get _needsFlutterScreen => _startupStalled;

  bool get _nativeTvWanted =>
      _isInitialized &&
      !_isLeaving &&
      !_isDisposing &&
      !_needsFlutterScreen &&
      _nativeTvFallback == null;

  /// Ce que le média demande, relu à chaque construction : la route logicielle
  /// qui s'installe en cours de film, ou une piste image que le natif n'a pas
  /// su peindre, rendent l'interface Flutter sans couper la lecture.
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
      hlsStartOffset: _nativeTvTimelineOffset,
    );
  }

  /// Où commence l'item que joue AVKit sur la timeline du film : une session
  /// HLS repart de zéro à son point de départ.
  Duration get _nativeTvTimelineOffset =>
      _playerController.currentQuality != null
          ? Duration(seconds: _playerController.hlsStartOffset)
          : Duration.zero;

  /// Appelé à chaque construction de l'écran : c'est là que tout changement
  /// d'état arrive. Le présentateur ne passe le pont que si la spec a changé.
  void _scheduleNativeTvSync() {
    if (_nativeTv == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNativeTv());
  }

  void _syncNativeTv() {
    final presenter = _nativeTv;
    if (presenter == null || !mounted) return;
    presenter.sync(
      wanted: _nativeTvWanted,
      spec: _nativeTvSpec(presenter),
      playerReady:
          _playerController.session.nativeTvScreen?.hasNativePlayer ?? true,
    );
    // La route du moteur n'arrive pas par une reconstruction de cet écran :
    // tant que la présentation l'attend, on revient voir.
    if (presenter.claimRecheck()) {
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        presenter.recheckFired();
        if (mounted) _syncNativeTv();
      });
    }
    if (!presenter.isShown) return;
    _requestNativeEpisodes(presenter.memory);
    presenter.syncFit(
      _displayMode.fit,
      _playerController.videoAspectRatio,
      MediaQuery.sizeOf(context),
    );
  }

  /// L'onglet Épisodes se remplit dès la première présentation, comme
  /// `_openEpisodesPanel` sans l'interface : le contrat ne dit pas quand AVKit
  /// affiche l'onglet. La saison seule, sans ouvrir le panneau Onyx, qui
  /// apparaîtrait si Flutter reprenait la main.
  void _requestNativeEpisodes(NativeTvMemory memory) {
    if (memory.episodesRequested || !_info.isEpisode) return;
    memory.episodesRequested = true;
    final season = _info.seasonId;
    if (season == null || season <= 0 || _apiClient == null) return;
    unawaited(_episodesPanel.selectSeason(season));
  }

  NativeTvSpec _nativeTvSpec(NativeTvPresenter presenter) {
    final controller = _playerController;
    final nav = _episodeNav;
    final media = _info.media;
    final memory = presenter.memory;
    final party = _party.party;
    String? imageOf(String? url) =>
        detailPosterUrl(url, serverBaseUrl: _apiClient?.baseUrl);
    return NativeTvSpecBuilder.build(NativeTvState(
      title: _info.showTitle,
      subtitle: _info.overline,
      posterUrl: imageOf(_info.item?.displayPosterUrl ?? media.posterUrl),
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
        directHasWrongColours: controller.directPlayHasWrongColours,
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
      sleep: NativeTvSleep.of(SleepTimer.instance, offersEpisodes: nav != null),
      chapters: nav?.chapters ?? const [],
      duration: controller.duration,
      timelineOffset: _nativeTvTimelineOffset,
      canGoPrevious: _episodesPanel.previousEpisode != null,
      canGoNext: nav?.nextEpisode != null,
      nextUp: _nativeTvNextUp(memory),
      question: _nativeTvQuestion,
      episodes: _info.isEpisode
          ? NativeTvEpisodes(
              seasons: _episodesPanel.seasons,
              selectedSeasonId:
                  _episodesPanel.selectedSeasonId ?? _info.seasonId,
              episodes: _episodesPanel.episodes,
              currentEpisodeId: media.id,
              loading: _episodesPanel.isLoading || !memory.episodesRequested,
              imageUrl: (episode) => imageOf(episode.media.posterUrl),
            )
          : null,
      watchParty: _watchPartyAction == null
          ? null
          : NativeTvWatchParty(
              code: party?.code,
              members: party?.members ?? const [],
              starting: memory.watchPartyStarting,
              error: memory.watchPartyError,
            ),
      toast: party?.waitingMessage ??
          (_party.noticeVisible ? _party.notice : null),
      // En HLS, une recherche hors de ce que la session a encodé la
      // reconstruit : c'est au contrôleur d'en décider, pas à AVKit.
      interceptSeeks: controller.currentQuality != null,
    ));
  }

  /// Les conditions de `NextEpisodeOverlay` : au générique, vers un épisode
  /// qui existe, sans carte de fin par-dessus.
  NativeTvNextUpState? _nativeTvNextUp(NativeTvMemory memory) {
    final nav = _episodeNav;
    final next = nav?.nextEpisode;
    if (nav == null || next == null) return null;
    if (!nav.showNextEpisodeOutro || _endCardVisible) return null;
    if (memory.nextUpDeferred(next.media.id)) return null;
    // Pas de compte à rebours vers un épisode que la minuterie de veille ne
    // laissera pas démarrer, ni quand quelqu'un l'a gelé.
    final counting = nav.outroAutoPlayActive &&
        !nav.outroAutoPlayFrozen &&
        !SleepTimer.instance.stopsAfterThisEpisode;
    return NativeTvNextUpState(
      episode: next,
      transition: memory.nextUpTransition(
        next.media.id,
        () =>
            _playerController.position -
            _nativeTvTimelineOffset +
            NativeTvSpecBuilder.nextUpLead,
      ),
      countdownSeconds: counting ? nav.outroCountdownSeconds : null,
      imageUrl: detailPosterUrl(next.media.posterUrl,
          serverBaseUrl: _apiClient?.baseUrl),
    );
  }

  /// La question en cours, dans l'ordre où l'interface Onyx les empile : la
  /// plus haute gagne.
  NativeTvQuestion? get _nativeTvQuestion {
    if (_stillWatchingAsked) return const NativeTvStillWatchingQuestion();
    final elsewhere = _handoff.handedOffTo;
    if (elsewhere != null) return NativeTvPlayingElsewhereQuestion(elsewhere);
    final nav = _episodeNav;
    if (nav == null) return null;
    if (nav.showLaunchLanguageCard) {
      return NativeTvLanguageQuestion(nav.launchLanguageGap!, atLaunch: true);
    }
    if (nav.showLanguageGapCard) {
      return NativeTvLanguageQuestion(nav.languageGap!, atLaunch: false);
    }
    if (nav.showUpcomingEpisodeCard) {
      return NativeTvUpcomingQuestion(nav.upcomingEpisode!,
          canPlayNext: nav.nextEpisode != null);
    }
    if (nav.showNextSeasonCard) {
      return NativeTvNextSeasonQuestion(nav.nextSeason!,
          canPlayNext: nav.isSeasonLookahead);
    }
    return null;
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
      case NativeTvPreviousEpisode():
        _goToPreviousEpisode();
      case NativeTvCancelAutoPlay():
        _deferNativeNextUp();
      case NativeTvStartWatchParty():
        unawaited(_startWatchPartyFromNative());
      case NativeTvLeaveWatchParty():
        _party.leave(notice: tr('Vous avez quitté la séance'));
      case NativeTvAnswer(:final question, :final answer):
        _answerNativeQuestion(question, answer);
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
      case NativeTvSetSleep(:final episodes?):
        SleepTimer.instance.startEpisodes(episodes);
      case NativeTvSetSleep(:final duration?):
        SleepTimer.instance.start(duration);
      case NativeTvSetSleep():
        SleepTimer.instance.cancel();
      case NativeTvJumpToChapter(:final chapterId):
        final chapter = _episodeNav?.chapters
            .where((chapter) => chapter.id == chapterId)
            .firstOrNull;
        if (chapter != null) unawaited(_seekTo(chapter.startTime.round()));
      case NativeTvSetSubtitle(:final trackId):
        // Le menu AVKit ne liste que les pistes du fichier, texte et image :
        // le même chemin que le menu Onyx en Direct Play, mémoire des pistes
        // comprise. Le moteur n'a rien adopté de lui-même, c'est ce rappel
        // qui fait tenir le choix.
        final track = nativeTvSubtitleChoice(
            trackId, _playerController.session.subtitleTracks);
        if (track == null || !_playerController.listsEmbeddedSubtitles) {
          debugPrint('Lecteur natif : sous-titre $trackId ignoré');
          break;
        }
        _playerController.selectInternalSubtitle(track);
      case NativeTvTransport(:final playing, :final position):
        _applyNativeTransport(playing, position);
      case NativeTvUserSeeked(:final position):
        _announceNativeSeek(position);
      case NativeTvSeekRequested(:final position):
        _noteNativeActivity();
        unawaited(_seekTo(
            nativeTvAbsolute(position, _nativeTvTimelineOffset).inSeconds));
      case NativeTvUserActivity():
        _noteNativeActivity();
      case NativeTvSelectSeason(:final seasonId):
        unawaited(_episodesPanel.selectSeason(seasonId));
      case NativeTvOpenEpisode(:final mediaId):
        final episode = _episodesPanel.episodes
            .where((episode) => episode.media.id == mediaId)
            .firstOrNull;
        if (episode != null) _navigateToEpisode(episode);
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

  /// Quelqu'un tient la télécommande : ce que l'interface Onyx tire de chaque
  /// touche (`StillWatching` les écoute à la racine Flutter, que UIKit ne
  /// leur transmet plus), et les deux comptes à rebours se gèlent.
  void _noteNativeActivity() {
    StillWatching.instance.noteActivity();
    _episodeNav?.onUserActivity();
  }

  /// AVKit a déjà lu ou mis en pause l'`AVPlayer` : le chemin de
  /// [_togglePlayPause], sans rappeler le moteur, pour que la séance, la
  /// reprise voulue et `StillWatching` le sachent.
  void _applyNativeTransport(bool playing, Duration position) {
    // Devant une question, « lecture » y répond, comme dans
    // [_togglePlayPause] : la reprendre ici, ou « oui » à « Vous regardez
    // encore ? », qui enchaîne sur l'épisode suivant.
    if (playing && (_handoff.handedOffTo != null || _stillWatchingAsked)) {
      _togglePlayPause();
      return;
    }
    _noteNativeActivity();
    _wantsPlayback = playing;
    final party = _party.party;
    if (party != null) {
      unawaited(party.sendPlaying(
          playing, nativeTvAbsolute(position, _nativeTvTimelineOffset)));
    }
  }

  /// Un saut déjà fait par AVKit : seule la séance reste à prévenir, comme
  /// le fait [_seekTo].
  void _announceNativeSeek(Duration position) {
    _noteNativeActivity();
    final party = _party.party;
    if (party == null) return;
    unawaited(party.sendSeek(
      nativeTvAbsolute(position, _nativeTvTimelineOffset),
      playing: _playerController.isPlaying,
    ));
  }

  /// « Plus tard » : le compte à rebours se gèle là où il en est, comme sous
  /// la main de quelqu'un, et la proposition ne revient pas pour cet épisode.
  /// L'action « Épisode suivant » reste. Pas `cancelAutoPlay` : il range la
  /// pastille, et la position suivante, toujours au générique, la relève
  /// avec un compte à rebours neuf.
  void _deferNativeNextUp() {
    final nav = _episodeNav;
    final next = nav?.nextEpisode;
    if (nav == null || next == null) return;
    _nativeTv?.memory.deferNextUp(next.media.id);
    nav.onUserActivity();
  }

  /// Le bouton « Démarrer une séance » de `WatchPartyPanel`, dont l'attente
  /// et l'erreur vivent ici, faute de widget.
  Future<void> _startWatchPartyFromNative() async {
    final memory = _nativeTv?.memory;
    if (memory == null || memory.watchPartyStarting) return;
    memory
      ..watchPartyStarting = true
      ..watchPartyError = null;
    _rebuild();
    try {
      await _party.start();
    } catch (error) {
      debugPrint('Lecteur natif : séance impossible ($error)');
      memory.watchPartyError =
          tr('Impossible de démarrer la séance. Réessayez.');
    } finally {
      memory.watchPartyStarting = false;
      _rebuild();
    }
  }

  /// Une réponse à une alerte native, rendue au gestionnaire du bouton de la
  /// carte Onyx correspondante.
  void _answerNativeQuestion(String question, String answer) {
    final nav = _episodeNav;
    switch ((question, answer)) {
      case (NativeTvIds.stillWatching, NativeTvIds.answerContinue):
        _confirmStillWatching();
      case (
          NativeTvIds.stillWatching || NativeTvIds.playingElsewhere,
          NativeTvIds.answerLeave
        ):
        unawaited(_leavePlayer());
      case (NativeTvIds.playingElsewhere, NativeTvIds.answerResume):
        unawaited(_handoff.resumeHere());
      case (NativeTvIds.launchLanguageGap, NativeTvIds.answerContinue):
        _continueAtLaunch();
      case (NativeTvIds.launchLanguageGap, NativeTvIds.answerWait):
        unawaited(_waitAtLaunch());
      case (NativeTvIds.languageGap, NativeTvIds.answerContinue):
        _continueInOfferedLanguage();
      case (NativeTvIds.languageGap, NativeTvIds.answerWait):
        _waitForAudioLanguage();
      case (
          NativeTvIds.launchLanguageGap || NativeTvIds.languageGap,
          NativeTvIds.answerDismiss
        ):
        _dismissEndCard();
      case (NativeTvIds.upcomingEpisode, NativeTvIds.answerDismiss):
        nav?.dismissUpcomingEpisodeCard();
      case (NativeTvIds.nextSeason, NativeTvIds.answerDismiss):
        nav?.dismissNextSeasonCard();
      case (
          NativeTvIds.upcomingEpisode || NativeTvIds.nextSeason,
          NativeTvIds.answerPlayNext
        ):
        _goToNextEpisode();
      case (NativeTvIds.nextSeason, NativeTvIds.answerRequest):
        unawaited(_requestNextSeasonFromNative());
      default:
        debugPrint('Lecteur natif : réponse $question.$answer ignorée');
    }
  }

  /// L'alerte se ferme sur la réponse, là où la carte Onyx passe à son état
  /// « demandé » : une fois la demande partie, la question est rangée et une
  /// annonce dit ce qu'il en est (la `SnackBar` d'un échec ne se voit pas
  /// sous l'écran natif).
  Future<void> _requestNextSeasonFromNative() async {
    await _requestNextSeason();
    final nav = _episodeNav;
    if (!mounted || nav == null) return;
    _party.showNotice((nav.nextSeason?.isRequested ?? false)
        ? tr('Demande envoyée')
        : tr('Impossible d’envoyer la demande.'));
    nav.dismissNextSeasonCard();
  }
}
