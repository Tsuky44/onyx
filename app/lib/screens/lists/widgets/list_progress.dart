import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/watch_list.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/poster_url.dart';
import '../../../widgets/global/app_network_image.dart';
import 'watch_list_tile.dart' show watchListCaption;

/// « 3 vus sur 12 » : ce que le compte a vu d'une liste, M comptant aussi ce
/// qu'il reste à demander (ADR-0159).
String watchedOfText(int watched, int total) =>
    trPlural(watched, '{0} vu sur {1}', '{0} vus sur {1}', [total]);

/// « 2 à demander » : les titres de la liste que le serveur n'a pas.
String toRequestText(int count) => tr('{0} à demander', [count]);

/// La ligne d'une carte de liste sous sa barre : ce qui est vu et ce qui vient
/// ensuite, ou ce qu'il reste à demander. [warn] colore la ligne quand rien
/// n'est regardable.
({String text, bool warn}) watchListProgressLine(WatchList list) {
  if (!list.hasProgress) return (text: watchListCaption(list), warn: false);
  if (list.itemCount == 0) return (text: tr('Aucun titre'), warn: false);
  final watched = list.watchedCount!;
  final toRequest = list.toRequestCount;
  final next = list.nextItem;
  if (watched == 0) {
    if (list.onServerCount == 0 && toRequest > 0) {
      return (text: toRequestText(toRequest), warn: true);
    }
    return (text: tr('Rien de vu sur {0}', [list.itemCount]), warn: false);
  }
  final seen = watchedOfText(watched, list.itemCount);
  if (next != null) {
    return (text: tr('{0} · prochain : {1}', [seen, next.title]), warn: false);
  }
  if (toRequest > 0) {
    return (text: '$seen · ${toRequestText(toRequest)}', warn: true);
  }
  return (text: seen, warn: false);
}

/// Les adresses d'affiches d'une liste, au format de la vignette.
List<String?> watchListPosterUrls(BuildContext context, WatchList list,
    {int? max}) {
  final baseUrl = context.read<ApiClient>().baseUrl;
  final urls = [
    for (final p in list.posters) cardPosterUrl(p, serverBaseUrl: baseUrl),
  ];
  return max == null || urls.length <= max ? urls : urls.sublist(0, max);
}

/// La barre d'avancement d'une liste : fine, blanche sur fond de filet.
class WatchListProgressBar extends StatelessWidget {
  const WatchListProgressBar({super.key, required this.value, this.height = 4});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.border),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: const ColoredBox(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une affiche entière, ou une case vide à sa place : une rangée garde sa
/// forme que la liste ait un, trois ou quatre titres.
class WatchListPoster extends StatelessWidget {
  const WatchListPoster({
    super.key,
    required this.url,
    required this.width,
    this.radius = 6,
  });

  final String? url;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: url == null
            ? const ColoredBox(color: AppColors.surface)
            : AppNetworkImage(
                url: url,
                fit: BoxFit.cover,
                decodeWidth: width,
                placeholder: const ColoredBox(color: AppColors.surface),
                errorWidget: const ColoredBox(color: AppColors.surface),
              ),
      ),
    );
  }
}

/// Le texte de la ligne de progression : [warn] en `AppColors.warning`.
class WatchListProgressText extends StatelessWidget {
  const WatchListProgressText(this.line, {super.key});

  final ({String text, bool warn}) line;

  @override
  Widget build(BuildContext context) {
    return Text(
      line.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: line.warn ? AppColors.warning : AppColors.textMuted,
        fontSize: AppType.footnote,
      ),
    );
  }
}

/// Quatre affiches qui se chevauchent, la dernière ajoutée devant : la tête
/// de « À regarder plus tard » et du détail d'une liste.
class WatchListPosterFan extends StatelessWidget {
  const WatchListPosterFan({
    super.key,
    required this.urls,
    this.posterWidth = 84,
  });

  final List<String?> urls;
  final double posterWidth;

  double get _posterWidth => posterWidth;
  double get _step => posterWidth * 0.4;

  @override
  Widget build(BuildContext context) {
    final count = math.max(urls.length, 1);
    final width = _posterWidth + _step * (count - 1);
    // Un éventail de pose : l'angle monte de gauche à droite, autour de 0.
    final angles = [
      for (var i = 0; i < count; i++)
        count == 1 ? 0.0 : (i - (count - 1) / 2) * 0.07,
    ];
    return ExcludeSemantics(
      child: SizedBox(
        width: width + 16,
        height: _posterWidth * 1.5 + 16,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (urls.isEmpty)
              const Icon(AppIcons.inList, size: 40, color: AppColors.textMuted)
            else
              // La plus ancienne d'abord : la dernière ajoutée finit au-dessus.
              for (var i = urls.length - 1; i >= 0; i--)
                Positioned(
                  left: 8 + _step * (urls.length - 1 - i),
                  top: 8,
                  child: Transform.rotate(
                    angle: angles[urls.length - 1 - i],
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: AppColors.surfaceElevated, width: 2),
                      ),
                      child: SizedBox(
                        width: _posterWidth,
                        child: WatchListPoster(
                            url: urls[i], width: _posterWidth, radius: 5),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
