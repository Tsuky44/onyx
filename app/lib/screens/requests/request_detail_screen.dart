import 'dart:async';

import '../../utils/external_url.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/media_request.dart';
import '../../models/media_details.dart';
import '../../models/models.dart' show CastMember, MediaType;
import '../../navigation/catalog_navigation.dart';
import '../../navigation/play_link.dart';
import '../../services/api_client.dart';
import '../../providers/media_requests_provider.dart';
import '../../theme/app_colors.dart';
import '../../tv/nav/tv_region.dart';
import '../../utils/poster_url.dart';
import '../../widgets/global/detail_cast_section.dart';
import '../../widgets/global/detail_hero.dart';
import '../../widgets/global/detail_metadata.dart';
import '../../widgets/global/detail_summary_section.dart';
import '../../widgets/global/empty_state.dart';
import '../../widgets/global/poster_rail.dart';
import '../../utils/responsive.dart';
import 'widgets/request_detail_actions.dart';
import 'widgets/request_detail_hero.dart';
import 'widgets/request_info_table.dart';
import 'widgets/request_media_card.dart';
import 'widgets/request_progress_panel.dart';
import 'widgets/request_season_picker_sheet.dart';
import 'widgets/request_season_list.dart';
import 'widgets/request_status_badge.dart';
import '../../l10n/tr.dart';
import '../../widgets/global/media_countdown.dart';
import '../../models/watch_list.dart';

class RequestDetailScreen extends StatefulWidget {
  final RequestMediaItem item;

  const RequestDetailScreen({super.key, required this.item});

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  late Future<RequestMediaDetails> _details;
  bool _submitting = false;
  bool _launching = false;
  EpisodeAirRef? _fallbackNextEpisode;
  EpisodeAirRef? _fallbackLastEpisode;
  bool _resolvingEpisodes = false;

  void _resolveFallbackCountdown(RequestMediaDetails details) {
    if (_resolvingEpisodes ||
        details.mediaType != RequestMediaType.tv ||
        details.nextEpisodeToAir != null ||
        details.seasons.isEmpty) {
      return;
    }
    _resolvingEpisodes = true;

    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final todayStr = '$y-$m-$d';

    RequestSeason? targetSeason;
    for (final s in details.seasons) {
      if (s.number <= 0) continue;
      if (s.airDate != null && s.airDate!.compareTo(todayStr) >= 0) {
        if (targetSeason == null ||
            s.airDate!.compareTo(targetSeason.airDate!) < 0) {
          targetSeason = s;
        }
      }
    }
    if (targetSeason == null) {
      for (final s in details.seasons) {
        if (s.number <= 0) continue;
        if (targetSeason == null || s.number > targetSeason.number) {
          targetSeason = s;
        }
      }
    }

    final season = targetSeason;
    if (season == null) return;

    final provider = context.read<MediaRequestsProvider>();
    provider.loadSeasonEpisodes(details.id, season.number).then((episodes) {
      if (!mounted || episodes.isEmpty) return;

      RequestEpisode? nextEp;
      RequestEpisode? prevEp;

      for (final ep in episodes) {
        final air = ep.airDate;
        if (air == null || air.isEmpty) continue;
        if (air.compareTo(todayStr) >= 0) {
          if (nextEp == null || air.compareTo(nextEp.airDate!) < 0) {
            nextEp = ep;
          }
        } else {
          if (prevEp == null || air.compareTo(prevEp.airDate!) > 0) {
            prevEp = ep;
          }
        }
      }

      if (nextEp != null) {
        final ep = nextEp;
        final prev = prevEp;
        final seasonNum = season.number;
        setState(() {
          _fallbackNextEpisode = EpisodeAirRef(
            airDate: ep.airDate!,
            episodeNumber: ep.number,
            seasonNumber: seasonNum,
          );
          if (prev != null && prev.airDate != null) {
            _fallbackLastEpisode = EpisodeAirRef(
              airDate: prev.airDate!,
              episodeNumber: prev.number,
              seasonNumber: seasonNum,
            );
          }
        });
      } else {
        final normalizedStatus =
            (details.tmdbStatus ?? '').trim().toLowerCase();
        if (normalizedStatus == 'ended' ||
            normalizedStatus == 'canceled' ||
            normalizedStatus == 'cancelled') {
          final last = episodes.last;
          if (last.airDate != null && last.airDate!.isNotEmpty) {
            final seasonNum = season.number;
            setState(() {
              _fallbackLastEpisode = EpisodeAirRef(
                airDate: last.airDate!,
                episodeNumber: last.number,
                seasonNumber: seasonNum,
              );
            });
          }
        }
      }
    }).catchError((_) {
      // Donnée de secours facultative pour l'affichage : ne bloque pas la page.
    });
  }

