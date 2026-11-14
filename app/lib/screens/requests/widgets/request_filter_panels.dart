import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/request_catalog_filters.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../widgets/global/app_network_image.dart';
import '../../../widgets/global/onyx_menu.dart';
import '../../../widgets/global/onyx_menu_panel.dart';
import 'request_filter_fields.dart';
import 'request_filter_popover.dart';

/// Les panneaux qu'ouvrent les capsules de filtres. Chacun tient sa copie
/// de la sélection (la route ne se reconstruit pas avec l'écran) et rend
/// chaque changement aussitôt : le panneau reste ouvert, la grille suit.

/// Bascule [id] dans [ids], sans toucher à la liste d'origine.
List<int> _toggled(List<int> ids, int id) =>
    ids.contains(id) ? [...ids.where((e) => e != id)] : [...ids, id];

/// Un message ou un indicateur dans la matière des menus, le temps d'une
/// liste qui charge ou qui n'a rien à montrer.
class _PanelNote extends StatelessWidget {
  const _PanelNote({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    return RequestPopoverSurface(
      width: OnyxMenuMetrics.minWidth + 40,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: message == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: AppType.subhead,
                ),
              ),
      ),
    );
  }
}

/// Les genres du type affiché, à cocher et décocher sans fermer.
class RequestGenresPanel extends StatefulWidget {
  const RequestGenresPanel({
    super.key,
    required this.mediaType,
    required this.initial,
    required this.onChanged,
  });

  final String mediaType;
  final List<int> initial;
  final ValueChanged<List<int>> onChanged;

  @override
  State<RequestGenresPanel> createState() => _RequestGenresPanelState();
}

class _RequestGenresPanelState extends State<RequestGenresPanel> {
  late List<int> _selected = widget.initial;
  List<RequestGenre>? _genres;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final genres =
          await context.read<ApiClient>().getRequestFilterGenres(widget.mediaType);
      if (mounted) setState(() => _genres = genres);
    } catch (_) {
      // Le panneau le dit ; la capsule reste utilisable au prochain essai.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final genres = _genres;
    if (_failed) {
      return _PanelNote(message: tr('Impossible de charger les genres.'));
    }
    if (genres == null) return const _PanelNote();
    if (genres.isEmpty) return _PanelNote(message: tr('Aucun genre.'));
    return OnyxMenuPanel<int>(
      metrics: OnyxMenuMetrics.of(context),
      items: [
        for (final g in genres)
          OnyxMenuItem(
            value: g.id,
            label: g.name,
            checked: _selected.contains(g.id),
          ),
      ],
      onPick: (i) {
        setState(() => _selected = _toggled(_selected, genres[i].id));
        widget.onChanged(_selected);
      },
    );
  }
}

/// Les services de streaming d'une région. La première ligne change la
/// région (un menu Onyx simple) ; les suivantes se cochent sans fermer.
class RequestStreamingPanel extends StatefulWidget {
  const RequestStreamingPanel({
    super.key,
    required this.mediaType,
    required this.initialRegion,
    required this.initialProviders,
    required this.onChanged,
  });

  final String mediaType;
  final String initialRegion;
  final List<int> initialProviders;
  final void Function(String region, List<int> providers) onChanged;

  @override
  State<RequestStreamingPanel> createState() => _RequestStreamingPanelState();
}

class _RequestStreamingPanelState extends State<RequestStreamingPanel> {
  final GlobalKey _panelKey = GlobalKey();
  late String _region = widget.initialRegion;
  late List<int> _selected = widget.initialProviders;
  List<RequestWatchProvider>? _providers;
  bool _failed = false;

