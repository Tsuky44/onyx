import 'package:flutter/widgets.dart';

import '../../../models/retro.dart';
import '../widgets/retro_poster.dart';

/// Les affiches de l'année en éventail : le n°1 au centre, droit et devant,
/// les suivantes de part et d'autre, inclinées. La diapo et la carte du
/// Rétro sur l'accueil.
class RetroPosterFan extends StatelessWidget {
  const RetroPosterFan({
    super.key,
    required this.titles,
    required this.serverBaseUrl,
    required this.posterWidth,
    this.spread = 0.2,
  });

  /// Dans l'ordre du classement ; cinq au plus servent.
  final List<RetroTitle> titles;
  final String? serverBaseUrl;
  final double posterWidth;

  /// L'angle entre deux affiches voisines, en radians.
  final double spread;

  @override
  Widget build(BuildContext context) {
    // De gauche à droite : 4, 2, 1, 3, 5.
    const order = [3, 1, 0, 2, 4];
    final slots = [
      for (final rank in order)
        if (rank < titles.length) rank,
    ];
    if (slots.isEmpty) return const SizedBox.shrink();
    Widget card(int position) {
      final rank = slots[position];
      return Transform.rotate(
        angle: (position - (slots.length - 1) / 2) * spread,
        alignment: const Alignment(0, 2.4),
        child: RetroPoster(
          posterUrl: titles[rank].posterUrl,
          title: titles[rank].title,
          serverBaseUrl: serverBaseUrl,
          width: posterWidth,
        ),
      );
    }

    final first = slots.indexOf(0);
    return SizedBox(
      width: posterWidth * (1 + 0.6 * (slots.length - 1)),
      height: posterWidth * 1.5,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          for (var n = 0; n < slots.length; n++)
            if (n != first) card(n),
          // Le n°1 par-dessus les autres.
          card(first),
        ],
      ),
    );
  }
}
