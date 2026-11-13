import 'package:flutter/material.dart';

import '../../../desktop_window.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/tv_poster_wall.dart';
import 'library_spotlight.dart';

/// Une affiche de la grille d'une bibliothèque : un film avec sa progression,
/// ou une série.
typedef LibraryEntry = PosterWallEntry;

/// Une bibliothèque sur téléviseur : la fiche du titre que la télécommande
/// désigne dans un volet fixe à gauche, la grille d'affiches à droite
/// (ADR-0125, qui amende l'ADR-0123).
///
/// La grille du bureau montrait trois rangées pleines de sept affiches sans
/// titre : « trop rempli, trop compact » vu du canapé. Une première version
/// posait la fiche en tête d'écran et une seule rangée dessous : la grille n'y
/// défilait que sur la moitié basse, coupée net sous la fiche, et le
/// défilement se lisait mal. Ici la fiche est sur le côté : les affiches
/// ([TvPosterWall]) défilent sur toute la hauteur de l'écran et passent sous
/// la barre d'onglets, comme les rangées de l'accueil.
///
/// Le tri est une capsule de verre en haut à droite, au-dessus de la grille
/// (demande du 2026-11-13) : Haut depuis la dernière colonne y mène, Bas en
/// revient.
class LibraryTvView extends StatefulWidget {
  const LibraryTvView({
    super.key,
    required this.title,
    required this.countLabel,
    required this.entries,
    required this.order,
    required this.sortControl,
    required this.embedded,
  });

  /// Le nom de la bibliothèque.
  final String title;

  /// « 128 titres ». Nul pendant le chargement.
  final String? countLabel;

  /// Les affiches, déjà triées. Vide pendant le chargement : la page garde
  /// alors sa forme, des cases grises à la place des affiches.
  final List<LibraryEntry> entries;

  /// Le tri en vigueur. Quand il change, la grille repart du haut et la fiche
  /// de la première affiche.
  final Object order;

  /// Le tri, posé en haut à droite. Absent pendant le chargement : il n'y a
  /// rien à trier.
  final Widget sortControl;

  /// Vrai sous la barre d'onglets de la coquille.
  final bool embedded;

  /// Quatre affiches par ligne, de la taille de celles de l'accueil.
  static const int columns = 4;

  /// L'écart entre deux rangées.
  static const double rowGap = TvPosterWall.rowGap;

  /// Où se pose le tri, depuis la marge haute de l'onglet : au ras de la
  /// barre d'onglets.
  static const double sortTop = -12;

  /// Où se pose la rangée focalisée, depuis la marge haute de l'onglet : sous
  /// le tri (36 px), avec la place de l'affiche soulevée (un dixième de sa
  /// hauteur).
  static const double rowTop = 58;

  /// La largeur du texte de la fiche, et celle du volet avec ses gouttières.
  static const double textWidth = 374;

  /// L'image de fond déborde du volet et se fond sous les premières colonnes.
  static const double _backdropOverhang = 170;

  @override
  State<LibraryTvView> createState() => _LibraryTvViewState();
}

class _LibraryTvViewState extends State<LibraryTvView> {
  /// Le titre que la fiche présente : le dernier que la télécommande a
  /// désigné. Nul tant qu'elle n'est pas entrée dans la grille : la fiche
  /// présente alors la première affiche.
  ///
  /// Un `ValueNotifier` et non un `setState` : le focus qui passe d'une
  /// affiche à l'autre ne redessine que la fiche, pas la grille.
  final ValueNotifier<int?> _presented = ValueNotifier<int?>(null);

  @override
  void didUpdateWidget(LibraryTvView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order != widget.order) _presented.value = null;
  }

  @override
  void dispose() {
    _presented.dispose();
    super.dispose();
  }

  LibraryEntry _spotlight(int? presented) {
    final entries = widget.entries;
    for (final entry in entries) {
      if (entry.media.id == presented) return entry;
    }
    return entries.first;
  }

  @override
  Widget build(BuildContext context) {
    final padding = AppLayout.pagePadding(context);
    final topInset = shellTabTopInset(context, embedded: widget.embedded);
    final entries = widget.entries;
    final loading = entries.isEmpty;
    // Le volet : sa gouttière, le texte, puis une gouttière avant la grille.
    final paneWidth = padding + LibraryTvView.textWidth + padding;
    final rowTop = topInset + LibraryTvView.rowTop;

    return LayoutBuilder(builder: (context, constraints) {
      return Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: paneWidth + LibraryTvView._backdropOverhang,
            child: loading
                ? _LoadingPane(
                    title: widget.title,
                    padding: padding,
                    top: constraints.maxHeight * LibrarySpotlight.textTop,
                  )
                : ValueListenableBuilder<int?>(
                    valueListenable: _presented,
                    builder: (context, presented, _) => LibrarySpotlight(
                      media: _spotlight(presented).media,
                      eyebrow: '${widget.title} · ${widget.countLabel ?? ''}',
                      textWidth: LibraryTvView.textWidth,
                    ),
                  ),
          ),
          // Le mur commence une gouttière avant sa première colonne :
          // l'affiche focalisée, agrandie, n'est pas rognée par le bord de ce
          // qui défile.
          Positioned(
            left: paneWidth - padding,
            right: 0,
            top: 0,
            bottom: 0,
            child: TvPosterWall(
              sections: [PosterWallSection(entries: entries)],
              padding: EdgeInsets.fromLTRB(padding, rowTop, padding, padding),
              focusTop: rowTop,
              columns: LibraryTvView.columns,
              resetKey: widget.order,
              loading: loading,
              onFocused: (media) => _presented.value = media.id,
            ),
          ),
          // Les rangées déjà vues s'estompent en passant sous le tri : il se
          // lit sur un fond calme, pas sur un bas d'affiches.
          Positioned(
            left: paneWidth - padding,
            right: 0,
            top: 0,
            height: rowTop - 30,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.background.withValues(alpha: 0.72),
                      AppColors.background.withValues(alpha: 0.58),
                      AppColors.background.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.66, 1],
                  ),
                ),
              ),
            ),
          ),
          if (!loading)
            Positioned(
              right: padding,
              top: topInset + LibraryTvView.sortTop,
              child: widget.sortControl,
            ),
        ],
      );
    });
  }
}

/// Le volet pendant le chargement : le nom de la bibliothèque à la place du
/// titre d'une affiche, pour que la page ne change pas de forme quand ses
/// affiches arrivent.
class _LoadingPane extends StatelessWidget {
  const _LoadingPane({
    required this.title,
    required this.padding,
    required this.top,
  });

  final String title;
  final double padding;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: padding,
          top: top,
          width: LibraryTvView.textWidth,
          // La place du surtitre et du titre d'une fiche.
          height: LibrarySpotlight.headingHeight,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppType.hero,
                fontWeight: FontWeight.w800,
                height: 1.04,
                letterSpacing: -1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
