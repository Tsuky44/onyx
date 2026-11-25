import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/request_catalog_filters.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../widgets/global/onyx_menu.dart';
import 'request_filter_bar.dart';
import '../../../widgets/global/filter_panel/onyx_filter_chip.dart';
import 'request_filter_fields.dart';
import '../../../widgets/global/filter_panel/filter_presets.dart';
import '../../../widgets/global/filter_panel/onyx_filter_panel.dart';
import 'request_filters_side_sections.dart';

/// Le panneau latéral des filtres des demandes, sur grand écran (hors TV) :
/// ouvert par le bouton flottant, il tient tous les filtres sur une page,
/// sans navigation, dans la matière des menus Onyx (`OnyxPanelSurface`).
/// Chaque filtre est replié par défaut et dit sa valeur ; on le déplie pour
/// choisir.
///
/// Il vit dans l'arbre de l'écran, qui le reconstruit à chaque changement,
/// d'où qu'il vienne (le panneau ou les capsules du haut) : sa copie des
/// filtres se recale sur chaque reconstruction. Voir l'ADR du 2026-11-25.

class RequestFiltersSidePanel extends StatefulWidget {
  const RequestFiltersSidePanel({
    super.key,
    required this.filters,
    required this.mediaType,
    required this.onChanged,
    required this.onClose,
  });

  final RequestCatalogFilters filters;
  final String mediaType;
  final ValueChanged<RequestCatalogFilters> onChanged;
  final VoidCallback onClose;

  @override
  State<RequestFiltersSidePanel> createState() =>
      _RequestFiltersSidePanelState();
}

class _RequestFiltersSidePanelState extends State<RequestFiltersSidePanel> {
  late final _start = TextEditingController(text: widget.filters.startDate);
  late final _end = TextEditingController(text: widget.filters.endDate);
  late final _min = TextEditingController(text: widget.filters.minDuration);
  late final _max = TextEditingController(text: widget.filters.maxDuration);

  List<RequestGenre>? _genres;
  bool _genresFailed = false;
  List<RequestWatchProvider>? _providers;
  bool _providersFailed = false;

  /// Les filtres à jour, sans attendre que l'écran reconstruise : deux
  /// clics servis dans la même image partent chacun du précédent au lieu
  /// que le second efface le premier.
  late RequestCatalogFilters _f = widget.filters;

  @override
  void initState() {
    super.initState();
    _loadGenres();
    _loadProviders();
  }

  @override
  void didUpdateWidget(RequestFiltersSidePanel old) {
    super.didUpdateWidget(old);
    _f = widget.filters;
    // Un choix rapide, « Tout effacer » ou le ✕ d'une capsule du haut
    // changent la plage sans passer par les champs : ils se recalent. Une
    // frappe revient à l'identique et ne déplace pas le curseur.
    _sync(_start, _f.startDate);
    _sync(_end, _f.endDate);
    _sync(_min, _f.minDuration);
    _sync(_max, _f.maxDuration);
    if (old.mediaType != widget.mediaType) _loadGenres();
    if (old.mediaType != widget.mediaType ||
        old.filters.watchRegion != _f.watchRegion) {
      _loadProviders();
    }
  }

