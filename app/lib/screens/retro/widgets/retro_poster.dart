import 'package:flutter/widgets.dart';

import '../../../utils/poster_url.dart';
import '../../../widgets/global/app_network_image.dart';

/// Une affiche du Rétro. Sans image (un titre que TMDB n'a pas trouvé), un
/// dégradé dont la teinte vient du titre, pour que chaque titre garde sa
/// couleur d'un écran à l'autre.
class RetroPoster extends StatelessWidget {
  const RetroPoster({
    super.key,
    required this.posterUrl,
    required this.title,
    required this.serverBaseUrl,
    required this.width,
    this.showTitle = false,
  });

  final String posterUrl;
  final String title;
  final String? serverBaseUrl;
  final double width;

  /// Écrit le titre sur le dégradé quand l'image manque.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final url = cardPosterUrl(posterUrl, serverBaseUrl: serverBaseUrl);
    final fallback =
        _Fallback(title: title, showTitle: showTitle, width: width);
    return Semantics(
      label: title,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.07),
        child: SizedBox(
          width: width,
          height: width * 1.5,
          child: url == null || url.isEmpty
              ? fallback
              : AppNetworkImage(
                  url: url,
                  width: width,
                  height: width * 1.5,
                  fit: BoxFit.cover,
                  placeholder: fallback,
                  errorWidget: fallback,
                ),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.title,
    required this.showTitle,
    required this.width,
  });

  final String title;
  final bool showTitle;
  final double width;

  @override
  Widget build(BuildContext context) {
    final hue = (title.hashCode % 360).abs().toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.6, -0.8),
          radius: 1.3,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.85, 0.6).toColor(),
            HSLColor.fromAHSL(1, (hue + 30) % 360, 0.5, 0.14).toColor(),
          ],
        ),
      ),
      child: showTitle
          ? Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.all(width * 0.07),
                child: Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFFFFFFF),
                    fontSize: width * 0.11,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            )
          : const SizedBox.expand(),
    );
  }
}
