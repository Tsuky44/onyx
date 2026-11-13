import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../providers/library_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../tv/nav/tv_region.dart';
import '../../tv/tv_deferred_keyboard.dart';
import '../../utils/responsive.dart';
import '../../widgets/global/empty_state.dart';
import '../../widgets/global/glass_chrome.dart';
import '../../widgets/global/tv_poster_wall.dart';

/// La recherche d'un téléviseur : le champ en tête, qui ouvre le clavier du
/// système, et dessous les résultats rangés par rayons (ADR-0126).
///
/// Demande de l'utilisateur : « un truc comme l'app Emby sur Apple TV », et
/// « ça doit ouvrir le clavier Apple, pour qu'on puisse parler et utiliser la
/// dictée ». Le clavier est donc celui du système, jamais un clavier dessiné
/// par l'app : c'est lui qui porte la dictée et la saisie depuis un
/// téléphone. Il s'ouvre en même temps que la page.
///
/// Ce que la page change à la recherche d'avant (`SearchResultsScreen`, une
/// grille du bureau sous une barre d'app) :
///
/// - avant de taper, elle propose les derniers ajouts au lieu d'un écran
///   vide ;
/// - les résultats sont rangés par rayons, films puis séries, chacun avec
///   son compte ;
/// - valider referme le clavier et pose la télécommande sur le premier
///   résultat ;
/// - les affiches ont la taille de celles de l'accueil et défilent rangée
///   par rangée ([TvPosterWall]).
class TvSearchScreen extends StatefulWidget {
  const TvSearchScreen({super.key});

  /// La largeur du champ, centré en tête de page.
  static const double fieldWidth = 640;

  /// Où se pose le champ, depuis le haut de la page.
  static const double fieldTop = 30;

  /// L'écart entre le champ et le titre du premier rayon.
  static const double fieldGap = 18;

  /// Six affiches par ligne, comme une rangée de l'accueil.
  static const int columns = 6;

  /// Les titres proposés tant que rien n'est tapé : deux rangées.
  static const int suggestions = 12;

  @override
  State<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends State<TvSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _fieldNode = FocusNode(debugLabel: 'tv-search-field');
  final GlobalKey<TvDeferredKeyboardState> _keyboard =
      GlobalKey<TvDeferredKeyboardState>();

  /// Ne prend pas le focus : il sert à trouver les affiches qui le peuvent.
  final FocusNode _results = FocusNode(
    debugLabel: 'tv-search-results',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LibraryProvider>().ensureCatalogLoaded();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _fieldNode.dispose();
    _results.dispose();
    super.dispose();
  }

  void _onQueryChanged() => setState(() {});

  /// Valider : le clavier se referme et la télécommande va droit au premier
  /// résultat, sans un pas de plus. Sans résultat, elle reste dans le champ.
  void _onSubmitted() {
    final posters = _results.traversalDescendants
        .where((node) => node.context != null && !node.rect.isEmpty)
        .toList();
    if (posters.isEmpty) return;
    // Le premier : le plus haut, puis le plus à gauche.
    final first = posters.reduce((best, node) {
      final byTop = node.rect.top.compareTo(best.rect.top);
      if (byTop != 0) return byTop < 0 ? node : best;
      return node.rect.left < best.rect.left ? node : best;
    });
    // Le champ redevient un bouton d'abord : sans cela il reprendrait le
    // focus en voyant le clavier se refermer.
    _keyboard.currentState?.releaseKeyboard();
    first.requestFocus();
  }

  List<PosterWallSection> _sections(LibraryProvider library, String query) {
    PosterWallEntry entry(Media media) => (
          media: media,
          movie: media.type == MediaType.movie
              ? library.movieItemFor(media.id)
              : null,
        );

    if (query.isEmpty) {
      final recent = <Media>[
        for (final item in library.movies) item.media,
        ...library.shows,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return [
        PosterWallSection(
          title: tr('Ajouts récents'),
          entries: [
            for (final media in recent.take(TvSearchScreen.suggestions))
              entry(media),
          ],
        ),
      ];
    }
    final results = library.searchCatalog(query);
    List<PosterWallEntry> of(MediaType type) => [
          for (final media in results)
            if (media.type == type) entry(media),
        ];
    final movies = of(MediaType.movie);
    final shows = of(MediaType.show);
    return [
      PosterWallSection(
        title: '${tr('Films')} · ${movies.length}',
        entries: movies,
      ),
      PosterWallSection(
        title: '${tr('Séries')} · ${shows.length}',
        entries: shows,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final padding = AppLayout.pagePadding(context);
    final query = _controller.text.trim();
    final sections = _sections(library, query);
    final empty = sections.every((section) => section.entries.isEmpty);
    final loading = empty &&
        query.isEmpty &&
        (library.isLoadingMovies || library.isLoadingShows);
    final fieldHeight = GlassSearchInput.heightFor(large: true);
    // Le premier titre de rayon, sous le champ.
    final wallTop =
        TvSearchScreen.fieldTop + fieldHeight + TvSearchScreen.fieldGap;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              // Une page : Bas depuis le champ entre par la première affiche,
              // puis par celle qu'on avait quittée.
              child: TvRegion.page(
                child: empty && !loading
                    ? Padding(
                        padding: EdgeInsets.only(top: wallTop),
                        child: EmptyStateView(
                          icon: AppIcons.search,
                          title: tr('Aucun résultat'),
                          message: query.isEmpty
                              ? tr('Rechercher un film ou une série…')
                              : tr(
                                  'Aucun film ou série ne correspond à '
                                  '« {0} ».',
                                  [query]),
                        ),
                      )
                    : Focus(
                        focusNode: _results,
                        canRequestFocus: false,
                        skipTraversal: true,
                        child: TvPosterWall(
                          sections: sections,
                          padding: EdgeInsets.fromLTRB(
                              padding, wallTop, padding, padding),
                          // Sous le titre de son rayon.
                          focusTop: wallTop + TvPosterWall.sectionHeader,
                          columns: TvSearchScreen.columns,
                          resetKey: query,
                          loading: loading,
                          // Pas de fiche à côté : l'affiche dit son titre.
                          showDetails: true,
                        ),
                      ),
              ),
            ),
            // Les rangées déjà vues s'estompent en passant sous le champ.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: wallTop + 12,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.background,
                        AppColors.background.withValues(alpha: 0.86),
                        AppColors.background.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.7, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: TvSearchScreen.fieldTop,
              child: Center(
                child: SizedBox(
                  width: TvSearchScreen.fieldWidth,
                  // Le clavier du système s'ouvre avec la page : on parle ou
                  // l'on tape tout de suite. Refermé, le champ redevient un
                  // bouton que OK rouvre.
                  child: TvDeferredKeyboard(
                    key: _keyboard,
                    fieldFocusNode: _fieldNode,
                    autofocus: true,
                    borderRadius: BorderRadius.circular(fieldHeight / 2),
                    builder: (context, focusNode, canRequestFocus) =>
                        GlassSearchInput(
                      controller: _controller,
                      focusNode: focusNode,
                      canRequestFocus: canRequestFocus,
                      large: true,
                      // Rouvert sur une recherche déjà tapée : la
                      // sélectionner au focus la ferait remplacer par la
                      // lettre suivante.
                      selectAllOnFocus: false,
                      onClear: _controller.clear,
                      onSubmitted: (_) => _onSubmitted(),
                      hint: tr('Rechercher un film ou une série…'),
                      focused: focusNode.hasFocus,
                      hasText: _controller.text.isNotEmpty,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
