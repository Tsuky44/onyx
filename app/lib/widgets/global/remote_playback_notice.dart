import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/remote_playback.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../tv/nav/tv_focusable.dart';
import '../../utils/format.dart';
import 'app_network_image.dart';
import 'glass_chrome.dart';

/// « En lecture sur un autre appareil » : une notification de verre en haut à
/// droite de l'accueil, comme celles de tvOS (ADR-0127). Partout sauf sur un
/// téléphone.
///
/// Elle ne déplace rien : la carte d'avant tenait toute la largeur de la page
/// d'un téléviseur et poussait les rangées vers le bas. La dernière ligne dit
/// toujours quoi faire, selon ce qu'on a en main :
///
/// - **une télécommande** ([hold]) : maintenir la touche lecture/pause.
///   L'anneau autour de la touche se remplit pendant l'appui, et le texte dit
///   de ne pas lâcher. Sur Apple TV c'est le seul geste, et la notification ne
///   prend pas le focus ;
/// - **une télécommande sans cette touche** ([selectable]) : la notification
///   prend aussi le focus, et OK reprend ;
/// - **une souris ou un doigt** ([onResume] sans [hold]) : un clic reprend,
///   la croix ([onDismiss]) l'écarte.
class RemotePlaybackNotice extends StatefulWidget {
  const RemotePlaybackNotice({
    super.key,
    required this.play,
    required this.posterUrl,
    this.hold,
    this.onResume,
    this.onDismiss,
    this.selectable = false,
  });

  final RemotePlayback play;
  final String? posterUrl;

  /// L'appui en cours sur lecture/pause : 0 au repos, 1 quand la lecture
  /// reprend. Nul sans télécommande.
  final Animation<double>? hold;

  /// Reprend tout de suite : OK sur la notification focalisée, ou un clic.
  /// Nul sur Apple TV, où l'on ne reprend qu'en maintenant lecture/pause, et
  /// pendant que la reprise est déjà lancée.
  final VoidCallback? onResume;

  /// Écarte la notification, à la souris.
  final VoidCallback? onDismiss;

  /// Vrai sur un téléviseur dont la télécommande peut ne pas avoir de touche
  /// lecture/pause : la notification entre dans le parcours du focus.
  final bool selectable;

  /// La largeur de la notification, en pixels de la page.
  static const double width = 388;

  @override
  State<RemotePlaybackNotice> createState() => _RemotePlaybackNoticeState();
}

