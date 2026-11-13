import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/models.dart';
import '../../../services/api_client.dart';
import '../../../services/media_details_cache.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../utils/poster_url.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/app_network_image.dart';
import '../../../widgets/global/detail_metadata.dart';
import '../../../widgets/global/media_logo_display.dart';
import '../../../widgets/global/poster_flight.dart';

/// La fiche du titre que la télécommande désigne, dans le volet gauche d'une
/// bibliothèque sur téléviseur (ADR-0123, ADR-0125) : son image de fond, son logo ou son
/// titre, une ligne de métadonnées et son résumé.
///
/// Ce que la bibliothèque sait déjà s'écrit tout de suite : le titre, l'année,
/// la durée, le résumé. Le reste (image de fond, logo, genres, note) vient de
/// la fiche du catalogue (`MediaDetailsCache`), demandée une fois que le focus
/// s'est posé : traverser une rangée ne demande pas une fiche par affiche.
/// C'est la même fiche, à la même adresse d'image, que `DetailPrefetch`
/// réchauffe pour la page du titre : l'ouvrir ensuite ne recharge rien.
///
/// Rien ne clignote sous un focus qui court : le titre change tout de suite,
/// le logo ne remplace le titre qu'une fois décodé, et l'image de fond du
/// titre précédent reste jusqu'à ce que la suivante soit prête.
class LibrarySpotlight extends StatefulWidget {
  const LibrarySpotlight({
    super.key,
    required this.media,
    required this.eyebrow,
    required this.textWidth,
  });

  /// Le titre présenté.
  final Media media;

  /// Le surtitre : le nom de la bibliothèque et son nombre de titres.
  final String eyebrow;

  /// La largeur laissée au texte, depuis la gouttière de la page. L'image de
  /// fond, elle, remplit tout le widget et se fond vers la grille.
  final double textWidth;

  /// Le temps que le focus doit rester sur une affiche avant que sa fiche soit
  /// demandée. Un peu plus que les 120 ms du préchargement d'une carte
  /// (`PosterCard`) : la demande est alors déjà partie, et celle-ci la rejoint.
  static const Duration settle = Duration(milliseconds: 220);

  /// La hauteur du logo, ou de deux lignes de titre.
  static const double titleHeight = 84;

  /// Le surtitre et l'écart qui le sépare du titre.
  static const double _eyebrowHeight = 24;

  /// La place du surtitre et du titre, la même pour toutes les fiches.
  static const double headingHeight = _eyebrowHeight + titleHeight;

  /// Où commence le texte, en part de la hauteur de l'écran : assez bas pour
  /// laisser l'image respirer au-dessus, assez haut pour six lignes de résumé
  /// et le tri dessous.
  static const double textTop = 0.30;

  @override
  State<LibrarySpotlight> createState() => _LibrarySpotlightState();
}

class _LibrarySpotlightState extends State<LibrarySpotlight> {
  /// La fiche du catalogue de [_detailsOf], ou nul tant qu'elle n'est pas là.
  MediaDetails? _details;
  int? _detailsOf;

  /// Le logo du titre présenté, une fois connu ; d'ici là, son titre en
  /// toutes lettres.
  String? _logo;

  /// L'image de fond à l'écran : celle du dernier titre dont l'image est
  /// décodée. Elle reste le temps que la suivante soit prête, pour un fondu
  /// d'image à image et non un passage par le fond nu.
  String? _backdrop;

  Timer? _settle;

