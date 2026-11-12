import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/poster_url.dart';
import '../../../widgets/global/app_network_image.dart';

/// La vignette d'une ligne du stockage : l'affiche, ou une icône de film ou
/// de série quand le titre n'en a pas.
class StoragePoster extends StatelessWidget {
  const StoragePoster({
    super.key,
    required this.url,
    required this.isShow,
    this.width = 40,
  });

  final String? url;
  final bool isShow;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.5;
    final fallback = Container(
      width: width,
      height: height,
      color: AppColors.surfaceElevated,
      alignment: Alignment.center,
      child: Icon(isShow ? Icons.tv_rounded : Icons.movie_rounded,
          size: width * 0.45, color: AppColors.textMuted),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: AppNetworkImage(
        url: cardPosterUrl(url,
            serverBaseUrl: context.read<ApiClient>().baseUrl),
        width: width,
        height: height,
        placeholder: Container(
            width: width, height: height, color: AppColors.surfaceElevated),
        errorWidget: fallback,
      ),
    );
  }
}
