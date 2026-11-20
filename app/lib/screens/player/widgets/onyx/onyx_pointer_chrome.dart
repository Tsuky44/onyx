part of 'onyx_controls_layer.dart';

/// Le chrome d'un écran à souris, ordinateur ou navigateur (ADR-0139) :
/// l'arrangement d'un téléviseur ([_buildTvChrome], ADR-0124), à la distance
/// d'un moniteur.
///
/// Ce qu'il en garde : rien au milieu de l'image (un clic sur l'image met en
/// pause, Espace aussi, les flèches déplacent de dix secondes, comme la
/// télécommande le fait sur un téléviseur), le logo en haut à gauche, ce
/// qu'on regarde en une ligne, l'essentiel en boutons ronds de verre, la
/// barre fine à repère, les temps écoulé et restant, les onglets sous la
/// barre et leur volet.
///
/// Ce qui change, parce qu'il y a une fenêtre et un pointeur :
/// - Retour est un bouton, en haut à gauche, sous les feux de la fenêtre d'un
///   Mac ;
/// - le volume, l'image dans l'image et le plein écran sont en haut à droite,
///   là où un écran tenu en main a son verrou ;
/// - un onglet s'ouvre d'un clic, et se referme d'un second ;
/// - l'heure de fin se lit au survol du temps restant ;
/// - dans une fenêtre trop petite pour le volet
///   ([OnyxChromeTheme.pointerCarriesTabs]), les onglets passent derrière un
///   bouton de la rangée, comme sur un écran tenu en main.
extension _OnyxPointerChrome on OnyxControlsLayer {
  /// Sous cette largeur le curseur du volume chasserait le logo de la rangée
  /// du haut : il reste le bouton muet.
  static const double _volumeSliderFrom = 560;

  Widget _buildPointerChrome(OnyxChromeMetrics m, Size size) {
    final carriesTabs =
        tabs.isNotEmpty && OnyxChromeTheme.pointerCarriesTabs(size);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _fadeWithChrome(_buildPointerTop(m, size.width)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Stack(
            children: [
              _fadeWithChrome(_buildPointerBottom(m, carriesTabs)),
              // Hors du fondu, comme sur les autres chromes : l'offre est
              // limitée dans le temps et ne doit pas expirer derrière un
              // chrome masqué. Dans la marge de dégradé, juste au-dessus des
              // boutons ronds.
              if (onSkipIntro != null)
                Positioned(
                  left: m.gutter,
                  right: m.gutter,
                  top: 0,
                  height: OnyxControlsLayer._bottomBarLead,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: OnyxSkipIntroButton(
                      onPressed: onSkipIntro!,
                      metrics: m,
                      autoSkipIn: skipIntroCountdown,
                      segment: skipSegment,
                      capsule: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Haut -----------------------------------------------------------------

  Widget _buildPointerTop(OnyxChromeMetrics m, double width) {
    // Le dégradé ne prend pas les clics : voir [OnyxScrim].
    return OnyxScrim(
      gradient: OnyxChromeTheme.topScrim,
      child: Padding(
        // Les feux d'un Mac vivent dans cette bande : la rangée commence
        // dessous.
        padding: EdgeInsets.fromLTRB(
          m.gutter,
          macOSWindowControlsTopInset + m.topInset,
          m.gutter,
          OnyxControlsLayer._topBarTail,
        ),
        // La barre de titre de Windows qui sort au bord haut pousse la
        // rangée vers le bas au lieu de la recouvrir.
        child: CaptionPeekInset(
          child: Row(
            children: [
              OnyxIconButton(
                key: const ValueKey('onyx-back'),
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: tr('Retour'),
                metrics: m,
                glass: true,
                onPressed: onBack,
              ),
              const SizedBox(width: 8),
              // Transparent aux clics ([_buildTitleMark]) : on déplace la
              // fenêtre en la tirant par son titre comme par l'image.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildTitleMark(m),
                ),
              ),
              if (showVolume)
                OnyxVolumeControl(
                  volume: volume,
                  onChanged: onVolumeChanged,
                  metrics: m,
                  glass: true,
                  showSlider: width >= _volumeSliderFrom,
                ),
              ...onyxWindowButtons(
                metrics: m,
                glass: true,
                onToggleFullscreen: onToggleFullscreen,
                onTogglePictureInPicture: onTogglePictureInPicture,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Bas ------------------------------------------------------------------

  Widget _buildPointerBottom(OnyxChromeMetrics m, bool carriesTabs) {
    return OnyxScrim(
      gradient: OnyxChromeTheme.bottomScrim,
      child: Padding(
        padding: const EdgeInsets.only(top: OnyxControlsLayer._bottomBarLead),
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
                      // Transparent aux clics, comme le logo.
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: IgnorePointer(child: _buildIdentityLine(m)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      _buildEssentialActions(m, tabsButton: !carriesTabs),
                    ],
                  ),
                  KeyedSubtree(
                    key: timelineAnchorKey,
                    child: OnyxProgressBar(
                      progress: _progressFraction,
                      buffered: buffered,
                      duration: duration,
                      chapterMarks: chapterMarks,
                      metrics: m,
                      onSeek: onSeekFraction,
                      onScrubbingChanged: onScrubbingChanged,
                      previews: previews,
                      marker: true,
                    ),
                  ),
                  _buildPointerTimes(m),
                ],
              ),
            ),
            // Le volet va d'un bord à l'autre de la fenêtre : il pose lui-même
            // ses marges.
            if (carriesTabs)
              OnyxTvTabs(
                metrics: m,
                visible: visible,
                tabs: tabs,
                open: openTab,
                pointer: true,
                onChanged: (tab) => onTabChanged?.call(tab),
              )
            else
              SizedBox(height: m.bottomInset),
          ],
        ),
      ),
    );
  }

  /// Le temps écoulé à gauche, le temps restant à droite. L'heure de fin, que
  /// l'ancien chrome écrivait à côté, se lit au survol du temps restant : une
  /// souris a de quoi la demander, et la rangée reste celle des autres écrans.
  Widget _buildPointerTimes(OnyxChromeMetrics m) {
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
          Tooltip(
            key: const ValueKey('onyx-remaining'),
            message: tr('Fin à {0}', [formatEndClock(_remainingSeconds)]),
            waitDuration: const Duration(milliseconds: 300),
            child: Text(
              '-${formatPlaybackTime(_remainingSeconds)}',
              style: style,
            ),
          ),
      ],
    );
  }
}
