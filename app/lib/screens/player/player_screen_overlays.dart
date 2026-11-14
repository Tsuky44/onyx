part of 'player_screen.dart';

/// Ce qui se pose au-dessus du chrome : les onglets et leurs contenus, la page
/// de l'épisode suivant, les pages de fin, les annonces d'une séance.
extension _PlayerOverlays on _PlayerScreenState {
  // --- Onglets --------------------------------------------------------------

  /// Les onglets du lecteur, pour ce média et ce compte (ADR-0130). Les mêmes
  /// sous la barre d'un téléviseur et dans la feuille des autres écrans. Un
  /// onglet sans rien à montrer n'existe pas : pas d'épisodes pour un film,
  /// pas de chapitres sans chapitres, pas de séance hors ligne.
  List<OnyxTabEntry> get _tabEntries {
    final nav = _episodeNav;
    final chapters = nav?.chapters ?? const <VideoChapter>[];
    final party = _party.party;
    final media = _info.media;
    return [
      OnyxTabEntry(
        tab: OnyxTab.info,
        label: tr('Infos'),
        builder: (_) => PlayerInfoTab(
          media: media,
          title: _info.isEpisode
              ? (_info.item?.episodeTitle ?? media.title)
              : _info.showTitle,
          meta: _infoMeta,
          overview: media.overview,
          onPrevious: _episodesPanel.previousEpisode != null
              ? _goToPreviousEpisode
              : null,
          onNext: nav?.nextEpisode != null ? _goToNextEpisode : null,
        ),
      ),
      if (_info.isEpisode && _apiClient != null)
        OnyxTabEntry(
          tab: OnyxTab.episodes,
          label: tr('Épisodes'),
          builder: (_) => PlayerEpisodesTab(
            showTitle: _episodesPanel.showTitle,
            currentEpisodeId: media.id,
            seasons: _episodesPanel.seasons,
            selectedSeasonId:
                _episodesPanel.selectedSeasonId ?? _info.seasonId ?? 0,
            onSeasonChanged: (seasonId) =>
                unawaited(_episodesPanel.selectSeason(seasonId)),
            episodes: _episodesPanel.episodes,
            isLoading: _episodesPanel.isLoading,
            onEpisodeSelected: _navigateToEpisode,
          ),
        ),
      if (chapters.isNotEmpty)
        OnyxTabEntry(
          tab: OnyxTab.chapters,
          label: tr('Chapitres'),
          builder: (_) => PlayerChaptersTab(
            chapters: chapters,
            positionSeconds: _playerController.position.inSeconds,
            onSeek: (seconds) => unawaited(_seekTo(seconds)),
          ),
        ),
      if (_watchPartyAction != null)
        OnyxTabEntry(
          tab: OnyxTab.watchParty,
          label:
              party != null ? tr('Séance en cours') : tr('Regarder ensemble'),
          marked: party != null,
          builder: (_) => party == null
              ? PlayerWatchPartyTab(
                  code: null,
                  members: const [],
                  onStart: _party.start,
                  onLeave: () {},
                )
              // Les participants vont et viennent sans que le lecteur change.
              : ListenableBuilder(
                  listenable: party,
                  builder: (_, __) => PlayerWatchPartyTab(
                    code: party.code,
                    members: party.members,
                    onStart: _party.start,
                    onLeave: () =>
                        _party.leave(notice: tr('Vous avez quitté la séance')),
                  ),
                ),
        ),
      OnyxTabEntry(
        tab: OnyxTab.stats,
        label: tr('Stats'),
        builder: (_) => PlayerStatsTab(stats: _stats),
      ),
    ];
  }

