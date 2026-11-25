import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/global/filter_panel/filter_presets.dart';
import '../../../widgets/global/filter_panel/onyx_filter_chip.dart';
import '../../../widgets/global/filter_panel/onyx_filter_panel.dart';
import '../../../widgets/global/onyx_menu.dart';
import '../library_filters.dart';

/// Les libellés du tri d'une bibliothèque, lus par `tr()` à l'affichage.
const Map<LibrarySort, String> librarySortOptions = {
  LibrarySort.recent: 'Récents',
  LibrarySort.title: 'A → Z',
  LibrarySort.release: 'Date de sortie',
  LibrarySort.progress: 'En cours',
};

/// Le tri et les filtres d'une bibliothèque, dans le panneau des Demandes
/// (`OnyxFilterPanel`) : à droite de la grille sur grand écran, dans une
/// feuille du bas sur téléphone ([show]). Voir l'ADR du 2026-11-25.
///
/// La feuille est une route : elle ne se reconstruit pas avec l'écran. Le
/// panneau tient donc sa copie des filtres, recalée à chaque reconstruction
/// quand il vit dans l'écran.
class LibraryFiltersPanel extends StatefulWidget {
  const LibraryFiltersPanel({
    super.key,
    required this.filters,
    required this.isShows,
    required this.onChanged,
    required this.onClose,
    this.sheet = false,
  });

  final LibraryFilters filters;

  /// Une série n'a ni position de lecture à elle ni durée : le tri « En
  /// cours » et la durée ne valent que pour les films.
  final bool isShows;
  final ValueChanged<LibraryFilters> onChanged;
  final VoidCallback onClose;
  final bool sheet;

  /// La feuille du bas d'un téléphone.
  static Future<void> show(
    BuildContext context, {
    required LibraryFilters filters,
    required bool isShows,
    required ValueChanged<LibraryFilters> onChanged,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppColors.surfaceElevated,
        builder: (sheetContext) => LibraryFiltersPanel(
          filters: filters,
          isShows: isShows,
          onChanged: onChanged,
          onClose: () => Navigator.of(sheetContext).pop(),
          sheet: true,
        ),
      );

  @override
  State<LibraryFiltersPanel> createState() => _LibraryFiltersPanelState();
}

class _LibraryFiltersPanelState extends State<LibraryFiltersPanel> {
  late LibraryFilters _f = widget.filters;

  @override
  void didUpdateWidget(LibraryFiltersPanel old) {
    super.didUpdateWidget(old);
    _f = widget.filters;
  }

  void _update(LibraryFilters next) {
    setState(() => _f = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    final sorts = {
      for (final e in librarySortOptions.entries)
        if (!widget.isShows || e.key != LibrarySort.progress) e.key: e.value,
    };
    final watchLabels = {
      LibraryWatchFilter.unwatched: tr('Non vus'),
      LibraryWatchFilter.inProgress: tr('En cours'),
      LibraryWatchFilter.watched: tr('Vus'),
    };
    final period = filterPeriodPresets();
    final duration = filterDurationPresets();
    return OnyxFilterPanel(
      sheet: widget.sheet,
      onClose: widget.onClose,
      onClearAll: f.activeCount > 0 ? () => _update(f.cleared()) : null,
      children: [
        OnyxFilterInlineRow(
          title: tr('Trier par'),
          trailing: OnyxMenuButton<LibrarySort>(
            tooltip: tr('Trier par'),
            items: [
              for (final e in sorts.entries)
                OnyxMenuItem(
                  value: e.key,
                  label: tr(e.value),
                  checked: e.key == f.sort,
                ),
            ],
            onSelected: (v) => _update(f.copyWith(sort: v)),
            child: OnyxFilterChip(label: tr(sorts[f.sort] ?? '')),
          ),
        ),
        OnyxFilterSection(
          title: tr('Visionnage'),
          value: watchLabels[f.watch] ?? tr('Tous les titres'),
          active: f.watch != LibraryWatchFilter.all,
          onClear: () => _update(f.copyWith(watch: LibraryWatchFilter.all)),
          child: OnyxFilterPills(choices: [
            for (final e in watchLabels.entries)
              (
                label: e.value,
                selected: e.key == f.watch,
                onTap: () => _update(f.copyWith(
                    watch: e.key == f.watch ? LibraryWatchFilter.all : e.key)),
              ),
          ]),
        ),
        OnyxFilterSection(
          title: tr('Date de sortie'),
          value: filterRangeLabel(
              period, f.from, f.to, '', tr('Toutes les dates')),
          active: f.hasPeriod,
          onClear: () => _update(f.copyWith(from: '', to: '')),
          child: OnyxFilterRange(
            presets: period,
            from: f.from,
            to: f.to,
            onChanged: (from, to) => _update(f.copyWith(from: from, to: to)),
          ),
        ),
        if (!widget.isShows)
          OnyxFilterSection(
            title: tr('Durée'),
            value: filterRangeLabel(duration, f.minDuration, f.maxDuration,
                'min', tr('Toutes les durées')),
            active: f.hasDuration,
            onClear: () =>
                _update(f.copyWith(minDuration: '', maxDuration: '')),
            child: OnyxFilterRange(
              presets: duration,
              from: f.minDuration,
              to: f.maxDuration,
              onChanged: (min, max) =>
                  _update(f.copyWith(minDuration: min, maxDuration: max)),
            ),
          ),
      ],
    );
  }
}
