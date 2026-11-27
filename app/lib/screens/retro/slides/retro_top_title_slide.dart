import 'dart:math' as math;

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

/// 3. Le n°1 de l'année : son logo, son affiche, et la couleur de l'affiche
/// sur tout l'écran. Sur un écran large, l'affiche se tient à droite, de
/// biais ; le logo et deux chiffres à gauche.
class RetroTopTitleSlide extends RetroSlide {
  const RetroTopTitleSlide();

  @override
  RetroAmbient? ambient(RetroStoryData data) =>
      const RetroOrbs([Color(0x26FFFFFF), Color(0x1AC9DAFF)]);

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

  String _kicker(RetroTitle top) => top.isShow
      ? tr('La série de ton année')
      : tr('Le film que tu n’as pas lâché');

  /// L'affiche, assombrie vers le texte : le logo reste lisible quelle que
  /// soit sa couleur.
  @override
  Widget? backdrop(BuildContext context, RetroStoryData data) {
    final top = data.report.top.firstOrNull;
    if (top == null) return null;
    final units = RetroUnits.of(context);
    final background = colors(data).background;
    return Stack(
      fit: StackFit.expand,
      children: [
        RetroPosterTint(
          posterUrl: top.posterUrl,
          title: top.title,
          serverBaseUrl: data.serverBaseUrl,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: units.landscape
                ? LinearGradient(
                    colors: [
                      background.withValues(alpha: 0.94),
                      background.withValues(alpha: 0.8),
                      background.withValues(alpha: 0.3),
                    ],
                    stops: const [0, 0.4, 0.85],
                  )
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      background.withValues(alpha: 0.85),
                      background.withValues(alpha: 0.45),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget text(BuildContext context, RetroStoryData data) {
    final top = data.report.top.firstOrNull;
    if (top == null) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final u = RetroUnits.of(context).u;
      return RetroText(children: [
        RetroKicker(_kicker(top)),
        RetroTitleLogo(
          title: top.title,
          logoUrl: data.topLogoUrl,
          height: u * 22,
          width: math.min(constraints.maxWidth, u * 80),
          size: 11,
        ),
        RetroNote(detail(top)),
      ]);
    });
  }

  @override
  Widget? visual(BuildContext context, RetroStoryData data) {
    final top = data.report.top.firstOrNull;
    if (top == null) return null;
    return LayoutBuilder(builder: (context, constraints) {
      final u = RetroUnits.of(context).u;
      final width = (constraints.maxHeight / 1.5).clamp(u * 20, u * 48);
      return _FlipIn(child: _poster(data, top, width));
    });
  }

  Widget _poster(RetroStoryData data, RetroTitle top, double width) =>
      RetroPoster(
        posterUrl: top.posterUrl,
        title: top.title,
        serverBaseUrl: data.serverBaseUrl,
        width: width,
        showTitle: true,
      );

  @override
  Widget? compose(BuildContext context, RetroStoryData data) {
    final units = RetroUnits.of(context);
    final top = data.report.top.firstOrNull;
    if (!units.landscape || top == null) return null;
    final u = units.u;
    final padding = units.padding;
    final size = units.size;
    final room = size.height - padding.top - padding.bottom - u * 6;
    final posterWidth = math.min(room / 1.5, size.width * 0.36);
    final posterHeight = posterWidth * 1.5;
    final textWidth = size.width * 0.52 - padding.left;
    final figures = [
      if (top.isShow)
        ('${top.episodes}', trPlural(top.episodes, 'épisode', 'épisodes'))
      else if (top.times >= 2)
        ('${top.times}', trPlural(top.times, 'visionnage', 'visionnages')),
      (formatWatchTime(top.watchedSeconds), tr('de visionnage')),
    ];
    return Stack(
      children: [
        Positioned(
          right: size.width * 0.07,
          top: padding.top +
              (size.height - padding.top - padding.bottom - posterHeight) / 2,
          width: posterWidth,
          height: posterHeight,
          child: _FlipIn(child: _poster(data, top, posterWidth)),
        ),
        Positioned(
          left: padding.left,
          top: padding.top,
          bottom: padding.bottom,
          width: textWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RetroKicker(_kicker(top)),
              SizedBox(height: u * 4),
              RetroTitleLogo(
                title: top.title,
                logoUrl: data.topLogoUrl,
                height: u * 30,
                width: math.min(textWidth, u * 110),
                size: 22,
              ),
              SizedBox(height: u * 6),
              Wrap(
                spacing: u * 9,
                runSpacing: u * 3,
                children: [
                  for (final (i, (value, label)) in figures.indexed)
                    RetroReveal.rise(
                      delay: Duration(milliseconds: 900 + 150 * i),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(value,
                              style: RetroBig.styleOf(context, 13)
                                  .copyWith(height: 1)),
                          SizedBox(height: u),
                          Opacity(
                            opacity: 0.8,
                            child: Text(label,
                                style:
                                    TextStyle(fontSize: math.max(12, u * 3.8))),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
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
