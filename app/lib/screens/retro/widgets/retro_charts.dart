import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/locale_formats.dart';
import '../../../l10n/tr.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/retro_motion.dart';
import 'retro_entrance.dart';
import 'retro_type.dart';

/// L'horloge de « Ton heure » : 24 barres autour d'un cadran, l'heure de pointe
/// au centre. Peinte, sans image.
class RetroClockChart extends StatelessWidget {
  const RetroClockChart({
    super.key,
    required this.hours,
    required this.peak,
    this.size,
    this.showPeak = true,
  });

  /// 24 totaux, minuit d'abord.
  final List<int> hours;
  final int peak;

  /// Le diamètre ; sans lui, l'horloge prend sa place à elle (74 unités au
  /// plus).
  final double? size;

  /// L'heure de pointe écrite au centre. Un écran large l'écrit en grand à
  /// côté, et laisse le cadran vide.
  final bool showPeak;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final ink =
        DefaultTextStyle.of(context).style.color ?? const Color(0xFFFFFFFF);
    return Semantics(
      label: tr('Répartition par heure, pic à {0} h', [peak]),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: size ?? u * 74,
          maxHeight: size ?? u * 74,
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ClockPainter(
                    hours: hours,
                    ink: ink,
                    unit: u,
                    entrance: RetroEntrance.of(context),
                  ),
                ),
              ),
              if (showPeak)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RetroBig(tr('{0} h', [peak]), size: 9),
                    SizedBox(height: u),
                    RetroKicker(tr('Ton heure')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({
    required this.hours,
    required this.ink,
    required this.unit,
    required this.entrance,
  }) : super(repaint: entrance);

  final List<int> hours;
  final Color ink;
  final double unit;

  /// L'horloge d'entrée de l'écran : les barres sortent du cadran l'une
  /// après l'autre, dans le sens des aiguilles.
  final Animation<double> entrance;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    // Les heures s'écrivent dans le cadran, sous les barres : le cercle
    // intérieur s'élargit pour elles, et les barres gagnent la place que les
    // étiquettes prenaient dehors.
    final inner = radius * 0.42;
    final outer = radius * 0.97;
    final top = hours.fold<int>(0, math.max);
    final step = 2 * math.pi / 24;
    for (var h = 0; h < 24; h++) {
      final grow = _grow(entrance.value,
          delay: const Duration(milliseconds: 450) + _clockStagger * h,
          duration: const Duration(milliseconds: 700));
      final share = top > 0 ? hours[h] / top : 0.0;
      final reach = inner + (outer - inner) * share * grow;
      final start = h * step - math.pi / 2;
      final sweep = step * 0.72;
      final path = Path()
        ..arcTo(
            Rect.fromCircle(center: center, radius: reach), start, sweep, true)
        ..arcTo(Rect.fromCircle(center: center, radius: inner), start + sweep,
            -sweep, false)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = ink.withValues(
              alpha: (0.22 + 0.78 * share) * grow.clamp(0.0, 1.0)),
      );
    }
    final labelSize = math.max(9.0, radius * 0.075);
    final labelStyle = TextStyle(
      fontFamily: AppTheme.fontFamily,
      color: ink.withValues(alpha: 0.7),
      fontSize: labelSize,
      fontWeight: FontWeight.w600,
    );
    for (final h in const [0, 6, 12, 18]) {
      final angle = h * step - math.pi / 2;
      final at = center +
          Offset(math.cos(angle), math.sin(angle)) * (inner - labelSize * 1.3);
      final painter = TextPainter(
        text: TextSpan(text: tr('{0} h', [h]), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
    }
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.hours != hours || old.ink != ink || old.unit != unit;
}

const Duration _clockStagger = Duration(milliseconds: 35);

/// La part déjà poussée d'une barre qui commence après [delay], d'après la
/// valeur [t] de l'horloge d'entrée.
double _grow(double t, {required Duration delay, required Duration duration}) {
  final total = RetroMotion.entrance.inMicroseconds;
  final start = delay.inMicroseconds / total;
  final end = (delay + duration).inMicroseconds / total;
  if (t <= start) return 0;
  if (t >= end) return 1;
  return RetroMotion.back.transform((t - start) / (end - start));
}

/// « Mois par mois » : douze barres, le mois record en plein.
class RetroMonthsChart extends StatelessWidget {
  const RetroMonthsChart({
    super.key,
    required this.months,
    required this.year,
    required this.best,
    this.fill = false,
    this.labelSize,
    this.valueSize,
  });

  /// Prend toute la place donnée au lieu de garder ses proportions : les
  /// barres d'un écran large courent sur toute sa largeur.
  final bool fill;

  /// La taille des initiales des mois et celle des heures du mois record ;
  /// par défaut, une petite étiquette pour les deux.
  final double? labelSize;
  final double? valueSize;

  /// 12 totaux en secondes.
  final List<int> months;
  final int year;

  /// Le mois record, de 1 à 12.
  final int best;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final ink =
        DefaultTextStyle.of(context).style.color ?? const Color(0xFFFFFFFF);
    final initials = [
      for (var m = 1; m <= 12; m++)
        LocaleFormats.month(DateTime(year, m)).characters.first.toUpperCase(),
    ];
    return Semantics(
      label: tr('Heures par mois, record en {0}',
          [LocaleFormats.month(DateTime(year, best))]),
      child: _sized(
        CustomPaint(
          painter: _MonthsPainter(
            months: months,
            best: best - 1,
            ink: ink,
            labelSize: labelSize ?? math.max(9.0, u * 2.6),
            valueSize: valueSize ?? math.max(9.0, u * 2.6),
            initials: initials,
            entrance: RetroEntrance.of(context),
          ),
        ),
      ),
    );
  }
}

