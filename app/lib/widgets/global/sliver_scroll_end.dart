import 'package:flutter/widgets.dart';

/// La fin d'une page qui défile : sa marge, plus ce que le bas de l'écran
/// recouvre, lu dans la marge du bas du [MediaQuery] — l'indicateur d'accueil,
/// et sur un téléphone la barre d'onglets qui flotte au-dessus des pages
/// (ADR-0142). Sans elle, la dernière rangée s'arrêtait sous le verre de la
/// barre.
class SliverScrollEnd extends StatelessWidget {
  const SliverScrollEnd({super.key, this.base = 48});

  /// La marge de la page elle-même, quand rien ne recouvre le bas.
  final double base;

  /// La même place, pour une page qui la pose dans son propre rembourrage.
  static double extentOf(BuildContext context, [double base = 48]) =>
      base + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) =>
      SliverToBoxAdapter(child: SizedBox(height: extentOf(context, base)));
}
