part of 'onyx_controls_layer.dart';

/// Les rangées du Chrome Onyx : le chrome télé entier (celui du lecteur
/// d'Apple, ADR-0124), puis la rangée de transport et le groupe des
/// utilitaires des arrangements à souris et à doigt.
///
/// Sortis de `onyx_controls_layer.dart` à la phase 7 de l'ADR-0110, quand les
/// rangées télé sont passées de `TvFocusRows` à `TvRegion.controls`.
extension _OnyxControlsRows on OnyxControlsLayer {
  // --- Television ---------------------------------------------------------

  /// L'arrangement d'un téléviseur : celui du lecteur d'Apple (ADR-0124).
  ///
  /// Rien au milieu de l'image ni de bouton Retour : OK met en pause, gauche
  /// et droite déplacent sur la barre, Retour quitte. En haut à gauche le logo
  /// du titre ; en bas, le titre et un bouton rond par réglage, la barre de
  /// lecture et ses temps, puis les onglets et leur volet (ADR-0130).
  ///
  /// Des rangées parcourues en ligne droite ([TvRegion.controlRows]) : les
  /// boutons ronds, la barre, les onglets, puis celles du volet ouvert. La
  /// télécommande arrive sur la barre : c'est elle qui répond à OK, à gauche
  /// et à droite.
  Widget _buildTvChrome(OnyxChromeMetrics m) {
    return TvRegion.controlRows(
      onNavigate: onRemoteNavigate,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _fadeWithChrome(_buildTvTop(m)),
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
                    capsule: true,
                  ),
                _fadeWithChrome(_buildTvBottom(m)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Le logo du titre, en haut à gauche. Sans logo, rien : le titre est déjà
  /// écrit au-dessus de la barre, et le répéter ici le dirait deux fois.
  Widget _buildTvTop(OnyxChromeMetrics m) {
    final url = logoUrl;
    return OnyxScrim(
      gradient: OnyxChromeTheme.topScrim,
      child: Padding(
        padding: EdgeInsets.fromLTRB(m.gutter, m.topInset, m.gutter, 64),
        child: Align(
          alignment: Alignment.centerLeft,
          child: url == null || url.isEmpty
              ? SizedBox(height: m.logoHeight)
              : IgnorePointer(
                  child: AppNetworkImage(
                    url: url,
                    height: m.logoHeight,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    fadeInDuration: const Duration(milliseconds: 120),
                    // La même image décodée que l'en-tête de la fiche.
                    decodeAtSourceSize: true,
                    placeholder: SizedBox(height: m.logoHeight),
                    errorWidget: SizedBox(height: m.logoHeight),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildTvBottom(OnyxChromeMetrics m) {
    return OnyxScrim(
      gradient: OnyxChromeTheme.bottomScrim,
      child: Padding(
        // Assez de dégradé au-dessus du titre pour qu'il se lise sur une
        // image claire, sans repousser « Passer l'intro » au milieu de
        // l'écran.
        padding: const EdgeInsets.only(top: 84),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: m.gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: _buildTvTitleBlock(m)),
                      const SizedBox(width: 24),
                      TvRegion.controls(child: _buildTvActions(m)),
                    ],
                  ),
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
                        marker: true,
                      ),
                    ),
                  ),
                  _buildTvTimes(m),
                ],
              ),
            ),
            // Le volet des onglets va d'un bord à l'autre de l'écran : il
            // pose lui-même ses marges.
            if (tabs.isEmpty)
              SizedBox(height: m.bottomInset)
            else
              OnyxTvTabs(
                metrics: m,
                visible: visible,
                tabs: tabs,
                open: openTab,
                onChanged: (tab) => onTabChanged?.call(tab),
              ),
          ],
        ),
      ),
    );
  }

  /// Le titre en gras, l'épisode ou l'année dessous : l'ordre du lecteur
  /// d'Apple, l'inverse des autres arrangements.
  Widget _buildTvTitleBlock(OnyxChromeMetrics m) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: OnyxChromeTheme.title,
            fontSize: m.titleSize,
            fontWeight: FontWeight.w700,
            height: 1.15,
            letterSpacing: -0.4,
          ),
        ),
        if (overline != null && overline!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            overline!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: OnyxChromeTheme.time,
              fontSize: m.metaSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  /// Les boutons ronds, à droite du titre : un par réglage, chacun avec son
  /// menu, entre l'épisode précédent et le suivant quand il y en a
  /// (ADR-0130). L'ADR-0124 rangeait la qualité, la vitesse, le format
  /// d'image et la minuterie derrière un seul bouton « Réglages » : un index
  /// à traverser pour chaque changement.
  Widget _buildTvActions(OnyxChromeMetrics m) {
    Widget plain(
      String id,
      IconData icon,
      String label,
      VoidCallback onPressed,
    ) =>
        OnyxIconButton(
          key: ValueKey('onyx-$id'),
          icon: icon,
          tooltip: label,
          metrics: m,
          isTv: true,
          glass: true,
          onPressed: onPressed,
        );
    // Le bouton est son propre repère : le menu se pose au-dessus de lui.
    Widget menu(OnyxMenuSection section, IconData icon, String label) =>
        Builder(
          key: ValueKey('onyx-${section.name}'),
          builder: (anchor) => OnyxIconButton(
            icon: icon,
            tooltip: label,
            metrics: m,
            isTv: true,
            glass: true,
            lit: openMenu == section,
            onPressed: () => onOpenMenu?.call(section, anchor),
          ),
        );
    final buttons = <Widget>[
      if (onSkipPrevious != null)
        plain(
          'previous',
          Icons.skip_previous_rounded,
          tr('Épisode précédent'),
          onSkipPrevious!,
        ),
      menu(OnyxMenuSection.subtitles, Icons.subtitles_rounded,
          tr('Sous-titres')),
      menu(OnyxMenuSection.audio, Icons.graphic_eq_rounded, tr('Pistes audio')),
      menu(OnyxMenuSection.quality, Icons.high_quality_rounded, tr('Qualité')),
      menu(OnyxMenuSection.speed, Icons.speed_rounded,
          tr('Vitesse de lecture')),
      menu(OnyxMenuSection.display, Icons.aspect_ratio_rounded,
          tr('Format d’image')),
      menu(OnyxMenuSection.sleep, Icons.bedtime_rounded,
          tr('Minuterie de veille')),
      if (onSkipNext != null)
        plain(
          'next',
          Icons.skip_next_rounded,
          tr('Épisode suivant'),
          onSkipNext!,
        ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) SizedBox(width: m.clusterGap),
          buttons[i],
        ],
      ],
    );
  }

  /// Le temps écoulé à gauche, le temps restant à droite, sans l'heure de fin
  /// des autres arrangements.
  Widget _buildTvTimes(OnyxChromeMetrics m) {
    final style = TextStyle(
      color: OnyxChromeTheme.time,
      fontSize: m.timeSize,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(formatPlaybackTime(position.inSeconds), style: style),
        if (duration.inSeconds > 0)
          Text('-${formatPlaybackTime(_remainingSeconds)}', style: style),
      ],
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
        ] else if (onOpenInfo != null) ...[
          // Un film n'a pas d'épisodes, mais il a un résumé, des chapitres et
          // des statistiques : le même emplacement ouvre le même volet.
          OnyxIconButton(
            key: const ValueKey('onyx-info'),
            icon: Icons.info_outline_rounded,
            tooltip: tr('Infos'),
            metrics: m,
            isTv: isTv,
            onPressed: onOpenInfo!,
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