  static void _sync(TextEditingController c, String value) {
    if (c.text.trim() != value) c.text = value;
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _loadGenres() async {
    setState(() {
      _genres = null;
      _genresFailed = false;
    });
    final type = widget.mediaType;
    try {
      final genres =
          await context.read<ApiClient>().getRequestFilterGenres(type);
      if (mounted && type == widget.mediaType) {
        setState(() => _genres = genres);
      }
    } catch (_) {
      // La section le dit et propose « Réessayer » ; le reste du panneau
      // reste utilisable.
      if (mounted) setState(() => _genresFailed = true);
    }
  }

  Future<void> _loadProviders() async {
    setState(() {
      _providers = null;
      _providersFailed = false;
    });
    final type = widget.mediaType;
    final region = _f.watchRegion;
    try {
      final providers = await context
          .read<ApiClient>()
          .getRequestWatchProviders(type: type, region: region);
      // Une réponse d'une région ou d'un type quittés entre-temps ne
      // remplace pas celle qui est attendue.
      if (mounted && type == widget.mediaType && region == _f.watchRegion) {
        setState(() => _providers = providers);
      }
    } catch (_) {
      // Même chose que les genres : la section le dit, « Réessayer » relance.
      if (mounted) setState(() => _providersFailed = true);
    }
  }

  void _update(RequestCatalogFilters next) {
    _f = next;
    widget.onChanged(next);
  }

  static List<int> _toggled(List<int> ids, int id) =>
      ids.contains(id) ? [...ids.where((e) => e != id)] : [...ids, id];

  @override
  Widget build(BuildContext context) {
    return OnyxFilterPanel(
      onClose: widget.onClose,
      onClearAll: RequestFilterBar.hasActive(_f)
          ? () => _update(RequestFilterBar.cleared(_f))
          : null,
      children: [
        _sort(),
        _genresSection(),
        _periodSection(),
        _languageSection(),
        _streamingSection(),
        _durationSection(),
      ],
    );
  }

  /// Les noms cochés, ou leur compte tant que la liste n'est pas arrivée.
  static String _names<T>(List<int> ids, List<T>? all, int Function(T) id,
      String Function(T) name) {
    if (all == null) return tr('{0} choisis', [ids.length]);
    return [
      for (final item in all)
        if (ids.contains(id(item))) name(item)
    ].join(', ');
  }

  Widget _sort() {
    final current = requestCatalogSortOptions.firstWhere(
        (o) => o.value == _f.sortBy,
        orElse: () => requestCatalogSortOptions.first);
    return OnyxFilterInlineRow(
      title: tr('Trier par'),
      trailing: OnyxMenuButton<String>(
        tooltip: tr('Trier par'),
        items: [
          for (final o in requestCatalogSortOptions)
            OnyxMenuItem(
              value: o.value,
              label: tr(o.label),
              checked: o.value == _f.sortBy,
            ),
        ],
        onSelected: (v) => _update(_f.copyWith(sortBy: v)),
        child: OnyxFilterChip(label: tr(current.label)),
      ),
    );
  }

  Widget _genresSection() {
    final genres = _genres;
    final Widget body;
    if (_genresFailed) {
      body = RequestPanelNote(
          message: tr('Impossible de charger les genres.'),
          onRetry: _loadGenres);
    } else if (genres == null) {
      body = const RequestPanelNote.loading();
    } else if (genres.isEmpty) {
      body = RequestPanelNote(message: tr('Aucun genre.'));
    } else {
      body = OnyxFilterPills(choices: [
        for (final g in genres)
          (
            label: g.name,
            selected: _f.genres.contains(g.id),
            onTap: () =>
                _update(_f.copyWith(genres: _toggled(_f.genres, g.id))),
          ),
      ]);
    }
    return OnyxFilterSection(
      title: tr('Genres'),
      value: _f.genres.isEmpty
          ? tr('Tous les genres')
          : _names<RequestGenre>(_f.genres, genres, (g) => g.id, (g) => g.name),
      active: _f.genres.isNotEmpty,
      onClear: () => _update(_f.copyWith(genres: const [])),
      child: body,
    );
  }

  Widget _periodSection() {
    final presets = filterPeriodPresets();
    return OnyxFilterSection(
      title: tr('Date de sortie'),
      value: filterRangeLabel(
          presets, _f.startDate, _f.endDate, '', tr('Toutes les dates')),
      active: _f.startDate.isNotEmpty || _f.endDate.isNotEmpty,
      onClear: () => _update(_f.copyWith(startDate: '', endDate: '')),
      child: OnyxFilterRange(
        presets: presets,
        from: _f.startDate,
        to: _f.endDate,
        customLabel: tr('Dates précises'),
        onChanged: (from, to) =>
            _update(_f.copyWith(startDate: from, endDate: to)),
        // Les dates l'une sous l'autre : côte à côte, « AAAA-MM-JJ » et le
        // calendrier ne tiennent pas dans la moitié du panneau.
        fields: Column(
          children: [
            RequestDateField(
              label: tr('Du'),
              controller: _start,
              onChanged: (v) => _update(_f.copyWith(startDate: v.trim())),
            ),
            const SizedBox(height: 12),
            RequestDateField(
              label: tr('Au'),
              controller: _end,
              onChanged: (v) => _update(_f.copyWith(endDate: v.trim())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageSection() {
    final all = RequestCatalogFilters.defaults.language;
    final current = requestCatalogLanguageOptions.firstWhere(
        (o) => o.code == _f.language,
        orElse: () => (code: _f.language, label: _f.language));
    return OnyxFilterSection(
      title: tr('Langue d’origine'),
      value: tr(current.label),
      active: _f.language != all,
      onClear: () => _update(_f.copyWith(language: all)),
      child: OnyxFilterPills(choices: [
        for (final o in requestCatalogLanguageOptions)
          if (o.code != all)
            (
              label: tr(o.label),
              selected: o.code == _f.language,
              onTap: () => _update(
                  _f.copyWith(language: o.code == _f.language ? all : o.code)),
            ),
      ]),
    );
  }

  Widget _streamingSection() {
    final region = requestCatalogRegions.firstWhere(
        (r) => r.value == _f.watchRegion,
        orElse: () => (value: _f.watchRegion, label: _f.watchRegion));
    final providers = _providers;
    final Widget body;
    if (_providersFailed) {
      body = RequestPanelNote(
          message: tr('Impossible de charger les services.'),
          onRetry: _loadProviders);
    } else if (providers == null) {
      body = const RequestPanelNote.loading();
    } else if (providers.isEmpty) {
      body = RequestPanelNote(message: tr('Aucun service pour cette région.'));
    } else {
      body = RequestProviderTiles(
        providers: providers,
        selected: _f.watchProviders,
        onToggle: (id) => _update(
            _f.copyWith(watchProviders: _toggled(_f.watchProviders, id))),
      );
    }
    // Changer de région garde les services cochés, comme les capsules
    // (ADR-0131) ; la liste se recharge par didUpdateWidget.
    final regionMenu = OnyxMenuButton<String>(
      tooltip: tr('Région'),
      items: [
        for (final r in requestCatalogRegions)
          OnyxMenuItem(
            value: r.value,
            label: tr(r.label),
            checked: r.value == _f.watchRegion,
          ),
      ],
      onSelected: (v) {
        if (v != _f.watchRegion) _update(_f.copyWith(watchRegion: v));
      },
      child: OnyxFilterChip(label: tr(region.label)),
    );
    return OnyxFilterSection(
      title: tr('Disponible sur'),
      value: _f.watchProviders.isEmpty
          ? tr('Tous les services')
          : _names<RequestWatchProvider>(_f.watchProviders, providers,
              (p) => p.providerId, (p) => p.providerName),
      active: _f.watchProviders.isNotEmpty,
      onClear: () => _update(_f.copyWith(watchProviders: const [])),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Région'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppType.subhead,
                  ),
                ),
              ),
              regionMenu,
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  Widget _durationSection() {
    final presets = filterDurationPresets();
    return OnyxFilterSection(
      title: tr('Durée'),
      value: filterRangeLabel(presets, _f.minDuration, _f.maxDuration, 'min',
          tr('Toutes les durées')),
      active: _f.minDuration.isNotEmpty || _f.maxDuration.isNotEmpty,
      onClear: () => _update(_f.copyWith(minDuration: '', maxDuration: '')),
      child: OnyxFilterRange(
        presets: presets,
        from: _f.minDuration,
        to: _f.maxDuration,
        customLabel: tr('Durée précise'),
        onChanged: (min, max) =>
            _update(_f.copyWith(minDuration: min, maxDuration: max)),
        fields: Row(
          children: [
            Expanded(
              child: RequestDurationField(
                label: tr('Min (minutes)'),
                controller: _min,
                onChanged: (v) => _update(_f.copyWith(minDuration: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RequestDurationField(
                label: tr('Max (minutes)'),
                controller: _max,
                onChanged: (v) => _update(_f.copyWith(maxDuration: v)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
