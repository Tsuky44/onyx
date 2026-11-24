import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'interface_tour/tour_anchor.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../services/hero_series_preview.dart';
import '../../services/media_details_cache.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/lite_mode.dart';
import '../../utils/format.dart';
import '../../utils/poster_url.dart';
import '../../tv/tv_mode.dart';
import 'detail_actions.dart';
import 'hero/hero_actions.dart';
import 'hero/hero_heading.dart';
import 'hero/hero_living_backdrop.dart';
import 'hero/hero_next_episode_card.dart';
import 'hero_top_fade.dart';
import 'media_logo_display.dart';
import '../../theme/app_type.dart';
import '../../l10n/tr.dart';

class HeroBanner extends StatefulWidget {
  final Media media;
  final String? subtitle;
  final String? titleOverride;
  final String? backgroundUrlOverride;
  final String playLabel;
  final VoidCallback onPlay;
  final VoidCallback? onInfo;

  /// Le média dont on lit la fiche TMDB pour l'image de fond et le logo : la
  /// série pour un épisode, le média lui-même sinon.
  final int? detailsMediaId;

  final bool autofocusPlay;

  /// La hauteur ajoutée au-dessus du bandeau pour que l'image monte sous la
  /// barre d'état et la barre du haut du téléphone (ADR-0144). Le texte et
  /// les boutons, calés en bas, ne bougent pas.
  final double extendTop;

  /// L'épisode de « Reprendre » que présente la diapositive. Pour une série
  /// de la découverte, nul : le bandeau demande au serveur l'épisode à
  /// reprendre, comme la fiche (ADR-0154).
  final HomeMediaItem? continueItem;

  /// La diapositive est celle qu'on voit. Ses voisines, que le carrousel
  /// construit pendant un passage, ne font pas défiler leur fond.
  final bool active;

  /// Le nombre d'images que le fond fera défiler : le carrousel laisse à la
  /// diapositive le temps de les montrer.
  final ValueChanged<int>? onFrameCount;

  const HeroBanner({
    super.key,
    required this.media,
    this.subtitle,
    this.titleOverride,
    this.backgroundUrlOverride,
    this.playLabel = 'Lecture',
    required this.onPlay,
    this.onInfo,
    this.detailsMediaId,
    this.autofocusPlay = false,
    this.extendTop = 0,
    this.continueItem,
    this.active = true,
    this.onFrameCount,
  });

  /// La largeur à partir de laquelle la carte « À suivre » d'une série se pose
  /// à droite du texte : en dessous, elle le chevauchait.
  static const double cardMinWidth = 1000;

