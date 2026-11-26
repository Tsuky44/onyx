import 'package:flutter/widgets.dart';

import '../../../l10n/tr.dart';
import '../../../models/retro.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_charts.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 5. Quand on regarde : l'horloge des 24 heures.
class RetroHourSlide extends RetroSlide {
  const RetroHourSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      const RetroOrbs(RetroPalette.hourGlows);

  @override
  RetroColors colors(RetroStoryData data) => RetroPalette.hour;

  /// La même borne que le profil « Oiseau de nuit ».
  static const double _nightOwlShare = 0.4;

  static String headline(RetroReport report) {
    if (report.nightShare > _nightOwlShare) return tr('La nuit t’appartient.');
    final peak = report.peakHour;
    if (peak >= 5 && peak < 12) return tr('Le matin, avant tout le monde.');
    if (peak >= 12 && peak < 18) return tr('L’après-midi, tranquillement.');
    return tr('Le soir, après la journée.');
  }

  String _night(RetroReport report) => tr(
      '{0} % de ton temps entre 22 h et 4 h.',
      [(report.nightShare * 100).round()]);

  @override
  String summary(RetroStoryData data) =>
      '${headline(data.report)} ${tr('Ton heure : {0} h.', [
            data.report.peakHour
          ])} '
      '${_night(data.report)}';

  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      RetroText(children: [
        RetroKicker(tr('Quand tu regardes')),
        RetroBig(headline(data.report), size: 11),
        RetroNote(_night(data.report)),
      ]);

  @override
  Widget? visual(BuildContext context, RetroStoryData data) =>
      RetroClockChart(hours: data.report.hours, peak: data.report.peakHour);
}
