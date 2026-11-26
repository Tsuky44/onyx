import 'package:flutter/widgets.dart';

import '../../../l10n/locale_formats.dart';
import '../../../l10n/tr.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_blocks.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 7. Les moments : le plus gros marathon, la première séance de l'année et
/// la plus tardive. Sans marathon, le nombre de séances prend sa place.
class RetroMomentsSlide extends RetroSlide {
  const RetroMomentsSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) {
    final title = data.report.marathon?.title ?? data.report.firstPlay?.title;
    return title == null || title.isEmpty
        ? null
        : RetroBands(title.toUpperCase());
  }

  @override
  RetroColors colors(RetroStoryData data) => RetroPalette.moments;

  @override
  bool get centered => true;

  @override
  String summary(RetroStoryData data) {
    final marathon = data.report.marathon;
    if (marathon == null) {
      return trPlural(data.report.plays, '{0} séance cette année.',
          '{0} séances cette année.');
    }
    return tr('{0} épisodes de {1} le même jour.',
        [marathon.episodes, marathon.title]);
  }

  @override
  Widget text(BuildContext context, RetroStoryData data) {
    final marathon = data.report.marathon;
    if (marathon == null) {
      return RetroText(children: [
        RetroKicker(tr('Tes séances')),
        RetroCount(value: data.report.plays),
        RetroLede(trPlural(
            data.report.plays, 'séance cette année.', 'séances cette année.')),
      ]);
    }
    final date = marathon.date;
    return RetroText(children: [
      RetroKicker(tr('Ton plus gros marathon')),
      RetroCount(value: marathon.episodes),
      RetroLede(tr('épisodes de {0} le même jour.', [marathon.title])),
      if (date != null) RetroNote(LocaleFormats.weekdayDate(date)),
    ]);
  }

  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final first = data.report.firstPlay;
    final late = data.report.latestNight;
    if (first == null && late == null) return null;
    return RetroText(children: [
      if (first != null)
        RetroReveal.pop(
          delay: const Duration(milliseconds: 1400),
          child: RetroTicket(
            label: tr('Première séance'),
            title: first.title,
            when: LocaleFormats.shortDateTime(first.at),
          ),
        ),
      if (late != null)
        RetroReveal.pop(
          delay: const Duration(milliseconds: 1600),
          child: RetroTicket(
            label: tr('La plus tardive'),
            title: late.title,
            when: LocaleFormats.shortDateTime(late.at),
          ),
        ),
    ]);
  }
}
