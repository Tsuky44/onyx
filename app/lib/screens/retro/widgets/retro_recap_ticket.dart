import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/retro_archetypes.dart';
import '../../../l10n/tr.dart';
import '../../../models/retro.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/retro_palette.dart';

/// L'image de récap du Rétro : un ticket de séance au nom du membre, aux
/// couleurs de son profil. Le dernier écran la montre telle qu'elle se
/// partagera (phase 5 de `docs/retro-annuel.md`).
///
/// Dessinée à une taille fixe ([size], 9:16) et sans lire l'écran autour :
/// elle se rend de la même façon dans la story et hors écran, pour l'image
/// en 1080 × 1920 (trois fois [size]).
class RetroRecapTicket extends StatelessWidget {
  const RetroRecapTicket({super.key, required this.report, required this.name});

  final RetroReport report;
  final String name;

  static const Size size = Size(360, 640);

  @override
  Widget build(BuildContext context) {
    final palette = RetroPalette.forArchetype(report.archetype);
    final dark = palette.background;
    final paper = Color.lerp(const Color(0xFFFFFBF5), palette.ink, 0.18)!;
    TextStyle style(double fontSize,
            {FontWeight weight = FontWeight.w600,
            double spacing = 0,
            double alpha = 1,
            Color? color}) =>
        TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: fontSize,
          fontWeight: weight,
          letterSpacing: spacing,
          height: 1.1,
          color: (color ?? dark).withValues(alpha: alpha),
        );
    TextStyle small({double alpha = 0.62}) =>
        style(8.6, spacing: 1.3, alpha: alpha);

    final cells = [
      (tr('Heures'), tr('{0} h', [report.hoursWatched.round()])),
      (tr('Titres'), '${report.titles}'),
      (tr('N°1'), report.top.firstOrNull?.title ?? '—'),
      (tr('Ton heure'), tr('{0} h', [report.peakHour])),
    ];

    return SizedBox.fromSize(
      size: size,
      child: ColoredBox(
        color: palette.ink,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 29, vertical: 45),
          child: ClipPath(
            clipper: const _TicketShape(),
            child: ColoredBox(
              color: paper,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(
                    color: dark,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(25, 19, 25, 17),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Onyx',
                              style: style(19,
                                  weight: FontWeight.w800,
                                  spacing: -0.4,
                                  color: palette.ink)),
                          const Spacer(),
                          Text(
                            tr('Rétro {0}', [report.year]).toUpperCase(),
                            style: style(9.5,
                                spacing: 1.4, color: palette.ink, alpha: 0.9),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(25, 24, 25, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Membre · {0}', [name]).toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: small(alpha: 0.65)),
                          const SizedBox(height: 10),
                          Text(
                            retroArchetypeName(report.archetype),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: style(41,
                                    weight: FontWeight.w800, spacing: -1.3)
                                .copyWith(height: 0.95),
                          ),
                          const Spacer(),
                          for (var row = 0; row < cells.length; row += 2)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final (label, value)
                                      in cells.sublist(row, row + 2))
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(label.toUpperCase(),
                                              style: small()),
                                          const SizedBox(height: 4),
                                          Text(
                                            value,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: style(19,
                                                weight: FontWeight.w800,
                                                spacing: -0.4),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  // Le talon, sous le pointillé, entre les deux encoches.
                  SizedBox(
                    height: 550 * (1 - _TicketShape.stub),
                    child: CustomPaint(
                      painter: _DashLine(dark.withValues(alpha: 0.35)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(25, 26, 25, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: CustomPaint(
                                painter: _Barcode(
                                  color: dark.withValues(alpha: 0.85),
                                  seed: Object.hash(name, report.year),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Deux mentions qui se partagent la ligne : la
                            // plus longue se coupe plutôt que de déborder.
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                      trPlural(report.plays, '{0} séance',
                                              '{0} séances')
                                          .toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: small(alpha: 0.75)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                      tr('Du 1er janvier au 30 novembre')
                                          .toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: small(alpha: 0.75)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le contour du ticket : coins arrondis, une encoche de chaque côté au
/// niveau du talon.
class _TicketShape extends CustomClipper<Path> {
  const _TicketShape();

  /// Où commence le talon, en part de la hauteur.
  static const double stub = 0.72;

  @override
  Path getClip(Size size) {
    final y = size.height * stub;
    final shape = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(14)));
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, y), radius: 16))
      ..addOval(Rect.fromCircle(center: Offset(size.width, y), radius: 16));
    return Path.combine(PathOperation.difference, shape, holes);
  }

  @override
  bool shouldReclip(_TicketShape oldClipper) => false;
}

/// Le pointillé en haut du talon.
class _DashLine extends CustomPainter {
  const _DashLine(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (var x = 22.0; x < size.width - 22; x += 12) {
      canvas.drawLine(Offset(x, 0), Offset(x + 6, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashLine old) => old.color != color;
}

/// Un code-barres décoratif, le même pour un membre et une année.
class _Barcode extends CustomPainter {
  const _Barcode({required this.color, required this.seed});
  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final paint = Paint()..color = color;
    var x = 0.0;
    while (x < size.width) {
      final bar = 1.0 + random.nextInt(3) * 1.2;
      canvas.drawRect(Rect.fromLTWH(x, 0, bar, size.height), paint);
      x += bar + 1.5 + random.nextInt(3) * 1.3;
    }
  }

  @override
  bool shouldRepaint(_Barcode old) => old.color != color || old.seed != seed;
}