  @override
  void initState() {
    super.initState();
    _details = context.read<MediaRequestsProvider>().loadDetails(widget.item);
  }

  void _retry() {
    setState(() {
      _details = context.read<MediaRequestsProvider>().loadDetails(widget.item);
    });
  }

  /// « Demander » envoie le titre entier (un film, ou toutes les saisons d'une
  /// série encore vierge) et referme la fiche ; quand MediaHub laisse choisir
  /// les saisons ([RequestAccess.seasonChoice]), il ouvre d'abord leur liste.
  /// « Compléter » ouvre la liste des saisons pas encore demandées
  /// ([RequestSeasonPickerSheet]) et n'envoie que celles qu'on coche, puis
  /// recharge la fiche pour que « Lire » reste là. Une saison seule se
  /// demande aussi en la dépliant ([RequestSeasonList]).
  Future<void> _request(RequestMediaDetails details,
      {bool complete = false}) async {
    if (_submitting) return;
    List<int>? seasons;
    if (complete) {
      seasons = await RequestSeasonPickerSheet.show(context, details);
      if (seasons == null || seasons.isEmpty || !mounted) return;
    } else if (details.mediaType == RequestMediaType.tv) {
      final all = [for (final s in details.requestableSeasons) s.number];
      final access = await context.read<MediaRequestsProvider>().loadAccess();
      if (!mounted) return;
      if (access.seasonChoice && all.length > 1) {
        seasons = await RequestSeasonPickerSheet.show(context, details,
            completing: false);
        if (seasons == null || seasons.isEmpty || !mounted) return;
      } else {
        seasons = all.isEmpty ? null : all;
      }
    }
    setState(() => _submitting = true);
    try {
      await context
          .read<MediaRequestsProvider>()
          .request(details, seasons: seasons);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Demande envoyée à MediaHub.'))));
      if (complete) {
        setState(() => _submitting = false);
        _retry();
      } else {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        // MediaHub dit pourquoi il refuse (droit, quota, déjà demandé) :
        // son message passe tel quel.
        final data = error is DioException ? error.response?.data : null;
        final message = data is Map && data['error'] is String
            ? data['error'] as String
            : tr('Impossible d’envoyer la demande.');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        setState(() => _submitting = false);
      }
    }
  }

  /// « Lire » : le titre est déjà dans la bibliothèque (en entier ou en
  /// partie), la fiche de lecture s'ouvre et lance la lecture, comme le lien
  /// « Lire sur Onyx » de MediaHub (ADR-0091).
  Future<void> _play(RequestMediaDetails details) async {
    if (_launching) return;
    final api = context.read<ApiClient>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final type = details.mediaType == RequestMediaType.tv
        ? MediaType.show
        : MediaType.movie;
    setState(() => _launching = true);
    final route = await PlayLink.routeForTmdb(api, type, details.id);
    if (!mounted) return;
    setState(() => _launching = false);
    if (route == null) {
      PlayLink.notFound(messenger);
      return;
    }
    unawaited(navigator.push(route));
  }

