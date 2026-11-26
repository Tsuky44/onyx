import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/locale_formats.dart';
import '../../../l10n/tr.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_blocks.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 7. Les moments : le plus gros marathon en chiffre géant, puis la première
/// séance de l'année et la plus tardive en tickets. Sans marathon, le nombre
/// de séances prend sa place.
class RetroMomentsSlide extends RetroSlide {
  const RetroMomentsSlide();

  /// Des halos plutôt que des bandeaux : le titre du marathon passait derrière
  /// le texte et les tickets, qui se lisaient mal.
  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      const RetroOrbs(RetroPalette.momentsGlows);

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

  String _kicker(RetroStoryData data) => data.report.marathon == null
      ? tr('Tes séances')
      : tr('Ton plus gros marathon');

  int _count(RetroStoryData data) =>
      data.report.marathon?.episodes ?? data.report.plays;

  RetroLede _lede(RetroStoryData data) {
    final marathon = data.report.marathon;
    return RetroLede(marathon == null
        ? trPlural(
            data.report.plays, 'séance cette année.', 'séances cette année.')
        : tr('épisodes de {0} le même jour.', [marathon.title]));
  }

  RetroNote? _date(RetroStoryData data) {
    final date = data.report.marathon?.date;
    return date == null
        ? null
        : RetroNote(LocaleFormats.weekdayDate(date),
            delay: const Duration(milliseconds: 900));
  }

  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      RetroText(children: [
        RetroKicker(_kicker(data)),
        RetroCount(value: _count(data)),
        _lede(data),
        if (_date(data) case final date?) date,
      ]);

  /// Les tickets, du premier au dernier ; [tilt] les pose de biais.
  List<Widget> _tickets(RetroStoryData data, {required bool tilt}) {
    final first = data.report.firstPlay;
    final late = data.report.latestNight;
    final tickets = [
      if (first != null)
        RetroTicket(
          label: tr('Première séance'),
          title: first.title,
          date: LocaleFormats.shortDate(first.at),
          time: LocaleFormats.time(first.at),
        ),
      if (late != null)
        RetroTicket(
          label: tr('La plus tardive'),
          title: late.title,
          date: LocaleFormats.shortDate(late.at),
          time: LocaleFormats.time(late.at),
        ),
    ];
    return [
      for (final (i, ticket) in tickets.indexed)
        RetroReveal.pop(
          delay: Duration(milliseconds: 1300 + 200 * i),
          child: tilt
              ? Transform.rotate(
                  angle: (i.isEven ? -2.5 : 2) * math.pi / 180,
                  child: ticket,
                )
              : ticket,
        ),
    ];
  }

  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final tickets = _tickets(data, tilt: false);
    return tickets.isEmpty ? null : RetroText(children: tickets);
  }

  @override
  Widget? compose(BuildContext context, RetroStoryData data) {
    final units = RetroUnits.of(context);
    if (!units.landscape) return null;
    final u = units.u;
    final size = units.size;
    final padding = units.padding;
    final tickets = _tickets(data, tilt: true);
    final textWidth = size.width * (tickets.isEmpty ? 0.86 : 0.48);
    final date = _date(data);
    return Stack(
      children: [
        Positioned(
          left: padding.left,
          top: padding.top,
          child: RetroKicker(_kicker(data)),
        ),
        Positioned(
          left: padding.left - u * 1.2,
          bottom: padding.bottom + u * (date == null ? 12 : 19),
          width: textWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: RetroCount(value: _count(data), size: 80),
          ),
        ),
        Positioned(
          left: padding.left,
          bottom: padding.bottom + (date == null ? 0 : u * 7),
          width: textWidth - padding.left,
          child: _lede(data),
        ),
        if (date != null)
          Positioned(left: padding.left, bottom: padding.bottom, child: date),
        if (tickets.isNotEmpty)
          Positioned(
            right: padding.right,
            top: padding.top + u * 4,
            bottom: padding.bottom,
            width: size.width * 0.42,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, ticket) in tickets.indexed) ...[
                  if (i > 0) SizedBox(height: u * 7),
                  Padding(
                    padding: EdgeInsets.only(left: i.isOdd ? u * 5 : 0),
                    child: ticket,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
