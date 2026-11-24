import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/request_catalog_filters.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../widgets/global/onyx_menu.dart';
import 'request_filter_bar.dart';
import 'request_filter_chip.dart';
import 'request_filter_fields.dart';
import 'request_filters_sheet_rows.dart';
import 'request_provider_logo.dart';

/// Les filtres de la feuille, dans l'ordre de l'index.
enum _Page { sort, genres, period, language, streaming, duration }

/// La feuille des filtres qui remonte du bas, ouverte par le bouton flottant
/// de la page Demandes (hors TV).
///
/// Deux niveaux, comme les réglages d'un téléphone : un index d'une ligne
/// par filtre, qui dit sa valeur (« Tous », « Action, Drame »), puis le
/// détail du filtre touché. Tout montrer d'un coup (la première version)
/// empilait une centaine de services sous les genres, et on ne savait plus
/// à quel filtre appartenait une capsule. Voir ADR-0132.
///
/// Chaque changement remonte aussitôt par [onChanged], comme les capsules ;
/// l'écran recharge la grille derrière la feuille, et « Voir les résultats »
/// ne fait que la fermer. La feuille tient sa propre copie des filtres : la
/// route ne se reconstruit pas avec l'écran.
class RequestFiltersBottomSheet extends StatefulWidget {
  const RequestFiltersBottomSheet({
    super.key,
    required this.initial,
    required this.mediaType,
    required this.onChanged,
  });

  final RequestCatalogFilters initial;
  final String mediaType;
  final ValueChanged<RequestCatalogFilters> onChanged;

  /// Largeur au-delà de laquelle la feuille ne s'étire plus (bureau).
  static const double maxWidth = 560;

  static Future<void> show(
    BuildContext context, {
    required RequestCatalogFilters initial,
    required String mediaType,
    required ValueChanged<RequestCatalogFilters> onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      constraints: const BoxConstraints(maxWidth: maxWidth),
      builder: (_) => RequestFiltersBottomSheet(
        initial: initial,
        mediaType: mediaType,
        onChanged: onChanged,
      ),
    );
  }

  /// Le nombre de familles de filtres posées (genres, période, langue,
  /// streaming, durée), le tri mis à part : c'est le compte du bouton.
  static int activeCount(RequestCatalogFilters f) =>
      _Page.values.where((p) => p != _Page.sort && _isSet(p, f)).length;

  static bool _isSet(_Page page, RequestCatalogFilters f) {
    final d = RequestCatalogFilters.defaults;
    return switch (page) {
      _Page.sort => f.sortBy != d.sortBy,
      _Page.genres => f.genres.isNotEmpty,
      _Page.period => f.startDate.isNotEmpty || f.endDate.isNotEmpty,
      _Page.language => f.language != d.language,
      _Page.streaming => f.watchProviders.isNotEmpty,
      _Page.duration => f.minDuration.isNotEmpty || f.maxDuration.isNotEmpty,
    };
  }

  @override
  State<RequestFiltersBottomSheet> createState() =>
      _RequestFiltersBottomSheetState();
}

class _RequestFiltersBottomSheetState extends State<RequestFiltersBottomSheet> {
  late RequestCatalogFilters _f = widget.initial;
  late final _start = TextEditingController(text: _f.startDate);
  late final _end = TextEditingController(text: _f.endDate);
  late final _minDuration = TextEditingController(text: _f.minDuration);
  late final _maxDuration = TextEditingController(text: _f.maxDuration);

  /// Le détail ouvert ; nul : l'index.
  _Page? _page;

