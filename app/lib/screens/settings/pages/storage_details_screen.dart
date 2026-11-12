import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/storage_admin.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../utils/format.dart';
import '../../../utils/responsive.dart';
import '../widgets/settings_ui.dart';
import 'storage_page.dart';
import 'storage_poster.dart';

/// Le détail d'un titre du stockage (ADR-0115) : qui l'a demandé, qui en est
/// où, ce que pèse chaque saison, et la suppression du disque, du titre
/// entier ou d'une saison.
class StorageDetailsScreen extends StatefulWidget {
  const StorageDetailsScreen({
    super.key,
    required this.item,
    required this.requestsAvailable,
  });

  final StorageItem item;
  final bool requestsAvailable;

  @override
  State<StorageDetailsScreen> createState() => _StorageDetailsScreenState();
}

class _StorageDetailsScreenState extends State<StorageDetailsScreen> {
  StorageDetails? _details;
  String? _error;
  int? _deleting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final details =
          await context.read<ApiClient>().getAdminStorageDetails(widget.item.id);
      if (!mounted) return;
      setState(() {
        _details = details;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _error = settingsErrorText(e, tr('Impossible de charger ce titre.')));
    }
  }

  Future<void> _delete({StorageSeason? season}) async {
    final item = widget.item;
    final what = season != null
        ? tr('la saison {0} de {1}', [season.number, item.title])
        : item.title;
    final size = season?.size ?? _showSize ?? item.size;
    final confirmed = await confirmSettingsAction(
      context,
      title: tr('Supprimer {0} ?', [what]),
      message: tr('Les fichiers ({0}) seront effacés du disque et retirés '
          'd’Onyx, pour tous les comptes. MediaHub le retire aussi de sorraa '
          '(ou de Radarr/Sonarr) et supprime ses demandes. C’est définitif.',
          [formatBytes(size)]),
      confirmLabel: tr('Supprimer du disque'),
    );
    if (!confirmed || !mounted) return;
    final id = season?.id ?? item.id;
    setState(() => _deleting = id);
    try {
      final report = await context.read<ApiClient>().deleteAdminStorage(id);
      if (!mounted) return;
      showSettingsSnack(context, storageDeletedText(report));
      if (season == null) {
        Navigator.of(context).pop();
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) {
        showSettingsSnack(
            context, settingsErrorText(e, tr('La suppression a échoué.')),
            error: true);
      }
    }
    if (mounted) setState(() => _deleting = null);
  }

  /// Une saison supprimée change le poids de la série : la somme des saisons
  /// restantes est plus juste que la liste d'où l'on vient.
  int? get _showSize {
    final details = _details;
    if (details == null || !details.isShow) return null;
    return details.seasons.fold<int>(0, (sum, s) => sum + s.size);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final details = _details;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(item.title),
        actions: [
          IconButton(
            tooltip: tr('Actualiser'),
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: AppLayout.pageInsets(context, top: 20, bottom: 36),
            children: [
              _Header(item: item, size: _showSize ?? item.size, path: details?.path),
              const SizedBox(height: 20),
              if (_error != null) SettingsBanner(_error!, tone: BannerTone.error),
              if (details == null && _error == null) const SettingsLoading(),
              if (widget.requestsAvailable) _Requests(item.requests),
              if (details != null) ...[
                _Viewers(details),
                if (details.isShow)
                  SettingsGroup(
                    title: tr('Saisons'),
                    children: [
                      if (details.seasons.isEmpty)
                        SettingsEmptyNote(tr('Aucune saison sur le disque.')),
                      for (final season in details.seasons)
                        SettingsTile(
                          icon: Icons.folder_rounded,
                          title: season.title.isNotEmpty
                              ? season.title
                              : tr('Saison {0}', [season.number]),
                          subtitle: tr('{0} · {1} épisode(s)', [
                            formatBytes(season.size),
                            season.episodeCount,
                          ]),
                          trailing: _deleting == season.id
                              ? const SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  tooltip: tr('Supprimer cette saison'),
                                  color: AppColors.error,
                                  onPressed: _deleting != null
                                      ? null
                                      : () => _delete(season: season),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                        ),
                    ],
                  ),
                SettingsGroup(
                  children: [
                    SettingsTile(
                      icon: Icons.delete_forever_rounded,
                      destructive: true,
                      title: item.isShow
                          ? tr('Supprimer toute la série')
                          : tr('Supprimer le film'),
                      subtitle: tr('Efface {0} du disque, le retire de sorraa '
                          'ou de Radarr/Sonarr et supprime ses demandes.',
                          [formatBytes(_showSize ?? item.size)]),
                      trailing: _deleting == item.id
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : null,
                      onTap: _deleting != null ? null : () => _delete(),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.size, this.path});

  final StorageItem item;
  final int size;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final where = (path?.isNotEmpty ?? false) ? path! : item.path;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StoragePoster(url: item.posterUrl, isShow: item.isShow, width: 72),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatBytes(size),
                  style: const TextStyle(
                      fontSize: AppType.title3, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(storageIdleText(item),
                  style: const TextStyle(color: AppColors.textSecondary)),
              if (where.isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText(where,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: AppType.footnote)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Requests extends StatelessWidget {
  const _Requests(this.requests);

  final List<StorageRequest> requests;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: tr('Demandes'),
      children: [
        if (requests.isEmpty)
          SettingsEmptyNote(tr('Personne ne l’a demandé : ajouté à la main.')),
        for (final request in requests)
          SettingsTile(
            icon: Icons.person_add_alt_rounded,
            title: request.requester,
            subtitle: [
              if (request.requestedAt != null)
                tr('Demandé le {0}', [formatFrenchDay(request.requestedAt!)]),
              if (request.seasons.isNotEmpty)
                tr('Saisons {0}', [request.seasons.join(', ')]),
            ].join(' · '),
            trailing: SettingsPill(_statusLabel(request.status)),
          ),
      ],
    );
  }

  static String _statusLabel(String status) => switch (status) {
        'pending' => tr('En attente'),
        'approved' => tr('Approuvée'),
        'processing' => tr('En téléchargement'),
        'partial' => tr('En partie disponible'),
        'available' => tr('Disponible'),
        'declined' => tr('Refusée'),
        _ => status,
      };
}

class _Viewers extends StatelessWidget {
  const _Viewers(this.details);

  final StorageDetails details;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: tr('Qui regarde'),
      children: [
        if (details.viewers.isEmpty)
          SettingsEmptyNote(tr('Aucun compte ne l’a encore lancé.')),
        for (final viewer in details.viewers)
          SettingsTile(
            leading: UserAvatar(viewer.username),
            title: viewer.username,
            subtitle: storageViewerText(viewer, show: details.isShow),
            trailing: viewer.lastPlayedAt == null
                ? null
                : Text(relativeTime(viewer.lastPlayedAt!),
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: AppType.footnote)),
          ),
      ],
    );
  }
}

/// « S2 · E4 à 12 min sur 50 min · 7/20 épisodes vus », ou pour un film
/// « 35 min sur 2 h 10 (27 %) ».
String storageViewerText(StorageViewer viewer, {required bool show}) {
  String at(int position, int duration) => duration > 0
      ? tr('{0} sur {1}', [formatWatchTime(position), formatWatchTime(duration)])
      : formatWatchTime(position);
  if (!show) {
    if (viewer.finished) return tr('Film terminé');
    final pct = viewer.durationSeconds > 0
        ? (viewer.positionSeconds * 100 ~/ viewer.durationSeconds)
        : 0;
    return tr('{0} ({1} %)',
        [at(viewer.positionSeconds, viewer.durationSeconds), pct]);
  }
  final watched = tr('{0}/{1} épisodes vus',
      [viewer.watchedEpisodes, viewer.totalEpisodes]);
  if (viewer.finished) return tr('Série terminée · {0}', [watched]);
  final current = viewer.currentEpisode;
  if (current == null) return watched;
  final where = current.finished
      ? tr('S{0} · E{1} fini', [current.season, current.episode])
      : tr('S{0} · E{1} à {2}', [
          current.season,
          current.episode,
          at(current.positionSeconds, current.durationSeconds),
        ]);
  return '$where · $watched';
}

/// « 12,4 Go libérés · retiré de sorraa · 2 demande(s) supprimée(s) ».
String storageDeletedText(StorageDeleteReport report) {
  final parts = [tr('{0} libérés', [formatBytes(report.bytesFreed)])];
  final hub = report.mediaHub;
  if (hub != null) {
    if (hub.managerRemoved) {
      parts.add(hub.manager == 'sorraa'
          ? tr('retiré de sorraa')
          : tr('retiré de Radarr/Sonarr'));
    }
    if (hub.requestsRemoved > 0) {
      parts.add(tr('{0} demande(s) supprimée(s)', [hub.requestsRemoved]));
    }
  }
  return '${parts.join(' · ')}.';
}
