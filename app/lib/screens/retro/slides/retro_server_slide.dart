import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/locale_formats.dart';
import '../../../l10n/tr.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/retro_motion.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_blocks.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_poster.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 8. Le serveur, ensemble : un total, une place, le titre le plus partagé.
/// Les membres en cercle, rangés par temps de lecture, sans nom ni chiffre :
/// ton point s'allume à ta place. Personne n'y est nommé.
class RetroServerSlide extends RetroSlide {
  const RetroServerSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      const RetroRings(Alignment.center);

  @override
  RetroColors colors(RetroStoryData data) => RetroPalette.server;

  int _hours(RetroStoryData data) =>
      (data.report.server.watchedSeconds / 3600).round();

  String _members(RetroStoryData data) => trPlural(data.report.server.members,
      '{0} membre a regardé', '{0} membres ont regardé');

  bool _hasTopTitle(RetroStoryData data) {
    final server = data.report.server;
    return server.topTitle.isNotEmpty && server.topTitleViewers >= 2;
  }

  bool _ranked(RetroStoryData data) {
    final server = data.report.server;
    return server.members >= 2 && server.rank > 0;
  }

  @override
  String summary(RetroStoryData data) {
    final server = data.report.server;
    return [
      '${_members(data)} ${tr('{0} h sur ton serveur cette année.', [
            _hours(data)
          ])}',
      if (_ranked(data)) tr('Ta place : n°{0}.', [server.rank]),
      if (_hasTopTitle(data))
        tr('Le titre le plus partagé : {0}, vu par {1} membres.',
            [server.topTitle, server.topTitleViewers]),
    ].join(' ');
  }

  List<Widget> _lines(RetroStoryData data, {required double size}) => [
        RetroKicker(tr('Ton serveur, ensemble')),
        RetroLede(_members(data), delay: const Duration(milliseconds: 150)),
        RetroCount(
          value: _hours(data),
          size: size,
          delay: const Duration(milliseconds: 500),
          format: (v) => tr('{0} h', [LocaleFormats.integer(v)]),
        ),
        RetroLede(tr('sur ton serveur cette année.'),
            delay: const Duration(milliseconds: 900)),
        if (_hasTopTitle(data)) _SharedTitle(data: data),
      ];

  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      RetroText(children: _lines(data, size: 24));

  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final server = data.report.server;
    if (!_ranked(data)) {
      return RetroReveal.pop(
        delay: const Duration(milliseconds: 1300),
        child: RetroCard(
          child: RetroNote(tr(
              'Tu es la seule personne à regarder ici cette année. Le serveur est à toi.')),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => _MembersRing(
        members: server.members,
        rank: server.rank,
        diameter: math.min(constraints.maxWidth, constraints.maxHeight),
      ),
    );
  }

  @override
  Widget? compose(BuildContext context, RetroStoryData data) {
    final units = RetroUnits.of(context);
    if (!units.landscape || !_ranked(data)) return null;
    final size = units.size;
    final padding = units.padding;
    final server = data.report.server;
    final textWidth = size.width * 0.48 - padding.left;
    final diameter = math.min(size.height * 0.74, size.width * 0.4);
    return Stack(
      children: [
        Positioned(
          left: padding.left,
          top: padding.top,
          bottom: padding.bottom,
          width: textWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: textWidth,
              child: RetroText(children: _lines(data, size: 35)),
            ),
          ),
        ),
        Positioned(
          right: size.width * 0.07,
          top: (size.height - diameter) / 2 + padding.top / 4,
          width: diameter,
          height: diameter,
          child: _MembersRing(
            members: server.members,
            rank: server.rank,
            diameter: diameter,
          ),
        ),
      ],
    );
  }
}

