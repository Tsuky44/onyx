import 'package:flutter/widgets.dart';

import '../../../l10n/tr.dart';
import '../../../models/server_activity.dart' show StatBucket;
import '../../../theme/retro_palette.dart';
import '../widgets/retro_blocks.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 8. Les écrans, et ce que le serveur a eu à faire.
class RetroDevicesSlide extends RetroSlide {
  const RetroDevicesSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      const RetroOrbs(RetroPalette.devicesGlows);

  /// Au-delà, presque tout a été lu tel quel.
  static const int _quietYearPercent = 90;

  @override
  RetroColors colors(RetroStoryData data) => RetroPalette.devices;

  String _name(StatBucket device) =>
      device.label.isEmpty ? tr('Un appareil sans nom') : device.label;

  String _headline(RetroStoryData data) {
    final first = data.report.devices.firstOrNull;
    if (first == null) return tr('Tes écrans');
    return tr('{0}, ton fauteuil attitré.', [_name(first)]);
  }

  String _direct(RetroStoryData data) => data.report.directPercent >=
          _quietYearPercent
      ? tr(
          'Presque tout lu tel quel, sans conversion. Ton serveur a eu une année tranquille.')
      : tr(
          'Une partie a été convertie à la volée pour tes appareils. Le serveur a fait le travail.');

  @override
  String summary(RetroStoryData data) =>
      '${_headline(data)} ${tr('Lecture directe : {0} %.', [
            data.report.directPercent
          ])} '
      '${_direct(data)}';

  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      RetroText(children: [
        RetroKicker(tr('Tes écrans')),
        RetroBig(_headline(data), size: 10),
        RetroReveal.pop(
          delay: const Duration(milliseconds: 1300),
          child: RetroCard(
            child: RetroText(children: [
              RetroKicker(
                  tr('Lecture directe · {0} %', [data.report.directPercent])),
              RetroNote(_direct(data),
                  delay: const Duration(milliseconds: 1500)),
            ]),
          ),
        ),
      ]);

  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final total = data.report.watchedSeconds;
    final devices = data.report.devices.take(3).toList();
    if (devices.isEmpty || total <= 0) return null;
    return RetroText(children: [
      for (final (i, device) in devices.indexed)
        RetroReveal.rise(
          delay: Duration(milliseconds: 450 + 180 * i),
          child: RetroMeter(
            label: _name(device),
            percent: (device.watchedSeconds * 100 / total).round(),
            delay: Duration(milliseconds: 450 + 180 * i),
          ),
        ),
    ]);
  }
}
