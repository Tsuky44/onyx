import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/locale_formats.dart';
import '../../../l10n/retro_archetypes.dart';
import '../../../l10n/tr.dart';
import '../../../models/retro.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/retro_palette.dart';
import '../../settings/widgets/settings_ui.dart' show formatWatchTime;
import '../characters/retro_character.dart';

/// L'image de récap du Rétro : un ticket de séance au nom du membre, aux
/// couleurs de son profil. Le dernier écran la montre telle qu'elle se
/// partagera (phase 5 de `docs/retro-annuel.md`).
///
/// L'année tient dessus : le profil et sa raison, le top 3, six chiffres, et
/// un talon. Rien qui vienne du réseau (pas d'affiche) : elle se dessine d'une
/// seule passe, hors écran, en 1080 × 1920 (trois fois [size]).
class RetroRecapTicket extends StatelessWidget {
  const RetroRecapTicket({super.key, required this.report, required this.name});

  final RetroReport report;
  final String name;

  static const Size size = Size(360, 640);

  /// Le ticket dans l'image : une marge de la couleur du profil autour.
  static const EdgeInsets margin =
      EdgeInsets.symmetric(horizontal: 16, vertical: 26);

  @override
  Widget build(BuildContext context) {
    final palette = RetroPalette.forArchetype(report.archetype);
    final dark = palette.background;
    final paper = Color.lerp(const Color(0xFFFFFBF5), palette.ink, 0.16)!;
    final text = _Type(dark);
    final server = report.server;
    final marathon = report.marathon;

    final cells = <(String, String)>[
      (
        tr('Heures'),
        tr('{0} h', [LocaleFormats.integer(report.hoursWatched.round())])
      ),
      (tr('Titres'), '${report.titles}'),
      (tr('Séances'), LocaleFormats.integer(report.plays)),
      (tr('Ton heure'), tr('{0} h', [report.peakHour])),
      (
        tr('Mois record'),
        _capitalized(
            LocaleFormats.month(DateTime(report.year, report.bestMonth))),
      ),
      if (server.members >= 2 && server.rank > 0)
        (tr('Ta place'), tr('n°{0} sur {1}', [server.rank, server.members]))
      else if (marathon != null)
        (
          tr('Marathon'),
          trPlural(marathon.episodes, '{0} épisode', '{0} épisodes')
        )
      else
        (tr('Films'), '${(report.movieSeconds / 3600).round()} h'),
    ];

    return SizedBox.fromSize(
      size: size,
      child: ColoredBox(
        color: palette.ink,
        child: Padding(
          padding: margin,
          child: ClipPath(
            clipper: const _TicketShape(),
            child: ColoredBox(
              color: paper,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // L'en-tête : la marque et l'année, en négatif.
                  ColoredBox(
                    color: dark,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 16, 22, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Onyx',
                              style: text.style(20,
                                  weight: FontWeight.w800,
                                  spacing: -0.4,
                                  color: palette.ink)),
                          const Spacer(),
                          Text(
                            tr('Rétro {0}', [report.year]).toUpperCase(),
                            style: text.style(9.5,
                                spacing: 1.4, color: palette.ink, alpha: 0.9),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Le profil, et son personnage en médaillon,
                          // comme un tampon d'entrée.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        tr('Membre · {0}', [name])
                                            .toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.small(alpha: 0.65)),
                                    const SizedBox(height: 8),
                                    Text(
                                      retroArchetypeName(report.archetype),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: text
                                          .style(32,
                                              weight: FontWeight.w800,
                                              spacing: -1.2)
                                          .copyWith(height: 0.95),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      retroArchetypeReason(report),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: text
                                          .style(11.5,
                                              weight: FontWeight.w500,
                                              alpha: 0.75)
                                          .copyWith(height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _Badge(
                                archetype: report.archetype,
                                ink: palette.ink,
                                rim: dark,
                              ),
                            ],
                          ),
                          // La place qui reste va entre le profil et la
                          // suite : le bas du ticket reste calé sur le talon.
                          const Spacer(),
                          _Rule(color: dark),
                          const SizedBox(height: 12),
                          Text(
                              tr('Ton top {0}', [
                                math.min(5, report.top.length)
                              ]).toUpperCase(),
                              style: text.small()),
                          const SizedBox(height: 6),
                          for (final (i, title) in report.top.take(5).indexed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    child: Text('${i + 1}',
                                        style: text.style(16,
                                            weight: FontWeight.w800,
                                            color: i == 0
                                                ? palette.accent
                                                : null)),
                                  ),
                                  Expanded(
                                    child: Text(
                                      title.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.style(15.5,
                                          weight: FontWeight.w700,
                                          spacing: -0.2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(formatWatchTime(title.watchedSeconds),
                                      style: text.style(11.5, alpha: 0.65)),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          _Rule(color: dark),
                          const SizedBox(height: 12),
                          for (var row = 0; row < cells.length; row += 3)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final (label, value) in cells.sublist(
                                      row, math.min(row + 3, cells.length)))
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(label.toUpperCase(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: text.small()),
                                          const SizedBox(height: 3),
                                          Text(
                                            value,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: text.style(18,
                                                weight: FontWeight.w800,
                                                spacing: -0.3),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Le talon, sous le pointillé, entre les deux encoches.
                  SizedBox(
                    height: (size.height - margin.vertical) *
                        (1 - _TicketShape.stub),
                    child: CustomPaint(
                      painter: _DashLine(dark.withValues(alpha: 0.35)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
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
                            const SizedBox(height: 10),
                            // Deux mentions qui se partagent la ligne : la
                            // plus longue se coupe plutôt que de déborder.
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                      'onyx · ${report.year}'.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.small(alpha: 0.75)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                      // La période en dates courtes : « 1 JANV.
                                      // → 30 NOV. », qui tient sur la ligne.
                                      '${LocaleFormats.shortDate(DateTime(report.year))} → '
                                              '${LocaleFormats.shortDate(DateTime(report.year, 11, 30))}'
                                          .toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: text.small(alpha: 0.75)),
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

/// Le personnage du profil dans un médaillon rond, de biais : le haut du
/// corps, sur un dégradé de l'encre du profil.
class _Badge extends StatelessWidget {
  const _Badge({required this.archetype, required this.ink, required this.rim});

  final RetroArchetype archetype;
  final Color ink;
  final Color rim;

  static const double size = 84;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: 6 * math.pi / 180,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: rim, width: 3),
            gradient: RadialGradient(
              center: const Alignment(0, -0.2),
              colors: [Color.lerp(ink, const Color(0xFFFFFFFF), 0.4)!, ink],
            ),
          ),
          child: ClipOval(
            child: OverflowBox(
              maxWidth: size * 1.2,
              maxHeight: size * 1.2 * 1.3,
              alignment: const Alignment(0, -0.35),
              child: RetroCharacter(archetype: archetype),
            ),
          ),
        ),
      );
}

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// Les styles du ticket : une seule police, l'encre du profil.
class _Type {
  const _Type(this.ink);
  final Color ink;

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
        color: (color ?? ink).withValues(alpha: alpha),
      );

  /// Les petites capitales des intitulés.
  TextStyle small({double alpha = 0.6}) =>
      style(8.6, spacing: 1.3, alpha: alpha);
}

/// Un filet entre deux parties du ticket.
class _Rule extends StatelessWidget {
  const _Rule({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 1, child: ColoredBox(color: color.withValues(alpha: 0.18)));
}

/// Le contour du ticket : coins arrondis, une encoche de chaque côté au
/// niveau du talon.
class _TicketShape extends CustomClipper<Path> {
  const _TicketShape();

  /// Où commence le talon, en part de la hauteur.
  static const double stub = 0.84;

  @override
  Path getClip(Size size) {
    final y = size.height * stub;
    final shape = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(14)));
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, y), radius: 13))
      ..addOval(Rect.fromCircle(center: Offset(size.width, y), radius: 13));
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
    for (var x = 18.0; x < size.width - 18; x += 12) {
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