  /// Le rang du titre présenté : une réponse arrivée après que la
  /// télécommande est passée à un autre est ignorée.
  int _turn = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pas dans initState : la suite lit la densité de l'écran.
    if (_started) return;
    _started = true;
    _follow();
  }

  @override
  void didUpdateWidget(LibrarySpotlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id) _follow();
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  /// Suit le titre présenté : sa fiche tout de suite si elle est en mémoire,
  /// sinon demandée quand le focus s'est posé.
  void _follow() {
    _settle?.cancel();
    final turn = ++_turn;
    final id = widget.media.id;
    final api = Provider.of<ApiClient>(context, listen: false);
    final cached = MediaDetailsCache.peek(id);
    _details = cached;
    _detailsOf = id;
    // Une fiche déjà vue a son logo en mémoire : il se pose sans attendre.
    _logo = logoImageUrl(cached?.logoUrl, serverBaseUrl: api.baseUrl);
    if (cached != null) unawaited(_showBackdrop(cached, turn));
    if (id <= 0 || MediaDetailsCache.isFresh(id)) return;
    _settle = Timer(LibrarySpotlight.settle, () async {
      try {
        final details = await MediaDetailsCache.load(api, id);
        if (!mounted || turn != _turn) return;
        setState(() {
          _details = details;
          _detailsOf = id;
        });
        await _showLogo(details, turn);
        await _showBackdrop(details, turn);
      } catch (_) {
        // Sans réseau, la fiche garde ce que la bibliothèque sait déjà : le
        // titre, l'année et le résumé. L'image du titre précédent, elle, ne
        // doit pas rester sous celui-ci.
        if (mounted && turn == _turn && cached == null && _backdrop != null) {
          setState(() => _backdrop = null);
        }
      }
    });
  }

  /// Pose le logo de [details] une fois décodé : le titre en toutes lettres
  /// reste d'ici là, au lieu d'une place vide.
  Future<void> _showLogo(MediaDetails details, int turn) async {
    if (!mounted) return;
    final baseUrl = Provider.of<ApiClient>(context, listen: false).baseUrl;
    final logo = logoImageUrl(details.logoUrl, serverBaseUrl: baseUrl);
    await AppNetworkImage.precache(
      logo,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    if (!mounted || turn != _turn || logo == _logo) return;
    setState(() => _logo = logo);
  }

  /// Pose l'image de fond de [details] une fois décodée. Même adresse et même
  /// largeur de décodage que le fond de la page du titre (`DetailBackdrop`),
  /// que `DetailPrefetch` réchauffe déjà : une seule image pour les trois.
  Future<void> _showBackdrop(MediaDetails details, int turn) async {
    if (!mounted) return;
    final baseUrl = Provider.of<ApiClient>(context, listen: false).baseUrl;
    final backdrop =
        detailBackdropUrl(details.backdropUrl, serverBaseUrl: baseUrl);
    await AppNetworkImage.precache(
      backdrop,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      decodeWidth: MediaQuery.sizeOf(context).width,
    );
    if (!mounted || turn != _turn || backdrop == _backdrop) return;
    setState(() => _backdrop = backdrop);
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final details = _detailsOf == media.id ? _details : null;
    final backdrop = _backdrop;
    final logo = _logo;
    final overview = (details?.overview ?? media.overview)?.trim() ?? '';
    final metadata = buildMetadataChips(
      type: media.type,
      releaseDate: details?.releaseDate ?? media.releaseDate,
      runtimeMinutes: details?.runtime ?? 0,
      durationSeconds: media.duration,
      rating: details?.voteAverage ?? 0,
      seasons: details?.numberOfSeasons ?? 0,
      // Deux genres : avec la note et la durée, un troisième passait la
      // ligne et poussait le résumé.
      genres: details?.genres.take(2).toList() ?? const [],
    );
    final padding = AppLayout.pagePadding(context);

    return LayoutBuilder(builder: (context, constraints) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Un fondu d'une image à l'autre : coupée net, l'écran clignotait à
          // chaque affiche.
          AnimatedSwitcher(
            duration: AppMotion.fade(context, AppMotion.emphasis),
            switchInCurve: AppMotion.curve,
            switchOutCurve: AppMotion.curve,
            child: backdrop == null
                ? const SizedBox.expand(key: ValueKey<String>('sans-image'))
                : SizedBox.expand(
                    key: ValueKey<String>(backdrop),
                    child: AppNetworkImage(
                      url: backdrop,
                      fit: BoxFit.cover,
                      alignment: PosterFlight.focus,
                      filterQuality: FilterQuality.high,
                      decodeWidth: MediaQuery.sizeOf(context).width,
                      // Déjà décodée ([_showBackdrop]) : le fondu est celui de
                      // l'`AnimatedSwitcher`, pas un second par-dessus.
                      fadeInDuration: Duration.zero,
                      placeholder: const SizedBox.expand(),
                      errorWidget: const SizedBox.expand(),
                    ),
                  ),
          ),
          // L'image se fond vers la grille, à droite, et vers le bas : elle se
          // voit en haut du volet, et le texte se lit sur un fond presque
          // uni, même devant un ciel blanc.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.background.withValues(alpha: 0.25),
                  AppColors.background.withValues(alpha: 0.45),
                  AppColors.background,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background.withValues(alpha: 0.10),
                  AppColors.background.withValues(alpha: 0.25),
                  AppColors.background.withValues(alpha: 0.80),
                  AppColors.background.withValues(alpha: 0.96),
                  AppColors.background,
                ],
                // Le surtitre commence à [LibrarySpotlight.textTop].
                stops: const [0.0, 0.22, 0.42, 0.60, 1.0],
              ),
            ),
          ),
          Positioned(
            left: padding,
            top: constraints.maxHeight * LibrarySpotlight.textTop,
            width: widget.textWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Une place fixe, remplie depuis le bas : le logo qui arrive
                // après le titre ne décale ni les métadonnées ni le résumé,
                // et le surtitre reste collé au titre, qu'il tienne sur une
                // ligne ou sur deux.
                SizedBox(
                  height: LibrarySpotlight.headingHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        widget.eyebrow.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: AppType.caption,
                          letterSpacing: 1.6,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Sans fondu : sous un focus qui court, deux titres
                      // superposés ne se lisent ni l'un ni l'autre.
                      MediaLogoDisplay(
                        key: ValueKey<String>('${media.id}:${logo ?? ''}'),
                        title: media.title,
                        logoUrl: logo,
                        maxHeight: LibrarySpotlight.titleHeight,
                        maxWidth: widget.textWidth,
                        textStyle: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: AppType.hero,
                          fontWeight: FontWeight.w800,
                          height: 1.04,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (metadata.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (var i = 0; i < metadata.length; i++) ...[
                        if (i > 0) const MetadataDot(),
                        metadata[i],
                      ],
                    ],
                  ),
                ],
                if (overview.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    overview,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppType.callout,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    });
  }
}
