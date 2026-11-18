import 'dart:ui';

import 'package:flutter/material.dart';

import 'glass_chrome.dart';

/// Le verre liquide du téléphone (ADR-0144) : la capsule des onglets et le
/// rond de la recherche en bas, la pilule de la marque et le rond du compte en
/// haut. Une seule matière pour le haut et le bas de l'écran.
///
/// Plus clair que le verre dépoli des barres d'avant : un flou court, un voile
/// à peine teinté, un peu plus de couleur dans ce qui passe dessous, et un
/// liseré clair. L'affiche se devine à travers, comme sous le verre d'iOS 26.
/// En mode léger et sur un téléviseur LG, un fond dense sans flou
/// ([glassBlurs]).
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = stadium,
  });

  final Widget child;

  /// Une pilule par défaut : le rayon se réduit à la moitié du côté le plus
  /// court.
  final BorderRadius borderRadius;

  static const BorderRadius stadium = BorderRadius.all(Radius.circular(999));

  /// Le flou de ce qui passe dessous. Court : à 22, la capsule devenait un
  /// verre dépoli où l'affiche ne se lisait plus.
  static const double blurSigma = 12;

  /// Un peu plus de couleur dans ce qui passe sous le verre : le flou seul
  /// grisait les affiches.
  static const double _saturation = 1.5;

  /// La teinte sans flou : assez dense pour porter les noms des onglets.
  static const Color denseFill = Color(0xF22A2A2E);

  static final ImageFilter _filter = ImageFilter.compose(
    outer: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
    inner: ColorFilter.matrix(_saturationMatrix(_saturation)),
  );

  static List<double> _saturationMatrix(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final i = 1 - s;
    return [
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0, //
      r * i, g * i, b * i + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final blurs = glassBlurs(context);
    final glass = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: blurs ? null : denseFill,
        // La lumière en haut, un reflet plus discret en bas : le verre
        // d'iOS 26 éclaire ses deux bords.
        gradient: blurs
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.13),
                  Colors.white.withValues(alpha: 0.03),
                  Colors.white.withValues(alpha: 0.06),
                ],
                stops: const [0, 0.55, 1],
              )
            : null,
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          // Une ombre courte et légère : longue et dense, elle dessinait une
          // tache sombre sous la capsule, sur l'indicateur d'accueil.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: blurs
            ? BackdropFilter.grouped(filter: _filter, child: glass)
            : glass,
      ),
    );
  }
}
