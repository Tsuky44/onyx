import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_mode.dart';
import '../../utils/poster_grid_zoom.dart';
import '../../utils/responsive.dart';

/// Le bouton « Affichage » : un menu déroulant à quatre modes (4, 6, 8 ou 10
/// affiches par ligne), le pendant, à la souris et au doigt, du Ctrl + molette
/// de `PosterGridZoomRegion`.
///
/// Se pose en haut à droite d'une page en grille, sous une région de zoom : il
/// lit et règle le même choix que la molette, et les grilles suivent.
/// Absent sur un téléviseur, où la télécommande n'a pas de molette et où un
/// bouton de plus ne ferait qu'un arrêt de plus pour le focus.
class PosterGridDisplayMenu extends StatelessWidget {
  const PosterGridDisplayMenu({super.key, this.compact = false});

  /// Réduit le bouton à son icône, pour les en-têtes de téléphone où le texte
  /// ne tient pas à côté du titre.
  final bool compact;

  /// Faux sur un téléviseur : l'appelant s'en sert pour ne pas laisser d'espace
  /// vide à la place du bouton.
  static bool availableIn(BuildContext context) => !TvScope.of(context);

  /// Plus il y a d'affiches par ligne, plus l'icône du mode est dense.
  static IconData _iconFor(int columns) =>
      columns >= 8 ? AppIcons.postersSmall : AppIcons.postersLarge;

  @override
  Widget build(BuildContext context) {
    if (!availableIn(context)) return const SizedBox.shrink();
    final zoom = PosterGridZoomScope.watch(context);
    final selected = zoom.selected;
    return PopupMenuButton<int>(
      tooltip: tr('Affichage'),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      padding: EdgeInsets.zero,
      initialValue: selected,
      onSelected: zoom.select,
      itemBuilder: (_) => [
        for (final columns in PosterGridZoom.presets)
          PopupMenuItem<int>(
            value: columns,
            child: _ModeRow(columns: columns, selected: columns == selected),
          ),
      ],
      child: _Trigger(compact: compact),
    );
  }
}

class _Trigger extends StatelessWidget {
  const _Trigger({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: AppLayout.minTouchTarget(context)),
      child: Center(
        widthFactor: 1,
        child: Container(
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.postersLarge,
                  size: 18, color: AppColors.textSecondary),
              if (!compact) ...[
                const SizedBox(width: 8),
                Text(
                  tr('Affichage'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(AppIcons.expand,
                    size: 16, color: AppColors.textSecondary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.columns, required this.selected});

  final int columns;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          PosterGridDisplayMenu._iconFor(columns),
          size: 18,
          color: selected ? AppColors.accent : AppColors.textSecondary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            tr('{0} par ligne', [columns]),
            style: TextStyle(
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 16),
        // La place du repère est réservée même quand il est absent : le texte
        // des quatre lignes reste aligné.
        Icon(
          AppIcons.check,
          size: 16,
          color: selected ? AppColors.accent : Colors.transparent,
        ),
      ],
    );
  }
}

/// Une rangée à droite, entre l'en-tête d'une page et sa grille, pour les
/// pages dont l'en-tête n'a pas de ligne où loger le bouton. Vide sur un
/// téléviseur.
class SliverPosterGridDisplayBar extends StatelessWidget {
  const SliverPosterGridDisplayBar({super.key});

  /// L'espace que la barre ajoute au-dessus de la grille ; les pages qui la
  /// posent en retranchent autant du haut de leur grille.
  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    if (!PosterGridDisplayMenu.availableIn(context)) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: AppLayout.pageInsets(context),
        child: const SizedBox(
          height: height,
          child: Align(
            alignment: Alignment.centerRight,
            child: PosterGridDisplayMenu(),
          ),
        ),
      ),
    );
  }
}
