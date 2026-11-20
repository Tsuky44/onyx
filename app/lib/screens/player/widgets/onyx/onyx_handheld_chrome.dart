part of 'onyx_controls_layer.dart';

/// Le chrome d'un écran tenu en main, téléphone ou tablette (ADR-0136) :
/// l'arrangement d'un téléviseur ([_buildTvChrome], ADR-0124), adapté au doigt.
///
/// Ce qu'il en garde : le logo en haut à gauche, ce qu'on regarde en une
/// ligne en bas à gauche, des boutons ronds de verre à sa droite, la barre
/// fine et son repère, les temps écoulé et restant.
///
/// Ce qui change, parce qu'il n'y a pas de télécommande :
/// - lecture/pause et ±10 s sont au milieu de l'image. Sur un téléviseur ils
///   doublaient la télécommande ; ici un toucher sur l'image ne fait
///   qu'afficher le chrome, et il faut bien un bouton pour mettre en pause ;
/// - Retour et le verrou sont des boutons, en haut ;
/// - les onglets ne sont plus sous la barre (ADR-0139) : un bouton de la
///   rangée ouvre la feuille du bas (`PlayerTabSheet`), qui les porte tous.
///   La rangée d'onglets coûtait 44 points de haut à un écran qui en a 390.
///
/// La rangée des boutons ronds est celle d'un téléviseur
/// ([_buildEssentialActions]) : l'essentiel a son bouton, la roue crantée
/// ouvre le reste.
extension _OnyxHandheldChrome on OnyxControlsLayer {
  /// Sous cette largeur, le titre et les boutons ronds ne tiennent plus sur
  /// une rangée : ils s'empilent. Un téléphone couché fait au moins 568 ; il
  /// n'y a qu'une tablette en écran partagé pour passer dessous.
  static const double _stackBelow = 520;

  /// Ce que la rangée des temps ajoute sous celle de la barre. Les temps sont
  /// dessinés dans la cible de la barre plutôt que dessous : la rangée garde
  /// la hauteur d'un doigt sans que le chrome prenne celle de deux rangées.
  static const double _timesBelowBar = 8;

  /// ±10 s contre lecture/pause : « légèrement plus petits », à la demande de
  /// l'utilisateur (ADR-0139). À 0,64 ils se lisaient comme des commandes
  /// secondaires, alors qu'on les touche autant que la pause.
  static const double _sideRatio = 0.8;

