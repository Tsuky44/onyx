part of 'player_screen.dart';

/// L'écran « Vous regardez » d'un film laissé en pause (ADR-0137) : ce que
/// l'écran du lecteur donne à [PauseInfoWatch], et la couche qu'il dessine.
extension _PlayerPauseInfo on _PlayerScreenState {
  PauseInfoWatch _createPauseInfo() =>
      PauseInfoWatch(mayShow: _pauseInfoMayShow)
        ..addListener(_handlePauseInfoChanged);

  /// L'écran est à l'image. Relu contre la lecture : une reprise venue d'un
  /// autre chemin (séance « Regarder ensemble », autre appareil) le retire
  /// sans attendre que le compte à rebours le sache.
  bool get _pauseInfoShown =>
      _pauseInfo.visible && !_playerController.isPlaying;

  /// Quelqu'un est là : une souris qui bouge, un doigt, une touche. Les
  /// comptes à rebours qui guettent une salle vide s'arrêtent tous ici.
  void _noteUserActivity() {
    _episodeNav?.onUserActivity();
    _pauseInfo.noteActivity();
  }

  /// La lecture vient d'être mise en pause, ou relancée, par quelqu'un.
  ///
  /// Pas sur un téléphone ni une tablette : l'écran est dans la main, et un
  /// résumé n'y aurait pas la place de se lire par-dessus le film.
  void _notePlaybackChoiceForPauseInfo() {
    if (_handheld || _wantsPlayback) {
      _pauseInfo.noteResumed();
      return;
    }
    _pauseInfo.notePaused();
  }

  bool _pauseInfoMayShow() {
    if (!mounted || _isDisposing || _isLeaving || !_isInitialized) {
      return false;
    }
    if (_playerController.isPlaying || _playerController.isDraggingSlider) {
      return false;
    }
    // Ce qui tient déjà l'écran garde la main : un menu, le volet des
    // onglets, une page de fin, une question, le cadenas, l'autre appareil.
    if (_popups.isOpen || _tabs.isOpen) return false;
    if (_pageOverImage || _stillWatchingAsked || _screenLocked) return false;
    if (_handoff.handedOffTo != null) return false;
    if (_inPip || _inDesktopPip) return false;
    return true;
  }

  void _handlePauseInfoChanged() {
    if (!mounted || _isDisposing) return;
    if (!_pauseInfo.visible) {
      _update(() {});
      return;
    }
    // Le chrome s'efface sous l'écran : barre et résumé ne se lisent pas
    // l'un sur l'autre. La télécommande quitte la barre avec lui, pour que
    // OK arrive au lecteur, qui relance la lecture.
    _controlsTimer?.cancel();
    if (_remoteBrowsingControls) {
      _leaveControlBar();
      return;
    }
    _update(() => _showControls = false);
  }

  /// Monté tant que le film est en pause hors d'un téléphone, pour que
  /// l'écran entre en fondu ; invisible, il ne dessine rien.
  Widget? _buildPauseInfo(bool isTv) {
    if (_handheld || _playerController.isPlaying || !_isInitialized) {
      return null;
    }
    final detailsId = _info.logoDetailsId;
    final content = PauseInfoContent.from(
      info: _info,
      details: detailsId == null ? null : MediaDetailsCache.peek(detailsId),
      nextEpisode: _episodeNav?.nextEpisode,
      positionSeconds: _playerController.position.inSeconds,
      durationSeconds: _playerController.duration.inSeconds,
      logoUrl: _mediaLogoUrl,
      serverBaseUrl: _apiClient?.baseUrl,
    );
    return PlayerTvScale.layer(
      isTv: isTv,
      child: Positioned.fill(
        child: PauseInfoOverlay(
          content: content,
          visible: _pauseInfoShown,
          isTv: isTv,
        ),
      ),
    );
  }
}
