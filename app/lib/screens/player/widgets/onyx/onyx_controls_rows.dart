part of 'onyx_controls_layer.dart';

/// Les rangées du Chrome Onyx : le chrome télé entier (celui du lecteur
/// d'Apple, ADR-0124), et ce que les trois arrangements partagent : le logo,
/// la ligne de ce qu'on regarde, la rangée de l'essentiel, les temps.
///
/// Sortis de `onyx_controls_layer.dart` à la phase 7 de l'ADR-0110, quand les
/// rangées télé sont passées de `TvFocusRows` à `TvRegion.controls`.
extension _OnyxControlsRows on OnyxControlsLayer {
  // --- Television ---------------------------------------------------------

  /// L'arrangement d'un téléviseur : celui du lecteur d'Apple (ADR-0124).
  ///
  /// Rien au milieu de l'image ni de bouton Retour : OK met en pause, gauche
  /// et droite déplacent sur la barre, Retour quitte. En haut à gauche le logo
  /// du titre ; en bas, ce qu'on regarde et l'essentiel en boutons ronds, la barre de
  /// lecture et ses temps, puis les onglets et leur volet (ADR-0130, ADR-0137).
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

  /// Le logo du titre, en haut à gauche. Voir [_buildTitleMark].
  Widget _buildTvTop(OnyxChromeMetrics m) {
    return OnyxScrim(
      gradient: OnyxChromeTheme.topScrim,
      child: Padding(
        padding: EdgeInsets.fromLTRB(m.gutter, m.topInset, m.gutter, 64),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _buildTitleMark(m),
        ),
      ),
    );
  }

  /// Ce qui dit le titre, en haut à gauche d'un téléviseur et d'un écran tenu
  /// en main : son logo.
  ///
  /// Sans logo, ou le temps qu'il arrive, le nom de la série en toutes
  /// lettres pour un épisode : la ligne du bas ne dit plus que l'épisode
  /// ([_buildIdentityLine]), et sans cela rien ne dirait la série. Rien pour
  /// un film, dont le titre est écrit en bas. Transparent aux touchers.
  Widget _buildTitleMark(OnyxChromeMetrics m) {
    final Widget standIn = isEpisode
        ? SizedBox(height: m.logoHeight, child: _brandText(m))
        : SizedBox(height: m.logoHeight);
    final url = logoUrl;
    if (url == null || url.isEmpty) return IgnorePointer(child: standIn);
    return IgnorePointer(
      child: AppNetworkImage(
        url: url,
        height: m.logoHeight,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        fadeInDuration: AppMotion.micro,
        // La même image décodée que l'en-tête de la fiche.
        decodeAtSourceSize: true,
        placeholder: standIn,
        errorWidget: standIn,
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
                      Expanded(child: _buildIdentityLine(m)),
                      const SizedBox(width: 24),
                      TvRegion.controls(child: _buildEssentialActions(m)),
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
                  _buildTimes(m),
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

  /// Ce qu'on regarde, en une ligne, en bas à gauche : le nom de l'épisode
  /// pour une série, le titre pour un film, dans le même dessin.
  ///
  /// L'ADR-0124 y écrivait le nom de la série en gras, l'épisode dessous. Le
  /// logo, en haut, dit déjà la série ([_buildTitleMark]) : le répéter en
  /// gros ici le disait deux fois sur le même écran (demande de
  /// l'utilisateur, ADR-0137).
  Widget _buildIdentityLine(OnyxChromeMetrics m) {
    final episode = overline;
    final line = isEpisode && episode != null && episode.isNotEmpty
        ? episode
        : (title ?? '');
    return Text(
      line,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: OnyxChromeTheme.time,
        fontSize: m.metaSize,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// L'essentiel, à droite du titre, en boutons ronds de verre : les
  /// sous-titres et l'audio, chacun avec son menu, la roue crantée pour le
  /// reste (qualité, vitesse, format d'image, minuterie), entre l'épisode
  /// précédent et le suivant quand il y en a. Le bouton reste allumé tant que
  /// son menu est ouvert.
  ///
  /// La même rangée sur un téléviseur et sur un écran tenu en main (ADR-0136,
  /// ADR-0137). L'ADR-0130 donnait à un téléviseur un bouton par réglage :
  /// huit disques contre le titre, dont quatre qu'on ne touche presque jamais
  /// en cours de film.
  ///
  /// [tabsButton] : le chrome ne porte pas les onglets sous sa barre (un écran
  /// tenu en main, une fenêtre étroite). Un bouton les ouvre alors, entre
  /// l'épisode précédent et les sous-titres : « Épisodes » pour une série,
  /// « Infos » pour un film, et la feuille qu'il ouvre porte tous les autres
  /// (ADR-0139).
  Widget _buildEssentialActions(OnyxChromeMetrics m, {bool tabsButton = false}) {
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
          isTv: isTv,
          glass: true,
          onPressed: onPressed,
        );
    // Le bouton est son propre repère : le menu se pose au-dessus de lui.
    // Sans [onOpenMenu], le chrome retombe sur l'ouverture d'avant.
    Widget menu(
      OnyxMenuSection section,
      String id,
      IconData icon,
      String label, {
      required VoidCallback fallback,
      GlobalKey? buttonKey,
    }) =>
        Builder(
          key: ValueKey('onyx-$id'),
          builder: (anchor) => OnyxIconButton(
            buttonKey: buttonKey,
            icon: icon,
            tooltip: label,
            metrics: m,
            isTv: isTv,
            glass: true,
            lit: openMenu == section,
            onPressed: () {
              final open = onOpenMenu;
              if (open == null) return fallback();
              open(section, anchor);
            },
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
      if (tabsButton && onOpenEpisodes != null)
        plain(
          'episodes',
          Icons.playlist_play_rounded,
          tr('Épisodes'),
          onOpenEpisodes!,
        )
      else if (tabsButton && onOpenInfo != null)
        plain(
          'info',
          Icons.info_outline_rounded,
          tr('Infos'),
          onOpenInfo!,
        ),
      if (hasSubtitles)
        menu(
          OnyxMenuSection.subtitles,
          'subtitles',
          Icons.closed_caption_rounded,
          tr('Sous-titres'),
          fallback: onToggleSubtitles,
          buttonKey: subtitlesButtonKey,
        ),
      menu(
        OnyxMenuSection.audio,
        'audio',
        Icons.graphic_eq_rounded,
        tr('Pistes audio'),
        fallback: onOpenAudio,
      ),
      // L'index : [OnyxMenuSection.root].
      menu(
        OnyxMenuSection.root,
        'settings',
        Icons.settings_rounded,
        tr('Réglages'),
        fallback: onOpenSettings,
        buttonKey: settingsButtonKey,
      ),
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

  /// Le temps écoulé à gauche ; à droite le temps restant et, juste à côté,
  /// l'heure à laquelle le média se termine si la lecture ne s'arrête plus
  /// (ADR-0163). Une seule rangée pour les trois arrangements du chrome : un
  /// téléviseur, un écran tenu en main et une souris la lisent pareil.
  ///
  /// La rangée est reconstruite à chaque position, et l'heure de fin se
  /// recalcule depuis l'horloge : une pause la repousse d'autant.
  Widget _buildTimes(OnyxChromeMetrics m) {
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('-${formatPlaybackTime(_remainingSeconds)}', style: style),
              SizedBox(width: m.timeSize * 0.9),
              Text(
                tr('Fin à {0}', [formatEndClock(_remainingSeconds)]),
                key: const ValueKey('onyx-end-clock'),
                style: style.copyWith(
                  color: style.color?.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
