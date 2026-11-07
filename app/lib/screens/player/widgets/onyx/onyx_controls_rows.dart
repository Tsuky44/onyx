part of 'onyx_controls_layer.dart';

/// Les rangées du Chrome Onyx : le chrome télé entier, la rangée de transport
/// et le groupe des utilitaires, que les deux arrangements partagent.
///
/// Sortis de `onyx_controls_layer.dart` à la phase 7 de l'ADR-0110, quand les
/// rangées télé sont passées de `TvFocusRows` à `TvRegion.controls`.
extension _OnyxControlsRows on OnyxControlsLayer {
  // --- Television ---------------------------------------------------------

  /// The television arrangement: the title and the track
  /// menus along the top, the transport in the middle of the picture, the
  /// timeline along the bottom.
  ///
  /// Three rows, walked in straight lines ([TvRegion.controlRows]): left and right stay
  /// on the row, up and down go to the next one — onto play/pause in the
  /// middle, onto the timeline at the bottom, onto the nearest button at the
  /// top.
  Widget _buildTvChrome(OnyxChromeMetrics m) {
    return TvRegion.controlRows(
      onNavigate: onRemoteNavigate,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A soft shade behind the middle row, so white icons still read over
          // a bright scene. Part of the fade like everything else.
          Positioned.fill(
            child: IgnorePointer(
              child: _fadeWithChrome(
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 0.6,
                      colors: [Color(0x59000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _fadeWithChrome(_buildTvTop(m)),
          ),
          Positioned.fill(
            child: Center(
              child: _fadeWithChrome(
                TvRegion.controls(
                  preferredFocus: playPauseFocusNode,
                  child: _buildTransport(m),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Outside the fade, as on the other chromes: the offer is
                // time-limited and must not expire behind a hidden chrome.
                if (onSkipIntro != null)
                  OnyxSkipIntroSlot(
                    onPressed: onSkipIntro!,
                    metrics: m,
                    autoSkipIn: skipIntroCountdown,
                    segment: skipSegment,
                    focusRow: true,
                  ),
                _fadeWithChrome(_buildTvBottom(m)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTvTop(OnyxChromeMetrics m) {
    return OnyxScrim(
      gradient: OnyxChromeTheme.topScrim,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          m.gutter,
          m.topInset,
          m.gutter,
          OnyxControlsLayer._topBarTail,
        ),
        child: TvRegion.controls(
          child: Row(
            children: [
              OnyxIconButton(
                key: const ValueKey('onyx-back'),
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: tr('Retour'),
                metrics: m,
                isTv: true,
                onPressed: onBack,
              ),
              const SizedBox(width: 8),
              Flexible(child: _buildBrand(m)),
              const SizedBox(width: 24),
              _buildUtilities(m),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTvBottom(OnyxChromeMetrics m) {
    return OnyxScrim(
      gradient: OnyxChromeTheme.bottomScrim,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          m.gutter,
          OnyxControlsLayer._bottomBarLead,
          m.gutter,
          m.bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTitleBlock(m),
            const SizedBox(height: 10),
            TvRegion.controls(
              preferredFocus: progressFocusNode,
              child: KeyedSubtree(
                key: timelineAnchorKey,
                child: OnyxProgressBar(
                  progress: _progressFraction,
                  buffered: buffered,
                  duration: duration,
                  chapterMarks: chapterMarks,
                  metrics: m,
                  onSeek: onSeekFraction,
                  onScrubbingChanged: onScrubbingChanged,
                  focusable: true,
                  onStepBack: onScrubStepBack ?? onRewind,
                  onStepForward: onScrubStepForward ?? onForward,
                  onSelect: onPlayPause,
                  focusNode: progressFocusNode,
                  previews: previews,
                  previewAtProgress: remoteSeekPending,
                ),
              ),
            ),
            _buildTimes(m),
          ],
        ),
      ),
    );
  }

  Widget _buildUtilities(OnyxChromeMetrics m) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Series only: a movie has no episode list to browse.
        if (onOpenEpisodes != null) ...[
          OnyxIconButton(
            key: const ValueKey('onyx-episodes'),
            icon: Icons.playlist_play_rounded,
            tooltip: tr('Épisodes suivants'),
            metrics: m,
            isTv: isTv,
            onPressed: onOpenEpisodes!,
          ),
          SizedBox(width: m.clusterGap),
        ],
        OnyxIconButton(
          key: const ValueKey('onyx-subtitles'),
          buttonKey: subtitlesButtonKey,
          icon: Icons.closed_caption_rounded,
          tooltip: tr('Sous-titres'),
          metrics: m,
          isTv: isTv,
          onPressed: onToggleSubtitles,
        ),
        SizedBox(width: m.clusterGap),
        OnyxIconButton(
          key: const ValueKey('onyx-audio'),
          icon: Icons.graphic_eq_rounded,
          tooltip: tr('Pistes audio'),
          metrics: m,
          isTv: isTv,
          onPressed: onOpenAudio,
        ),
        // Not on a television: the rate lives in the settings menu, and one
        // button fewer is one press fewer to reach the settings.
        if (!isTv) ...[
          SizedBox(width: m.clusterGap),
          OnyxIconButton(
            key: const ValueKey('onyx-speed'),
            icon: Icons.speed_rounded,
            // The current rate is the whole point of the control, so it goes
            // in the tooltip rather than making the user open a menu to read it.
            tooltip: tr('Vitesse ×{0}', [_formatRate(playbackRate)]),
            metrics: m,
            onPressed: onCycleSpeed,
          ),
        ],
        if (onOpenWatchParty != null) ...[
          SizedBox(width: m.clusterGap),
          OnyxIconButton(
            key: const ValueKey('onyx-watch-party'),
            icon: watchPartyActive
                ? Icons.groups_rounded
                : Icons.group_add_outlined,
            tooltip: watchPartyActive
                ? tr('Séance en cours')
                : tr('Regarder ensemble'),
            metrics: m,
            isTv: isTv,
            onPressed: onOpenWatchParty!,
          ),
        ],
        SizedBox(width: m.clusterGap),
        OnyxIconButton(
          key: const ValueKey('onyx-settings'),
          buttonKey: settingsButtonKey,
          icon: Icons.settings_rounded,
          tooltip: tr('Réglages'),
          metrics: m,
          isTv: isTv,
          onPressed: onOpenSettings,
        ),
        // A television has no window to fill: the buttons would do nothing.
        if (!isTv)
          ...onyxWindowButtons(
            metrics: m,
            onToggleFullscreen: onToggleFullscreen,
            onTogglePictureInPicture: onTogglePictureInPicture,
          ),
      ],
    );
  }

  static String _formatRate(double rate) {
    final asInt = rate.round();
    return rate == asInt ? '$asInt' : rate.toStringAsFixed(2);
  }

  Widget _buildTransport(OnyxChromeMetrics m) {
    // Keyed, because the episode buttons come and go — the neighbours load
    // after playback starts — and without keys every button after them would
    // inherit the state, and the focus, of the one that used to sit there.
    //
    // On a television the seek buttons are drawn larger: they sit alone in the
    // middle of the picture, next to a play button that is larger still.
    final sideSize = isTv ? m.iconSize + 8 : null;
    final gap = SizedBox(width: m.clusterGap + (isTv ? 16 : 4));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Same rule as the next button: only when there is somewhere to go.
        if (onSkipPrevious != null) ...[
          OnyxIconButton(
            key: const ValueKey('onyx-previous'),
            icon: Icons.skip_previous_rounded,
            tooltip: tr('Épisode précédent'),
            metrics: m,
            isTv: isTv,
            onPressed: onSkipPrevious!,
          ),
          gap,
        ],
        OnyxIconButton(
          key: const ValueKey('onyx-rewind'),
          icon: Icons.replay_10_rounded,
          tooltip: tr('Reculer de 10 s'),
          metrics: m,
          size: sideSize,
          isTv: isTv,
          onPressed: onRewind,
        ),
        gap,
        OnyxIconButton(
          key: const ValueKey('onyx-play-pause'),
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: isPlaying ? tr('Pause') : tr('Lecture'),
          metrics: m,
          size: m.playIconSize,
          focusNode: playPauseFocusNode,
          isTv: isTv,
          prominent: isTv,
          onPressed: onPlayPause,
        ),
        gap,
        OnyxIconButton(
          key: const ValueKey('onyx-forward'),
          icon: Icons.forward_10_rounded,
          tooltip: tr('Avancer de 10 s'),
          metrics: m,
          size: sideSize,
          isTv: isTv,
          onPressed: onForward,
        ),
        // Series only: on a movie, or at the end of a season, there is nothing
        // to go to and the button would sit there doing nothing.
        if (onSkipNext != null) ...[
          gap,
          OnyxIconButton(
            key: const ValueKey('onyx-next'),
            icon: Icons.skip_next_rounded,
            tooltip: tr('Épisode suivant'),
            metrics: m,
            isTv: isTv,
            onPressed: onSkipNext!,
          ),
        ],
      ],
    );
  }
}