  List<RequestGenre>? _genres;
  bool _genresFailed = false;
  List<RequestWatchProvider>? _providers;
  bool _providersFailed = false;

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    // Chargés dès l'ouverture : l'index nomme les genres et les services
    // cochés plutôt que d'en donner le compte.
    _loadGenres();
    _loadProviders();
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _minDuration.dispose();
    _maxDuration.dispose();
    super.dispose();
  }

  Future<void> _loadGenres() async {
    try {
      final genres = await _api.getRequestFilterGenres(widget.mediaType);
      if (mounted) setState(() => _genres = genres);
    } catch (_) {
      // Le détail des genres le dit ; les autres filtres restent utilisables.
      if (mounted) setState(() => _genresFailed = true);
    }
  }

  Future<void> _loadProviders() async {
    setState(() {
      _providers = null;
      _providersFailed = false;
    });
    try {
      final providers = await _api.getRequestWatchProviders(
          type: widget.mediaType, region: _f.watchRegion);
      if (mounted) setState(() => _providers = providers);
    } catch (_) {
      // Le détail du streaming le dit ; changer de région relance.
      if (mounted) setState(() => _providersFailed = true);
    }
  }

  void _update(RequestCatalogFilters next) {
    setState(() => _f = next);
    widget.onChanged(next);
  }

  /// Retire un seul filtre (le « Effacer » d'un détail).
  void _clear(_Page page) {
    final d = RequestCatalogFilters.defaults;
    switch (page) {
      case _Page.sort:
        _update(_f.copyWith(sortBy: d.sortBy));
      case _Page.genres:
        _update(_f.copyWith(genres: const []));
      case _Page.period:
        _start.clear();
        _end.clear();
        _update(_f.copyWith(startDate: '', endDate: ''));
      case _Page.language:
        _update(_f.copyWith(language: d.language));
      case _Page.streaming:
        _update(_f.copyWith(watchProviders: const []));
      case _Page.duration:
        _minDuration.clear();
        _maxDuration.clear();
        _update(_f.copyWith(minDuration: '', maxDuration: ''));
    }
  }

  void _clearAll() {
    _start.clear();
    _end.clear();
    _minDuration.clear();
    _maxDuration.clear();
    final regionChanged =
        _f.watchRegion != RequestCatalogFilters.defaults.watchRegion;
    _update(RequestFilterBar.cleared(_f));
    if (regionChanged) _loadProviders();
  }

  static List<int> _toggled(List<int> ids, int id) =>
      ids.contains(id) ? [...ids.where((e) => e != id)] : [...ids, id];

  // ---- Libellés ----------------------------------------------------------

  String _title(_Page page) => switch (page) {
        _Page.sort => tr('Trier par'),
        _Page.genres => tr('Genres'),
        _Page.period => tr('Date de sortie'),
        _Page.language => tr('Langue d’origine'),
        _Page.streaming => tr('Disponible sur'),
        _Page.duration => tr('Durée'),
      };

  IconData _icon(_Page page) => switch (page) {
        _Page.sort => AppIcons.sortOrder,
        _Page.genres => AppIcons.filter,
        _Page.period => AppIcons.calendar,
        _Page.language => AppIcons.language,
        _Page.streaming => AppIcons.series,
        _Page.duration => AppIcons.duration,
      };

  /// Les noms cochés, ou leur compte tant que la liste n'est pas arrivée.
  static String _names<T>(List<int> ids, List<T>? all, int Function(T) id,
      String Function(T) name) {
    if (all == null) return tr('{0} choisis', [ids.length]);
    return [
      for (final item in all)
        if (ids.contains(id(item))) name(item)
    ].join(', ');
  }

  static String _range(String from, String to, String unit) {
    final suffix = unit.isEmpty ? '' : ' $unit';
    if (from.isNotEmpty && to.isNotEmpty) return '$from – $to$suffix';
    if (from.isNotEmpty) return tr('Dès {0}', ['$from$suffix']);
    return tr('Jusqu’à {0}', ['$to$suffix']);
  }

  String _value(_Page page) {
    if (!RequestFiltersBottomSheet._isSet(page, _f) && page != _Page.sort) {
      return switch (page) {
        _Page.streaming => tr('Tous les services'),
        _Page.language => tr('Toutes les langues'),
        _ => tr('Tous'),
      };
    }
    return switch (page) {
      _Page.sort => tr(requestCatalogSortOptions
          .firstWhere((o) => o.value == _f.sortBy,
              orElse: () => requestCatalogSortOptions.first)
          .label),
      _Page.genres =>
        _names<RequestGenre>(_f.genres, _genres, (g) => g.id, (g) => g.name),
      _Page.period => _range(_f.startDate, _f.endDate, ''),
      _Page.language => tr(requestCatalogLanguageOptions
          .firstWhere((o) => o.code == _f.language,
              orElse: () => (code: _f.language, label: _f.language))
          .label),
      _Page.streaming => _names<RequestWatchProvider>(_f.watchProviders,
          _providers, (p) => p.providerId, (p) => p.providerName),
      _Page.duration => _range(_f.minDuration, _f.maxDuration, 'min'),
    };
  }

  // ---- Mise en page ------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final media = MediaQuery.of(context);
    return PopScope(
      // Retour sur un détail ramène à l'index au lieu de fermer la feuille.
      canPop: page == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _page = null);
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(page),
              const Divider(height: 1),
              Flexible(
                child: AnimatedSwitcher(
                  duration: AppMotion.fade(context, AppMotion.micro),
                  switchInCurve: AppMotion.curve,
                  switchOutCurve: AppMotion.curve,
                  child: KeyedSubtree(
                    key: ValueKey(page),
                    child: page == null ? _index() : _detail(page),
                  ),
                ),
              ),
              const Divider(height: 1),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.textPrimary,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(tr('Voir les résultats')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(_Page? page) {
    final clear = page == null
        ? (RequestFilterBar.hasActive(_f) ? _clearAll : null)
        : (RequestFiltersBottomSheet._isSet(page, _f)
            ? () => _clear(page)
            : null);
    return Padding(
      padding: EdgeInsets.fromLTRB(page == null ? 20 : 4, 0, 8, 8),
      child: Row(
        children: [
          if (page != null)
            IconButton(
              tooltip: tr('Retour'),
              onPressed: () => setState(() => _page = null),
              icon: const Icon(AppIcons.back, size: 20),
            ),
          Expanded(
            child: Text(
              page == null ? tr('Filtres') : _title(page),
              style: const TextStyle(
                fontSize: AppType.title3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (clear != null)
            TextButton(
              onPressed: clear,
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary),
              child: Text(page == null ? tr('Tout effacer') : tr('Effacer')),
            ),
        ],
      ),
    );
  }

  Widget _index() => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final p in _Page.values)
            RequestFilterIndexRow(
              icon: _icon(p),
              title: _title(p),
              value: _value(p),
              active: RequestFiltersBottomSheet._isSet(p, _f),
              onTap: () => setState(() => _page = p),
            ),
        ],
      );

  Widget _detail(_Page page) => switch (page) {
        _Page.sort => _options([
            for (final o in requestCatalogSortOptions)
              RequestFilterOptionRow(
                label: tr(o.label),
                selected: o.value == _f.sortBy,
                onTap: () => _update(_f.copyWith(sortBy: o.value)),
              ),
          ]),
        _Page.genres => _genreOptions(),
        _Page.period => _fields(
            RequestDateField(
              label: tr('Du'),
              controller: _start,
              onChanged: (v) => _update(_f.copyWith(startDate: v)),
            ),
            RequestDateField(
              label: tr('Au'),
              controller: _end,
              onChanged: (v) => _update(_f.copyWith(endDate: v)),
            ),
          ),
        _Page.language => _options([
            for (final o in requestCatalogLanguageOptions)
              RequestFilterOptionRow(
                label: tr(o.label),
                selected: o.code == _f.language,
                onTap: () => _update(_f.copyWith(language: o.code)),
              ),
          ]),
        _Page.streaming => _streamingOptions(),
        _Page.duration => _fields(
            RequestDurationField(
              label: tr('Min (minutes)'),
              controller: _minDuration,
              onChanged: (v) => _update(_f.copyWith(minDuration: v)),
            ),
            RequestDurationField(
              label: tr('Max (minutes)'),
              controller: _maxDuration,
              onChanged: (v) => _update(_f.copyWith(maxDuration: v)),
            ),
          ),
      };

  Widget _options(List<Widget> rows, {Widget? top}) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [if (top != null) top, ...rows],
      );

  Widget _fields(Widget a, Widget b) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Row(
          children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ],
        ),
      );

  Widget _note(String message) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: AppType.subhead),
        ),
      );

  static const _loading = Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );

  Widget _genreOptions() {
    final genres = _genres;
    if (_genresFailed) return _note(tr('Impossible de charger les genres.'));
    if (genres == null) return _loading;
    if (genres.isEmpty) return _note(tr('Aucun genre.'));
    return _options([
      for (final g in genres)
        RequestFilterOptionRow(
          label: g.name,
          selected: _f.genres.contains(g.id),
          onTap: () =>
              _update(_f.copyWith(genres: _toggled(_f.genres, g.id))),
        ),
    ]);
  }

  Widget _streamingOptions() {
    final region = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr('Région'),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: AppType.subhead),
            ),
          ),
          OnyxMenuButton<String>(
            tooltip: tr('Région'),
            items: [
              for (final r in requestCatalogRegions)
                OnyxMenuItem(
                  value: r.value,
                  label: tr(r.label),
                  checked: r.value == _f.watchRegion,
                ),
            ],
            onSelected: (value) {
              if (value == _f.watchRegion) return;
              // Changer de région garde les services cochés, comme les
              // capsules (ADR-0131).
              _update(_f.copyWith(watchRegion: value));
              _loadProviders();
            },
            child: RequestFilterChip(
              label: tr(requestCatalogRegions
                  .firstWhere((r) => r.value == _f.watchRegion,
                      orElse: () =>
                          (value: _f.watchRegion, label: _f.watchRegion))
                  .label),
            ),
          ),
        ],
      ),
    );
    final providers = _providers;
    if (_providersFailed) {
      return _options([_note(tr('Impossible de charger les services.'))],
          top: region);
    }
    if (providers == null) return _options([_loading], top: region);
    if (providers.isEmpty) {
      return _options([_note(tr('Aucun service pour cette région.'))],
          top: region);
    }
    return _options([
      for (final p in providers)
        RequestFilterOptionRow(
          leading: RequestProviderLogo(url: p.logoUrl, size: 32),
          label: p.providerName,
          selected: _f.watchProviders.contains(p.providerId),
          onTap: () => _update(_f.copyWith(
              watchProviders: _toggled(_f.watchProviders, p.providerId))),
        ),
    ], top: region);
  }
}
