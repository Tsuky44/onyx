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

/// 4. Le classement de l'année, cinq titres au plus : une liste qui remplit
/// l'écran d'un téléphone, un podium en ligne sur un écran large.
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

  /// Sur un téléphone, la liste prend toute la hauteur laissée par le texte :
  /// les lignes se la partagent, le n°1 plus haut que les autres, et
  /// l'affiche, le rang et le titre grandissent avec leur ligne.
  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final u = RetroUnits.of(context).u;
    final top = data.report.top;
    if (top.isEmpty) return null;
    return LayoutBuilder(builder: (context, box) {
      const firstWeight = 1.5;
      final gap = u * 2.4;
      final weights = firstWeight + top.length - 1;
      final room = box.maxHeight - gap * (top.length - 1);
      // Une ligne ordinaire : sa part de la hauteur, sans dépasser la taille
      // où l'affiche mangerait la place du titre.
      final row = math.min(room / weights, u * 30);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            // Les lignes arrivent de la droite, la première en premier.
            RetroReveal.slide(
              delay: Duration(milliseconds: 450 + 120 * i),
              child: _ListItem(
                rank: i + 1,
                title: top[i],
                height: row * (i == 0 ? firstWeight : 1),
                data: data,
              ),
            ),
          ],
        ],
      );
    });
  }
}

/// Une ligne du classement sur un téléphone : le rang en grand, l'affiche à
/// la hauteur de la ligne, le titre et le détail à côté.
class _ListItem extends StatelessWidget {
  const _ListItem({
    required this.rank,
    required this.title,
    required this.height,
    required this.data,
  });

  final int rank;
  final RetroTitle title;
  final double height;
  final RetroStoryData data;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final first = rank == 1;
    final accent = RetroPalette.topFive.accent;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: u * 12,
            child: Text(
              '$rank',
              maxLines: 1,
              style: RetroBig.styleOf(context, first ? 15 : 11).copyWith(
                height: 1,
                letterSpacing: -u * 0.4,
                color: first ? accent : null,
              ),
            ),
          ),
          RetroPoster(
            posterUrl: title.posterUrl,
            title: title.title,
            serverBaseUrl: data.serverBaseUrl,
            width: height / 1.5,
          ),
          SizedBox(width: u * 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: math.max(13, u * (first ? 6 : 4.6)),
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: u * 0.8),
                Opacity(
                  opacity: 0.7,
                  child: Text(
                    RetroTopTitleSlide.detail(title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: math.max(11, u * 3.4)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