  static double heightFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Un téléviseur se met en page sur 1280 × 720 (voir [TvUiScale]) : à 55 %,
    // le bandeau faisait 396 px pour un contenu de plus de 400, calé en bas.
    // Le logo et le type sortaient par le haut, coupés sous l'en-tête.
    final fraction = TvScope.of(context)
        ? 0.7
        : size.width < 600
            ? 0.55
            : 0.65;
    return (size.height * fraction).clamp(360.0, 580.0);
  }

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  MediaDetails? _details;
  bool _detailsSettled = false;

  /// L'épisode à lancer et les images du fond, pour une série (ADR-0154).
  HeroSeriesPreview? _preview;

  /// L'image du fond à l'écran, pour sa légende.
  final ValueNotifier<int> _frame = ValueNotifier(0);
  int? _reportedFrames;

  int get _detailsId => widget.detailsMediaId ?? widget.media.id;

  /// Une série de la découverte, ou un épisode de « Reprendre ».
  bool get _isSeries =>
      widget.media.type == MediaType.show ||
      widget.media.type == MediaType.episode;

  /// L'épisode que la lecture lance, quand c'est une série.
  HomeMediaItem? get _episode => widget.continueItem ?? _preview?.next;

  @override
  void initState() {
    super.initState();
    _resolveDetails();
    _resolvePreview();
  }

  @override
  void didUpdateWidget(covariant HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detailsMediaId != widget.detailsMediaId ||
        oldWidget.media.id != widget.media.id) {
      _resolveDetails();
    }
    if (oldWidget.media.id != widget.media.id ||
        oldWidget.continueItem?.media.id != widget.continueItem?.media.id) {
      _frame.value = 0;
      _resolvePreview();
    }
  }

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }

  /// La fiche TMDB porte l'image de fond en paysage et le logo du titre. Le
  /// bandeau étirait jusqu'ici l'affiche — un portrait 2:3 recadré en 16:9,
  /// agrandi jusqu'au flou, visages coupés — sous un titre en texte brut.
  void _resolveDetails() {
    final id = _detailsId;
    _details = MediaDetailsCache.peek(id);
    _detailsSettled = _details != null || id <= 0;
    if (_detailsSettled) return;
    final api = Provider.of<ApiClient>(context, listen: false);
    MediaDetailsCache.load(api, id).then((details) {
      if (!mounted || id != _detailsId) return;
      setState(() {
        _details = details;
        _detailsSettled = true;
      });
    }, onError: (_) {
      if (!mounted || id != _detailsId) return;
      setState(() => _detailsSettled = true);
    });
  }

  /// L'épisode à lancer et les images de sa saison. Jusqu'à la réponse, le
  /// bandeau d'une série de la découverte garde « Lecture » seul, qui ouvre
  /// la fiche ; celui d'une reprise connaît déjà son épisode.
  void _resolvePreview() {
    final showId = _detailsId;
    final known = widget.continueItem;
    if (!_isSeries || showId <= 0) {
      _preview = null;
      return;
    }
    final cached = HeroSeriesPreviewCache.peek(showId, known: known);
    _preview = cached;
    if (cached != null) return;
    final api = Provider.of<ApiClient>(context, listen: false);
    HeroSeriesPreviewCache.load(api, showId, known: known).then((preview) {
      if (!mounted || showId != _detailsId) return;
      if (known?.media.id != widget.continueItem?.media.id) return;
      setState(() => _preview = preview);
    }, onError: (Object error) {
      // Le bandeau reste celui d'avant : « Lecture » ouvre la fiche, le fond
      // est l'image de la série.
      debugPrint('HeroBanner: aperçu de la série $showId indisponible: $error');
    });
  }

  String? _backgroundUrl(String baseUrl) {
    final media = widget.media;
    // Un épisode a déjà son image en paysage : l'arrêt sur image de
    // l'épisode, plus parlant que le fond générique de la série.
    if (media.type == MediaType.episode &&
        widget.backgroundUrlOverride != null) {
      return widget.backgroundUrlOverride;
    }
    final backdrop = _details?.backdropUrl;
    if (backdrop != null && backdrop.isNotEmpty) {
      return backdropImageUrl(backdrop, serverBaseUrl: baseUrl);
    }
    // Tant que la fiche n'a pas répondu, rien plutôt que l'affiche : elle
    // serait remplacée une demi-seconde plus tard par une autre image.
    if (!_detailsSettled) return null;
    return widget.backgroundUrlOverride ??
        resolveHeroImageUrl(media.posterUrl, serverBaseUrl: baseUrl);
  }

  /// Le fond vivant : l'image du titre, puis celles des épisodes de la saison
  /// jusqu'à celui à lancer, chacune une fois.
  List<HeroBackdropFrame> _frames(
      String? backgroundUrl, String baseUrl, bool animate) {
    if (backgroundUrl == null) return const [];
    final frames = [HeroBackdropFrame(backgroundUrl)];
    if (!animate) return frames;
    final seen = {backgroundUrl};
    for (final still in _preview?.stills ?? const <HomeMediaItem>[]) {
      final url =
          resolveHeroImageUrl(still.media.posterUrl, serverBaseUrl: baseUrl);
      if (url == null || !seen.add(url)) continue;
      frames.add(HeroBackdropFrame(url, caption: heroEpisodeTitle(still)));
    }
    return frames;
  }

  /// Dit au carrousel combien d'images passeront, après l'image en cours.
  void _reportFrames(int count) {
    if (count == _reportedFrames) return;
    _reportedFrames = count;
    final report = widget.onFrameCount;
    if (report == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) report(count);
    });
  }

  @override
  Widget build(BuildContext context) {
    final apiClient = Provider.of<ApiClient>(context, listen: false);
    final media = widget.media;
    final details = _details;
    final backgroundUrl = _backgroundUrl(apiClient.baseUrl);
    final title = widget.titleOverride ?? media.title;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 600;
    final isTv = TvScope.of(context);
    final horizontalPadding = isCompact ? 16.0 : 48.0;
    final textBottom = isCompact
        ? 52.0
        : isTv
            ? 72.0
            : 140.0;
    final bannerHeight = HeroBanner.heightFor(context) + widget.extendTop;
    final detailsOverview = details?.overview;
    final overview = media.type != MediaType.episode &&
            detailsOverview != null &&
            detailsOverview.isNotEmpty
        ? detailsOverview
        : media.overview;

    // Le fond ne bouge que sous les yeux, et pas là où le mouvement coûte ou
    // gêne : téléviseur, mode léger, « réduire les animations ».
    final animate = widget.active &&
        !isTv &&
        !AppMotion.reduced(context) &&
        !LiteScope.of(context);
    final frames = _frames(backgroundUrl, apiClient.baseUrl, animate);
    _reportFrames(frames.length);
    final captioned = frames.length > 1;

    final episode = _isSeries ? _episode : null;
    final resuming = episode != null &&
        episode.currentPositionSeconds > 0 &&
        !episode.isFinished;
    final playLabel = episode == null
        ? tr(widget.playLabel)
        : resuming
            ? tr('Reprendre')
            : tr('Lecture');
    final showCard = episode != null &&
        !isCompact &&
        !isTv &&
        screenWidth >= HeroBanner.cardMinWidth;

    final seasons = details?.numberOfSeasons ?? 0;
    final eyebrow = [
      mediaTypeLabel(_isSeries ? MediaType.show : media.type),
      if (_isSeries && seasons > 0)
        trPlural(seasons, '{0} saison', '{0} saisons'),
    ].join('  ·  ');
    final meta = HeroMetaLine(
      year: extractYear(media.releaseDate),
      genres: details?.genres ?? const [],
      rating: details?.voteAverage ?? 0,
      // Pour une série, le bouton et la carte disent déjà l'épisode : la
      // ligne annonce plutôt le prochain à sortir. Pas au téléphone, où il ne
      // tenait plus et finissait en « Prochain épisode le… ».
      trailing: _isSeries
          ? (isCompact ? null : heroNextAirLabel(details))
          : widget.subtitle,
    );

    final play = HeroPlayButton(
      label: playLabel,
      episodeCode: episode == null ? null : episodeShortCode(episode.media),
      onPressed: widget.onPlay,
      autofocus: widget.autofocusPlay,
      isTv: isTv,
    );
    final info = widget.onInfo == null
        ? null
        : HeroInfoButton(
            onPressed: widget.onInfo!,
            compact: isCompact,
            isTv: isTv,
          );

    return SizedBox(
      height: bannerHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.background),
          if (frames.isNotEmpty)
            // Sous la barre du téléphone, l'image garde son cadrage et se
            // fond dans le noir par le haut (ADR-0144).
            HeroTopFade(
              top: widget.extendTop,
              image: HeroLivingBackdrop(
                key: ValueKey(media.id),
                frames: frames,
                animate: animate,
                // Logical width — AppNetworkImage applies the device pixel ratio.
                decodeWidth: screenWidth,
                frame: _frame,
              ),
            ),

          // Le voile latéral d'abord, le vertical ensuite, et tous deux vers
          // la couleur de la page : peint en noir pur par-dessus le fondu
          // vertical, le voile latéral laissait une marche visible entre le
          // bas du bandeau et la première rangée.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.background
                      .withValues(alpha: isCompact ? 0.55 : 0.9),
                  AppColors.background
                      .withValues(alpha: isCompact ? 0.2 : 0.45),
                  AppColors.background.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.4, 0.75],
              ),
            ),
          ),
          Positioned.fill(
            top: widget.extendTop,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    // Un voile en haut, pour que l'en-tête reste lisible sur un
                    // fond clair. Pas sous la barre du téléphone : elle est
                    // sur le noir, et le voile cachait les têtes que l'image
                    // fait sortir du fondu (ADR-0144).
                    AppColors.background
                        .withValues(alpha: widget.extendTop > 0 ? 0 : 0.45),
                    AppColors.background.withValues(alpha: 0),
                    AppColors.background.withValues(alpha: 0.35),
                    AppColors.background,
                  ],
                  stops: const [0.0, 0.25, 0.6, 1.0],
                ),
              ),
            ),
          ),

          Positioned(
            left: horizontalPadding,
            right: horizontalPadding,
            bottom: textBottom,
            // L'Align relâche la largeur imposée par le Positioned : sans lui,
            // la limite de 560 px était ignorée et le synopsis courait sur toute
            // la largeur de l'écran.
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: isCompact ? double.infinity : 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HeroEyebrow(
                      text: eyebrow,
                      newEpisode: episode?.hasNewEpisode ?? false,
                    ),
                    const SizedBox(height: 12),
                    MediaLogoDisplay(
                      title: title,
                      logoUrl: logoImageUrl(details?.logoUrl,
                          serverBaseUrl: apiClient.baseUrl),
                      maxHeight: isCompact ? 72 : 128,
                      maxWidth: isCompact ? screenWidth * 0.8 : 560,
                      textStyle:
                          Theme.of(context).textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: isCompact ? 30 : 44,
                                height: 1.05,
                                letterSpacing: isCompact ? -0.6 : -1.0,
                              ),
                    ),
                    if (!meta.isEmpty) ...[
                      const SizedBox(height: 12),
                      meta,
                    ],
                    if (overview != null && overview.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        overview,
                        // Deux lignes sur un téléviseur : lues de loin, la
                        // troisième poussait le logo sous l'en-tête.
                        maxLines: isCompact || isTv || showCard ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: AppType.callout,
                          height: 1.5,
                        ),
                      ),
                    ],
                    SizedBox(height: isCompact ? 20 : 24),
                    TourTarget(
                      anchor: TourAnchor.hero,
                      // Sur téléphone, la lecture prend la largeur et
                      // « Plus d'infos » se réduit à son rond de verre.
                      child: isCompact
                          ? Row(
                              children: [
                                Expanded(child: play),
                                if (info != null) ...[
                                  const SizedBox(width: 10),
                                  info,
                                ],
                              ],
                            )
                          : Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [play, if (info != null) info],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (showCard)
            Positioned(
              right: horizontalPadding,
              bottom: textBottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (captioned) ...[
                    SizedBox(
                      width: HeroNextEpisodeCard.width,
                      child: HeroBackdropCaption(frames: frames, frame: _frame),
                    ),
                    const SizedBox(height: 10),
                  ],
                  HeroNextEpisodeCard(episode: episode, onTap: widget.onPlay),
                ],
              ),
            )
          else if (captioned)
            Positioned(
              right: horizontalPadding,
              // Sur téléphone, à hauteur des traits du carrousel.
              bottom: isCompact ? 24 : textBottom,
              width: isCompact ? 180 : HeroNextEpisodeCard.width,
              child: HeroBackdropCaption(frames: frames, frame: _frame),
            ),
        ],
      ),
    );
  }
}
