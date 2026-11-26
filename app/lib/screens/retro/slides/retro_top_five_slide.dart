import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/tr.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_poster.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';
import 'retro_top_title_slide.dart';

/// 4. Le classement de l'année, cinq titres au plus.
class RetroTopFiveSlide extends RetroSlide {
  const RetroTopFiveSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) => const RetroDots();

  @override
  RetroColors colors(RetroStoryData data) => RetroPalette.topFive;

  @override
  String summary(RetroStoryData data) => [
        tr('Ton top {0}', [data.report.top.length]),
        for (var i = 0; i < data.report.top.length; i++)
          '${i + 1}. ${data.report.top[i].title}',
      ].join('. ');

  @override
  Widget text(BuildContext context, RetroStoryData data) =>
      RetroText(children: [
        RetroKicker(tr('Ton top {0}', [data.report.top.length])),
        RetroLede(trPlural(
            data.report.titles,
            '{0} titre commencé cette année.',
            '{0} titres commencés cette année.')),
      ]);

  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final u = RetroUnits.of(context).u;
    final accent = RetroPalette.topFive.accent;
    final top = data.report.top;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < top.length; i++) ...[
          if (i > 0) SizedBox(height: u * 2.6),
          // Les lignes arrivent de la droite, la première en premier.
          RetroReveal.slide(
              delay: Duration(milliseconds: 450 + 120 * i),
              child: Row(
                children: [
                  SizedBox(
                    width: u * 7,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: u * 6.5,
                        fontWeight: FontWeight.w800,
                        color: i == 0 ? accent : null,
                      ),
                    ),
                  ),
                  RetroPoster(
                    posterUrl: top[i].posterUrl,
                    title: top[i].title,
                    serverBaseUrl: data.serverBaseUrl,
                    width: u * 10,
                  ),
                  SizedBox(width: u * 3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          top[i].title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: math.max(12, u * 3.8),
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        Opacity(
                          opacity: 0.7,
                          child: Text(
                            RetroTopTitleSlide.detail(top[i]),
                            style: TextStyle(fontSize: math.max(10, u * 2.9)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )),
        ],
      ],
    );
  }
}
