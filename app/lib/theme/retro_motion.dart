import 'package:material_ui/material_ui.dart';

import 'app_motion.dart';

/// Le mouvement du Rétro (ADR 2026-11-26-tsuky-retro-annuel, décision 7).
///
/// Hors de l'échelle d'[AppMotion] (180–280 ms, une courbe) : le Rétro est un
/// moment de fête qu'on regarde, pas une navigation qu'on traverse. Ses
/// durées sont celles de la maquette (`design-plans/onyx-wrapped-maquette.html`).
/// Le reste de l'app ne s'en sert pas.
///
/// Sous « réduire les animations » et en mode léger ([AppMotion.reduced]),
/// rien ne bouge : chaque écran se pose d'un fondu court, les chiffres
/// s'affichent tout de suite et les fonds restent fixes.
abstract final class RetroMotion {
  /// L'ouverture en cercle d'un écran sur le précédent.
  static const Duration transition = Duration(milliseconds: 800);

  /// L'horloge d'entrée d'un écran : tout ce qui arrive (mots, chiffres,
  /// barres, cartes) se place dans cette fenêtre.
  static const Duration entrance = Duration(milliseconds: 2600);

  /// Un mot qui monte, une carte qui glisse.
  static const Duration rise = Duration(milliseconds: 900);

  /// L'écart entre deux mots, deux lignes d'un classement, deux barres.
  static const Duration stagger = Duration(milliseconds: 70);

  /// Un chiffre qui défile jusqu'à sa valeur.
  static const Duration count = Duration(milliseconds: 1500);

  /// Une boucle des fonds animés : assez lente pour ne pas attirer l'œil.
  static const Duration ambient = Duration(seconds: 18);

  /// La pluie de confettis de la carte de fin.
  static const Duration confetti = Duration(milliseconds: 4500);

  /// Ce qui arrive : part vite, se pose en douceur (`cubic-bezier(.16,1,.3,1)`).
  static const Curve out = Cubic(0.16, 1, 0.3, 1);

  /// Ce qui rebondit un peu en arrivant : une pastille, une carte.
  static const Curve back = Cubic(0.34, 1.5, 0.64, 1);

  /// La transition entre deux écrans : lente aux deux bouts.
  static const Curve inOut = Cubic(0.7, 0, 0.2, 1);

  /// Vrai quand le Rétro doit rester immobile. Voir [AppMotion.reduced].
  static bool still(BuildContext context) => AppMotion.reduced(context);
}
