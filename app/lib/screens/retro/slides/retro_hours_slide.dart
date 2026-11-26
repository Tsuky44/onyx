import 'package:flutter/widgets.dart';

import '../../../l10n/locale_formats.dart';
import '../../../l10n/tr.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 2. Le temps passé, en heures, et ce qu'il représente.
class RetroHoursSlide extends RetroSlide {
  const RetroHoursSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      RetroBands(tr('{0} H', [_hours(data)]));

  /// Un film dure deux heures, en gros : de quoi parler d'« équivalent ».
  static const double _hoursPerFilm = 2;

  @override
  RetroColors colors(RetroStoryData data) => RetroPalette.hours;

  @override
  bool get centered => true;

  int _hours(RetroStoryData data) => data.report.hoursWatched.round();

  @override
  String summary(RetroStoryData data) =>
      trPlural(_hours(data), '{0} heure de lecture.', '{0} heures de lecture.');

  @override
  Widget text(BuildContext context, RetroStoryData data) {
    final hours = _hours(data);
    return RetroText(children: [
      RetroKicker(tr('Temps passé devant Onyx')),
      RetroCount(value: hours),
      RetroLede(trPlural(hours, 'heure de lecture.', 'heures de lecture.')),
    ]);
  }

  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final report = data.report;
    final days = report.hoursWatched / 24;
    final films = (report.hoursWatched / _hoursPerFilm).floor();
    final ahead = report.server.aheadOfPercent;
    final u = RetroUnits.of(context).u;
    return RetroText(children: [
      Wrap(
        spacing: u * 2,
        runSpacing: u * 2,
        children: [
          if (days >= 1)
            RetroReveal.pop(
              delay: const Duration(milliseconds: 1300),
              child: RetroChip(
                tr('≈ {0} jours entiers',
                    [LocaleFormats.decimal(days.toStringAsFixed(1))]),
                solid: true,
              ),
            ),
          if (films >= 1)
            RetroReveal.pop(
              delay: const Duration(milliseconds: 1450),
              child: RetroChip(trPlural(films, '≈ {0} film', '≈ {0} films')),
            ),
        ],
      ),
      RetroNote(
          delay: const Duration(milliseconds: 1650),
          ahead >= 50
              ? tr('Plus que {0} % des membres de ton serveur.', [ahead])
              : tr('Pas forcément beaucoup, mais bien choisies.')),
    ]);
  }
}
