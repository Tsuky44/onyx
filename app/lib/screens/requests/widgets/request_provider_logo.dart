import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/global/app_network_image.dart';

/// Le logo carré d'un service de streaming (TMDB), aux coins arrondis, avec
/// une case vide à la place tant qu'il charge ou s'il manque. Partagé par le
/// panneau de la capsule Streaming et la feuille des filtres.
class RequestProviderLogo extends StatelessWidget {
  const RequestProviderLogo({super.key, required this.url, this.size = 20});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return ClipRRect(
      // Le rayon suit la taille : TMDB dessine ses logos en tuiles d'app.
      borderRadius: BorderRadius.circular(size / 4),
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? const ColoredBox(color: AppColors.surfaceElevated)
            : AppNetworkImage(
                url: url,
                width: size,
                height: size,
                placeholder: const ColoredBox(color: AppColors.surfaceElevated),
                errorWidget: const ColoredBox(color: AppColors.surfaceElevated),
              ),
      ),
    );
  }
}