/// Le titre le plus partagé du serveur, avec son affiche quand c'est aussi un
/// titre de ton top ; sinon, le dégradé de secours.
class _SharedTitle extends StatelessWidget {
  const _SharedTitle({required this.data});
  final RetroStoryData data;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final server = data.report.server;
    final mine = data.report.top
        .where((title) => title.title == server.topTitle)
        .firstOrNull;
    return RetroReveal.rise(
      delay: const Duration(milliseconds: 1600),
      child: RetroCard(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RetroPoster(
              posterUrl: mine?.posterUrl ?? '',
              title: server.topTitle,
              serverBaseUrl: data.serverBaseUrl,
              width: math.max(34, u * 10),
            ),
            SizedBox(width: u * 3.5),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RetroKicker(tr('Le titre le plus partagé')),
                  SizedBox(height: u),
                  Text(
                    server.topTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: math.max(14, u * 5),
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  Opacity(
                    opacity: 0.8,
                    child: Text(
                      tr('vu par {0} membres', [server.topTitleViewers]),
                      style: TextStyle(fontSize: math.max(11, u * 3.2)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Les membres en cercle, du n°1 en haut, dans le sens des aiguilles. Au-delà
/// de [_maxDots], un point vaut plusieurs membres et le tien garde sa place
/// relative.
class _MembersRing extends StatelessWidget {
  const _MembersRing({
    required this.members,
    required this.rank,
    required this.diameter,
  });

  final int members;
  final int rank;
  final double diameter;

  static const _maxDots = 48;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final ink =
        DefaultTextStyle.of(context).style.color ?? const Color(0xFFFFFFFF);
    final dots = math.min(members, _maxDots);
    final me = members <= _maxDots
        ? rank - 1
        : ((rank - 1) / (members - 1) * (dots - 1)).round();
    return Semantics(
      label: tr('Ta place : n°{0}.', [rank]),
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RingPainter(
                  dots: dots,
                  me: me,
                  ink: ink,
                  unit: u,
                  you: tr('toi'),
                  entrance: RetroEntrance.of(context),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Le rang descend comme un compteur, du dernier à sa place.
                RetroCount(
                  value: rank,
                  from: members,
                  size: math.min(27, diameter / u * 0.24),
                  delay: const Duration(milliseconds: 1200),
                  format: (v) => tr('n°{0}', [v]),
                ),
                SizedBox(height: u),
                Opacity(
                  opacity: 0.8,
                  child: Text(
                    tr('ta place sur {0}', [members]),
                    style: TextStyle(fontSize: math.max(12, u * 3.6)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.dots,
    required this.me,
    required this.ink,
    required this.unit,
    required this.you,
    required this.entrance,
  }) : super(repaint: entrance);

  final int dots;
  final int me;
  final Color ink;
  final double unit;
  final String you;

  /// Les points s'allument l'un après l'autre, le tien en dernier.
  final Animation<double> entrance;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 * 0.86;
    final dot = math.max(3.0, size.shortestSide * 0.024);
    final total = RetroMotion.entrance.inMilliseconds;
    final stagger = math.min(70.0, 1100 / dots);
    for (var i = 0; i < dots; i++) {
      final start = (700 + stagger * i) / total;
      final t = ((entrance.value - start) / (400 / total)).clamp(0.0, 1.0);
      if (t == 0) continue;
      final angle = 2 * math.pi * i / dots - math.pi / 2;
      final at = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i != me) {
        canvas.drawCircle(
            at, dot, Paint()..color = ink.withValues(alpha: 0.32 * t));
        continue;
      }
      // Ton point : plus gros, avec un halo peint en dégradé (pas de flou).
      final halo = dot * 5;
      canvas.drawCircle(
        at,
        halo,
        Paint()
          ..shader = RadialGradient(colors: [
            ink.withValues(alpha: 0.45 * t),
            ink.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: at, radius: halo)),
      );
      canvas.drawCircle(at, dot * 2 * t, Paint()..color = ink);
      final label = TextPainter(
        text: TextSpan(
          text: you,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            color: ink.withValues(alpha: t),
            fontSize: math.max(10, unit * 3),
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Le mot se pose à l'extérieur du cercle, pour ne pas toucher le rang.
      final out = Offset(math.cos(angle), math.sin(angle)) *
          (dot * 2 + label.height * 0.9);
      label.paint(canvas, at + out - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.dots != dots || old.me != me || old.ink != ink || old.you != you;
}
