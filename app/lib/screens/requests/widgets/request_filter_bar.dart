import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../models/request_catalog_filters.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../widgets/global/onyx_menu.dart';
import 'request_filter_chip.dart';
import 'request_filter_panels.dart';
import 'request_filter_popover.dart';

/// La rangée de capsules au-dessus de la grille des demandes (bureau et
/// téléphone ; la TV garde la feuille des filtres) : Genres, Période,
/// Langue, Streaming, Durée, « Tout effacer » dès qu'un filtre est posé, et
/// le tri à droite. Voir ADR-0131.
///
/// La rangée ne charge rien : chaque changement remonte par [onChanged] avec
/// les filtres complets, et l'écran recharge la grille.
class RequestFilterBar extends StatefulWidget {
  const RequestFilterBar({
    super.key,
    required this.filters,
    required this.mediaType,
    required this.onChanged,
  });

  final RequestCatalogFilters filters;
  final String mediaType;
  final ValueChanged<RequestCatalogFilters> onChanged;

  /// Les filtres que « Tout effacer » retire : tout sauf le tri, qui a
  /// toujours une valeur et sa propre capsule.
  static RequestCatalogFilters cleared(RequestCatalogFilters f) =>
      RequestCatalogFilters.defaults.copyWith(sortBy: f.sortBy);

  /// Au moins un filtre posé, le tri mis à part.
  static bool hasActive(RequestCatalogFilters f) =>
      !cleared(f).equals(f);

  @override
  State<RequestFilterBar> createState() => _RequestFilterBarState();
}

class _RequestFilterBarState extends State<RequestFilterBar> {
  final _genresKey = GlobalKey();
  final _periodKey = GlobalKey();
  final _streamingKey = GlobalKey();
  final _durationKey = GlobalKey();

  /// Lu au moment du changement, pas à l'ouverture du panneau : l'écran
  /// reconstruit la rangée entre deux coches, et chaque coche part des
  /// filtres à jour.
  void _update(RequestCatalogFilters Function(RequestCatalogFilters) change) =>
      widget.onChanged(change(widget.filters));

  void _open(GlobalKey key, WidgetBuilder builder, {double height = 360}) {
    showRequestFilterPopover(
      context: context,
      anchorKey: key,
      builder: builder,
      estimatedHeight: height,
    );
  }

  static String _range(String from, String to, String unit) {
    final suffix = unit.isEmpty ? '' : ' $unit';
    if (from.isNotEmpty && to.isNotEmpty) return '$from – $to$suffix';
    if (from.isNotEmpty) return tr('Dès {0}', ['$from$suffix']);
    return tr('Jusqu’à {0}', ['$to$suffix']);
  }

  String _languageLabel(String code) {
    for (final opt in requestCatalogLanguageOptions) {
      if (opt.code == code) return tr(opt.label);
    }
    return code;
  }

  String _sortLabel(String value) {
    for (final opt in requestCatalogSortOptions) {
      if (opt.value == value) return tr(opt.label);
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filters;
    final hasPeriod = f.startDate.isNotEmpty || f.endDate.isNotEmpty;
    final hasDuration = f.minDuration.isNotEmpty || f.maxDuration.isNotEmpty;
    final hasLanguage = f.language != RequestCatalogFilters.defaults.language;

    final chips = <Widget>[
      RequestFilterChip(
        key: _genresKey,
        label: f.genres.isEmpty
            ? tr('Genres')
            : tr('Genres · {0}', [f.genres.length]),
        active: f.genres.isNotEmpty,
        onTap: () => _open(
          _genresKey,
          (_) => RequestGenresPanel(
            mediaType: widget.mediaType,
            initial: f.genres,
            onChanged: (ids) => _update((c) => c.copyWith(genres: ids)),
          ),
          height: 420,
        ),
        onClear: () => _update((c) => c.copyWith(genres: const [])),
      ),
      RequestFilterChip(
        key: _periodKey,
        label: hasPeriod ? _range(f.startDate, f.endDate, '') : tr('Période'),
        active: hasPeriod,
        onTap: () => _open(
          _periodKey,
          (_) => RequestRangePanel.period(
            start: f.startDate,
            end: f.endDate,
            onChanged: (start, end) =>
                _update((c) => c.copyWith(startDate: start, endDate: end)),
          ),
          height: 200,
        ),
        onClear: () => _update((c) => c.copyWith(startDate: '', endDate: '')),
      ),
      OnyxMenuButton<String>(
        tooltip: tr('Langue'),
        items: [
          for (final opt in requestCatalogLanguageOptions)
            OnyxMenuItem(
              value: opt.code,
              label: tr(opt.label),
              checked: opt.code == f.language,
            ),
        ],
        onSelected: (code) => _update((c) => c.copyWith(language: code)),
        child: RequestFilterChip(
          label: hasLanguage ? _languageLabel(f.language) : tr('Langue'),
          active: hasLanguage,
          onClear: () => _update((c) => c.copyWith(
              language: RequestCatalogFilters.defaults.language)),
        ),
      ),
      RequestFilterChip(
        key: _streamingKey,
        label: f.watchProviders.isEmpty
            ? tr('Streaming')
            : tr('Streaming · {0}', [f.watchProviders.length]),
        active: f.watchProviders.isNotEmpty,
        onTap: () => _open(
          _streamingKey,
          (_) => RequestStreamingPanel(
            mediaType: widget.mediaType,
            initialRegion: f.watchRegion,
            initialProviders: f.watchProviders,
            onChanged: (region, ids) => _update(
                (c) => c.copyWith(watchRegion: region, watchProviders: ids)),
          ),
          height: 420,
        ),
        onClear: () => _update((c) => c.copyWith(
              watchProviders: const [],
              watchRegion: RequestCatalogFilters.defaults.watchRegion,
            )),
      ),
      RequestFilterChip(
        key: _durationKey,
        label: hasDuration
            ? _range(f.minDuration, f.maxDuration, 'min')
            : tr('Durée'),
        active: hasDuration,
        onTap: () => _open(
          _durationKey,
          (_) => RequestRangePanel.duration(
            min: f.minDuration,
            max: f.maxDuration,
            onChanged: (min, max) =>
                _update((c) => c.copyWith(minDuration: min, maxDuration: max)),
          ),
          height: 130,
        ),
        onClear: () =>
            _update((c) => c.copyWith(minDuration: '', maxDuration: '')),
      ),
      if (RequestFilterBar.hasActive(f))
        TextButton(
          onPressed: () => _update(RequestFilterBar.cleared),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            textStyle: const TextStyle(
              fontSize: AppType.subhead,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(tr('Tout effacer')),
        ),
    ];

    final sort = OnyxMenuButton<String>(
      tooltip: tr('Trier par'),
      items: [
        for (final opt in requestCatalogSortOptions)
          OnyxMenuItem(
            value: opt.value,
            label: tr(opt.label),
            checked: opt.value == f.sortBy,
          ),
      ],
      onSelected: (value) => _update((c) => c.copyWith(sortBy: value)),
      child: RequestFilterChip(
        label: tr('Trier : {0}', [_sortLabel(f.sortBy)]),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: chips,
          ),
        ),
        const SizedBox(width: 12),
        sort,
      ],
    );
  }
}
