import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/retro_archetypes.dart';
import '../../../l10n/tr.dart';
import '../../../theme/retro_motion.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_recap_ticket.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 9. La fin : le profil en grand, et l'image de récap — un ticket au nom du
/// membre — posée à côté comme une carte qu'on vient de recevoir. Ce qu'on
/// voit est ce qui se partagera (phase 5 de `docs/retro-annuel.md`).
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

  RetroText _text(RetroStoryData data, {required double size}) =>
      RetroText(children: [
        RetroKicker(tr('Ton profil {0}', [data.report.year])),
        RetroBig(retroArchetypeName(data.report.archetype), size: size),
        RetroNote(retroArchetypeReason(data.report)),
      ]);

  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      _text(data, size: 13);

  Widget _ticket(RetroStoryData data) => _DealIn(
        child: FittedBox(
          child: RetroRecapTicket(report: data.report, name: data.name),
        ),
      );

  @override
  Widget? visual(BuildContext context, RetroStoryData data) => AspectRatio(
        aspectRatio: RetroRecapTicket.size.width / RetroRecapTicket.size.height,
        child: _ticket(data),
      );

  @override
  Widget? compose(BuildContext context, RetroStoryData data) {
    final units = RetroUnits.of(context);
    if (!units.landscape) return null;
    final size = units.size;
    final padding = units.padding;
    final ratio = RetroRecapTicket.size.width / RetroRecapTicket.size.height;
    final height = math.min(size.height * 0.82, size.width * 0.4 / ratio);
    final textWidth = size.width * 0.5 - padding.left;
    return Stack(
      children: [
        Positioned(
          left: padding.left,
          top: padding.top,
          bottom: padding.bottom,
          width: textWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SizedBox(width: textWidth, child: _text(data, size: 21)),
          ),
        ),
        Positioned(
          right: size.width * 0.09,
          top: (size.height - height) / 2,
          width: height * ratio,
          height: height,
          child: _ticket(data),
        ),
      ],
    );
  }
}

/// Le ticket arrive d'en bas en tournant, comme une carte qu'on distribue,
/// et se pose légèrement de biais.
class _DealIn extends StatelessWidget {
  const _DealIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = RetroEntrance.slice(
      context,
      delay: const Duration(milliseconds: 400),
      duration: const Duration(milliseconds: 1300),
      curve: RetroMotion.back,
    );
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) {
        final hidden = 1 - t.value;
        return Opacity(
          opacity: t.value.clamp(0.0, 1.0),
          child: FractionalTranslation(
            translation: Offset(0, 0.3 * hidden),
            child: Transform.rotate(
              angle: (3 - 17 * hidden) * math.pi / 180,
              child: Transform.scale(scale: 1 - 0.2 * hidden, child: child),
            ),
          ),
        );
      },
    );
  }
}
