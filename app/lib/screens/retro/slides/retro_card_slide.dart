import 'package:flutter/widgets.dart';

import '../../../l10n/retro_archetypes.dart';
import '../../../l10n/tr.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_card_reveal.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 9. La fin : la carte du titre de l'année se retourne (`RetroCardReveal`),
/// puis le ticket à partager prend la place. Les boutons « Partager
/// l'image » et « Revoir » sont posés par `RetroStoryChrome`, une fois la
/// carte révélée.
class RetroCardSlide extends RetroSlide {
  const RetroCardSlide();

  @override
  RetroColors colors(RetroStoryData data) =>
      RetroPalette.forArchetype(data.report.archetype);

  @override
  String summary(RetroStoryData data) => tr('Ton profil {0} : {1}. {2}', [
        data.report.year,
        retroArchetypeName(data.report.archetype),
        retroArchetypeReason(data.report),
      ]);

  /// Le texte seul, si l'écran se montait sans la carte ; elle le remplace
  /// toujours.
  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      RetroText(children: [
        RetroKicker(tr('Ton titre {0}', [data.report.year])),
        RetroBig(retroArchetypeName(data.report.archetype), size: 13),
        RetroNote(retroArchetypeReason(data.report)),
      ]);

  @override
  Widget compose(BuildContext context, RetroStoryData data) =>
      RetroCardReveal(data: data);
}
