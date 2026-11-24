import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../models/watch_list.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_focus.dart';
import 'list_progress.dart';

/// Le cadre d'une carte de la vue large : fond, filet, et le contour blanc du
/// focus. La télécommande et le clavier passent par [TvFocusable] ; le contour
/// dit le focus, pas un second anneau autour de la carte.
class _FocusCard extends StatefulWidget {
  const _FocusCard({
    required this.label,
    required this.onTap,
    required this.child,
    this.autofocus = false,
    this.subdued = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  /// Une carte au second plan : fond de page, filet plus discret.
  final bool subdued;
  final Widget child;

  @override
  State<_FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<_FocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: TvFocusable(
        autofocus: widget.autofocus,
        onSelect: widget.onTap,
        focusScale: 1.0,
        showRing: false,
        onFocusChange: (f) => setState(() => _focused = f),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.fade(context),
            curve: AppMotion.curve,
            decoration: BoxDecoration(
              color: widget.subdued
                  ? AppColors.surface
                  : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused ? AppColors.focus : AppColors.border,
                width: _focused ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Une carte de « Mes listes » dans la vue large : un bandeau d'affiches
/// entières, le nom, la barre d'avancement et ce qui vient ensuite (ADR-0159).
class WatchListCard extends StatelessWidget {
  const WatchListCard({
    super.key,
    required this.list,
    required this.onTap,
    this.autofocus = false,
  });

  final WatchList list;
  final VoidCallback onTap;
  final bool autofocus;

  /// Les affiches d'un bandeau : quatre, comme le serveur en donne.
  static const bannerSlots = 4;
  static const _pad = 10.0;
  static const _gap = 6.0;

  /// La hauteur d'une carte de largeur [cardWidth], pour une grille à hauteur
  /// fixe : le bandeau, puis une zone de texte qui suit l'échelle du texte.
  static double heightFor(BuildContext context, double cardWidth) {
    final posterWidth =
        (cardWidth - 2 * _pad - (bannerSlots - 1) * _gap) / bannerSlots;
    final scaler = MediaQuery.textScalerOf(context);
    final text = scaler.scale(AppType.callout * 1.4) +
        scaler.scale(AppType.footnote * 1.4);
    // Bandeau, nom, barre, ligne, avec leurs espaces.
    return _pad + posterWidth * 1.5 + 12 + text + 4 + 8 + 14 + 2;
  }

  @override
  Widget build(BuildContext context) {
    final line = watchListProgressLine(list);
    final urls = watchListPosterUrls(context, list, max: bannerSlots);
    return _FocusCard(
      label: tr('Ouvrir la liste {0}', [list.displayName]),
      onTap: onTap,
      autofocus: autofocus,
      child: Padding(
        padding: const EdgeInsets.all(_pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final width = (constraints.maxWidth - (bannerSlots - 1) * _gap) /
                  bannerSlots;
              return Row(
                children: [
                  for (var i = 0; i < bannerSlots; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(
                      child: WatchListPoster(
                        url: i < urls.length ? urls[i] : null,
                        width: width,
                      ),
                    ),
                  ],
                ],
              );
            }),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    list.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: AppType.callout,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  list.isShared ? AppIcons.sharedList : AppIcons.privateList,
                  size: 16,
                  color: AppColors.textMuted,
                  semanticLabel: list.isShared ? tr('Partagée') : tr('Privée'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (list.hasProgress) ...[
              WatchListProgressBar(value: list.watchedFraction),
              const SizedBox(height: 8),
            ],
            WatchListProgressText(line),
          ],
        ),
      ),
    );
  }
}

/// Une carte de « Partagées par les autres » : plus discrète, trois
/// mini-affiches, le nom, son propriétaire et où en est le compte.
class SharedWatchListCard extends StatelessWidget {
  const SharedWatchListCard({
    super.key,
    required this.list,
    required this.onTap,
  });

  final WatchList list;
  final VoidCallback onTap;

  static const posterSlots = 3;
  static const _posterWidth = 40.0;
  static const _overlap = 14.0;

  /// La teinte de la pastille d'un propriétaire : stable d'un lancement à
  /// l'autre (comme celle des profils de « Qui regarde ? »).
  static Color tintFor(int ownerId) =>
      AppColors.profileTints[ownerId.abs() % AppColors.profileTints.length];

  @override
  Widget build(BuildContext context) {
    final urls = watchListPosterUrls(context, list, max: posterSlots);
    final owner = list.owner.username;
    final count = list.itemCount == 1
        ? tr('1 titre')
        : tr('{0} titres', [list.itemCount]);
    return _FocusCard(
      label: tr('Ouvrir la liste {0}', [list.displayName]),
      onTap: onTap,
      subdued: true,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _MiniPosters(urls: urls),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    list.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tintFor(list.owner.id),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          owner.isEmpty
                              ? '?'
                              : owner.characters.first.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: AppType.micro,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$owner · $count',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: AppType.footnote),
                        ),
                      ),
                    ],
                  ),
                  if (list.hasProgress) ...[
                    const SizedBox(height: 8),
                    WatchListProgressBar(
                        value: list.watchedFraction, height: 3),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trois affiches qui se chevauchent à peine.
class _MiniPosters extends StatelessWidget {
  const _MiniPosters({required this.urls});

  final List<String?> urls;

  @override
  Widget build(BuildContext context) {
    const w = SharedWatchListCard._posterWidth;
    const step = w - SharedWatchListCard._overlap;
    final slots = SharedWatchListCard.posterSlots;
    return ExcludeSemantics(
      child: SizedBox(
        width: w + step * (slots - 1),
        height: w * 1.5,
        child: Stack(
          children: [
            // La première affiche passe devant : on pose les autres d'abord.
            for (var i = slots - 1; i >= 0; i--)
              Positioned(
                left: step * i,
                top: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  child: WatchListPoster(
                    url: i < urls.length ? urls[i] : null,
                    width: w,
                    radius: 4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Le cadre en pointillé qui dit où apparaîtront les listes que les autres
/// comptes partageront.
class NoSharedListsFrame extends StatelessWidget {
  const NoSharedListsFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedFrame(color: AppColors.border),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Row(
          children: [
            const Icon(AppIcons.sharedList,
                size: 28, color: AppColors.textMuted),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Personne n’a encore partagé de liste sur ce serveur.'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('Quand un autre compte partagera une liste, elle '
                        'apparaîtra ici.'),
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: AppType.subhead),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedFrame extends CustomPainter {
  const _DashedFrame({required this.color});

  final Color color;

  static const _dash = 6.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(14)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame old) => old.color != color;
}
