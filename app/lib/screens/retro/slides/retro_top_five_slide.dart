import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/tr.dart';
import '../../../models/retro.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_poster.dart';
import '../widgets/retro_slide_layout.dart';
import '../widgets/retro_type.dart';
import 'retro_slide.dart';
import 'retro_top_title_slide.dart';

/// 4. Le classement de l'année, cinq titres au plus : une liste sur un
/// téléphone, un podium en ligne sur un écran large.
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

  /// Sur un écran large, les affiches côte à côte sur toute la largeur, le
  /// n°1 plus grand, chacune avec son rang en chiffre géant.
  @override
  Widget? compose(BuildContext context, RetroStoryData data) {
    final units = RetroUnits.of(context);
    final top = data.report.top;
    if (!units.landscape || top.isEmpty) return null;
    final u = units.u;
    final padding = units.padding;
    final size = units.size;
    const firstWeight = 1.45;
    final gap = size.width * 0.024;
    final room =
        size.width - padding.left - padding.right - gap * (top.length - 1);
    // La largeur d'une affiche ordinaire : la ligne tient dans la largeur, et
    // l'affiche du n°1 dans la moitié de la hauteur.
    final unit = math.min(
      room / (firstWeight + top.length - 1),
      size.height * 0.54 / 1.5 / firstWeight,
    );
    return Stack(
      children: [
        Positioned(
          left: padding.left,
          top: padding.top,
          right: padding.right,
          child: text(context, data),
        ),
        // Les affiches gardent leur taille ; ce qui reste de la largeur va
        // aux espaces entre elles.
        Positioned(
          left: padding.left,
          right: padding.right,
          bottom: padding.bottom + u * 3,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: top.length > 2
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.start,
            children: [
              for (var i = 0; i < top.length; i++) ...[
                if (i > 0 && top.length <= 2) SizedBox(width: gap),
                RetroReveal.rise(
                  delay: Duration(milliseconds: 450 + 120 * i),
                  child: _PodiumItem(
                    rank: i + 1,
                    title: top[i],
                    width: unit * (i == 0 ? firstWeight : 1),
                    data: data,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

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

/// Une marche du podium : l'affiche, son rang en chiffre géant à cheval sur
/// son coin, le titre et le détail dessous.
class _PodiumItem extends StatelessWidget {
  const _PodiumItem({
    required this.rank,
    required this.title,
    required this.width,
    required this.data,
  });

  final int rank;
  final RetroTitle title;
  final double width;
  final RetroStoryData data;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final palette = RetroPalette.topFive;
    final first = rank == 1;
    final rankStyle = RetroBig.styleOf(context, first ? 34 : 26)
        .copyWith(height: 0.8, letterSpacing: -u);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              RetroPoster(
                posterUrl: title.posterUrl,
                title: title.title,
                serverBaseUrl: data.serverBaseUrl,
                width: width,
              ),
              Positioned(
                left: -u * 2.5,
                bottom: -u * 2,
                // Un liseré couleur papier sous le chiffre plein : il se
                // détache de l'affiche qu'il chevauche.
                child: Stack(
                  children: [
                    Text(
                      '$rank',
                      style: rankStyle.copyWith(
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeJoin = StrokeJoin.round
                          ..strokeWidth = math.max(4, u * 1.6)
                          ..color = palette.background,
                      ),
                    ),
                    Text(
                      '$rank',
                      style: rankStyle.copyWith(
                          color: first ? palette.accent : palette.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: u * 3.5),
          Text(
            title.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: math.max(12, u * 4),
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          Opacity(
            opacity: 0.7,
            child: Text(
              RetroTopTitleSlide.detail(title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: math.max(10, u * 3)),
            ),
          ),
        ],
      ),
    );
  }
}
