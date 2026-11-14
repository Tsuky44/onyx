import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../desktop_window.dart';
import '../../l10n/tr.dart';
import '../../models/offline_download.dart';
import '../../services/download_manager.dart';
import '../../services/server_reachability.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_mode.dart';
import '../../utils/responsive.dart';
import '../../widgets/global/empty_state.dart';
import '../device_library/device_library_entry.dart';
import 'download_group_headers.dart';
import 'widgets/download_row.dart';
import 'widgets/download_tv_row.dart';
import 'widgets/downloads_header.dart';

/// Ce qui est sur l'appareil, et rien d'autre.
///
/// C'est le seul écran qui tient debout sans serveur, et c'est sa raison
/// d'être : dans un avion ou dans un métro, c'est l'app tout entière. Il ne
/// fait donc aucun appel réseau — tout ce qu'il affiche vient du manifeste
/// local, y compris les affiches.
class DownloadsScreen extends StatelessWidget {
  final bool embedded;

  const DownloadsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<DownloadManager>();
    final reachability = context.watch<ServerReachability>();
    final compact = AppLayout.isCompact(context);
    final pad = AppLayout.pagePadding(context);
    final items = manager.downloads;
    // Un téléviseur garde l'écran d'avant la refonte du PC (regroupement par
    // série de tout ce qui est là) : sa navigation est épinglée par
    // `downloads_navigation_map_test.dart`.
    final tv = TvScope.of(context);
    final groups = tv ? _groupByShow(items) : const <_Group>[];
    // Hors TV, ce qui descend passe d'abord, dans l'ordre de la file ; ce qui
    // est déjà là garde le regroupement par série.
    final inProgress = tv
        ? const <OfflineDownload>[]
        : items.where((e) => !e.isCompleted).toList();
    final onDevice = tv
        ? const <OfflineDownload>[]
        : items.where((e) => e.isCompleted).toList();
    final watchedCount =
        items.where((e) => e.isCompleted && e.isFinished).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        scrollCacheExtent: AppLayout.imageCacheExtent(context),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                pad,
                shellTabTopInset(context, embedded: embedded),
                pad,
                0,
              ),
              child: DownloadsHeader(
                compact: compact,
                itemCount: items.length,
                bytes: manager.totalBytesOnDisk,
                watchedCount: watchedCount,
                offline: reachability.isOffline,
                pendingSync: manager.pendingSyncCount,
                heldForNetwork: manager.isHeldForNetwork,
                queuedCount: manager.queuedCount,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
              child: const DeviceLibraryEntryTile(),
            ),
          ),
          if (!manager.isSupported)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateView(
                icon: AppIcons.cloudOff,
                title: tr('Indisponible ici'),
                message: tr('Le téléchargement hors ligne demande un espace de '
                    'stockage propre à l\'application. Utilisez l\'app '
                    'installée sur votre appareil.'),
              ),
            )
          else if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateView(
                icon: AppIcons.offline,
                title: tr('Aucun téléchargement'),
                message: tr('Depuis la fiche d\'un film ou d\'une série, le '
                    'bouton de téléchargement garde le média sur cet '
                    'appareil. Il reste lisible même sans serveur.'),
              ),
            )
          else if (tv)
            ..._groupSlivers(groups, pad: pad, tv: true)
          else ...[
            if (inProgress.isNotEmpty) ...[
              _SectionTitle(
                label: tr('En cours · {0}', [inProgress.length]),
                pad: pad,
              ),
              SliverList.builder(
                itemCount: inProgress.length,
                itemBuilder: (context, index) =>
                    DownloadRow(entry: inProgress[index]),
              ),
            ],
            if (onDevice.isNotEmpty) ...[
              _SectionTitle(
                label: tr('Sur cet appareil · {0}', [onDevice.length]),
                pad: pad,
              ),
              ..._groupSlivers(_groupByShow(onDevice), pad: pad, tv: false),
            ],
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }

  /// Les en-têtes de série et de saison, puis leurs lignes.
  static List<Widget> _groupSlivers(
    List<_Group> groups, {
    required double pad,
    required bool tv,
  }) {
    return [
      for (final group in groups) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, tv ? 24 : 12, pad, 8),
            child: DownloadShowHeader(
              title: group.title,
              infoId: group.infoId,
              entries: group.entries,
              deletable: group.isShow,
            ),
          ),
        ),
        for (final season in group.seasons) ...[
          // Une seule saison : l'en-tête de la série dit déjà tout, et son
          // bouton supprime la même chose.
          if (group.seasons.length > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 12, pad - 8, 0),
                child: DownloadSeasonHeader(
                  seasonNumber: season.number,
                  entries: season.entries,
                ),
              ),
            ),
          SliverList.builder(
            itemCount: season.entries.length,
            itemBuilder: (context, index) => tv
                ? DownloadTvRow(
                    entry: season.entries[index],
                    compact: AppLayout.isCompact(context),
                  )
                : DownloadRow(entry: season.entries[index]),
          ),
        ],
      ],
    ];
  }

  /// Regroupe par série, les films ensemble à la fin.
  ///
  /// L'ordre à l'intérieur d'une série est celui des numéros, pas celui du
  /// téléchargement : on regarde une saison dans l'ordre, quel que soit celui
  /// dans lequel on l'a rapatriée.
  static List<_Group> _groupByShow(List<OfflineDownload> items) {
    final byShow = <String, List<OfflineDownload>>{};
    final movies = <OfflineDownload>[];
    for (final item in items) {
      if (item.showTitle != null && item.showTitle!.isNotEmpty) {
        byShow.putIfAbsent(item.showTitle!, () => []).add(item);
      } else {
        movies.add(item);
      }
    }
    final groups = <_Group>[];
    final showTitles = byShow.keys.toList()..sort();
    for (final title in showTitles) {
      final entries = byShow[title]!
        ..sort((a, b) {
          final season = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
          if (season != 0) return season;
          return (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
        });
      groups.add(
          _Group(title, entries, infoId: entries.first.infoId, isShow: true));
    }
    if (movies.isNotEmpty) {
      movies.sort((a, b) => a.title.compareTo(b.title));
      // Pas de fiche commune : chaque film est la sienne, et l'en-tête « Films »
      // ne décrit rien d'autre qu'un regroupement.
      groups.add(_Group(tr('Films'), movies));
    }
    return groups;
  }
}

class _Group {
  final String title;
  final List<OfflineDownload> entries;

  /// Identifiant sous lequel la fiche de la série est rangée, quand il y en a
  /// une (null pour le regroupement des films).
  final int? infoId;

  /// Faux pour le regroupement des films.
  final bool isShow;

  const _Group(this.title, this.entries, {this.infoId, this.isShow = false});

  /// Les épisodes découpés par saison, dans l'ordre où [entries] les range
  /// déjà. Les films forment une seule tranche sans numéro.
  List<_Season> get seasons {
    if (!isShow) return [_Season(null, entries)];
    final seasons = <_Season>[];
    for (final entry in entries) {
      if (seasons.isEmpty || seasons.last.number != entry.seasonNumber) {
        seasons.add(_Season(entry.seasonNumber, []));
      }
      seasons.last.entries.add(entry);
    }
    return seasons;
  }
}

class _Season {
  final int? number;
  final List<OfflineDownload> entries;

  const _Season(this.number, this.entries);
}

/// Le titre d'une section par état, en petites capitales.
class _SectionTitle extends StatelessWidget {
  final String label;
  final double pad;

  const _SectionTitle({required this.label, required this.pad});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, 28, pad, 6),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: AppType.caption,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }
}