  /// La ligne sous le titre de l'onglet « Infos ».
  String get _infoMeta {
    final media = _info.media;
    final duration = formatDuration(_info.knownDurationSeconds);
    if (!_info.isEpisode) {
      return [
        extractYear(media.releaseDate) ?? '',
        duration,
      ].where((part) => part.isNotEmpty).join(' · ');
    }
    final season = media.effectiveSeasonNumber;
    final episode = media.effectiveEpisodeNumber;
    return [
      _info.showTitle,
      if (season != null && episode != null && season > 0 && episode > 0)
        tr('Saison {0}, épisode {1}', [season, episode]),
      duration,
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  /// Un bouton de la barre ouvre le volet sur [tab] (hors téléviseur ; sur un
  /// téléviseur, c'est la télécommande qui l'ouvre en arrivant sur l'onglet).
  void _showTab(OnyxTab tab) {
    _popups.dismissTop();
    _update(() => _showControls = true);
    _tabs.show(tab);
  }

  /// Le volet des onglets vient de s'ouvrir ou de se fermer : le chrome reste
  /// affiché tant qu'il est là, puis son compte à rebours repart.
  void _handleTabsOpenChanged(bool open) {
    if (open) {
      _controlsTimer?.cancel();
    } else if (!_isDisposing && mounted) {
      _hideControlsWithDelay();
    }
  }

  /// Retour devant le volet ouvert. Sur un téléviseur la télécommande revient
  /// d'abord sur la barre : c'est d'avoir quitté les onglets qui ferme le
  /// volet, et un onglet resté focalisé le rouvrirait au premier pas.
  void _closeTabs() {
    if (!_tabs.isOpen) return;
    if (TvMode.isTv && _progressFocusNode.context != null) {
      _progressFocusNode.requestFocus();
    }
    _tabs.close();
  }

  // --- Pages par-dessus l'image ---------------------------------------------

  /// La page de l'épisode suivant est à l'écran (ADR-0130). Jamais sous la
  /// question « Vous regardez encore ? », qui prend sa place.
  bool get _nextEpisodePageVisible =>
      (_episodeNav?.showNextEpisodePage ?? false) && !_stillWatchingAsked;

  /// Une page tient l'écran et l'image s'est rangée dans un coin : une carte
  /// de fin ou l'épisode suivant. Le chrome ne s'y pose pas.
  bool get _pageOverImage => _endCardVisible || _nextEpisodePageVisible;

  /// La page de l'épisode suivant vient d'arriver : un menu ou un volet resté
  /// ouvert lui disputerait la télécommande.
  void _handleEpisodeNavChanged() {
    final visible = _nextEpisodePageVisible;
    if (visible && !_nextEpisodePageWasVisible) {
      _popups.dismissTop();
      _tabs.close();
    }
    _nextEpisodePageWasVisible = visible;
    _safeSetState(() {});
  }

  /// Tout ce que la pile du lecteur pose entre le chrome et les voiles de
  /// chargement.
  List<Widget> _buildOverChrome(bool isTv) {
    final party = _party.party;
    final nav = _episodeNav;
    final screen = MediaQuery.sizeOf(context);
    // Les pages sont mises en page à l'échelle du lecteur (`PlayerTvScale`) :
    // la place de l'image rétrécie s'y mesure dans la même unité.
    final layoutWidth = isTv ? PlayerTvScale.designWidth : screen.width;
    final videoInset = layoutWidth * _videoScale;
    Widget page(Widget child) => PlayerTvScale.layer(isTv: isTv, child: child);

    return [
      // Regarder ensemble : les annonces (« alex a mis en pause ») et l'attente
      // d'un participant qui charge, en haut au centre.
      if (party != null || _party.noticeVisible)
        Positioned(
          top: macOSWindowControlsTopInset + 20,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Center(
              child: WatchPartyToast(
                message: party?.waitingMessage ?? _party.notice,
                visible: party?.waitingMessage != null || _party.noticeVisible,
              ),
            ),
          ),
        ),
      // Les pages viennent APRÈS le chrome dans la pile, pour se dessiner
      // dessus.
      if (nav != null && _nextEpisodePageVisible) ...[
        page(NextEpisodePage(
          nextEpisode: nav.nextEpisode!,
          currentLabel: _info.overline,
          // Pas de compte à rebours vers un épisode que la minuterie de veille
          // ne laissera pas démarrer.
          countdownSeconds: nav.outroAutoPlayActive &&
                  !SleepTimer.instance.stopsAfterThisEpisode
              ? nav.outroCountdownSeconds
              : null,
          frozen: nav.outroAutoPlayFrozen,
          onPlayNext: _goToNextEpisode,
          onLater: nav.deferNextEpisode,
        )),
        // Toucher l'image rétrécie, c'est dire « plus tard » : elle reprend
        // l'écran.
        Positioned.fromRect(
          rect: PlayerVideoStage.frameFor(
            screen,
            scale: PlayerVideoStage.nextEpisodeScale,
            alignment: PlayerVideoStage.nextEpisodeAlignment,
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: nav.deferNextEpisode,
            ),
          ),
        ),
      ],
      // Tapping the shrunk video is a second way to say "no thanks": it
      // dismisses the page and gives the picture and the controls back. Placed
      // before the back button so that button, which sits inside this same
      // strip, still gets the tap.
      if (_endCardVisible)
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: screen.width * _videoScale,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissEndCard,
            ),
          ),
        ),
      // The only chrome that survives an end card: without it the page would
      // be a dead end, since every other way out is hidden.
      if (_pageOverImage)
        Positioned(
          top: macOSWindowControlsTopInset + 12,
          left: 20,
          child: PlayerBackButton(onTap: _leavePlayer),
        ),
      // Une seule page à la fois : la question de la langue se pose au moment
      // d'enchaîner, donc à la place de celle qui l'a lancée.
      if (nav != null && nav.showLaunchLanguageCard)
        page(LanguageGapOverlay(
          gap: nav.launchLanguageGap!,
          episode: _info.item,
          atLaunch: true,
          onContinue: _continueAtLaunch,
          onWait: () => unawaited(_waitAtLaunch()),
          onDismiss: _dismissEndCard,
          videoInset: videoInset,
        ))
      else if (nav != null && nav.showLanguageGapCard)
        page(LanguageGapOverlay(
          gap: nav.languageGap!,
          episode: nav.nextEpisode,
          onContinue: _continueInOfferedLanguage,
          onWait: _waitForAudioLanguage,
          onDismiss: _dismissEndCard,
          videoInset: videoInset,
        ))
      else if (nav != null && nav.showUpcomingEpisodeCard)
        page(UpcomingEpisodeOverlay(
          episode: nav.upcomingEpisode!,
          onDismiss: () => nav.dismissUpcomingEpisodeCard(),
          onPlayNext: nav.nextEpisode != null ? _goToNextEpisode : null,
          videoInset: videoInset,
        )),
      if (nav != null &&
          nav.showNextSeasonCard &&
          !nav.showLanguageGapCard &&
          !nav.showLaunchLanguageCard)
        page(NextSeasonOverlay(
          season: nav.nextSeason!,
          submitting: _requestingNextSeason,
          onRequest: _requestNextSeason,
          onDismiss: () => nav.dismissNextSeasonCard(),
          onPlayNext: nav.isSeasonLookahead ? _goToNextEpisode : null,
          videoInset: videoInset,
        )),
      // Hors téléviseur, les onglets sont une feuille qui monte du bas ; sur
      // un téléviseur, ils sont dans le chrome, sous la barre.
      if (!isTv && _tabs.isOpen)
        PlayerTabSheet(
          tabs: _tabEntries,
          open: _tabs.open!,
          onChanged: _tabs.show,
        ),
    ];
  }
}
