import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/media_request.dart';
import '../../models/models.dart';
import '../../navigation/detail_flight.dart';
import '../../providers/library_provider.dart';
import '../../services/api_client.dart';
import '../../services/tv_system_search.dart';
import '../../services/unavailable_titles_search.dart';
import '../../theme/app_colors.dart';
import '../../utils/format.dart';
import '../../utils/poster_url.dart';
import '../../widgets/global/unavailable_badge.dart';
import '../requests/request_availability.dart';
import '../requests/request_detail_launch.dart';
import 'search_shelves.dart';
import 'tv_search_screen.dart';

/// La recherche de l'Apple TV : l'écran de recherche du système, présenté par
/// l'hôte natif par-dessus cette page (ADR-0129).
///
/// Demande de l'utilisateur, capture de YouTube à l'appui : « je veux la même
/// recherche que YouTube, on a le clavier ou on peut utiliser l'iPhone pour
/// noter ou sinon Siri et on a les résultats ici ». Le clavier en ligne de
/// tvOS, sa dictée et la saisie depuis un iPhone n'existent que dans UIKit
/// (`UISearchController`) : l'écran entier est donc natif, affiches comprises,
/// et c'est le moteur de focus du système qui va du clavier aux résultats.
///
/// Cette page n'affiche rien elle-même. Elle tient le rôle du cerveau :
///
/// - elle apprend ce qu'on tape, cherche dans la bibliothèque et dans le
///   catalogue de demandes ([SearchShelves]), et dit à l'écran quoi montrer ;
/// - quand on choisit une affiche, elle ouvre la fiche Flutter par-dessus
///   elle : l'écran du système se retire, puis revient tel quel quand la
///   fiche se referme ;
/// - quand on quitte l'écran par Retour, elle se referme avec lui.
///
/// Si l'hôte ne présente pas l'écran, la page devient la recherche dessinée
/// par Flutter ([TvSearchScreen]) : on ne reste jamais devant une page vide.
class TvSystemSearchScreen extends StatefulWidget {
  const TvSystemSearchScreen({super.key});

  /// Au-delà, un rayon ne grandit plus : l'écran natif reçoit tout son
  /// contenu à chaque frappe, et une lettre seule ramène presque toute une
  /// bibliothèque. Le compte du rayon, lui, dit le vrai total : on tape une
  /// lettre de plus.
  static const int shelfLimit = 120;

  /// La largeur d'une affiche de l'écran natif, en part de celle de l'écran :
  /// six par ligne entre les marges de tvOS. Chaque image est demandée à
  /// cette taille, pas plus (`tmdbUrlForWidth`).
  static const double posterWidthFactor = 0.14;

  @override
  State<TvSystemSearchScreen> createState() => _TvSystemSearchScreenState();
}

class _TvSystemSearchScreenState extends State<TvSystemSearchScreen> {
  late final LibraryProvider _library = context.read<LibraryProvider>();
  late final UnavailableTitlesSearch _catalog =
      UnavailableTitlesSearch(context.read<ApiClient>());

  /// Ce qu'ouvre chaque affiche envoyée à l'écran : un titre de la
  /// bibliothèque ([Media]) ou un titre à demander ([RequestMediaItem]).
  final Map<String, Object> _targets = <String, Object>{};

  String _query = '';

  /// Nul tant que l'hôte n'a pas répondu ; faux s'il n'a pas montré l'écran.
  bool? _native;

  /// Vrai tant qu'une fiche recouvre cette page.
  bool _covered = false;

  /// Vrai quand c'est la télécommande qui a fermé l'écran : il n'y a plus
  /// rien à fermer en partant.
  bool _closedByRemote = false;