extension on RetroMonthsChart {
  Widget _sized(Widget chart) => fill
      ? SizedBox.expand(child: chart)
      : AspectRatio(aspectRatio: 300 / 170, child: chart);
}

class _MonthsPainter extends CustomPainter {
  _MonthsPainter({
    required this.months,
    required this.best,
    required this.ink,
    required this.labelSize,
    required this.valueSize,
    required this.initials,
    required this.entrance,
  }) : super(repaint: entrance);

  /// Les barres poussent de gauche à droite.
  final Animation<double> entrance;
  final List<int> months;
  final int best;
  final Color ink;
  final double labelSize;
  final double valueSize;
  final List<String> initials;

  @override
  void paint(Canvas canvas, Size size) {
    final labelBand = labelSize * 1.8;
    final valueBand = valueSize * 1.6;
    final chartHeight = size.height - labelBand - valueBand;
    final top = months.fold<int>(0, math.max);
    final barWidth = size.width / 12 * 0.6;
    final gap = (size.width - barWidth * 12) / 11;
    TextPainter label(String text, double alpha, FontWeight weight,
            [double? fontSize]) =>
        TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: ink.withValues(alpha: alpha),
              fontSize: fontSize ?? labelSize,
              fontWeight: weight,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

    for (var i = 0; i < 12; i++) {
      final isBest = i == best;
      final share = top > 0 ? months[i] / top : 0.0;
      final grow = _grow(entrance.value,
          delay: Duration(milliseconds: 450 + 60 * i),
          duration: const Duration(milliseconds: 900));
      final height = math.max(3.0, chartHeight * share) * grow;
      final left = i * (barWidth + gap);
      final bottom = valueBand + chartHeight;
      // Décembre n'est pas compté (l'année s'arrête au 30 novembre) : une
      // barre en creux plutôt qu'un mois vide.
      final notCounted = i == 11 && months[i] == 0;
      final barHeight =
          notCounted ? math.max(3.0, chartHeight * 0.06) * grow : height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, bottom - barHeight, barWidth, barHeight),
          Radius.circular(math.min(barWidth * 0.28, barHeight / 2)),
        ),
        notCounted
            ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = ink.withValues(alpha: 0.4))
            : (Paint()..color = ink.withValues(alpha: isBest ? 1 : 0.3)),
      );
      final initial = label(initials[i], isBest ? 1 : 0.6, FontWeight.w600);
      initial.paint(
          canvas,
          Offset(
              left + (barWidth - initial.width) / 2, bottom + labelSize * 0.5));
      if (isBest && top > 0 && grow >= 1) {
        final value = label(tr('{0} h', [(months[i] / 3600).round()]), 1,
            FontWeight.w800, valueSize);
        value.paint(
          canvas,
          Offset(left + (barWidth - value.width) / 2,
              bottom - height - value.height - valueSize * 0.15),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MonthsPainter old) =>
      old.months != months ||
      old.ink != ink ||
      old.labelSize != labelSize ||
      old.valueSize != valueSize;
}
