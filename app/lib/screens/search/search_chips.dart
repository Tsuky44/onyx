// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import 'search_layout.dart';

/// Les pastilles au-dessus des résultats d'une recherche : Tout, Films,
/// Séries, Pas sur le serveur, chacune avec son décompte.
///
/// Le bureau les range sur plusieurs lignes ; le téléphone sur une seule, qui
/// défile sous le pouce ([scrolls]) : deux lignes de pastilles mangeraient la
/// place que le clavier laisse aux résultats.
class SearchFilterChips extends StatelessWidget {
  const SearchFilterChips({
    super.key,
    required this.layout,
    required this.selected,
    required this.onSelected,
    required this.showUnavailable,
    this.scrolls = false,
    this.padding = EdgeInsets.zero,
  });

  final SearchLayout layout;
  final SearchFilter selected;
  final ValueChanged<SearchFilter> onSelected;

  /// Faux pour un compte qui ne peut rien demander : il ne voit jamais de
  /// titre absent, la pastille n'aurait rien à garder.
  final bool showUnavailable;

  /// Vrai : une seule ligne qui défile de côté.
  final bool scrolls;

  /// Les marges de la ligne qui défile, pour que la première pastille
  /// s'aligne sur la page et que la dernière ne colle pas au bord.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final chips = <(SearchFilter, String, int)>[
      (SearchFilter.all, tr('Tout'), layout.total),
      (SearchFilter.movies, tr('Films'), layout.movieCount),
      (SearchFilter.shows, tr('Séries'), layout.showCount),
      if (showUnavailable)
        (
          SearchFilter.unavailable,
          tr('Pas sur le serveur'),
          layout.unavailableCount
        ),
    ];
    final children = [
      for (final (filter, label, count) in chips)
        SearchFilterChip(
          label: label,
          count: count,
          selected: selected == filter,
          // Une pastille vide ne garderait rien : on ne la choisit pas.
          onTap: count == 0 && filter != SearchFilter.all
              ? null
              : () => onSelected(filter),
        ),
    ];
    // De la même région de toucher que le champ : toucher une pastille n'est
    // pas quitter le champ, et la frappe continue (ADR-0141). Sans elle, le
    // toucher retirait le focus au champ, sur un bureau comme sur un écran
    // tactile.
    return TextFieldTapRegion(
      child: !scrolls
          ? Wrap(spacing: 8, runSpacing: 8, children: children)
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: padding,
              child: Row(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    children[i],
                  ],
                ],
              ),
            ),
    );
  }
}

/// Une pastille de filtre et son décompte.
class SearchFilterChip extends StatefulWidget {
  const SearchFilterChip({
    super.key,
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
  State<SearchFilterChip> createState() => _SearchFilterChipState();
}

class _SearchFilterChipState extends State<SearchFilterChip> {
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