  Widget _buildHandheldChrome(OnyxChromeMetrics m, double width) {
    final hasBrightness = brightness != null && onBrightnessChanged != null;
    return CustomMultiChildLayout(
      delegate: _OnyxChromeLayout(
        topLead: OnyxControlsLayer._topBarTail,
        // « Passer l'intro » occupe cette bande quand il est là : la barre de
        // luminosité doit rester hors de lui.
        bottomLead: onSkipIntro == null ? OnyxControlsLayer._bottomBarLead : 0,
        centreLead: OnyxControlsLayer._bottomBarLead,
      ),
      children: [
        LayoutId(
          id: _OnyxChromeLayout.top,
          child: _fadeWithChrome(_buildHandheldTop(m)),
        ),
        if (hasBrightness)
          LayoutId(
            id: _OnyxChromeLayout.brightness,
            // À la verticale du verrou et de l'épisode suivant.
            child: _buildBrightnessBand(
              m,
              barWidth: OnyxIconButton.glassSize,
            ),
          ),
        LayoutId(
          id: _OnyxChromeLayout.bottom,
          child: Stack(
            children: [
              _fadeWithChrome(_buildHandheldBottom(m, width)),
              // Hors du fondu, comme sur les autres chromes : l'offre est
              // limitée dans le temps et ne doit pas expirer derrière un
              // chrome masqué. Dans la marge de dégradé de la barre plutôt
              // qu'au-dessus d'elle : la barre garde sa hauteur, et les
              // commandes du milieu ne bougent pas quand la capsule arrive.
              if (onSkipIntro != null)
                Positioned(
                  left: m.gutter,
                  right: m.gutter,
                  top: 0,
                  height: OnyxControlsLayer._bottomBarLead,
                  // Au bord droit des boutons ronds, juste au-dessus d'eux.
                  child: _dodgeCutouts(
                    Align(
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
                ),
            ],
          ),
        ),
        LayoutId(
          id: _OnyxChromeLayout.centre,
          // En dernier, donc touché en premier : sur un écran étroit la
          // colonne invisible de la barre de luminosité passe sous +10 s, et
          // lui prendrait le doigt. Rien d'autre ne le croise, le délégué le
          // tient entre les deux barres.
          //
          // Un menu ouvert les efface : son panneau de verre se pose sur
          // cette zone, et des boutons devinés derrière un flou ne sont ni
          // lisibles ni touchables.
          child: PlayerChromeFade(
            visible: visible && openMenu == null,
            child: _buildHandheldTransport(m),
          ),
        ),
      ],
    );
  }

  /// Un bouton rond de verre du haut de l'écran : Retour, le verrou.
  Widget _handheldGlassButton(
    OnyxChromeMetrics m, {
    required String id,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return OnyxIconButton(
      key: ValueKey('onyx-$id'),
      icon: icon,
      tooltip: tooltip,
      metrics: m,
      glass: true,
      onPressed: onPressed,
    );
  }

  // --- Haut -----------------------------------------------------------------

  Widget _buildHandheldTop(OnyxChromeMetrics m) {
    return OnyxScrim(
      gradient: OnyxChromeTheme.topScrim,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          m.gutter,
          m.topInset,
          m.gutter,
          OnyxControlsLayer._topBarTail,
        ),
        child: _dodgeCutouts(
          Row(
            children: [
              _handheldGlassButton(
                m,
                id: 'back',
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: tr('Retour'),
                onPressed: onBack,
              ),
              const SizedBox(width: 8),
              // Le logo prend toute la place jusqu'au verrou, calé à gauche.
              // Un `Flexible` suivi d'un `Spacer` ne le fait pas : le second
              // reçoit sa moitié de la rangée et pas un point de plus, et ce
              // que le logo laissait de la sienne restait vide à droite — le
              // verrou flottait au milieu de l'écran (iPhone, 1.1.54).
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildTitleMark(m),
                ),
              ),
              if (handheldFullscreen)
                _handheldGlassButton(
                  m,
                  id: 'fullscreen',
                  icon: Icons.fullscreen_rounded,
                  tooltip: tr('Plein écran'),
                  onPressed: onToggleFullscreen,
                ),
              if (onLockScreen != null)
                _handheldGlassButton(
                  m,
                  id: 'lock',
                  icon: Icons.lock_open_rounded,
                  tooltip: tr('Verrouiller l’écran'),
                  onPressed: onLockScreen!,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Milieu ---------------------------------------------------------------

  /// Lecture/pause entre −10 s et +10 s, sur l'image. Les épisodes précédent
  /// et suivant n'y sont pas : à cette taille, sous le pouce, un épisode
  /// changé par erreur coûte bien plus cher que dix secondes.
  Widget _buildHandheldTransport(OnyxChromeMetrics m) {
    final sideSize = m.playIconSize * _sideRatio;
    final gap = SizedBox(width: m.playIconSize * 0.66);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OnyxIconButton(
          key: const ValueKey('onyx-rewind'),
          icon: Icons.replay_10_rounded,
          tooltip: tr('Reculer de 10 s'),
          metrics: m,
          size: sideSize,
          onPicture: true,
          onPressed: onRewind,
        ),
        gap,
        // Sous l'anneau d'attente, posé au même endroit par l'écran du
        // lecteur : le bouton s'efface sans quitter sa place.
        AnimatedOpacity(
          opacity: isLoading ? 0 : 1,
          duration: AppMotion.micro,
          child: OnyxIconButton(
            key: const ValueKey('onyx-play-pause'),
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: isPlaying ? tr('Pause') : tr('Lecture'),
            metrics: m,
            size: m.playIconSize,
            focusNode: playPauseFocusNode,
            onPicture: true,
            onPressed: onPlayPause,
          ),
        ),
        gap,
        OnyxIconButton(
          key: const ValueKey('onyx-forward'),
          icon: Icons.forward_10_rounded,
          tooltip: tr('Avancer de 10 s'),
          metrics: m,
          size: sideSize,
          onPicture: true,
          onPressed: onForward,
        ),
      ],
    );
  }

  // --- Bas ------------------------------------------------------------------

  Widget _buildHandheldBottom(OnyxChromeMetrics m, double width) {
    // Transparent aux touchers, comme le titre des autres arrangements : un
    // toucher sur le titre range le chrome comme partout ailleurs sur l'image.
    final title = IgnorePointer(child: _buildIdentityLine(m));
    final actions = _buildEssentialActions(m, tabsButton: true);
    return OnyxScrim(
      gradient: OnyxChromeTheme.bottomScrim,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          m.gutter,
          OnyxControlsLayer._bottomBarLead,
          m.gutter,
          m.bottomInset,
        ),
        // Chaque rangée évite la caméra pour son compte : voir
        // [_buildBottomRows].
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (width < _stackBelow) ...[
              _dodgeCutouts(title),
              const SizedBox(height: 6),
              _dodgeCutouts(
                Align(alignment: Alignment.centerRight, child: actions),
              ),
            ] else
              _dodgeCutouts(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 16),
                    actions,
                  ],
                ),
              ),
            _dodgeCutouts(_buildHandheldTimeline(m)),
          ],
        ),
      ),
    );
  }

  /// La barre et, dans sa propre cible, les temps : écoulé à gauche, restant
  /// et heure de fin à droite (ADR-0163).
  Widget _buildHandheldTimeline(OnyxChromeMetrics m) {
    return SizedBox(
      height: m.hitSize + _timesBelowBar,
      child: Stack(
        // La vignette de la barre se dessine au-dessus de sa rangée.
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
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
                previews: previews,
                marker: true,
                rowHeight: m.hitSize,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // Dans la cible de la barre : le doigt posé sur un temps déplace
            // la lecture, il ne tombe pas sur un texte.
            child: IgnorePointer(child: _buildTimes(m)),
          ),
        ],
      ),
    );
  }
}
