import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../l10n/tr.dart';
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

  const CatalogHeader({
    super.key,
    required this.title,
    required this.countLabel,
    required this.sortOptions,
    required this.sort,
    required this.onSortChanged,
    this.compact = false,
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
        PopupMenuButton<T>(
          tooltip: tr('Trier'),
          initialValue: sort,
          position: PopupMenuPosition.under,
          onSelected: onSortChanged,
          itemBuilder: (_) => [
            for (final entry in sortOptions.entries)
              CheckedPopupMenuItem<T>(
                value: entry.key,
                checked: entry.key == sort,
                child: Text(tr(entry.value)),
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

/// Le tri d'un catalogue en capsule, pour un téléviseur (ADR-0123) : le même
/// menu que celui de [CatalogHeader], ouvert par un vrai bouton.
///
/// Un `PopupMenuButton` n'a pas d'état focalisé à lui : son libellé gris
/// restait gris sur le voile du focus. Un bouton du thème se remplit de
/// blanc comme toute commande d'un téléviseur ([FocusFill], ADR-0112).
class CatalogSortCapsule<T> extends StatelessWidget {
  const CatalogSortCapsule({
    super.key,
    required this.sortOptions,
    required this.sort,
    required this.onSortChanged,
  });

  final Map<T, String> sortOptions;
  final T sort;
  final ValueChanged<T> onSortChanged;

  Future<void> _open(BuildContext context) async {
    final button = context.findRenderObject();
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox) return;
    // Sous le bouton, calé sur son bord droit : c'est là qu'il est posé.
    final below = Rect.fromPoints(
      button.localToGlobal(button.size.bottomLeft(const Offset(0, 6)),
          ancestor: overlay),
      button.localToGlobal(button.size.bottomRight(const Offset(0, 6)),
          ancestor: overlay),
    );
    final picked = await showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(below, Offset.zero & overlay.size),
      initialValue: sort,
      items: [
        for (final entry in sortOptions.entries)
          CheckedPopupMenuItem<T>(
            value: entry.key,
            checked: entry.key == sort,
            child: Text(tr(entry.value)),
          ),
      ],
    );
    if (picked != null) onSortChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr('Trier'),
      child: OutlinedButton.icon(
        onPressed: () => _open(context),
        iconAlignment: IconAlignment.end,
        icon: const Icon(AppIcons.sort, size: 18),
        label: Text(tr(sortOptions[sort] ?? '')),
      ),
    );
  }
}
