import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/tr.dart';
import '../../../../theme/app_colors.dart';
import '../../../../tv/tv_focus.dart';
import '../../../../utils/format.dart';
import '../../playback/timeline_previews.dart';
import 'onyx_chrome_theme.dart';

/// The Chrome Onyx scrubber: thin white bar that thickens on hover, a handle that
/// only appears once pointed at, chapter ticks, and a time bubble following
/// the cursor — which grows into a still of that moment once the player has
/// [previews].
///
/// Seeking is committed on release, not while dragging: the parent owns the
/// HLS session and a mid-drag seek to a not-yet-served segment stalls it.
class OnyxProgressBar extends StatefulWidget {
  /// Played fraction, 0.0 -> 1.0.
  final double progress;

  /// Downloaded-ahead fraction, 0.0 -> 1.0.
  final double buffered;

  final Duration duration;

  /// Chapter start positions as fractions, 0.0 -> 1.0.
  final List<double> chapterMarks;

  final OnyxChromeMetrics metrics;

  /// Fired once, on release, with the target fraction.
  final ValueChanged<double> onSeek;

  /// Raised while the user is scrubbing so the parent can hold the chrome open.
  final ValueChanged<bool>? onScrubbingChanged;

  /// Television only: the bar takes the focus, and the D-pad seeks from it.
  ///
  /// It is also what makes the rest of the chrome reachable. Directional focus
  /// traversal prefers a target in the same vertical band as the control it
  /// starts from; a full-width bar sitting between the transport row and the
  /// top bar is in the band of every one of them, so up and down always find
  /// something instead of depending on which button happens to line up with
  /// which.
  final bool focusable;

  /// What left and right do while the bar holds the focus — the same ±10 s the
  /// transport buttons carry, because a remote cannot drag a handle.
  final VoidCallback? onStepBack;
  final VoidCallback? onStepForward;

  /// OK / D-pad centre while the bar holds the focus. The bar is where the
  /// remote lands, so it has to answer the most common press of all with the
  /// most common action — play/pause — rather than making the user walk down
  /// to a button for it.
  final VoidCallback? onSelect;

  /// Supplied by the player so it can put the remote here the moment the HUD
  /// comes up, instead of leaving traversal to pick a starting point.
  final FocusNode? focusNode;

  /// Stills of the timeline, shown above the pointer. Null, or not ready yet,
  /// leaves the plain time bubble.
  final TimelinePreviews? previews;

  /// Television: a remote seek is pending, so the still follows the handle —
  /// the remote has no pointer to follow.
  final bool previewAtProgress;

  const OnyxProgressBar({
    super.key,
    required this.progress,
    required this.buffered,
    required this.duration,
    required this.metrics,
    required this.onSeek,
    this.chapterMarks = const [],
    this.onScrubbingChanged,
    this.focusable = false,
    this.onStepBack,
    this.onStepForward,
    this.onSelect,
    this.focusNode,
    this.previews,
    this.previewAtProgress = false,
    this.marker = false,
    this.rowHeight,
  });

  /// L'arrangement d'un téléviseur, celui du lecteur d'Apple (ADR-0124) : la
  /// barre reste blanche sous la télécommande, et la position se lit à un
  /// repère vertical, toujours visible, qui s'allonge et s'éclaire au focus.
  /// La rangée est plus basse : elle n'a pas de doigt à recevoir.
  final bool marker;

  /// La hauteur de la rangée, quand elle n'est pas celle que [marker] décide.
  /// Un écran tenu en main prend le repère d'un téléviseur mais garde une
  /// rangée à la taille d'un doigt (ADR-0136).
  final double? rowHeight;

  @override
  State<OnyxProgressBar> createState() => _OnyxProgressBarState();
}

class _OnyxProgressBarState extends State<OnyxProgressBar> {
  bool _hovered = false;
  bool _focused = false;
  double? _dragFraction;
  double? _pointerFraction;

