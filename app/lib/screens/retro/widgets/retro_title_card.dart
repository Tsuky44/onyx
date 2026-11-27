import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/retro_archetypes.dart';
import '../../../l10n/tr.dart';
import '../../../models/retro.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/retro_palette.dart';
import '../characters/retro_character.dart';

/// La carte du titre de l'année, comme une carte à collectionner
/// (`design-plans/onyx-retro-revelation.html`, piste « La carte »).
///
/// Face cachée : le dos commun à tous, le logo et une bande aux couleurs
/// des six profils. Face visible : le personnage sur la couleur du profil,
/// le titre en bas. Proportions de 5 × 7 ; tout se mesure à la largeur.
class RetroTitleCard extends StatelessWidget {
  const RetroTitleCard.front({
    super.key,
    required this.archetype,
    required this.year,
    this.glint = 0,
  }) : face = true;

  const RetroTitleCard.back({super.key, required this.year})
      : archetype = null,
        glint = 0,
        face = false;

  final RetroArchetype? archetype;
  final int year;
  final bool face;

  /// Le reflet qui passe sur la face, de 0 (à gauche, hors carte) à 1.
  final double glint;

  static const double ratio = 5 / 7;

  static const _backColor = Color(0xFF17181D);
  static const _backEdge = Color(0xFF2A2D36);
  static const _backInk = Color(0xFFECEEF2);
  static const _backMuted = Color(0xFF9AA1AE);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          final radius = BorderRadius.circular(w * 0.06);
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: const Color(0x40000000),
                  blurRadius: h * 0.06,
                  offset: Offset(0, h * 0.015),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: face ? _front(w, h) : _back(w, h),
            ),
          );
        },
      );

  TextStyle _style(double size, Color color,
          {FontWeight weight = FontWeight.w700, double spacing = 0}) =>
      TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
      );

  Widget _front(double w, double h) {
    final archetype = this.archetype!;
    final palette = RetroPalette.forArchetype(archetype);
    final title = retroArchetypeName(archetype);
    final titleSize = w *
        (title.length <= 10
            ? 0.15
            : title.length <= 13
                ? 0.13
                : 0.115);
    final label = _style(w * 0.042, palette.background.withValues(alpha: 0.72),
        spacing: w * 0.006);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: palette.ink),
        Positioned(
          left: w * 0.07,
          right: w * 0.07,
          top: h * 0.05,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(tr('Rétro {0}', [year]).toUpperCase(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: label),
              ),
              SizedBox(width: w * 0.04),
              Flexible(
                child: Text(tr('Ton titre').toUpperCase(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: label),
              ),
            ],
          ),
        ),
        Positioned(
          left: w * 0.09,
          top: h * 0.40 - w * 0.41,
          width: w * 0.82,
          height: w * 0.82,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x52FFFFFF),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: h * 0.09,
          height: h * 0.6,
          child: Center(child: RetroCharacter(archetype: archetype)),
        ),
        Positioned(
          left: w * 0.07,
          right: w * 0.07,
          bottom: h * 0.06,
          child: Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: _style(titleSize, palette.background,
                    weight: FontWeight.w800, spacing: -w * 0.004)
                .copyWith(height: 0.94),
          ),
        ),
        if (glint > 0 && glint < 1)
          Transform.translate(
            offset: Offset((-1.3 + 2.6 * glint) * w, 0),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1, -0.3),
                  end: Alignment(1, 0.3),
                  colors: [
                    Color(0x00FFFFFF),
                    Color(0x99FFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: [0.38, 0.5, 0.62],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _back(double w, double h) => Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: _backColor,
              border: Border.all(color: _backEdge, width: w * 0.025),
              borderRadius: BorderRadius.circular(w * 0.06),
            ),
          ),
          Positioned(
            left: -w * 0.12,
            right: -w * 0.12,
            top: h * 0.41,
            height: h * 0.2,
            child: Transform.rotate(
              angle: -16 * math.pi / 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final archetype in RetroArchetype.values)
                    Expanded(
                      child: ColoredBox(
                          color: RetroPalette.forArchetype(archetype).ink),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: h * 0.12,
            child: Text(
              'Onyx',
              textAlign: TextAlign.center,
              style: _style(w * 0.15, _backInk,
                  weight: FontWeight.w800, spacing: -w * 0.004),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: h * 0.08,
            child: Text(
              tr('Rétro {0}', [year]).toUpperCase(),
              textAlign: TextAlign.center,
              style: _style(w * 0.046, _backMuted, spacing: w * 0.008),
            ),
          ),
        ],
      );
}
