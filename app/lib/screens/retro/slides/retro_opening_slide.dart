import 'package:flutter/widgets.dart';

import '../../../l10n/tr.dart';
import '../../../theme/retro_palette.dart';
import '../../../theme/retro_motion.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_poster.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 1. L'ouverture : le prénom, l'année, les affiches du top 5 en éventail.
class RetroOpeningSlide extends RetroSlide {
  const RetroOpeningSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      RetroOrbs(RetroPalette.glowsFor(colors(data)));

  @override
  RetroColors colors(RetroStoryData data) =>
      RetroPalette.forArchetype(data.report.archetype);

  @override
  String summary(RetroStoryData data) =>
      tr('{0}, ton année {1} sur Onyx.', [data.name, data.report.year]);

  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      RetroText(children: [
        RetroKicker(tr('Rétro {0}', [data.report.year])),
        RetroBig(tr('{0},\nton année\nsur Onyx.', [data.name]), size: 17),
        RetroNote(
            tr('Une année de séances, racontée par ton propre historique.')),
      ]);

  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final top = data.report.top;
    if (top.isEmpty) return null;
    return _Fan(data: data);
  }
}

/// Le n°1 au centre, les suivants de part et d'autre, inclinés.
class _Fan extends StatelessWidget {
  const _Fan({required this.data});
  final RetroStoryData data;

  @override
  Widget build(BuildContext context) {
    final top = data.report.top;
    // Positions de gauche à droite : 4, 2, 1, 3, 5.
    const order = [3, 1, 0, 2, 4];
    final slots = [
      for (final i in order)
        if (i < top.length) i
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final u = RetroUnits.of(context).u;
      final width = (constraints.maxHeight * 0.62 / 1.5).clamp(u * 16, u * 34);
      return Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          for (var n = 0; n < slots.length; n++)
            if (slots[n] != 0) _card(slots[n], n, slots.length, width),
          // Le n°1 par-dessus les autres.
          _card(0, slots.indexOf(0), slots.length, width),
        ],
      );
    });
  }

  Widget _card(int rank, int position, int count, double width) {
    final title = data.report.top[rank];
    return _FanCard(
      offset: position - (count - 1) / 2,
      order: position,
      child: RetroPoster(
        posterUrl: title.posterUrl,
        title: title.title,
        serverBaseUrl: data.serverBaseUrl,
        width: width,
        showTitle: true,
      ),
    );
  }
}

/// Une affiche de l'éventail : elle monte d'en bas, droite, puis s'ouvre à
/// son angle, avec un léger rebond.
class _FanCard extends StatelessWidget {
  const _FanCard(
      {required this.offset, required this.order, required this.child});

  /// Sa place depuis le centre : -2 à 2.
  final double offset;

  /// L'ordre d'arrivée, de gauche à droite.
  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = RetroEntrance.slice(
      context,
      delay: Duration(milliseconds: 600 + 90 * order),
      duration: const Duration(milliseconds: 1100),
      curve: RetroMotion.back,
    );
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) => Opacity(
        opacity: t.value.clamp(0.0, 1.0),
        child: FractionalTranslation(
          translation: Offset(0, 0.7 * (1 - t.value)),
          child: Transform.rotate(
            angle: offset * 0.22 * t.value,
            alignment: const Alignment(0, 2.4),
            child: child,
          ),
        ),
      ),
    );
  }
}
