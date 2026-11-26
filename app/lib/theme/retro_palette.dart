import 'package:flutter/painting.dart';

import '../models/retro.dart';
import 'app_colors.dart';

/// Les couleurs du Rétro (ADR 2026-11-26-tsuky-retro-annuel).
///
/// Le Rétro est le seul endroit de l'app où chaque écran a sa propre scène :
/// une couleur de fond franche et une couleur d'encre, comme une affiche. Le
/// reste de l'app garde la scène charbon d'[AppColors]. Les valeurs viennent
/// de la maquette (`design-plans/onyx-wrapped-maquette.html`).
class RetroColors {
  const RetroColors(this.background, this.ink, [Color? accent])
      : accent = accent ?? ink;

  final Color background;

  /// Le texte et les tracés.
  final Color ink;

  /// Une touche secondaire : les halos, la carte de fin.
  final Color accent;
}

abstract final class RetroPalette {
  /// Le temps passé : un bleu nuit qu'éclaire le bleu de la marque, en halo.
  /// Le bleu de la marque en plein cadre éblouissait sur un grand écran.
  static const hours = RetroColors(Color(0xFF071B45), Color(0xFFFFFFFF));

  /// Les halos du temps passé : le bleu de la marque, plus ou moins profond.
  static const hoursGlows = [
    Color(0xCC1466D6),
    Color(0x660A84FF),
    Color(0x553A8BFF),
  ];

  /// Ton n°1 : une nuit bleutée, que l'affiche éclaire.
  static const topTitle = RetroColors(Color(0xFF0B1220), Color(0xFFC9DAFF));

  /// Le top 5 : le seul écran clair, pour casser la suite de fonds sombres.
  /// Un papier tamisé plutôt qu'un blanc : après trois écrans de nuit, un
  /// blanc éblouissait, surtout sur un téléviseur dans une pièce sombre.
  static const topFive =
      RetroColors(Color(0xFFD6D0C4), Color(0xFF1D1A15), Color(0xFF0A5BD8));

  /// Ton heure : une lumière de lampe.
  static const hour = RetroColors(Color(0xFF120A05), Color(0xFFFFB86B));

  /// Mois par mois.
  static const months = RetroColors(Color(0xFF06201F), Color(0xFF7FF0DC));

  /// Tes moments.
  static const moments = RetroColors(Color(0xFF2A0A14), Color(0xFFFF9DB5));

  /// Les halos de « Tes moments » : des roses de salle de cinéma.
  static const momentsGlows = [
    Color(0x55FF3D6E),
    Color(0x33FF9DB5),
    Color(0x33A8485E),
  ];

  /// Le serveur, ensemble.
  static const server = RetroColors(Color(0xFF07090F), Color(0xFF9FC9FF));

  /// Les halos de « Ton heure » : une lampe, des braises.
  static const hourGlows = [
    Color(0x66FF7A1A),
    Color(0x33FFB86B),
    Color(0x44FF3D6E),
  ];

  /// Les couleurs des confettis, en plus de l'encre et de l'accent du profil.
  static const confetti = [
    AppColors.primary,
    Color(0xFFFFB86B),
    Color(0xFFFF9DB5),
  ];

  /// Les halos de l'ouverture et de la carte de fin, dans la couleur du profil.
  static List<Color> glowsFor(RetroColors colors) => [
        colors.accent,
        colors.ink.withValues(alpha: 0.27),
        AppColors.primary.withValues(alpha: 0.33),
      ];

  /// L'ouverture et la carte de fin prennent la couleur du profil : deux
  /// membres qui comparent leurs cartes ne voient pas la même.
  static RetroColors forArchetype(RetroArchetype archetype) =>
      switch (archetype) {
        RetroArchetype.marathon => const RetroColors(
            Color(0xFF0B1B3A), Color(0xFF9FD3FF), Color(0xFF3A6EA5)),
        RetroArchetype.nightOwl => const RetroColors(
            Color(0xFF1A0B2E), Color(0xFFE7B8FF), Color(0xFF8A5AAE)),
        RetroArchetype.cinephile => const RetroColors(
            Color(0xFF2A1405), Color(0xFFFFD08A), Color(0xFFB07A2E)),
        RetroArchetype.explorer => const RetroColors(
            Color(0xFF06201F), Color(0xFF7FF0DC), Color(0xFF3E8C96)),
        RetroArchetype.weekend => const RetroColors(
            Color(0xFF08261A), Color(0xFFB8F2C9), Color(0xFF3F8F5E)),
        RetroArchetype.goodAudience => const RetroColors(
            Color(0xFF2A0A14), Color(0xFFFF9DB5), Color(0xFFA8485E)),
      };
}
