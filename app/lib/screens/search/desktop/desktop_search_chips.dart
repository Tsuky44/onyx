import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import 'desktop_search_controller.dart';
import 'desktop_search_hits.dart';

/// Les pastilles au-dessus des résultats du bureau : Tout, Films, Séries,
/// Pas sur le serveur, chacune avec son décompte.
///
/// Elles ne prennent jamais le focus : on les clique, et le champ de
/// l'en-tête garde la frappe.
class DesktopSearchChips extends StatelessWidget {
  const DesktopSearchChips({
    super.key,
    required this.controller,
    required this.layout,
    required this.showUnavailable,
  });

  final DesktopSearchController controller;
  final DesktopSearchLayout layout;

  /// Faux pour un compte qui ne peut rien demander : il ne voit jamais de
  /// titre absent, la pastille n'aurait rien à garder.
  final bool showUnavailable;

  @override
  Widget build(BuildContext context) {
    final chips = <(DesktopSearchFilter, String, int)>[
      (DesktopSearchFilter.all, tr('Tout'), layout.total),
      (DesktopSearchFilter.movies, tr('Films'), layout.movieCount),
      (DesktopSearchFilter.shows, tr('Séries'), layout.showCount),
      if (showUnavailable)
        (
          DesktopSearchFilter.unavailable,
          tr('Pas sur le serveur'),
          layout.unavailableCount
        ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (filter, label, count) in chips)
          _FilterChip(
            label: label,
            count: count,
            selected: controller.filter.value == filter,
            // Une pastille vide ne garderait rien : on ne la choisit pas.
            onTap: count == 0 && filter != DesktopSearchFilter.all
                ? null
                : () => controller.setFilter(filter),
          ),
      ],
    );
  }
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final selected = widget.selected;
    final fill = selected
        ? AppColors.textPrimary
        : Colors.white.withValues(alpha: _hovered && enabled ? 0.12 : 0.07);
    final ink = selected
        ? AppColors.background
        : enabled
            ? AppColors.textPrimary
            : AppColors.textMuted;
    final countInk = selected
        ? AppColors.background.withValues(alpha: 0.6)
        : AppColors.textMuted;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${widget.label} ${widget.count}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.fade(context),
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: widget.label),
                  TextSpan(
                    text: '  ${widget.count}',
                    style: TextStyle(
                      color: countInk,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                color: ink,
                fontSize: AppType.subhead,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Une recherche récente, qu'un clic retape dans le champ.
class RecentSearchChip extends StatefulWidget {
  const RecentSearchChip({super.key, required this.query, required this.onTap});

  final String query;
  final VoidCallback onTap;

  @override
  State<RecentSearchChip> createState() => _RecentSearchChipState();
}

class _RecentSearchChipState extends State<RecentSearchChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.query,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.fade(context),
            curve: AppMotion.curve,
            padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _hovered ? 0.1 : 0.04),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  AppIcons.schedule,
                  size: 15,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 7),
                Text(
                  widget.query,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppType.subhead,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
