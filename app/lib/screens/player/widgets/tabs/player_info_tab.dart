import 'package:flutter/material.dart';

import '../../../../l10n/tr.dart';
import '../../../../models/models.dart';
import '../../../../theme/app_type.dart';
import '../../../../widgets/global/media_poster.dart';
import '../onyx/onyx_capsule_button.dart';
import '../onyx/onyx_chrome_theme.dart';

/// L'onglet « Infos » du lecteur : l'image du titre, ce qu'il raconte, et
/// l'épisode voisin quand il y en a un (ADR-0130).
class PlayerInfoTab extends StatelessWidget {
  const PlayerInfoTab({
    super.key,
    required this.media,
    required this.title,
    this.meta,
    this.overview,
    this.onPrevious,
    this.onNext,
  });

  /// Le média joué : son image.
  final Media media;

  /// Le titre du film, ou celui de l'épisode.
  final String title;

  /// La ligne sous le titre : la série, la saison et l'épisode, la durée.
  final String? meta;
  final String? overview;

  /// Nuls sur un film, ou au bord d'une saison.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// L'image d'un épisode est une vue de l'épisode, en 16:9 ; celle d'un film
  /// est son affiche.
  static const double _posterRatio = 2 / 3;
  static const double _stillRatio = 16 / 9;

  @override
  Widget build(BuildContext context) {
    final text = (overview ?? '').trim();
    final hasNeighbour = onPrevious != null || onNext != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isEpisode = media.type == MediaType.episode;
        // L'image prend la hauteur du volet, sans dépasser le tiers de sa
        // largeur : sur un téléphone, le texte garde la place de se lire.
        final maxImageWidth = constraints.maxWidth / 3;
        var imageHeight = constraints.maxHeight.clamp(0.0, 222.0);
        final ratio = isEpisode ? _stillRatio : _posterRatio;
        if (isEpisode) imageHeight = imageHeight.clamp(0.0, 166.0);
        var imageWidth = imageHeight * ratio;
        if (imageWidth > maxImageWidth) {
          imageWidth = maxImageWidth;
          imageHeight = imageWidth / ratio;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MediaPoster(
              media: media,
              width: imageWidth,
              height: imageHeight,
              borderRadius: 10,
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: OnyxChromeTheme.title,
                      fontSize: AppType.title2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (meta != null && meta!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OnyxChromeTheme.time,
                        fontSize: AppType.callout,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Le résumé prend ce qui reste : coupé plutôt que de pousser
                  // les boutons hors du volet.
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Text(
                        text.isEmpty ? tr('Aucun résumé disponible.') : text,
                        key: const ValueKey('player-info-overview'),
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          color: text.isEmpty
                              ? OnyxChromeTheme.meta
                              : OnyxChromeTheme.title,
                          fontSize: AppType.callout,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                  if (hasNeighbour) ...[
                    const SizedBox(height: 12),
                    OnyxControlsRow(
                      // Passe à la ligne sur un écran étroit plutôt que de
                      // déborder.
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (onPrevious != null)
                            OnyxCapsuleButton(
                              key: const ValueKey('player-info-previous'),
                              label: tr('Épisode précédent'),
                              icon: Icons.skip_previous_rounded,
                              onPressed: onPrevious,
                            ),
                          if (onNext != null)
                            OnyxCapsuleButton(
                              key: const ValueKey('player-info-next'),
                              label: tr('Épisode suivant'),
                              icon: Icons.skip_next_rounded,
                              onPressed: onNext,
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
