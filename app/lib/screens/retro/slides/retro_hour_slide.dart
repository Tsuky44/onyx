import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/tr.dart';
import '../../../models/retro.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_charts.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 5. Quand on regarde : l'horloge des 24 heures. Sur un écran large,
/// l'horloge en très grand sort du cadre à droite, et l'heure de pointe
/// s'écrit en chiffre géant à gauche.
class RetroHourSlide extends RetroSlide {
  const RetroHourSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      const RetroOrbs(RetroPalette.hourGlows);

  @override
  RetroColors colors(RetroStoryData data) => RetroPalette.hour;

  /// La même borne que le profil « Noctambule ».
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
        RetroBig(tr('{0} h', [data.report.peakHour]), size: 24),
        RetroBig(headline(data.report),
            size: 9, delay: const Duration(milliseconds: 500)),
        RetroNote(_night(data.report),
            delay: const Duration(milliseconds: 1100)),
      ]);

  /// Le cadran reste vide : les heures s'y écrivent, et l'heure de pointe
  /// est déjà en grand au-dessus. Sur un téléphone, il prend toute la place
  /// sous le texte plutôt qu'une taille fixe qui le laissait perdu au milieu.
  @override
  Widget? visual(BuildContext context, RetroStoryData data) => LayoutBuilder(
        builder: (context, box) => RetroClockChart(
          hours: data.report.hours,
          peak: data.report.peakHour,
          showPeak: false,
          size: math.min(box.maxWidth, box.maxHeight),
        ),
      );

  @override
  Widget? compose(BuildContext context, RetroStoryData data) {
    final units = RetroUnits.of(context);
    if (!units.landscape) return null;
    final size = units.size;
    final padding = units.padding;
    final report = data.report;
    // Le cadran garde la moitié droite : il déborde du bord, jamais sur le
    // texte.
    final diameter = math.min(size.height, size.width * 0.55);
    final textWidth = size.width * 0.46 - padding.left;
    return Stack(
      children: [
        Positioned(
          right: -size.width * 0.12,
          top: (size.height - diameter) / 2,
          width: diameter,
          height: diameter,
          child: RetroClockChart(
            hours: report.hours,
            peak: report.peakHour,
            size: diameter,
            showPeak: false,
          ),
        ),
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
              child: RetroText(children: [
                RetroKicker(tr('Quand tu regardes')),
                RetroBig(tr('{0} h', [report.peakHour]), size: 40),
                RetroBig(headline(report),
                    size: 13.5, delay: const Duration(milliseconds: 500)),
                RetroNote(_night(report),
                    delay: const Duration(milliseconds: 1100)),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}
