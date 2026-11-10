import 'package:flutter/material.dart';

import '../tv/tv_mode.dart';
import 'app_colors.dart';

/// Le focus d'une commande sur téléviseur : elle se remplit de blanc et son
/// texte passe au noir (ADR-0112).
///
/// Un anneau autour d'un bouton ne suffit pas : blanc sur le bouton blanc
/// « Reprendre », il ne se voyait plus du tout, et sur du verre il restait un
/// filet qu'il fallait chercher. Le modèle des interfaces de salon (Apple TV,
/// lecteurs du commerce) ne demande rien à personne : à l'écran, **une seule
/// commande est blanche, et c'est celle qui a le focus.** Pour que ce soit
/// vrai, le bouton plein qui est blanc au repos passe au verre sur téléviseur.
///
/// Hors téléviseur, rien ne change : le focus clavier garde son anneau, et le
/// bouton principal reste blanc.
abstract final class FocusFill {
  /// Le fond d'une commande focalisée.
  static const Color fill = AppColors.focus;

  /// Son texte et son icône.
  static const Color ink = AppColors.background;

  /// Le fond, sur téléviseur, d'un bouton qui est plein ailleurs : un verre
  /// assez dense pour se lire sur une image de fond.
  static const Color glass = Color(0x33FFFFFF);

  /// Vrai quand [states] décrit une commande focalisée à la télécommande.
  static bool applies(Set<WidgetState> states) =>
      TvMode.isTv &&
      states.contains(WidgetState.focused) &&
      !states.contains(WidgetState.disabled);

  /// [style] avec le remplissage du focus par-dessus ses couleurs.
  ///
  /// Les couleurs d'origine sont gardées pour tous les autres états : la
  /// fonction enveloppe, elle ne remplace pas. [restOnTv] est le fond à porter
  /// au repos sur téléviseur, pour un bouton blanc qui doit y céder sa place.
  static ButtonStyle wrap(ButtonStyle style, {Color? restOnTv}) {
    final background = style.backgroundColor;
    final foreground = style.foregroundColor;
    final icon = style.iconColor;
    final overlay = style.overlayColor;
    return style.copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (applies(states)) return fill;
        if (restOnTv != null &&
            TvMode.isTv &&
            !states.contains(WidgetState.disabled)) {
          return restOnTv;
        }
        return background?.resolve(states);
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (applies(states)) return ink;
        if (restOnTv != null &&
            TvMode.isTv &&
            !states.contains(WidgetState.disabled)) {
          return AppColors.textPrimary;
        }
        return foreground?.resolve(states);
      }),
      iconColor: WidgetStateProperty.resolveWith((states) {
        if (applies(states)) return ink;
        if (restOnTv != null &&
            TvMode.isTv &&
            !states.contains(WidgetState.disabled)) {
          return AppColors.textPrimary;
        }
        return icon?.resolve(states);
      }),
      // Le voile de focus de Material teintait le blanc d'un gris bleuté.
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (applies(states)) return Colors.transparent;
        return overlay?.resolve(states);
      }),
    );
  }
}
