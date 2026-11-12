import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/storage_admin.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/format.dart';
import '../widgets/settings_ui.dart';
import 'storage_details_screen.dart';
import 'storage_poster.dart';
import 'storage_query.dart';

/// Faire de la place (ADR-0115) : films et séries par taille, qui les a
/// demandés, depuis quand personne ne les a lancés. Le détail dit qui en est
/// où et supprime le titre, ou une saison, du disque.
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

/// Une bibliothèque de mille titres ferait mille lignes d'un coup : la page
/// les montre par paquets, le reste à la demande.
const _pageSize = 40;

class _StoragePageState extends State<StoragePage> {
  StorageList? _list;
  String? _error;
  StorageQuery _query = const StorageQuery();
  int _shown = _pageSize;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<ApiClient>().getAdminStorage();
      if (!mounted) return;
      setState(() {
        _list = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          settingsErrorText(e, tr('Impossible de charger le stockage.')));
    }
  }

  void _setQuery(StorageQuery query) => setState(() {
        _query = query;
        _shown = _pageSize;
      });

  /// Au retour, la liste se relit : une saison ou le titre a pu partir.
  Future<void> _open(StorageItem item, bool requestsAvailable) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) =>
          StorageDetailsScreen(item: item, requestsAvailable: requestsAvailable),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final visible = list == null ? const <StorageItem>[] : _query.apply(list.items);
    final total = list?.items.fold<int>(0, (sum, i) => sum + i.size) ?? 0;
    final idle = list == null
        ? const <StorageItem>[]
        : const StorageQuery(idle: StorageIdle.months6).apply(list.items);
    final idleBytes = idle.fold<int>(0, (sum, i) => sum + i.size);
    final visibleBytes = visible.fold<int>(0, (sum, i) => sum + i.size);

    return SettingsPage(
      title: tr('Stockage'),
      description: tr('Ce que chaque film et chaque série occupe sur le disque, '
          'qui l’a demandé et qui le regarde. Supprimez ce qui ne sert plus.'),
      onRefresh: _load,
      actions: [
        IconButton(
          tooltip: tr('Actualiser'),
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      children: [
        if (_error != null) SettingsBanner(_error!, tone: BannerTone.error),
        if (list == null && _error == null)
          const SettingsLoading()
        else if (list != null) ...[
          StatGrid(children: [
            StatTile(
              icon: Icons.storage_rounded,
              label: tr('Sur le disque'),
              value: formatBytes(total),
            ),
            StatTile(
              icon: Icons.movie_rounded,
              label: tr('Films'),
              value: '${list.items.where((i) => !i.isShow).length}',
              color: AppColors.accentMuted,
            ),
            StatTile(
              icon: Icons.tv_rounded,
              label: tr('Séries'),
              value: '${list.items.where((i) => i.isShow).length}',
              color: AppColors.accentMuted,
            ),
            StatTile(
              icon: Icons.hourglass_bottom_rounded,
              label: tr('Pas vu depuis 6 mois'),
              value: formatBytes(idleBytes),
              color: idleBytes > 0 ? AppColors.warning : AppColors.textMuted,
              hint: tr('{0} titre(s)', [idle.length]),
            ),
          ]),
          if (!list.requestsAvailable)
            SettingsBanner(tr('MediaHub n’a pas répondu : les demandes ne '
                's’affichent pas.')),
          SettingsGroup(
            title: tr('Afficher'),
            children: [
              SettingsChoiceTile<StorageKind>(
                title: tr('Type'),
                value: _query.kind,
                options: [
                  (StorageKind.all, tr('Tout')),
                  (StorageKind.movies, tr('Films')),
                  (StorageKind.shows, tr('Séries')),
                ],
                onChanged: (v) => _setQuery(_query.copyWith(kind: v)),
              ),
              SettingsChoiceTile<StorageIdle>(
                title: tr('Pas regardé depuis'),
                value: _query.idle,
                options: [
                  (StorageIdle.any, tr('Peu importe')),
                  (StorageIdle.months3, tr('3 mois')),
                  (StorageIdle.months6, tr('6 mois')),
                  (StorageIdle.year, tr('1 an')),
                  (StorageIdle.never, tr('Jamais lancé')),
                ],
                onChanged: (v) => _setQuery(_query.copyWith(idle: v)),
              ),
              SettingsChoiceTile<StorageSort>(
                title: tr('Trier par'),
                value: _query.sort,
                options: [
                  (StorageSort.size, tr('Taille')),
                  (StorageSort.idle, tr('Plus longtemps oublié')),
                  (StorageSort.added, tr('Ajout récent')),
                  (StorageSort.title, tr('Titre')),
                ],
                onChanged: (v) => _setQuery(_query.copyWith(sort: v)),
              ),
            ],
          ),
          SettingsGroup(
            title: tr('{0} titre(s) · {1}', [visible.length, formatBytes(visibleBytes)]),
            children: [
              if (visible.isEmpty)
                SettingsEmptyNote(list.items.isEmpty
                    ? tr('Aucun film ni série dans les bibliothèques.')
                    : tr('Aucun titre ne correspond à ces filtres.')),
              for (final item in visible.take(_shown))
                StorageItemTile(
                  item: item,
                  requestsAvailable: list.requestsAvailable,
                  onTap: () => _open(item, list.requestsAvailable),
                ),
              if (visible.length > _shown)
                SettingsTile(
                  icon: Icons.expand_more_rounded,
                  title: tr('Afficher {0} de plus', [
                    (visible.length - _shown).clamp(0, _pageSize),
                  ]),
                  subtitle: tr('{0} restant(s)', [visible.length - _shown]),
                  onTap: () => setState(() => _shown += _pageSize),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// « il y a 3 mois » : l'oubli se lit en mois, pas à la minute.
String storageIdleText(StorageItem item, {DateTime? now}) {
  final last = item.lastPlayedAt;
  if (last == null) {
    final added = item.addedAt;
    return added == null
        ? tr('Jamais lancé')
        : tr('Jamais lancé · ajouté {0}', [storageAgo(added, now: now)]);
  }
  return tr('Vu {0}', [storageAgo(last, now: now)]);
}

String storageAgo(DateTime moment, {DateTime? now}) {
  final days = (now ?? DateTime.now()).difference(moment).inDays;
  if (days < 1) return tr('aujourd’hui');
  if (days < 31) return tr('il y a {0} j', [days]);
  if (days < 365) return tr('il y a {0} mois', [days ~/ 30]);
  final years = days ~/ 365;
  return years == 1 ? tr('il y a 1 an') : tr('il y a {0} ans', [years]);
}

class StorageItemTile extends StatelessWidget {
  const StorageItemTile({
    super.key,
    required this.item,
    required this.requestsAvailable,
    required this.onTap,
  });

  final StorageItem item;
  final bool requestsAvailable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      formatBytes(item.size),
      if (item.isShow) tr('{0} épisode(s)', [item.episodeCount]),
      storageIdleText(item),
      if (requestsAvailable && item.requests.isNotEmpty)
        tr('Demandé par {0}',
            [item.requests.map((r) => r.requester).toSet().join(', ')]),
    ];
    return SettingsTile(
      leading: StoragePoster(url: item.posterUrl, isShow: item.isShow),
      title: item.title,
      subtitle: parts.join(' · '),
      onTap: onTap,
    );
  }
}
