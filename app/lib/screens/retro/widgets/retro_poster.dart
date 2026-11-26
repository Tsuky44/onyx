import 'package:flutter/widgets.dart';

import '../../../utils/poster_url.dart';
import '../../../widgets/global/app_network_image.dart';
import '../../../widgets/global/media_logo_display.dart';
import 'retro_entrance.dart';
import 'retro_type.dart';

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
    final hue = _hueOf(title);
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

/// La teinte d'un titre sans affiche : la même d'un écran à l'autre.
double _hueOf(String title) => (title.hashCode % 360).abs().toDouble();

/// Tout l'écran teinté par une affiche : l'affiche décodée sur une dizaine de
/// pixels, puis étirée. L'étirement lisse les couleurs comme un flou, sans en
/// calculer un à chaque image (ce qu'un téléviseur ne tient pas). Sans
/// affiche, la teinte du dégradé de secours.
class RetroPosterTint extends StatelessWidget {
  const RetroPosterTint({
    super.key,
    required this.posterUrl,
    required this.title,
    required this.serverBaseUrl,
  });

  final String posterUrl;
  final String title;
  final String? serverBaseUrl;

  /// La largeur de décodage : assez peu pour qu'il ne reste que des couleurs.
  static const int _pixels = 10;

  @override
  Widget build(BuildContext context) {
    final url = cardPosterUrl(posterUrl, serverBaseUrl: serverBaseUrl);
    final hue = _hueOf(title);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.5, -0.2),
          radius: 1.1,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.7, 0.45).toColor(),
            HSLColor.fromAHSL(1, (hue + 30) % 360, 0.5, 0.12).toColor(),
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
    if (url == null || url.isEmpty) return fallback;
    return Image(
      image: AppNetworkImage.providerFor(url, memCacheWidth: _pixels),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, _) =>
          frame == null ? fallback : child,
      errorBuilder: (context, _, __) => fallback,
    );
  }
}

/// Le logo du titre (TMDB) à la place de son nom, qui ne revient que quand le
/// logo manque. Il arrive comme un grand titre : il monte et apparaît.
class RetroTitleLogo extends StatelessWidget {
  const RetroTitleLogo({
    super.key,
    required this.title,
    required this.logoUrl,
    required this.height,
    required this.width,
    required this.size,
    this.delay = const Duration(milliseconds: 250),
  });

  final String title;
  final String? logoUrl;
  final double height;
  final double width;

  /// La taille du titre écrit, en unités du Rétro.
  final double size;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return RetroReveal.rise(
      delay: delay,
      child: MediaLogoDisplay(
        title: title,
        logoUrl: logoUrl,
        maxHeight: height,
        maxWidth: width,
        textStyle: RetroBig.styleOf(context, size).copyWith(
          color: DefaultTextStyle.of(context).style.color,
        ),
      ),
    );
  }
}
