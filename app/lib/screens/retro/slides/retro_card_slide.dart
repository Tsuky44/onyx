import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/locale_formats.dart';
import '../../../l10n/retro_archetypes.dart';
import '../../../l10n/tr.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_blocks.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 10. La carte de fin : le profil, et l'année résumée en six chiffres. C'est
/// elle qui se partagera en image (phase 5 de `docs/retro-annuel.md`).
class RetroCardSlide extends RetroSlide {
  const RetroCardSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      RetroOrbs(RetroPalette.glowsFor(colors(data)));

  @override
  bool get confetti => true;

  @override
  RetroColors colors(RetroStoryData data) =>
      RetroPalette.forArchetype(data.report.archetype);

  @override
  String summary(RetroStoryData data) => tr('Ton profil {0} : {1}. {2}', [
        data.report.year,
        retroArchetypeName(data.report.archetype),
        retroArchetypeReason(data.report),
      ]);

  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      RetroText(children: [
        RetroKicker(tr('Ton profil {0}', [data.report.year])),
        RetroBig(retroArchetypeName(data.report.archetype), size: 13),
        RetroNote(retroArchetypeReason(data.report)),
      ]);

  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final report = data.report;
    final u = RetroUnits.of(context).u;
    final cells = <(String, String)>[
      (tr('Heures'), tr('{0} h', [report.hoursWatched.round()])),
      (tr('Titres'), '${report.titles}'),
      (tr('N°1'), report.top.firstOrNull?.title ?? '—'),
      (tr('Ton heure'), tr('{0} h', [report.peakHour])),
      (
        tr('Mois record'),
        _capitalized(
            LocaleFormats.month(DateTime(report.year, report.bestMonth)))
      ),
      (
        tr('Écran'),
        report.devices.firstOrNull?.label.isNotEmpty == true
            ? report.devices.first.label
            : '—'
      ),
    ];
    final valueStyle = TextStyle(
      fontSize: math.max(13, u * 4),
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    return RetroReveal.pop(
        delay: const Duration(milliseconds: 1100),
        child: RetroCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var row = 0; row < cells.length; row += 2) ...[
                if (row > 0) SizedBox(height: u * 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final cell in cells.sublist(row, row + 2))
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RetroKicker(cell.$1),
                            SizedBox(height: u * 0.6),
                            Text(cell.$2,
                                style: valueStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              SizedBox(height: u * 3.5),
              RetroKicker(tr('Onyx · Rétro {0}', [report.year])),
            ],
          ),
        ));
  }
}

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
