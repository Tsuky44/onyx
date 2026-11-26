import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/retro_motion.dart';
import 'retro_entrance.dart';

/// L'unité de mesure du Rétro : un centième de la largeur, plafonné par la
/// hauteur. Tout se dessine en multiples de [u], pour que la même story tienne
/// sur un téléphone, une fenêtre de PC et un téléviseur sans casser sa
/// composition. Posée par `RetroSlideLayout`.
class RetroUnits extends InheritedWidget {
  const RetroUnits({
    super.key,
    required this.u,
    required this.landscape,
    required super.child,
  });

  final double u;

  /// Plus large que haut : texte à gauche, visuel à droite.
  final bool landscape;

  /// Le même calcul que la maquette : en portrait, la largeur décide ; en
  /// paysage, la hauteur, sans quoi un écran 16:9 aurait des chiffres plus
  /// hauts que lui.
  static double unitFor(Size size) => math.min(
        size.width / 100,
        size.height * (size.width > size.height ? 0.62 : 0.6) / 100,
      );

  static RetroUnits of(BuildContext context) {
    final units = context.dependOnInheritedWidgetOfExactType<RetroUnits>();
    assert(units != null, 'RetroUnits manquant au-dessus de ce widget');
    return units!;
  }

  @override
  bool updateShouldNotify(RetroUnits oldWidget) =>
      u != oldWidget.u || landscape != oldWidget.landscape;
}

/// Ligne de petites capitales au-dessus d'un écran : « Ton top 5 ».
class RetroKicker extends StatelessWidget {
  const RetroKicker(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    return RetroReveal.rise(
      delay: Duration.zero,
      child: Opacity(
        opacity: 0.8,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: math.max(10, u * 2.9),
            fontWeight: FontWeight.w600,
            letterSpacing: math.max(10, u * 2.9) * 0.14,
          ),
        ),
      ),
    );
  }
}

TextStyle _bigStyle(BuildContext context, double size) {
  final fontSize = RetroUnits.of(context).u * size;
  return TextStyle(
    fontFamily: AppTheme.fontFamily,
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    height: 0.95,
    letterSpacing: -fontSize * 0.035,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Le chiffre ou la phrase en très grand. [size] est en unités du Rétro.
/// Les mots montent un à un ; avec [maxLines], le texte arrive d'un bloc,
/// pour pouvoir se couper.
class RetroBig extends StatelessWidget {
  const RetroBig(
    this.text, {
    super.key,
    this.size = 20,
    this.maxLines,
    this.delay = const Duration(milliseconds: 250),
  });
  final String text;
  final double size;
  final int? maxLines;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final style = _bigStyle(context, size);
    if (maxLines != null) {
      return RetroReveal.rise(
        delay: delay,
        child: Text(text,
            maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style),
      );
    }
    return RetroKineticText(text, style: style, delay: delay);
  }
}

/// Un chiffre qui défile de [from] à [value], écrit par [format].
class RetroCount extends StatelessWidget {
  const RetroCount({
    super.key,
    required this.value,
    this.from = 0,
    this.format,
    this.size = 40,
    this.delay = const Duration(milliseconds: 350),
  });

  final int value;
  final int from;
  final String Function(int value)? format;
  final double size;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final t = RetroEntrance.slice(
      context,
      delay: delay,
      duration: RetroMotion.count,
      curve: Curves.easeOutExpo,
    );
    final style = _bigStyle(context, size);
    final write = format ?? (v) => '$v';
    return RetroReveal.rise(
      delay: delay,
      child: AnimatedBuilder(
        animation: t,
        builder: (context, _) => Text(
          write((from + (value - from) * t.value).round()),
          style: style,
        ),
      ),
    );
  }
}

/// La phrase d'accroche, sous un grand chiffre ou à sa place.
class RetroLede extends StatelessWidget {
  const RetroLede(this.text,
      {super.key, this.delay = const Duration(milliseconds: 500)});
  final String text;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final fontSize = math.max(15.0, RetroUnits.of(context).u * 6.2);
    return RetroKineticText(
      text,
      delay: delay,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -fontSize * 0.015,
      ),
    );
  }
}

/// Le texte d'appui, plus discret.
class RetroNote extends StatelessWidget {
  const RetroNote(this.text,
      {super.key, this.delay = const Duration(milliseconds: 900)});
  final String text;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return RetroReveal.rise(
      delay: delay,
      child: Opacity(
        opacity: 0.85,
        child: Text(
          text,
          style: TextStyle(
            fontSize: math.max(12, RetroUnits.of(context).u * 3.5),
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

/// Un texte dont chaque mot sort de sous sa ligne, l'un après l'autre. Les
/// retours à la ligne (`\n`) sont gardés ; le reste passe à la ligne de
/// lui-même.
class RetroKineticText extends StatelessWidget {
  const RetroKineticText(this.text,
      {super.key, required this.style, this.delay = Duration.zero});

  final String text;
  final TextStyle style;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    var index = 0;
    final lines = text.split('\n');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Wrap(
            children: [
              for (final (i, word) in line.split(' ').indexed)
                if (word.isNotEmpty)
                  _Word(
                    // L'espace reste collé au mot : un mot en fin de ligne
                    // ne commence pas la suivante par un blanc.
                    text: i < line.split(' ').length - 1 ? '$word ' : word,
                    style: style,
                    delay: delay + RetroMotion.stagger * index++,
                  ),
            ],
          ),
      ],
    );
  }
}

class _Word extends StatelessWidget {
  const _Word({required this.text, required this.style, required this.delay});
  final String text;
  final TextStyle style;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final t = RetroEntrance.slice(context, delay: delay);
    return ClipRect(
      child: AnimatedBuilder(
        animation: t,
        child: Text(text, style: style),
        builder: (context, child) {
          final hidden = 1 - t.value;
          return FractionalTranslation(
            translation: Offset(0, 1.1 * hidden),
            child: Transform.rotate(
              angle: 0.09 * hidden,
              alignment: Alignment.bottomLeft,
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// Une pastille : « ≈ 13 jours entiers ». Pleine, elle prend l'encre en fond.
class RetroChip extends StatelessWidget {
  const RetroChip(this.text, {super.key, this.solid = false});
  final String text;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final ink =
        DefaultTextStyle.of(context).style.color ?? const Color(0xFFFFFFFF);
    final background = RetroBackground.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: math.max(10, u * 3.2),
        vertical: math.max(5, u * 1.6),
      ),
      decoration: BoxDecoration(
        color: solid ? ink : ink.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: math.max(11, u * 3.2),
          fontWeight: FontWeight.w700,
          color: solid ? background : ink,
        ),
      ),
    );
  }
}

/// La couleur de fond de l'écran en cours, pour ce qui se dessine en négatif
/// (une pastille pleine, le creux d'un graphique).
class RetroBackground extends InheritedWidget {
  const RetroBackground({super.key, required this.color, required super.child});
  final Color color;

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RetroBackground>()?.color ??
      const Color(0xFF000000);

  @override
  bool updateShouldNotify(RetroBackground oldWidget) =>
      color != oldWidget.color;
}
