import 'package:material_ui/material_ui.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../l10n/tr.dart';
import '../../../widgets/global/onyx_menu.dart';
import '../../../widgets/global/poster_grid_display_menu.dart';

/// L'en-tête d'un catalogue : le titre, le nombre de titres et le tri, sur une
/// seule ligne.
///
/// Ils étaient empilés sur trois — le titre, puis une boîte de tri seule à
/// droite, puis le compte en dessous à gauche — soit une centaine de pixels
/// perdus avant la première affiche, et un menu déroulant Material encadré au
/// milieu d'un écran de verre.
class CatalogHeader<T> extends StatelessWidget {
  final String title;

  /// « 28 films ». Null pendant le chargement.
  final String? countLabel;
  final Map<T, String> sortOptions;
  final T sort;
  final ValueChanged<T> onSortChanged;
  final bool compact;

  /// Non nul hors téléviseur : un bouton « Filtres » prend la place du menu
  /// de tri, qui passe dans le panneau des filtres avec le reste.
  final VoidCallback? onFilters;

  /// Le nombre de familles de filtres posées, le tri mis à part.
  final int activeFilters;

  const CatalogHeader({
    super.key,
    required this.title,
    required this.countLabel,
    required this.sortOptions,
    required this.sort,
    required this.onSortChanged,
    this.compact = false,
    this.onFilters,
    this.activeFilters = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // Le titre et le compte prennent toute la place restante (Expanded) pour
        // que le tri reste collé au bord droit : un Flexible suivi d'un Spacer
        // se partageraient le vide, et le tri s'arrêterait au milieu de la ligne.
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Le titre est le nom qu'un administrateur a donné à sa
              // bibliothèque : sa longueur n'est pas la nôtre, il se coupe
              // plutôt que de déborder.
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 28 : 34,
                        letterSpacing: compact ? -0.6 : -0.9,
                      ),
                ),
              ),
              if (countLabel != null) ...[
                const SizedBox(width: 12),
                Text(
                  countLabel!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onFilters != null)
          _FiltersButton(
            onPressed: onFilters!,
            active: activeFilters,
            compact: compact,
          )
        else
          OnyxMenuButton<T>(
            tooltip: tr('Trier'),
            onSelected: onSortChanged,
            items: [
              for (final entry in sortOptions.entries)
                OnyxMenuItem<T>(
                  value: entry.key,
                  label: tr(entry.value),
                  checked: entry.key == sort,
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(sortOptions[sort] ?? ''),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(AppIcons.sort,
                      size: 18, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        if (PosterGridDisplayMenu.availableIn(context)) ...[
          const SizedBox(width: 12),
          // La ligne est alignée sur la ligne de base du texte, que le bouton
          // n'a pas : on place son centre à hauteur des minuscules. Sur un
          // téléphone, l'icône seule laisse la place au titre.
          Baseline(
            baseline: 19,
            baselineType: TextBaseline.alphabetic,
            child: PosterGridDisplayMenu(compact: compact),
          ),
        ],
      ],
    );
  }
}

/// Le bouton « Filtres » de l'en-tête, dans le dessin du menu de tri qu'il
/// remplace : du texte secondaire et une icône, sans cadre. Avec un filtre
/// posé, il passe en blanc et dit le compte.
class _FiltersButton extends StatelessWidget {
  const _FiltersButton({
    required this.onPressed,
    required this.active,
    required this.compact,
  });

  final VoidCallback onPressed;
  final int active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = active > 0 ? tr('Filtres · {0}', [active]) : tr('Filtres');
    final color = active > 0 ? AppColors.textPrimary : AppColors.textSecondary;
    return Tooltip(
      message: tr('Trier et filtrer'),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: AppType.body,
                  fontWeight: active > 0 ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Icon(AppIcons.filters, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
