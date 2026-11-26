import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/locale_formats.dart';
import '../../../l10n/tr.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_charts.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 6. L'année mois par mois, et le mois record. Sur un écran large, les
/// douze barres courent sur toute la largeur, sous le titre.
class RetroMonthsSlide extends RetroSlide {
  const RetroMonthsSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      const RetroRings(Alignment(0.76, -0.76));

  @override
  RetroColors colors(RetroStoryData data) => RetroPalette.months;

  String _month(RetroStoryData data) =>
      LocaleFormats.month(DateTime(data.report.year, data.report.bestMonth));

  int _bestHours(RetroStoryData data) =>
      (data.report.months[data.report.bestMonth - 1] / 3600).round();

  String _headline(RetroStoryData data) {
    final month = _month(data);
    return tr('{0}, ton mois record.',
        [month.isEmpty ? month : month[0].toUpperCase() + month.substring(1)]);
  }

  String _note(RetroStoryData data) => trPlural(_bestHours(data),
      '{0} heure en {1}.', '{0} heures en {1}.', [_month(data)]);

  @override
  String summary(RetroStoryData data) => '${_headline(data)} ${_note(data)}';

  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      RetroText(children: [
        RetroKicker(tr('Mois par mois')),
        RetroBig(_headline(data), size: 11),
        RetroNote(_note(data)),
      ]);

  @override
  Widget? visual(BuildContext context, RetroStoryData data) => RetroMonthsChart(
        months: data.report.months,
        year: data.report.year,
        best: data.report.bestMonth,
      );

  @override
  Widget? compose(BuildContext context, RetroStoryData data) {
    final units = RetroUnits.of(context);
    if (!units.landscape) return null;
    final u = units.u;
    final size = units.size;
    final padding = units.padding;
    return Stack(
      children: [
        Positioned(
          left: padding.left,
          right: padding.right,
          top: padding.top,
          child: RetroText(children: [
            RetroKicker(tr('Mois par mois')),
            RetroBig(_headline(data), size: 13.5),
          ]),
        ),
        Positioned(
          left: padding.left,
          right: padding.right,
          bottom: padding.bottom,
          height: size.height * 0.58,
          child: RetroMonthsChart(
            months: data.report.months,
            year: data.report.year,
            best: data.report.bestMonth,
            fill: true,
            labelSize: math.max(11, u * 3.2),
            valueSize: math.max(16, u * 7.4),
          ),
        ),
      ],
    );
  }
}
