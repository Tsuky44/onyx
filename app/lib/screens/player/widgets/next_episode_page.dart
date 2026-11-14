import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_mode.dart';
import '../../../utils/app_platform.dart';
import '../../../utils/format.dart';
import '../../../widgets/global/media_poster.dart';
import 'onyx/onyx_capsule_button.dart';
import 'onyx/onyx_chrome_theme.dart';
import 'player_video_stage.dart';

/// La page de l'épisode suivant, au générique (ADR-0130) : l'image en cours se
/// range dans un coin (`PlayerVideoStage`) et l'épisode qui vient se présente,
/// avec son image, son titre, l'anneau du compte à rebours, « Lire » et
/// « Plus tard ».
///
/// Elle remplace la pastille « Épisode suivant » posée sur le générique : une
/// cible de 48 px à viser, sans dire quel épisode elle lançait. La page ne
/// lance rien elle-même : le compte à rebours est celui du lecteur
/// (`EpisodeNavigationController`), elle le montre. Un geste le gèle, comme
/// partout.
class NextEpisodePage extends StatefulWidget {
  const NextEpisodePage({
    super.key,
    required this.nextEpisode,
    required this.onPlayNext,
    required this.onLater,
    this.currentLabel,
    this.countdownSeconds,
    this.countdownTotal = 5,
    this.frozen = false,
  });

  final HomeMediaItem nextEpisode;
  final VoidCallback onPlayNext;

  /// « Plus tard » : la page se range et ne revient pas pour cet épisode.
  final VoidCallback onLater;

  /// L'épisode qui finit, écrit sous son image rétrécie.
  final String? currentLabel;

  /// Les secondes qui restent avant l'enchaînement, ou nul quand rien ne
  /// compte : la minuterie de veille s'arrête après cet épisode.
  final int? countdownSeconds;
  final int countdownTotal;

  /// Quelqu'un a touché au lecteur : l'anneau reste où il en est.
  final bool frozen;

  @override
  State<NextEpisodePage> createState() => _NextEpisodePageState();
}

class _NextEpisodePageState extends State<NextEpisodePage> {
  final FocusNode _play = FocusNode(debugLabel: 'next-episode-play');

  @override
  void initState() {
    super.initState();
    // Demandé, pas `autofocus` : le lecteur tient déjà le focus. Sans cela la
    // télécommande n'aurait rien sous OK devant une page qui vient d'arriver.
    // Pas sur un écran tenu en main : personne n'y a de touche à presser, et
    // le focus y dessinerait un anneau que nul n'a demandé.
    if (AppPlatform.isMobile && !TvMode.isTv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _play.requestFocus();
    });
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.nextEpisode;
    final media = next.media;
    final title = next.episodeTitle ?? media.title;
    final code = media.seasonEpisodeCode;
    final duration = next.effectiveDuration;
    final meta = [
      if ((next.showTitle ?? '').isNotEmpty) next.showTitle!,
      if (code != null && code.isNotEmpty) code,
      if (duration > 0) formatDuration(duration),
    ].join(' · ');
    final seconds = widget.countdownSeconds;

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final video = PlayerVideoStage.frameFor(
              size,
              scale: PlayerVideoStage.nextEpisodeScale,
              alignment: PlayerVideoStage.nextEpisodeAlignment,
            );
            // Les proportions de la maquette, dessinée sur 1280 de large.
            final unit = size.width / 1280;
            final label = widget.currentLabel;
            return Stack(
              children: [
                if (label != null && label.isNotEmpty)
                  Positioned(
                    left: video.left + 12 * unit,
                    top: video.bottom + 4 * unit,
                    width: video.width,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OnyxChromeTheme.meta,
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Positioned(
                  left: video.right + 80 * unit,
                  top: video.top + 10 * unit,
                  right: 53 * unit,
                  bottom: 24 * unit,
                  // Réduit d'un bloc sur un petit écran plutôt que recomposé :
                  // la page garde sa forme d'un téléviseur à un téléphone.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 594,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MediaPoster(
                            media: media,
                            width: 420,
                            height: 236,
                            borderRadius: 12,
                          ),
                          const SizedBox(height: 22),
                          Text(
                            tr('Épisode suivant').toUpperCase(),
                            style: const TextStyle(
                              color: OnyxChromeTheme.meta,
                              fontSize: AppType.subhead,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            key: const ValueKey('next-episode-title'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: OnyxChromeTheme.title,
                              fontSize: AppType.hero,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              height: 1.1,
                            ),
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: OnyxChromeTheme.time,
                                fontSize: AppType.headline,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          OnyxControlsRow(
                            preferredFocus: _play,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (seconds != null) ...[
                                  _CountdownRing(
                                    seconds: seconds,
                                    total: widget.countdownTotal,
                                    frozen: widget.frozen,
                                  ),
                                  const SizedBox(width: 16),
                                ],
                                OnyxCapsuleButton(
                                  key: const ValueKey('next-episode-play'),
                                  label: tr('Lire'),
                                  icon: Icons.play_arrow_rounded,
                                  primary: true,
                                  large: true,
                                  focusNode: _play,
                                  onPressed: widget.onPlayNext,
                                ),
                                const SizedBox(width: 12),
                                OnyxCapsuleButton(
                                  key: const ValueKey('next-episode-later'),
                                  label: tr('Plus tard'),
                                  large: true,
                                  onPressed: widget.onLater,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// L'anneau du compte à rebours : il se vide jusqu'à l'enchaînement, le nombre
/// de secondes au milieu. Gelé, il garde son arc et montre une pause.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({
    required this.seconds,
    required this.total,
    required this.frozen,
  });

  final int seconds;
  final int total;
  final bool frozen;

  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : (seconds / total).clamp(0.0, 1.0);
    return Semantics(
      label: frozen
          ? tr('Lecture automatique en pause')
          : tr('Lecture dans {0} s', [seconds]),
      child: SizedBox(
        width: _size,
        height: _size,
        child: TweenAnimationBuilder<double>(
          // Une seconde par cran, sans courbe : l'arc avance à vitesse
          // constante entre deux battements du compte à rebours.
          tween: Tween<double>(end: fraction),
          duration: frozen ? Duration.zero : const Duration(seconds: 1),
          builder: (context, value, child) => CustomPaint(
            painter: _RingPainter(value),
            child: child,
          ),
          child: Center(
            child: frozen
                ? const Icon(
                    Icons.pause_rounded,
                    size: 22,
                    color: OnyxChromeTheme.title,
                  )
                : Text(
                    '$seconds',
                    style: const TextStyle(
                      color: OnyxChromeTheme.title,
                      fontSize: AppType.headline,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.fraction);

  final double fraction;

  static const double _stroke = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..color = OnyxChromeTheme.progressTrack;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (fraction <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = OnyxChromeTheme.progressPlayed;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * fraction, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}
