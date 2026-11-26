import 'package:flutter/widgets.dart';

import '../../../l10n/tr.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_blocks.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';

/// 9. Le serveur, ensemble : un total, une place, le titre le plus partagé.
/// Personne n'y est nommé.
class RetroServerSlide extends RetroSlide {
  const RetroServerSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      const RetroRings(Alignment.center);

  @override
  RetroColors colors(RetroStoryData data) => RetroPalette.server;

  int _hours(RetroStoryData data) =>
      (data.report.server.watchedSeconds / 3600).round();

  String _members(RetroStoryData data) => trPlural(data.report.server.members,
      '{0} membre a regardé', '{0} membres ont regardé');

  String? _topTitle(RetroStoryData data) {
    final server = data.report.server;
    if (server.topTitle.isEmpty || server.topTitleViewers < 2) return null;
    return tr('Le titre le plus partagé : {0}, vu par {1} membres.',
        [server.topTitle, server.topTitleViewers]);
  }

  @override
  String summary(RetroStoryData data) {
    final server = data.report.server;
    return [
      '${_members(data)} ${tr('{0} h sur ton serveur cette année.', [
            _hours(data)
          ])}',
      if (server.members >= 2 && server.rank > 0)
        tr('Ta place : n°{0}.', [server.rank]),
      if (_topTitle(data) case final top?) top,
    ].join(' ');
  }

  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      RetroText(children: [
        RetroKicker(tr('Ton serveur, ensemble')),
        RetroLede(_members(data), delay: const Duration(milliseconds: 150)),
        RetroCount(
          value: _hours(data),
          size: 24,
          delay: const Duration(milliseconds: 500),
          format: (v) => tr('{0} h', [v]),
        ),
        RetroLede(tr('sur ton serveur cette année.'),
            delay: const Duration(milliseconds: 900)),
      ]);

  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final server = data.report.server;
    final top = _topTitle(data);
    const delay = Duration(milliseconds: 1300);
    if (server.members < 2) {
      return RetroReveal.pop(
        delay: delay,
        child: RetroCard(
          child: RetroNote(tr(
              'Tu es la seule personne à regarder ici cette année. Le serveur est à toi.')),
        ),
      );
    }
    return RetroReveal.pop(
      delay: delay,
      child: RetroCard(
        child: RetroText(children: [
          Row(
            children: [
              Expanded(child: RetroKicker(tr('Ta place'))),
              // Le rang descend comme un compteur, du dernier à sa place.
              RetroCount(
                value: server.rank,
                from: server.members,
                size: 15,
                delay: const Duration(milliseconds: 1500),
                format: (v) => tr('n°{0}', [v]),
              ),
            ],
          ),
          if (top != null) RetroNote(top),
        ]),
      ),
    );
  }
}
