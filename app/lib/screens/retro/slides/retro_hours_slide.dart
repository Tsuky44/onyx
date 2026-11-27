import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/locale_formats.dart';
import '../../../l10n/tr.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 2. Le temps passé, en heures, et ce qu'il représente : le chiffre en très
/// grand, les équivalences entre des filets (à droite sur un écran large,
/// dessous sur un téléphone).
class RetroHoursSlide extends RetroSlide {
  const RetroHoursSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      const RetroOrbs(RetroPalette.hoursGlows);

  /// Un film dure deux heures, en gros : de quoi parler d'« équivalent ».
  static const double _hoursPerFilm = 2;

  @override
  RetroColors colors(RetroStoryData data) => RetroPalette.hours;

  int _hours(RetroStoryData data) => data.report.hoursWatched.round();

  /// « 13 » au-delà de dix jours, « 4,5 » en deçà.
  static String _days(double days) => days >= 10
      ? '${days.round()}'
      : LocaleFormats.decimal(days.toStringAsFixed(1));

  @override
  String summary(RetroStoryData data) =>
      trPlural(_hours(data), '{0} heure de lecture.', '{0} heures de lecture.');

  RetroLede _unit(RetroStoryData data) {
    final hours = _hours(data);
    return RetroLede(
        trPlural(hours, 'heure de lecture.', 'heures de lecture.'));
  }

  @override
  Widget text(BuildContext context, RetroStoryData data) {
    return RetroText(children: [
      RetroKicker(tr('Temps passé devant Onyx')),
      RetroCount(value: _hours(data)),
      _unit(data),
    ]);
  }

  /// Les équivalences, la valeur en grand et ce qu'elle veut dire dessous.
  List<(String, String)> _figures(RetroStoryData data) {
    final report = data.report;
    final days = report.hoursWatched / 24;
    final films = (report.hoursWatched / _hoursPerFilm).floor();
    final ahead = report.server.aheadOfPercent;
    return [
      if (days >= 1)
        (
          '≈ ${_days(days)}',
          trPlural(days >= 2 ? 2 : 1, 'jour entier, mis bout à bout',
              'jours entiers, mis bout à bout'),
        ),
      if (films >= 1)
        (
          '≈ $films',
          trPlural(films, 'film de deux heures', 'films de deux heures'),
        ),
      if (ahead >= 50)
        (
          tr('{0} %', [ahead]),
          tr('des membres de ton serveur en ont vu moins'),
        ),
    ];
  }

  /// Les équivalences empilées entre leurs filets, puis la note quand le
  /// classement n'a rien de flatteur à dire.
  Widget _figureList(RetroStoryData data, double u) {
    final figures = _figures(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (value, label)) in figures.indexed)
          RetroReveal.rise(
            delay: Duration(milliseconds: 1200 + 150 * i),
            child: _Figure(value: value, label: label, last: false),
          ),
        if (figures.isNotEmpty) const _Figure(value: '', label: '', last: true),
        if (data.report.server.aheadOfPercent < 50) ...[
          SizedBox(height: u * 3),
          RetroNote(
            delay: const Duration(milliseconds: 1650),
            tr('Pas forcément beaucoup, mais bien choisies.'),
          ),
        ],
      ],
    );
  }

  /// Sur un écran large, le chiffre ancré en bas à gauche et les équivalences
  /// à droite ; sur un téléphone, le chiffre sur toute la largeur et les
  /// équivalences dessous, le tout centré dans la hauteur : de petites
  /// pastilles sous un chiffre centré laissaient un trou au milieu de l'écran.
  @override
  Widget? compose(BuildContext context, RetroStoryData data) {
    final units = RetroUnits.of(context);
    final u = units.u;
    final padding = units.padding;
    final size = units.size;
    if (!units.landscape) {
      return Padding(
        padding: padding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RetroKicker(tr('Temps passé devant Onyx')),
            SizedBox(height: u * 2),
            // Le chiffre prend la largeur, et se réduit à quatre chiffres.
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: RetroCount(value: _hours(data), size: 46),
              ),
            ),
            _unit(data),
            SizedBox(height: u * 8),
            _figureList(data, u),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Positioned(
          left: padding.left,
          top: padding.top,
          child: RetroKicker(tr('Temps passé devant Onyx')),
        ),
        // Le chiffre se réduit plutôt que de passer sous les équivalences
        // quand il a quatre chiffres.
        Positioned(
          left: padding.left - u * 1.2,
          bottom: padding.bottom + u * 9,
          width: size.width * 0.56,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: RetroCount(value: _hours(data), size: 82),
          ),
        ),
        Positioned(
          left: padding.left,
          bottom: padding.bottom,
          width: size.width * 0.56,
          child: _unit(data),
        ),
        Positioned(
          right: padding.right,
          top: size.height * 0.22,
          width: size.width * 0.29,
          child: _figureList(data, u),
        ),
      ],
    );
  }
}

/// Une équivalence : la valeur en grand, ce qu'elle veut dire dessous, entre
/// deux filets. La dernière ligne ([last]) ne porte que le filet du bas.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, required this.last});
  final String value;
  final String label;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final ink =
        DefaultTextStyle.of(context).style.color ?? const Color(0xFFFFFFFF);
    final rule = BorderSide(color: ink.withValues(alpha: 0.28));
    if (last) {
      return DecoratedBox(
        decoration: BoxDecoration(border: Border(top: rule)),
        child: const SizedBox(height: 0),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: rule)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: u * 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              style: RetroBig.styleOf(context, 12).copyWith(height: 1),
            ),
            SizedBox(height: u),
            Opacity(
              opacity: 0.8,
              child: Text(
                label,
                style: TextStyle(fontSize: math.max(12, u * 4), height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
