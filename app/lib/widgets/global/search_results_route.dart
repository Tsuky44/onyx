import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// La page de résultats de recherche ouverte par la frappe.
///
/// Elle s'ouvre sous les doigts, au premier caractère : un glissement de page
/// (celui de [MaterialPageRoute] sur macOS, le zoom sous Windows) tombait sur
/// quelqu'un qui regarde son champ, pas l'écran, et le faisait sursauter.
///
/// L'ouverture se joue en trois temps, enchaînés en un peu plus d'une
/// demi-seconde :
///
/// 1. la page se fond doucement par-dessus celle qu'on quitte
///    ([AppMotion.reveal], [AppMotion.revealFade]) en s'approchant à peine,
///    depuis [startScale] ;
/// 2. son en-tête (« Résultats pour… ») se pose juste après, en montant de
///    quelques pixels ([SearchResultsEntrance]) ;
/// 3. les affiches suivent en cascade, en diagonale, jusqu'à la dernière ligne
///    de l'écran (`StaggeredEntranceScope.delay`).
///
/// Un fondu seul ne se remarquait pas : la page semblait clignoter. Une
/// échelle plus forte ou un glissement attiraient l'œil loin du champ. À
/// 260 ms et en ease-out, la page couvrait l'écran en moins de 200 ms : on
/// la recevait d'un coup. Sous
/// « réduire les animations » et en mode léger, il ne reste que les fondus.
///
/// Le retour est le même geste à l'envers, plus bref : effacer la recherche
/// rend la page d'avant sans la faire attendre.
class SearchResultsRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;

  /// L'échelle d'où part la page : assez près de 1 pour qu'on ne la voie pas
  /// grandir, assez loin pour qu'elle semble venir vers soi.
  static const double startScale = 0.975;

  /// Le moment, dans l'ouverture, où l'en-tête commence à se poser.
  static const double headerStart = 0.3;

  SearchResultsRoute({
    required this.builder,
    super.settings,
    super.requestFocus,
  });

  @override
  Duration get transitionDuration => AppMotion.reveal;

  @override
  Duration get reverseTransitionDuration => AppMotion.standard;

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Le fond couvre la page d'avant un peu avant la fin du mouvement : deux
    // pages lisibles jusqu'au bout se brouillaient.
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.85, curve: AppMotion.revealFade),
      reverseCurve: AppMotion.curve.flipped,
    );
    final fading = FadeTransition(opacity: fade, child: child);
    if (AppMotion.reduced(context)) return fading;
    final approach = CurvedAnimation(
      parent: animation,
      curve: AppMotion.curve,
      reverseCurve: AppMotion.curve.flipped,
    );
    return ScaleTransition(
      scale: Tween(begin: startScale, end: 1.0).animate(approach),
      child: fading,
    );
  }
}

/// L'en-tête d'une page de résultats, qui se pose juste après la page
/// ([SearchResultsRoute]) au lieu d'arriver avec elle.
///
/// Suit l'animation de la route qui le porte : hors d'une ouverture (frappe
/// suivante, route sans animation), il s'affiche tel quel.
class SearchResultsEntrance extends StatelessWidget {
  final Widget child;

  /// La montée de l'en-tête. Plus courte que celle des cartes
  /// (`StaggeredEntrance.rise`) : c'est du texte, que l'œil suit de près.
  static const double rise = 10;

  const SearchResultsEntrance({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (route is! SearchResultsRoute || animation == null) return child;

    final settle = CurvedAnimation(
      parent: animation,
      curve: const Interval(SearchResultsRoute.headerStart, 1,
          curve: AppMotion.curve),
      reverseCurve: AppMotion.curve.flipped,
    );
    final fading = FadeTransition(opacity: settle, child: child);
    if (AppMotion.reduced(context)) return fading;
    return AnimatedBuilder(
      animation: settle,
      child: fading,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, rise * (1 - settle.value)),
        child: child,
      ),
    );
  }
}
