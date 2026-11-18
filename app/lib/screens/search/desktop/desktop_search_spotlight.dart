import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../models/media_request.dart';
import '../../../models/models.dart';
import '../../../utils/poster_url.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/unavailable_badge.dart';
import '../../library/widgets/library_spotlight.dart';
import '../../library/widgets/library_tv_view.dart';
import '../../library/widgets/spotlight_scale.dart';
import 'desktop_search_controller.dart';
import '../search_layout.dart';

/// Le volet gauche de la recherche du bureau : le titre sélectionné (sous le
/// pointeur ou les flèches), présenté comme dans le volet d'une bibliothèque
/// sur téléviseur. On y retrouve l'image de fond, le logo ou le titre, une
/// ligne de métadonnées et le résumé (`LibrarySpotlight`, ADR-0123).
///
/// Le volet de la télévision se fond dans une page opaque. Ici, la page est
/// le voile de la recherche, à travers lequel on devine celle d'avant : un
/// fondu vers la couleur du fond y laissait une couture. Le volet s'efface
/// donc vers la transparence, sur la largeur où les affiches commencent.
///
/// Il a les proportions de celui de l'Apple TV, comme le volet d'une
/// bibliothèque ([SpotlightScale], ADR-0156) : [scale] l'agrandit avec la
/// fenêtre.
class DesktopSearchSpotlight extends StatelessWidget {
  const DesktopSearchSpotlight({
    super.key,
    required this.controller,
    this.scale = 1,
  });

  final DesktopSearchController controller;
  final double scale;

  /// La largeur du texte, celle du volet d'une bibliothèque sur téléviseur.
  static double get textWidth => LibraryTvView.textWidth;

  /// L'image de fond déborde sous les premières affiches avant de s'effacer.
  static const double overhang = 170;

  /// La place que le volet prend à gauche des affiches, avant
  /// l'agrandissement ([SpotlightScale.factorFor]).
  static double paneWidth(BuildContext context) =>
      AppLayout.pagePadding(context) * 2 + textWidth;

  @override
  Widget build(BuildContext context) {
    // Mesuré avant l'agrandissement, comme le volet que [SpotlightScale] met
    // en page : le fondu tombe au même endroit de la fiche à toute échelle.
    final pane = paneWidth(context);
    final total = pane + overhang;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: const [Colors.white, Colors.white, Colors.transparent],
        stops: [0, (pane - 40) / total, 1],
      ).createShader(bounds),
      child: SpotlightScale(
        scale: scale,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final hit = controller.current;
            if (hit == null) return const SizedBox.expand();
            return switch (hit) {
              LibraryHit(:final media) => LibrarySpotlight(
                  // Une seule fiche pour tous les titres de la bibliothèque :
                  // l'image d'un titre se fond dans la suivante.
                  key: const ValueKey('library'),
                  media: media,
                  eyebrow: librarySpotlightEyebrow(context, media),
                  textWidth: textWidth,
                ),
              UnavailableHit(:final item) => _unavailable(item),
            };
          },
        ),
      ),
    );
  }

  Widget _unavailable(RequestMediaItem item) {
    final backdrop = detailBackdropUrl(item.backdropUrl);
    final isMovie = item.mediaType == RequestMediaType.movie;
    return LibrarySpotlight(
      // Sans image connue, une fiche neuve : l'image du titre précédent ne
      // doit pas rester sous celui-ci.
      key: backdrop == null
          ? ValueKey(('catalog', item.mediaType, item.id))
          : const ValueKey('catalog'),
      // Un rang négatif : ce titre n'a pas de fiche dans la bibliothèque, le
      // volet ne la demande pas.
      media: Media(
        id: -item.id,
        type: isMovie ? MediaType.movie : MediaType.show,
        title: item.title,
        duration: 0,
        overview: item.overview,
        releaseDate: item.releaseDate,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      eyebrow: [
        isMovie ? tr('Film') : tr('Série'),
        UnavailableBadge.labelFor(
          requested: item.status != RequestMediaStatus.unknown,
        ),
      ].join(' · '),
      textWidth: textWidth,
      backdropUrl: backdrop,
    );
  }
}