class _RemotePlaybackNoticeState extends State<RemotePlaybackNotice> {
  static const double _posterWidth = 46;
  static const double _posterHeight = 69;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(22));
  static const Animation<double> _still = AlwaysStoppedAnimation<double>(0);

  bool _focused = false;
  bool _hovered = false;

  /// Ce que la dernière ligne dit de faire.
  String _hint(double held) {
    if (widget.hold == null) return tr('Reprendre ici');
    if (_focused) return tr('OK pour reprendre ici');
    return held > 0
        ? tr('Continuez d\'appuyer…')
        : tr('Maintenir pour reprendre ici');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.play.session;
    final device =
        s.deviceName.isNotEmpty ? s.deviceName : tr('un autre appareil');
    final remaining = formatRemaining(s.durationSeconds - s.positionSeconds);
    final detail = [
      if (s.detail.isNotEmpty) s.detail,
      if (remaining != null) remaining,
    ].join(' · ');
    final poster = widget.posterUrl;
    final hold = widget.hold ?? _still;
    final remote = widget.hold != null;
    final onDismiss = widget.onDismiss;

    final card = DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 44,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: GlassSurface(
        borderRadius: _radius,
        dense: true,
        child: AnimatedContainer(
          duration: AppMotion.fade(context, AppMotion.micro),
          curve: AppMotion.curve,
          decoration: BoxDecoration(
            borderRadius: _radius,
            // Sous la souris ou le focus, le verre s'éclaircit.
            color:
                Colors.white.withValues(alpha: _hovered || _focused ? 0.07 : 0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    EdgeInsets.fromLTRB(14, 14, onDismiss == null ? 16 : 6, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: _posterWidth,
                        height: _posterHeight,
                        child: poster == null
                            ? const ColoredBox(color: AppColors.surfaceHover)
                            : AppNetworkImage(
                                url: poster,
                                width: _posterWidth,
                                height: _posterHeight,
                                errorWidget: const ColoredBox(
                                    color: AppColors.surfaceHover),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(AppIcons.devices,
                                  size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  tr('En lecture sur {0}', [device])
                                      .toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: AppType.caption,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.9,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            s.headline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: AppType.headline,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              height: 1.25,
                            ),
                          ),
                          if (detail.isNotEmpty)
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: AppType.subhead,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: s.progress,
                              minHeight: 3,
                              color: AppColors.textPrimary,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onDismiss != null)
                      IconButton(
                        tooltip: tr('Ignorer'),
                        onPressed: onDismiss,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(AppIcons.close,
                            color: AppColors.textSecondary, size: 18),
                      ),
                  ],
                ),
              ),
              ColoredBox(
                color: Colors.white.withValues(alpha: 0.10),
                child: const SizedBox(height: 1),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 16, 11),
                child: AnimatedBuilder(
                  animation: hold,
                  builder: (context, _) => Row(
                    children: [
                      CustomPaint(
                        size: const Size.square(_ResumeKeyPainter.size),
                        painter: _ResumeKeyPainter(
                          progress: hold.value,
                          playPause: remote,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _hint(hold.value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Elle grossit à peine sous l'appui, depuis son coin : la touche a bien
    // été vue.
    Widget notice = AnimatedBuilder(
      animation: hold,
      builder: (context, child) => Transform.scale(
        scale: 1 + 0.03 * Curves.easeOut.transform(hold.value),
        alignment: Alignment.topRight,
        child: child,
      ),
      child: card,
    );

    final onResume = widget.onResume;
    if (widget.selectable) {
      notice = TvFocusable(
        onSelect: onResume,
        onFocusChange: (focused) => setState(() => _focused = focused),
        borderRadius: _radius,
        focusScale: 1,
        child: notice,
      );
    } else if (!remote) {
      notice = MouseRegion(
        cursor: onResume == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onResume,
          child: notice,
        ),
      );
    }

    return Semantics(
      container: true,
      liveRegion: true,
      button: onResume != null,
      label: remote
          ? tr(
              'En lecture sur {0} : {1}. Maintenir lecture/pause pour '
              'reprendre ici.',
              [device, s.headline],
            )
          : tr(
              'En lecture sur {0} : {1}. Reprendre ici.', [device, s.headline]),
      child: SizedBox(width: RemotePlaybackNotice.width, child: notice),
    );
  }
}

/// La touche qui reprend, dans son anneau : lecture/pause de la télécommande,
/// que l'appui remplit, ou le triangle de la lecture pour une souris.
class _ResumeKeyPainter extends CustomPainter {
  const _ResumeKeyPainter({required this.progress, required this.playPause});

  final double progress;
  final bool playPause;

  static const double size = 30;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.34),
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = AppColors.textPrimary,
      );
    }

    final unit = size.shortestSide / 36;
    final ink = Paint()..color = AppColors.textPrimary;
    // Seul, le triangle est centré ; avec la pause, il lui laisse sa place.
    final shift = playPause ? 0.0 : 5.0 * unit;
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - 8.5 * unit + shift, center.dy - 6 * unit)
        ..lineTo(center.dx - 0.5 * unit + shift, center.dy)
        ..lineTo(center.dx - 8.5 * unit + shift, center.dy + 6 * unit)
        ..close(),
      ink,
    );
    if (!playPause) return;
    for (final left in [2.0, 6.4]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            center.dx + left * unit,
            center.dy - 6 * unit,
            2.6 * unit,
            12 * unit,
          ),
          Radius.circular(unit),
        ),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(_ResumeKeyPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.playPause != playPause;
}
