import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../theme/retro_palette.dart';
import 'retro_type.dart';

/// La mise en page commune aux dix écrans du Rétro.
///
/// Une seule bascule : plus large que haut, le texte passe à gauche et le
/// visuel à droite (PC, tablette couchée, téléviseur) ; sinon, l'un sous
/// l'autre (téléphone). Pas de variante par plateforme : c'est la forme de
/// l'écran qui décide.
class RetroSlideLayout extends StatelessWidget {
  const RetroSlideLayout({
    super.key,
    required this.colors,
    required this.text,
    this.visual,
    this.background,
    this.centered = false,
  });

  final RetroColors colors;
  final Widget text;
  final Widget? visual;

  /// Ce qui vit derrière le texte, sur tout l'écran : fond animé, confettis.
  final Widget? background;

  /// Le texte porte l'écran (un grand chiffre) : en portrait, il prend la
  /// hauteur et le visuel se range dessous, à sa taille.
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      final landscape = size.width > size.height;
      final u = RetroUnits.unitFor(size);
      // Sous la barre de progression et l'en-tête de la story.
      final top = math.max(68.0, u * 17);
      final padding = landscape
          ? EdgeInsets.fromLTRB(u * 11, top, u * 11, u * 7)
          : EdgeInsets.fromLTRB(u * 6.5, top, u * 6.5, u * 7);
      final visual = this.visual;
      final Widget body;
      if (landscape) {
        body = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [text],
              ),
            ),
            if (visual != null) ...[
              SizedBox(width: u * 8),
              Expanded(child: Center(child: visual)),
            ],
          ],
        );
      } else {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (centered)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [text],
                ),
              )
            else
              text,
            if (visual != null)
              if (centered)
                visual
              else ...[
                SizedBox(height: u * 4),
                Expanded(child: Center(child: visual)),
              ],
          ],
        );
      }
      return RetroUnits(
        u: u,
        landscape: landscape,
        child: RetroBackground(
          color: colors.background,
          child: ColoredBox(
            color: colors.background,
            child: DefaultTextStyle.merge(
              style: TextStyle(color: colors.ink),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (background case final background?) background,
                  Padding(padding: padding, child: body),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Le texte d'un écran : ses lignes, espacées d'un même pas.
class RetroText extends StatelessWidget {
  const RetroText({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final gap = RetroUnits.of(context).u * 3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );
  }
}