  /// La ligne de la région, qui n'est pas un service.
  static const _regionRow = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _providers = null;
      _failed = false;
    });
    try {
      final providers = await context
          .read<ApiClient>()
          .getRequestWatchProviders(type: widget.mediaType, region: _region);
      if (mounted) setState(() => _providers = providers);
    } catch (_) {
      // Le panneau le dit ; changer de région relance le chargement.
      if (mounted) setState(() => _failed = true);
    }
  }

  String get _regionLabel {
    for (final r in requestCatalogRegions) {
      if (r.value == _region) return tr(r.label);
    }
    return _region;
  }

  Future<void> _pickRegion() async {
    final pick = await showOnyxMenu<String>(
      context: context,
      anchorKey: _panelKey,
      items: [
        for (final r in requestCatalogRegions)
          OnyxMenuItem(
            value: r.value,
            label: tr(r.label),
            checked: r.value == _region,
          ),
      ],
    );
    if (pick == null || pick.value == _region || !mounted) return;
    setState(() => _region = pick.value);
    widget.onChanged(_region, _selected);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final providers = _providers ?? const <RequestWatchProvider>[];
    final regionItem = OnyxMenuItem<int>(
      value: _regionRow,
      label: tr('Région : {0}', [_regionLabel]),
      icon: AppIcons.language,
    );
    final List<OnyxMenuItem<int>> items;
    if (_failed) {
      items = [
        regionItem,
        OnyxMenuItem(
            value: 0,
            label: tr('Impossible de charger les services.'),
            enabled: false),
      ];
    } else if (_providers == null) {
      items = [
        regionItem,
        OnyxMenuItem(value: 0, label: tr('Chargement…'), enabled: false),
      ];
    } else if (providers.isEmpty) {
      items = [
        regionItem,
        OnyxMenuItem(
            value: 0,
            label: tr('Aucun service pour cette région.'),
            enabled: false),
      ];
    } else {
      items = [
        regionItem,
        for (final p in providers)
          OnyxMenuItem(
            value: p.providerId,
            label: p.providerName,
            leading: _ProviderLogo(url: p.logoUrl),
            checked: _selected.contains(p.providerId),
          ),
      ];
    }
    return KeyedSubtree(
      key: _panelKey,
      child: OnyxMenuPanel<int>(
        // Un nouveau panneau à chaque région : il se recale sur la ligne
        // cochée de la nouvelle liste.
        key: ValueKey('$_region-${_providers?.length}'),
        metrics: OnyxMenuMetrics.of(context),
        items: items,
        onPick: (i) {
          final id = items[i].value;
          if (id == _regionRow) {
            _pickRegion();
            return;
          }
          setState(() => _selected = _toggled(_selected, id));
          widget.onChanged(_region, _selected);
        },
      ),
    );
  }
}

class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 20.0;
    final url = this.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? const ColoredBox(color: AppColors.surface)
            : AppNetworkImage(
                url: url,
                width: size,
                height: size,
                placeholder: const ColoredBox(color: AppColors.surface),
                errorWidget: const ColoredBox(color: AppColors.surface),
              ),
      ),
    );
  }
}

/// Deux champs (de / à) dans la matière des menus : la période et la durée.
class RequestRangePanel extends StatefulWidget {
  const RequestRangePanel._({
    super.key,
    required this.title,
    required this.from,
    required this.to,
    required this.fromLabel,
    required this.toLabel,
    required this.dates,
    required this.onChanged,
  });

  /// Les dates de sortie, `AAAA-MM-JJ`.
  factory RequestRangePanel.period({
    Key? key,
    required String start,
    required String end,
    required void Function(String start, String end) onChanged,
  }) =>
      RequestRangePanel._(
        key: key,
        title: tr('Période'),
        from: start,
        to: end,
        fromLabel: tr('De'),
        toLabel: tr('À'),
        dates: true,
        onChanged: onChanged,
      );

  /// La durée en minutes.
  factory RequestRangePanel.duration({
    Key? key,
    required String min,
    required String max,
    required void Function(String min, String max) onChanged,
  }) =>
      RequestRangePanel._(
        key: key,
        title: tr('Durée (minutes)'),
        from: min,
        to: max,
        fromLabel: tr('Min'),
        toLabel: tr('Max'),
        dates: false,
        onChanged: onChanged,
      );

  final String title;
  final String from;
  final String to;
  final String fromLabel;
  final String toLabel;
  final bool dates;
  final void Function(String from, String to) onChanged;

  @override
  State<RequestRangePanel> createState() => _RequestRangePanelState();
}

class _RequestRangePanelState extends State<RequestRangePanel> {
  late final _from = TextEditingController(text: widget.from);
  late final _to = TextEditingController(text: widget.to);

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _changed() => widget.onChanged(_from.text.trim(), _to.text.trim());

  Widget _field(String label, TextEditingController controller) =>
      widget.dates
          ? RequestDateField(
              label: label,
              controller: controller,
              onChanged: (_) => _changed(),
            )
          : RequestDurationField(
              label: label,
              controller: controller,
              onChanged: (_) => _changed(),
            );

  @override
  Widget build(BuildContext context) {
    final fields = [
      _field(widget.fromLabel, _from),
      _field(widget.toLabel, _to),
    ];
    return RequestPopoverSurface(
      width: widget.dates ? 280 : 260,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppType.footnote,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.dates) ...[
              fields[0],
              const SizedBox(height: 12),
              fields[1],
            ] else
              Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[1]),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