  Future<void> _openTrailer(String key) async {
    final url =
        'https://www.youtube.com/watch?v=${Uri.encodeQueryComponent(key)}';
    if (await openExternalUrl(url)) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Ouvrez la bande-annonce : {0}', [url]))));
    }
  }

  /// Le chargement garde le fond que l'envol vient de poser : la carte le
  /// connaît déjà, et la fiche n'attend pas le réseau pour avoir son image.
  Widget _loading() {
    if (widget.item.backdropUrl == null) return const LoadingView();
    return Stack(
      children: [
        DetailBackdrop(url: detailBackdropUrl(widget.item.backdropUrl)),
        const LoadingView(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<RequestMediaDetails>(
        future: _details,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _loading();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorStateView(
                message: tr('Impossible de charger ce média.'),
                onRetry: _retry);
          }
          return _content(snapshot.data!);
        },
      ),
    );
  }

  Widget _content(RequestMediaDetails details) {
    final isTv = details.mediaType == RequestMediaType.tv;
    final waiting = details.waitingMessage;
    final tracked = details.status != RequestMediaStatus.available &&
        details.status != RequestMediaStatus.unknown;

    if (isTv &&
        details.nextEpisodeToAir == null &&
        _fallbackNextEpisode == null &&
        _fallbackLastEpisode == null) {
      _resolveFallbackCountdown(details);
    }

    final nextEp = details.nextEpisodeToAir ?? _fallbackNextEpisode;
    final lastEp = details.lastEpisodeToAir ?? _fallbackLastEpisode;

    final hasSeasons = isTv && details.seasons.isNotEmpty;
    Widget cast() => CastSection(
          horizontalPadding: 0,
          cast: [
            for (final member in details.cast.take(25))
              CastMember(
                tmdbId: member.tmdbId,
                name: member.name,
                character: member.character,
                profileUrl: member.profileUrl,
              ),
          ],
          onTapMember: (member) =>
              openPerson(context, member.tmdbId, name: member.name),
        );

    return TvRegion.sections(
      child: CustomScrollView(
        scrollCacheExtent: AppLayout.imageCacheExtent(context),
        slivers: [
          SliverToBoxAdapter(
            child: TvRegion.section(
              id: 'hero',
              child: DetailHero(
                playKey: details.id,
                backdropUrl: detailBackdropUrl(details.backdropUrl),
                posterUrl: detailPosterUrl(details.posterUrl),
                logoUrl: logoImageUrl(details.logoUrl),
                title: details.title,
                tagline: details.tagline,
                overview: details.overview,
                emptyOverviewLabel: tr('Aucun synopsis disponible.'),
                eyebrow: _eyebrow(details),
                metadata: buildMetadataChips(
                  type: isTv ? MediaType.show : MediaType.movie,
                  releaseDate: details.releaseDate,
                  runtimeMinutes: details.runtime ?? 0,
                  rating: details.rating,
                  seasons: details.numberOfSeasons ?? 0,
                  genres: details.genres,
                ),
                actions: RequestDetailActions(
                  details: details,
                  listTitle: ListableTitle.catalog(widget.item),
                  submitting: _submitting,
                  launching: _launching,
                  onRequest: () => _request(details),
                  onComplete: () => _request(details, complete: true),
                  onPlay: () => _play(details),
                  onTrailer: () => _openTrailer(details.trailerKey!),
                ),
                trailing: MediaCountdown.fromDetails(
                  isTv: isTv,
                  nextEpisode: nextEp,
                  lastEpisode: lastEp,
                  status: details.tmdbStatus,
                  releaseDate: details.releaseDate,
                ),
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          // Sous l'en-tête et non dedans : sa hauteur est fixe, et le suivi d'une
          // demande a la taille qu'il veut.
          if ((waiting != null &&
                  details.status != RequestMediaStatus.available) ||
              tracked)
            SliverToBoxAdapter(
              child: TvRegion.section(
                id: 'progress',
                child: Padding(
                  padding: AppLayout.pageInsets(context, top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (waiting != null &&
                          details.status != RequestMediaStatus.available)
                        RequestImportNotice(message: waiting),
                      // Le suivi vient de MediaHub : un titre disponible n'a plus
                      // rien à montrer, les autres sont interrogés tant que l'écran
                      // est ouvert.
                      if (tracked)
                        RequestProgressPanel(
                            tmdbId: details.id, mediaType: details.mediaType),
                    ],
                  ),
                ),
              ),
            ),
          // Même ordre que les fiches de la bibliothèque. Une série passe par
          // ses saisons — c'est là qu'on demande. Dans les deux cas, le casting
          // ouvre la colonne de gauche, les crédits et les tags dessous, à côté
          // de la card d'infos : plus de vide sous les crédits.
          if (hasSeasons)
            SliverToBoxAdapter(
              child: TvRegion.section(
                id: 'seasons',
                child: Padding(
                  padding: AppLayout.pageInsets(context, top: 48),
                  child: RequestSeasonList(
                    tmdbId: details.id,
                    showItem: widget.item,
                    seasons: details.seasons,
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: TvRegion.section(
              id: 'info',
              child: Padding(
                padding: EdgeInsets.only(top: hasSeasons ? 32 : 0),
                child: DetailSummarySection(
                  credits: const [],
                  keywords: const [],
                  infoTable: RequestInfoTable(details: details),
                  mainTitle: tr('Informations'),
                  extra: details.cast.isEmpty ? null : cast(),
                ),
              ),
            ),
          ),
          for (final (index, (title, items)) in [
            (tr('Recommandations'), details.recommendations),
            (tr('Titres similaires'), details.similar),
          ].indexed)
            if (items.isNotEmpty)
              SliverToBoxAdapter(
                child: TvRegion.section(
                  id: 'rail-$index',
                  child: Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: PosterRail(
                      title: title,
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          RequestMediaCard(item: items[index]),
                    ),
                  ),
                ),
              ),
          const SliverToBoxAdapter(child: SizedBox(height: 56)),
        ],
      ),
    );
  }

  /// OnyxHub cache le surtitre en téléphone : la pastille de statut des
  /// boutons dit déjà la même chose, juste en dessous.
  Widget? _eyebrow(RequestMediaDetails details) {
    if (AppLayout.isCompact(context) ||
        details.status == RequestMediaStatus.unknown) {
      return null;
    }
    return RequestAvailabilityBadge(
      status: details.status,
      awaitingRelease: details.isAwaitingRelease(),
    );
  }
}
