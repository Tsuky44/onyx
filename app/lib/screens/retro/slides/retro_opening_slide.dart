import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/tr.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_poster_wall.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 1. L'ouverture : le prénom et l'année en très grand, ancrés en bas à
/// gauche, devant un mur des affiches de l'année qui défile — à droite sur un
/// écran large, en haut sur un téléphone.
class RetroOpeningSlide extends RetroSlide {
  const RetroOpeningSlide();

  @override
  RetroColors colors(RetroStoryData data) =>
      RetroPalette.forArchetype(data.report.archetype);

  @override
  String summary(RetroStoryData data) =>
      tr('{0}, ton année {1} sur Onyx.', [data.name, data.report.year]);

  @override
  Widget backdrop(BuildContext context, RetroStoryData data) {
    final palette = colors(data);
    return RetroPosterWall(
      titles: data.report.top,
      serverBaseUrl: data.serverBaseUrl,
      background: palette.background,
      glows: RetroPalette.glowsFor(palette),
    );
  }

  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      _text(data, size: 17);

  Widget _text(RetroStoryData data, {required double size}) =>
      RetroText(children: [
        RetroKicker(tr('Rétro {0}', [data.report.year])),
        RetroBig(tr('{0},\nton année\nsur Onyx.', [data.name]), size: size),
        RetroNote(
            tr('Une année de séances, racontée par ton propre historique.')),
      ]);

  /// Le texte au pied de l'écran, sur la moitié gauche en paysage : le mur
  /// tient le reste. Le titre grandit avec la place, et le tout se réduit
  /// plutôt que de déborder d'une petite fenêtre.
  @override
  Widget compose(BuildContext context, RetroStoryData data) {
    final units = RetroUnits.of(context);
    final u = units.u;
    final padding = units.landscape
        ? units.padding.copyWith(bottom: units.padding.bottom + u * 6)
        : units.padding;
    final room = units.size.width - padding.horizontal;
    final width =
        units.landscape ? units.size.width * 0.5 - padding.left : room;
    // « ton année » fait un peu plus de cinq fois la taille du titre.
    final size = units.landscape ? math.min(23.0, width / u / 5.2) : 17.0;
    return Padding(
      padding: padding,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomLeft,
        child: SizedBox(width: width, child: _text(data, size: size)),
      ),
    );
  }
}