  @override
  void initState() {
    super.initState();
    _library.addListener(_send);
    _catalog.addListener(_send);
    TvSystemSearch.listen(TvSystemSearchEvents(
      onQuery: _onQuery,
      onSelect: _onSelect,
      onClosed: _onClosed,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _library.ensureCatalogLoaded();
      _present();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `ModalRoute.of` prévient quand une fiche recouvre la page, puis quand
    // elle la rend : l'écran du système se retire devant la fiche, et
    // revient avec la page.
    final covered = !(ModalRoute.of(context)?.isCurrent ?? true);
    if (covered == _covered) return;
    _covered = covered;
    if (_native != true) return;
    if (covered) {
      TvSystemSearch.hide();
    } else {
      // La fiche a pu changer ce qu'on montre : un titre demandé, un film vu.
      _catalog.refresh();
      _send();
      TvSystemSearch.show();
    }
  }

  @override
  void dispose() {
    TvSystemSearch.listen(null);
    if (_native == true && !_closedByRemote) TvSystemSearch.close();
    _library.removeListener(_send);
    _catalog.removeListener(_send);
    _catalog.dispose();
    super.dispose();
  }

  Future<void> _present() async {
    final shown = await TvSystemSearch.present(
      placeholder: tr('Rechercher un film ou une série…'),
      colors: {
        'background': AppColors.background.toARGB32(),
        'surfaceElevated': AppColors.surfaceElevated.toARGB32(),
        'textPrimary': AppColors.textPrimary.toARGB32(),
        'textSecondary': AppColors.textSecondary.toARGB32(),
        'textMuted': AppColors.textMuted.toARGB32(),
        'progress': AppColors.progress.toARGB32(),
        'success': AppColors.success.toARGB32(),
        'unavailableTint': AppColors.unavailableTint.toARGB32(),
      },
      content: _content(),
    );
    if (!mounted) {
      // La page est partie avant la réponse : rien ne doit rester devant.
      if (shown) TvSystemSearch.close();
      return;
    }
    setState(() => _native = shown);
    if (!shown) return;
    // Ce qui a bougé pendant la présentation : la bibliothèque finit souvent
    // de se charger à ce moment-là.
    _send();
    if (_covered) TvSystemSearch.hide();
  }

  void _onQuery(String query) {
    if (!mounted) return;
    _query = query;
    _catalog.search(query, enabled: canRequestMedia(context));
    _send();
  }

  void _onSelect(String id) {
    if (!mounted || _covered) return;
    final target = _targets[id];
    if (target is Media) {
      openMediaDetail(
        context,
        target,
        item: target.type == MediaType.movie
            ? _library.movieItemFor(target.id)
            : null,
        // Les affiches sont natives : il n'y a pas de carte d'où s'envoler.
        measureCard: false,
      );
    } else if (target is RequestMediaItem) {
      openRequestDetail(context, target, measureCard: false);
    }
  }

  void _onClosed() {
    _closedByRemote = true;
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      route.navigator?.removeRoute(route);
    }
  }

  void _send() {
    if (!mounted || _native != true) return;
    TvSystemSearch.update(_content());
  }

  /// Ce que l'écran montre pour la recherche en cours, et, dans [_targets],
  /// ce qu'ouvre chacune de ses affiches.
  SystemSearchContent _content() {
    final api = context.read<ApiClient>();
    final query = _query.trim();
    final posterWidth = View.of(context).physicalSize.width *
        TvSystemSearchScreen.posterWidthFactor;
    String? poster(String? url, {String? serverBaseUrl}) {
      final resolved = cardPosterUrl(url, serverBaseUrl: serverBaseUrl);
      return resolved == null ? null : tmdbUrlForWidth(resolved, posterWidth);
    }

    _targets.clear();
    SystemSearchItem held(Media media) {
      final id = 'm${media.id}';
      _targets[id] = media;
      final movie = media.type == MediaType.movie
          ? _library.movieItemFor(media.id)
          : null;
      final watched = movie?.isFinished ??
          (media.type == MediaType.show && media.isFullyWatched);
      final progress = movie == null || watched ? 0.0 : movie.percentWatched;
      return SystemSearchItem(
        id: id,
        title: media.title,
        subtitle: extractYear(media.releaseDate) ?? '',
        posterUrl: poster(media.posterUrl, serverBaseUrl: api.baseUrl),
        progress: progress > 0 && progress < 0.99 ? progress : null,
        watched: watched,
      );
    }

    SystemSearchItem absent(RequestMediaItem item) {
      final id = 'r${item.mediaType.name}${item.id}';
      _targets[id] = item;
      final requested = item.status != RequestMediaStatus.unknown;
      return SystemSearchItem(
        id: id,
        title: item.title,
        // Ce rayon mêle films et séries : chaque affiche dit ce qu'elle est.
        subtitle: [
          item.mediaType == RequestMediaType.movie ? tr('Film') : tr('Série'),
          if (item.year != null) item.year!,
        ].join(' · '),
        posterUrl: poster(item.posterUrl),
        badge: UnavailableBadge.labelFor(requested: requested),
        badgeTint: requested ? AppColors.warning.toARGB32() : null,
        dimmed: true,
      );
    }

    SystemSearchSection shelf<T>(
      String id,
      String title,
      List<T> titles,
      SystemSearchItem Function(T) item,
    ) =>
        SystemSearchSection(
          id: id,
          title: '$title · ${titles.length}',
          items: [
            for (final title in titles.take(TvSystemSearchScreen.shelfLimit))
              item(title),
          ],
        );

    final List<SystemSearchSection> sections;
    if (query.isEmpty) {
      final recent =
          SearchShelves.recentlyAdded(_library, TvSearchScreen.suggestions);
      sections = [
        SystemSearchSection(
          id: 'recent',
          title: tr('Ajouts récents'),
          items: [for (final media in recent) held(media)],
        ),
      ];
    } else {
      final shelves = SearchShelves.of(
        _library,
        query,
        catalog: _catalog.resultsFor(query),
      );
      sections = [
        shelf('movies', tr('Films'), shelves.movies, held),
        shelf('shows', tr('Séries'), shelves.shows, held),
        shelf(
          'unavailable',
          tr('Pas sur le serveur'),
          shelves.unavailable,
          absent,
        ),
      ];
    }

    final shown = [
      for (final section in sections)
        if (section.items.isNotEmpty) section,
    ];
    // Tant que la bibliothèque se charge, l'écran reste vide plutôt que de
    // dire qu'il n'y a rien.
    final silent = shown.isNotEmpty ||
        (query.isEmpty &&
            (_library.isLoadingMovies || _library.isLoadingShows));
    return SystemSearchContent(
      sections: shown,
      emptyTitle: silent ? null : tr('Aucun résultat'),
      emptyMessage: silent
          ? null
          : query.isEmpty
              ? tr('Rechercher un film ou une série…')
              : tr('Aucun film ou série ne correspond à « {0} ».', [query]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_native == false) return const TvSearchScreen();
    // Rien de focalisable ici : tant que l'écran du système est devant, la
    // télécommande est à lui. Ce qui en parviendrait quand même à Flutter (le
    // pavé de la Siri Remote lui est toujours transmis) ne trouve rien à
    // déplacer ni à activer ; Retour, lui, referme la page.
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: SizedBox.expand(),
    );
  }
}
