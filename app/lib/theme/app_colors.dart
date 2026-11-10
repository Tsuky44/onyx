import 'package:flutter/material.dart';

/// Quiet Premium tokens — OLED charcoal stage, blue accent sparingly, white focus.
abstract final class AppColors {
  static const background = Color(0xFF0A0A0A);
  static const surface = Color(0xFF141414);
  static const surfaceElevated = Color(0xFF1C1C1C);
  static const surfaceHover = Color(0xFF252525);
  static const border = Color(0xFF2C2C2E);

  /// Interactive accent (selection, links). Not a fill wash, not the focus.
  static const primary = Color(0xFF0A84FF);
  static const accent = Color(0xFF0A84FF);
  static const accentMuted = Color(0xFF64B5FF);
  static const onAccent = Color(0xFFFFFFFF);

  /// L'anneau de focus (télécommande, clavier) : blanc, pas bleu. Le bleu se
  /// confondait avec l'accent des boutons pleins et des sélections, et sur une
  /// affiche il criait plus que l'image. Voir ADR-0111.
  static const focus = Color(0xFFF5F5F7);

  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFFA1A1A6);
  static const textMuted = Color(0xFF6E6E73);

  /// Le bleu de « Demander » (saison pas encore demandée), comme MediaHub :
  /// plus franc que l'accent, qui reste réservé au focus.
  static const request = Color(0xFF2F6FE4);

  static const progress = Color(0xFF0A84FF);
  static const success = Color(0xFF30D158);
  static const warning = Color(0xFFFF9F0A);
  static const error = Color(0xFFFF453A);

  /// L'étoile des notes : l'or que le public associe aux notes de films,
  /// réservé à ce seul usage.
  static const rating = Color(0xFFF5C518);

  /// Le vert de la pastille TMDB, dans la colonne d'informations des fiches.
  static const tmdb = Color(0xFF01D277);

  static const gradientBottom = Color(0xFF0A0A0A);
  static const gradientTop = Colors.transparent;

  static const navBackground = Color(0xE6141414);

  /// Le voile d'une affiche absente du serveur (titres similaires, listes,
  /// épisodes pas encore là), posé en `BlendMode.darken` sur l'image même :
  /// un seul gris pour dire « pas là » partout.
  static const unavailableTint = Color(0x73000000);

  /// Les pastilles de « Qui regarde ? » : une teinte par personne, pour la
  /// reconnaître de loin avant d'avoir lu son nom. Assourdies, pour que le
  /// focus bleu reste la seule chose qui ressorte.
  static const profileTints = [
    Color(0xFF3A6EA5),
    Color(0xFF3F8F5E),
    Color(0xFFB07A2E),
    Color(0xFF8A5AAE),
    Color(0xFFA8485E),
    Color(0xFF3E8C96),
  ];

  /// Hairline glass edge highlight.
  static Color get glassBorder => Colors.white.withValues(alpha: 0.08);
  static Color get glassFill => Colors.white.withValues(alpha: 0.06);
  static Color get glassFillStrong => Colors.black.withValues(alpha: 0.45);
}
