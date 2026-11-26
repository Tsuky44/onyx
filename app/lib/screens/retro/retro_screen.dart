import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/retro.dart';
import '../../providers/auth_provider.dart';
import '../../providers/retro_provider.dart';
import '../../services/api_client.dart';
import '../../services/media_details_cache.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../tv/nav/tv_focusable.dart';
import '../../utils/poster_url.dart';
import '../../widgets/global/app_network_image.dart';
import '../../widgets/global/empty_state.dart';
import 'hooks/retro_story_controller.dart';
import 'services/retro_share.dart';
import 'services/retro_share_action.dart';
import 'slides/retro_slide.dart';
import 'slides/retro_slides.dart';
import 'widgets/retro_slide_transition.dart';
import 'widgets/retro_story_chrome.dart';

/// Le Rétro de fin d'année, plein écran (ADR 2026-11-26-tsuky-retro-annuel).
///
/// Charge le Rétro de [year], le marque vu, puis déroule ses écrans. Une
/// seule mise en page s'adapte à la forme de l'écran : portrait sur un
/// téléphone, deux colonnes sur un PC ou un téléviseur.
class RetroScreen extends StatefulWidget {
  const RetroScreen({super.key, required this.year});

  final int year;

  static Future<void> open(BuildContext context, int year) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RetroScreen(year: year),
      ));

  @override
  State<RetroScreen> createState() => _RetroScreenState();
}

class _RetroScreenState extends State<RetroScreen> {
  late Future<({RetroReport report, String? logo})> _report;

  /// Ce qu'on attend au plus le logo du n°1 : au-delà, l'écran écrit le titre
  /// plutôt que de retenir toute la story.
  static const _logoWait = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _report = _load();
  }

  Future<({RetroReport report, String? logo})> _load() async {
    final retro = context.read<RetroProvider>();
    final api = context.read<ApiClient>();
    final report = await retro.loadReport(widget.year);
    if (!report.eligible) return (report: report, logo: null);
    // Le logo vient de la fiche du titre, la même que celle des pages de
    // détail et du lecteur : souvent déjà en cache.
    final top = report.top.firstOrNull;
    final logo = top == null
        ? Future<String?>.value()
        : MediaDetailsCache.resolveLogo(api, top.mediaId)
            .timeout(_logoWait, onTimeout: () => null);
    await retro.markSeen(widget.year);
    return (
      report: report,
      logo: logoImageUrl(await logo, serverBaseUrl: api.baseUrl),
    );
  }

  void _retry() => setState(() => _report = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<({RetroReport report, String? logo})>(
        future: _report,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorStateView(
              message: tr(
                  'Impossible de charger ton Rétro. Vérifie la connexion au serveur, puis réessaie.'),
              onRetry: _retry,
            );
          }
          final loaded = snapshot.data;
          if (loaded == null) return const LoadingView();
          final report = loaded.report;
          if (!report.eligible) {
            return EmptyStateView(
              icon: AppIcons.close,
              title: tr('Rendez-vous l’an prochain'),
              message: tr(
                  'Il faut au moins 5 heures de lecture dans l’année pour avoir un Rétro.'),
              actionLabel: tr('Fermer'),
              onAction: () => Navigator.of(context).maybePop(),
            );
          }
          return _RetroStory(
            data: RetroStoryData(
              report: report,
              name: context.read<AuthProvider>().currentUser?.username ?? '',
              serverBaseUrl: context.read<ApiClient>().baseUrl,
              topLogoUrl: loaded.logo,
            ),
          );
        },
      ),
    );
  }
}

class _RetroStory extends StatefulWidget {
  const _RetroStory({required this.data});
  final RetroStoryData data;

  @override
  State<_RetroStory> createState() => _RetroStoryState();
}

class _RetroStoryState extends State<_RetroStory>
    with SingleTickerProviderStateMixin {
  late final RetroStoryController _story =
      RetroStoryController(count: kRetroSlides.length);
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;

  bool _warmed = false;

  /// L'image de récap se prépare : le bouton attend.
  bool _sharing = false;

  Future<void> _share(Rect origin) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    await shareRetroImage(
      context,
      report: widget.data.report,
      name: widget.data.name,
      origin: origin,
    );
    if (mounted) setState(() => _sharing = false);
  }

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_warmed) return;
    _warmed = true;
    // Le logo du n°1 arrive au troisième écran : ses octets ont le temps de
    // venir pendant les deux premiers, et il s'affiche sans attente.
    unawaited(AppNetworkImage.precache(
      widget.data.topLogoUrl,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    ));
  }

  void _onTick(Duration elapsed) {
    _story.tick(elapsed - _last);
    _last = elapsed;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _story.dispose();
    super.dispose();
  }

  bool _onDirection(TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.left:
        _story.previous();
        return true;
      case TraversalDirection.right:
        _story.next();
        return true;
      case TraversalDirection.up:
      case TraversalDirection.down:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: true,
      showRing: false,
      focusScale: 1,
      borderRadius: BorderRadius.zero,
      onSelect: _story.togglePause,
      onDirection: _onDirection,
      child: ListenableBuilder(
        listenable: _story,
        builder: (context, _) {
          final slide = kRetroSlides[_story.index];
          final colors = slide.colors(widget.data);
          return Stack(
            fit: StackFit.expand,
            children: [
              RetroSlideTransition(
                index: _story.index,
                origin: _story.origin,
                child: slide.build(context, widget.data),
              ),
              RetroStoryChrome(
                story: _story,
                ink: colors.ink,
                background: colors.background,
                onShare: _share,
                sharing: _sharing,
                shareSaves: RetroShare.savesFile,
                year: widget.data.report.year,
                onClose: () => Navigator.of(context).maybePop(),
              ),
            ],
          );
        },
      ),
    );
  }
}
