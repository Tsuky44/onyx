import 'package:flutter/widgets.dart';

import '../../../l10n/tr.dart';
import '../../../models/retro.dart';
import '../../../theme/retro_palette.dart';
import '../../settings/widgets/settings_ui.dart' show formatWatchTime;
import '../widgets/retro_entrance.dart';
import '../widgets/retro_poster.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 3. Le n°1 de l'année, en grand, avec son affiche.
class RetroTopTitleSlide extends RetroSlide {
  const RetroTopTitleSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) => const RetroRays();

  @override
  RetroColors colors(RetroStoryData data) => RetroPalette.topTitle;

  /// « 19 épisodes · 17 h 24 », « Vu 3 fois · 8 h 18 ».
  static String detail(RetroTitle title) {
    final time = formatWatchTime(title.watchedSeconds);
    if (title.isShow) {
      return '${trPlural(title.episodes, '{0} épisode', '{0} épisodes')} · $time';
    }
    return title.times >= 2
        ? '${tr('Vu {0} fois', [title.times])} · $time'
        : time;
  }

  @override
  String summary(RetroStoryData data) {
    final top = data.report.top.firstOrNull;
    if (top == null) return '';
    return tr('Ton n°1 : {0}, {1}.', [top.title, detail(top)]);
  }

  @override
  Widget text(BuildContext context, RetroStoryData data) {
    final top = data.report.top.firstOrNull;
    if (top == null) return const SizedBox.shrink();
    return RetroText(children: [
      RetroKicker(top.isShow
          ? tr('La série de ton année')
          : tr('Le film que tu n’as pas lâché')),
      RetroBig(top.title, size: 11, maxLines: 3),
      RetroNote(detail(top)),
    ]);
  }

  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final top = data.report.top.firstOrNull;
    if (top == null) return null;
    return LayoutBuilder(builder: (context, constraints) {
      final u = RetroUnits.of(context).u;
      final width = (constraints.maxHeight / 1.5).clamp(u * 20, u * 48);
      return _FlipIn(
        child: RetroPoster(
          posterUrl: top.posterUrl,
          title: top.title,
          serverBaseUrl: data.serverBaseUrl,
          width: width,
          showTitle: true,
        ),
      );
    });
  }
}

/// L'affiche du n°1 se retourne face à nous, comme une carte qu'on dévoile.
class _FlipIn extends StatelessWidget {
  const _FlipIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = RetroEntrance.slice(
      context,
      delay: const Duration(milliseconds: 350),
      duration: const Duration(milliseconds: 1200),
    );
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) {
        final hidden = 1 - t.value;
        return Opacity(
          opacity: t.value.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(-1.45 * hidden)
              ..scaleByDouble(1 - 0.25 * hidden, 1 - 0.25 * hidden, 1, 1),
            child: child,
          ),
        );
      },
    );
  }
}