  /// Ce qui touche la barre : une souris la survole encore après le clic, un
  /// doigt non.
  PointerDeviceKind? _pointerKind;

  /// Pointed at, dragged, or standing under the remote — all three mean the
  /// bar is the thing being aimed at, and all three thicken it.
  bool get _active => _hovered || _focused || _dragFraction != null;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (kTvSelectKeys.contains(key)) {
      final select = widget.onSelect;
      if (select == null) return KeyEventResult.ignored;
      // Holding OK is one play/pause, not one per repeat.
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      select();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      final step = widget.onStepBack;
      if (step == null) return KeyEventResult.ignored;
      step();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final step = widget.onStepForward;
      if (step == null) return KeyEventResult.ignored;
      step();
      return KeyEventResult.handled;
    }
    // Up and down are the traversal's, so the remote can leave the bar.
    return KeyEventResult.ignored;
  }

  /// What the bar draws: the drag position while scrubbing, so the bar tracks
  /// the finger even though the seek itself only lands on release.
  double get _shownFraction =>
      (_dragFraction ?? widget.progress).clamp(0.0, 1.0);

  double _fractionFor(double dx, double width) =>
      width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0);

  void _setDrag(double? value) {
    setState(() {
      _dragFraction = value;
      // Un doigt ne survole pas : la vignette qu'il a fait venir en glissant
      // part avec lui. Seule la sortie d'une souris l'effaçait, et sur un
      // iPhone elle restait à l'écran après le lever.
      if (value == null && _pointerKind != PointerDeviceKind.mouse) {
        _pointerFraction = null;
      }
    });
    widget.onScrubbingChanged?.call(value != null);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    // The row is taller than the bar so there is something to aim at: a 4px
    // bar is not a target, on a mouse or a finger.
    final rowHeight =
        widget.rowHeight ?? (widget.marker ? _markerRowHeight : m.hitSize);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final bar = MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pointerFraction = null;
          }),
          onHover: (event) => setState(
            () =>
                _pointerFraction = _fractionFor(event.localPosition.dx, width),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Décrite d'un bloc par [_described] : un tap et un glissement
            // anonymes ne disent rien à un lecteur d'écran.
            excludeFromSemantics: true,
            onTapDown: (d) {
              _pointerKind = d.kind;
              widget.onSeek(_fractionFor(d.localPosition.dx, width));
            },
            onHorizontalDragStart: (d) {
              _pointerKind = d.kind;
              _setDrag(_fractionFor(d.localPosition.dx, width));
            },
            onHorizontalDragUpdate: (d) => setState(() {
              _dragFraction = _fractionFor(d.localPosition.dx, width);
              _pointerFraction = _dragFraction;
            }),
            onHorizontalDragEnd: (_) {
              final target = _dragFraction;
              _setDrag(null);
              if (target != null) widget.onSeek(target);
            },
            onHorizontalDragCancel: () => _setDrag(null),
            child: SizedBox(
              height: rowHeight,
              width: width,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  _buildBar(width),
                  if (widget.marker)
                    _buildMarker(width, rowHeight)
                  else if (_active)
                    _buildHandle(width),
                  if (_previewFraction != null &&
                      widget.duration > Duration.zero)
                    _buildPointerLabel(width, rowHeight),
                ],
              ),
            ),
          ),
        );

        if (!widget.focusable) return _described(bar);

        // No frame around a focused bar: the bar itself says it. It thickens
        // and turns to the accent, which is what the eye is already on.
        return Focus(
          focusNode: widget.focusNode,
          onKeyEvent: _handleKey,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: _described(bar),
        );
      },
    );
  }

  /// Ce qu'un lecteur d'écran lit de la barre : un curseur, où en est le
  /// film, et dix secondes dans chaque sens.
  Widget _described(Widget bar) {
    final total = widget.duration.inSeconds;
    final played = (widget.progress.clamp(0.0, 1.0) * total).round();

    void nudge(int seconds) {
      if (total <= 0) return;
      widget.onSeek(((played + seconds) / total).clamp(0.0, 1.0));
    }

    String at(int seconds) => tr('{0} sur {1}', [
          formatPlaybackTime(seconds.clamp(0, total)),
          formatPlaybackTime(total),
        ]);

    return Semantics(
      slider: true,
      label: tr('Position de lecture'),
      value: at(played),
      increasedValue: at(played + 10),
      decreasedValue: at(played - 10),
      onIncrease: () => nudge(10),
      onDecrease: () => nudge(-10),
      child: bar,
    );
  }

  /// The played part and the handle: the accent under the remote, white
  /// otherwise.
  Color get _playedColor => _focused && !widget.marker
      ? AppColors.accent
      : OnyxChromeTheme.progressPlayed;

  static const double _markerRowHeight = 30;

  /// Le repère de position du lecteur d'Apple : un trait vertical, plus haut
  /// et lumineux quand la barre a la télécommande, plus haut aussi sous le
  /// doigt qui la déplace.
  Widget _buildMarker(double width, double rowHeight) {
    const thickness = 4.0;
    final height = _focused || _dragFraction != null ? 26.0 : 16.0;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      left: (_shownFraction * width) - thickness / 2,
      top: (rowHeight - height) / 2,
      width: thickness,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: OnyxChromeTheme.progressPlayed,
          borderRadius: BorderRadius.circular(thickness / 2),
          boxShadow: _focused
              ? const [BoxShadow(color: Color(0x8CFFFFFF), blurRadius: 14)]
              : null,
        ),
      ),
    );
  }

  Widget _buildBar(double width) {
    final m = widget.metrics;
    final thickness = _active ? m.barThicknessActive : m.barThickness;

    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: thickness,
        width: width,
        child: CustomPaint(
          painter: OnyxSegmentedBarPainter(
            cuts: OnyxSegmentedBarPainter.cutsFor(widget.chapterMarks, width),
            buffered: widget.buffered.clamp(0.0, 1.0),
            played: _shownFraction,
            playedColor: _playedColor,
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(double width) {
    final size = widget.metrics.handleSize;
    return Positioned(
      left: (_shownFraction * width) - size / 2,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _playedColor,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  /// Where the still or bubble points: the mouse or finger, or on a
  /// television the pending seek.
  double? get _previewFraction =>
      _pointerFraction ??
      (_focused && widget.previewAtProgress ? _shownFraction : null);

  Widget _buildPointerLabel(double width, double rowHeight) {
    final previews = widget.previews;
    if (previews == null) return _buildTimeBubble(width, rowHeight);
    // Only the label rebuilds as stills arrive, not the whole bar.
    return ListenableBuilder(
      listenable: previews,
      builder: (context, _) => previews.isReady
          ? _buildPreview(width, rowHeight, previews)
          : _buildTimeBubble(width, rowHeight),
    );
  }

  Widget _buildPreview(
    double width,
    double rowHeight,
    TimelinePreviews previews,
  ) {
    final manifest = previews.manifest!;
    final fraction = _previewFraction!;
    final position = Duration(
      milliseconds: (widget.duration.inMilliseconds * fraction).round(),
    );
    final index = manifest.indexFor(position);
    // Asynchronous by contract: the fetch it may start notifies later.
    previews.request(index);
    final image = previews.imageFor(index);

    final boxWidth = widget.metrics.previewWidth.clamp(0.0, width);
    final boxHeight = boxWidth / manifest.aspectRatio;
    final left = (fraction * width - boxWidth / 2).clamp(0.0, width - boxWidth);
    final radius = BorderRadius.circular(8);

    return Positioned(
      left: left,
      bottom: rowHeight / 2 + 12,
      child: IgnorePointer(
        child: Container(
          width: boxWidth,
          decoration: BoxDecoration(
            color: OnyxChromeTheme.tooltipSurface,
            borderRadius: radius,
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          // Drawn over the still rather than around it, so the picture keeps
          // its full width.
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: const Color(0x40FFFFFF)),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: boxWidth,
                  height: boxHeight,
                  child: image == null
                      ? null
                      : Image(
                          image: image,
                          fit: BoxFit.cover,
                          // Holds the previous still until the next one is
                          // decoded, so a scrub never flashes to empty.
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: _timeLabel(position.inSeconds),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeLabel(int seconds) {
    return Text(
      formatPlaybackTime(seconds),
      style: TextStyle(
        color: Colors.white,
        fontSize: widget.metrics.timeSize,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _buildTimeBubble(double width, double rowHeight) {
    final fraction = _previewFraction!;
    final seconds = (widget.duration.inSeconds * fraction).round();
    // Clamped so the bubble never hangs off either end of the bar.
    const bubbleWidth = 68.0;
    final left =
        (fraction * width - bubbleWidth / 2).clamp(0.0, width - bubbleWidth);

    return Positioned(
      left: left,
      bottom: rowHeight / 2 + 12,
      child: IgnorePointer(
        child: Container(
          width: bubbleWidth,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: OnyxChromeTheme.tooltipSurface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: _timeLabel(seconds),
        ),
      ),
    );
  }
}

/// La barre, coupée à chaque chapitre (ADR-0139) : un petit vide entre deux
/// tronçons aux bouts ronds, au lieu du trait posé sur une barre continue.
/// Le vide laisse voir l'image, ce qu'un trait ne faisait pas sur la partie
/// déjà lue, blanche comme lui.
class OnyxSegmentedBarPainter extends CustomPainter {
  const OnyxSegmentedBarPainter({
    required this.cuts,
    required this.buffered,
    required this.played,
    required this.playedColor,
  });

  /// Le vide entre deux chapitres.
  static const double gap = 4;

  /// Sous cette largeur un tronçon ne se lit plus : sa coupure est ignorée.
  static const double minSegment = 8;

  /// Où couper, en points depuis la gauche, dans l'ordre.
  final List<double> cuts;
  final double buffered;
  final double played;
  final Color playedColor;

  /// Les coupures que [marks] (des fractions) donnent sur [width] : ni au
  /// bord, ni à moins de [minSegment] de la précédente.
  static List<double> cutsFor(List<double> marks, double width) {
    final sorted = [...marks]..sort();
    final cuts = <double>[];
    var last = 0.0;
    for (final mark in sorted) {
      final x = mark * width;
      if (x - last < minSegment || width - x < minSegment) continue;
      cuts.add(x);
      last = x;
    }
    return cuts;
  }

  /// Les tronçons, de gauche à droite, sur [width].
  List<(double, double)> segments(double width) {
    final out = <(double, double)>[];
    var start = 0.0;
    for (final cut in cuts) {
      out.add((start, cut - gap / 2));
      start = cut + gap / 2;
    }
    out.add((start, width));
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height);
    final track = Paint()..color = OnyxChromeTheme.progressTrack;
    final ahead = Paint()..color = OnyxChromeTheme.progressBuffered;
    final done = Paint()..color = playedColor;
    final bufferedX = buffered * size.width;
    final playedX = played * size.width;

    for (final (start, end) in segments(size.width)) {
      final segment = RRect.fromLTRBR(start, 0, end, size.height, radius);
      canvas.drawRRect(segment, track);
      canvas.save();
      canvas.clipRRect(segment);
      if (bufferedX > start) {
        canvas.drawRect(Rect.fromLTRB(start, 0, bufferedX, size.height), ahead);
      }
      if (playedX > start) {
        canvas.drawRect(Rect.fromLTRB(start, 0, playedX, size.height), done);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(OnyxSegmentedBarPainter old) =>
      old.buffered != buffered ||
      old.played != played ||
      old.playedColor != playedColor ||
      !_sameCuts(old.cuts);

  bool _sameCuts(List<double> other) {
    if (other.length != cuts.length) return false;
    for (var i = 0; i < cuts.length; i++) {
      if (cuts[i] != other[i]) return false;
    }
    return true;
  }
}
