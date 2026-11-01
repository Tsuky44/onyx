import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'app_network_image.dart';

/// L'envol d'une affiche vers sa fiche, porté d'OnyxHub (`MotionDirector`,
/// `launchFly`) : la carte cliquée se soulève et se retourne, son dos montre
/// le fond de la fiche, qui fonce à sa place exacte en s'étirant, s'y écrase,
/// rebondit et se pose pendant que la fiche apparaît dessous.
///
/// Tenu à un coût qui ne se remarque pas sur un petit PC ou une TV :
///
/// * **une seule route, une seule horloge.** L'envol est la transition de la
///   route (`buildTransitions`) : pas d'`OverlayEntry`, pas de second
///   contrôleur. À la fin, Flutter rend la route opaque et met l'ancienne page
///   hors écran de lui-même ;
/// * **un seul élément en mouvement**, une image et un fond. Aucun filtre, aucun
///   flou, aucun `saveLayer` sauf le fondu final de cet élément ;
/// * **la fiche n'est pas dessinée** tant que l'image n'a pas atterri
///   (opacité nulle : Flutter saute sa peinture), puis posée sans fondu plein
///   écran. Ses blocs montent ensuite du bas ([FlightDrop]) ;
/// * **les images sont celles de la carte et de la fiche** : même URL, même
///   largeur de décodage, donc déjà dans le cache mémoire (préchauffé au
///   survol, voir [PosterFlight.warm]) ;
/// * **mode léger** : pas de retournement, pas d'ombre, pas d'écrasement, juste
///   l'affiche qui s'étend en fondu sur le fond. **Mouvement réduit** : pas
///   d'envol du tout (le lanceur rend alors une route ordinaire).
///
/// Voir ADR-0094.
class PosterFlight {
  PosterFlight._();

  /// Temps forts, en millisecondes : la carte se retourne, l'image fonce à sa
  /// place, s'y écrase et rebondit.
  static const Duration turn = Duration(milliseconds: 420);
  static const Duration flight = Duration(milliseconds: 430);
  static const Duration squash = Duration(milliseconds: 520);

  /// La montée des textes de la fiche, une fois l'image posée. Elle a sa
  /// propre phase : sous l'image qui s'écrase, les textes montaient sans qu'on
  /// les voie, et la fiche apparaissait d'un coup quand l'image s'effaçait.
  static const Duration rise = Duration(milliseconds: 460);

  /// L'écart le plus grand que [FlightDrop] accepte entre le départ de deux
  /// blocs : les blocs montent l'un après l'autre sur cet écart, et chacun met
  /// le même temps, quel que soit son rang.
  static const Duration dropSpread = Duration(milliseconds: 160);

  /// Le fond cadré par le haut, comme celui de la fiche (`DetailBackdrop`).
  static const Alignment focus = Alignment.topCenter;

  /// La part du fond que la fiche laisse voir : tout, ses voiles sont dessus.
  static const double backdropOpacity = 1;

  /// Si la page où on se trouve est la fiche d'un envol, dont les blocs
  /// montent à l'arrivée ([FlightDrop]). Ses autres arrivées, la cascade des
  /// cartes par exemple, se tairaient alors : elles joueraient sous l'image.
  static bool arriving(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_Arrival>() != null;

  /// Charge dans le cache mémoire ce que l'envol dessinera : l'affiche et le
  /// fond, à la largeur exacte où la carte et la fiche les décodent.
  static Future<void> warm(
    BuildContext context, {
    required String? posterUrl,
    required double posterWidth,
    required String? backdropUrl,
  }) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    return Future.wait([
      AppNetworkImage.precache(posterUrl,
          devicePixelRatio: dpr, decodeWidth: posterWidth),
      AppNetworkImage.precache(backdropUrl,
          devicePixelRatio: dpr, decodeWidth: width),
    ]);
  }
}

/// La route qui fait voler [posterUrl] de [from] jusqu'au fond de la page
/// [builder], haut de [backdropHeight].
class PosterFlightRoute<T> extends PageRoute<T> {
  PosterFlightRoute({
    required this.from,
    required this.radius,
    required this.posterUrl,
    required this.backdropUrl,
    required this.backdropHeight,
    required this.builder,
    required this.lite,
  });

  /// Le cadre de la carte cliquée, dans le repère du navigateur.
  final Rect from;
  final double radius;
  final String? posterUrl;
  final String backdropUrl;
  final double backdropHeight;
  final WidgetBuilder builder;
  final bool lite;

  late final _Timeline _timeline = _Timeline(lite: lite);

  @override
  Duration get transitionDuration => _timeline.total;

  /// Le retour est un fondu bref, pas un envol à l'envers : la carte a pu
  /// bouger depuis.
  @override
  Duration get reverseTransitionDuration =>
      lite ? Duration.zero : const Duration(milliseconds: 200);

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final arrival = _arrival ??= animation.drive(
      CurveTween(curve: Interval(_timeline.fadeStart, 1)),
    );
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = _timeline;
        final a = animation.value;
        final reversing = animation.status == AnimationStatus.reverse;
        final landed = reversing || a >= t.landing;
        final flying = !reversing && a < t.settled;
        // Même arbre du début à la fin, la page toujours en première place :
        // la reparenter perdrait son état (chargement, défilement).
        return LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              // La fiche attend l'atterrissage : opacité nulle, aucune
              // peinture, aucun toucher.
              IgnorePointer(
                ignoring: !landed,
                child: Opacity(
                  opacity: reversing ? (lite ? 1 : a) : (landed ? 1 : 0),
                  child: _Arrival(
                    progress: arrival,
                    window: t.arrivalWindow,
                    child: child!,
                  ),
                ),
              ),
              if (flying && !landed) _Scrim(opacity: t.scrim(a)),
              if (flying)
                IgnorePointer(
                  child: RepaintBoundary(
                    child: _FlightLayer(
                      timeline: t,
                      a: a,
                      from: from,
                      to: Rect.fromLTWH(
                          0, 0, constraints.maxWidth, backdropHeight),
                      radius: radius,
                      posterUrl: posterUrl,
                      backdropUrl: backdropUrl,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// L'avancement de l'arrivée des textes (0 quand l'image commence à
  /// s'effacer, 1 à la fin).
  Animation<double>? _arrival;
}

/// Les phases de l'envol, en part de la durée totale.
class _Timeline {
  _Timeline({required bool lite})
      : turnMs = lite ? 0 : PosterFlight.turn.inMilliseconds,
        flightMs = PosterFlight.flight.inMilliseconds,
        squashMs = lite ? 140 : PosterFlight.squash.inMilliseconds,
        riseMs = lite ? 220 : PosterFlight.rise.inMilliseconds;

  final int turnMs;
  final int flightMs;
  final int squashMs;
  final int riseMs;

  /// Part de l'écrasement où l'image commence à s'effacer sur la vraie fiche,
  /// et où les textes commencent à monter.
  static const double fadeAt = 0.6;

  int get totalMs => turnMs + flightMs + squashMs + riseMs;
  Duration get total => Duration(milliseconds: totalMs);

  /// Fin du retournement, puis atterrissage, puis fin de l'écrasement : l'image
  /// est effacée et plus rien ne vole.
  double get turnEnd => turnMs / totalMs;
  double get landing => (turnMs + flightMs) / totalMs;
  double get settled => (turnMs + flightMs + squashMs) / totalMs;

  /// Le début de l'effacement de l'image, qui est aussi celui de la montée.
  double get fadeStart => landing + fadeAt * (settled - landing);

  /// Ce que dure l'arrivée des textes, de l'effacement à la fin.
  Duration get arrivalWindow =>
      Duration(milliseconds: ((1 - fadeStart) * totalMs).round());

  /// Le fond de la page quittée s'assombrit jusqu'à l'atterrissage.
  double scrim(double a) =>
      0.6 * Curves.easeOut.transform((a / landing).clamp(0.0, 1.0));
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ColoredBox(color: Colors.black.withValues(alpha: opacity)),
      );
}

/// Ce que la fiche lit pour faire monter ses textes quand l'image s'efface.
class _Arrival extends InheritedWidget {
  const _Arrival({
    required this.progress,
    required this.window,
    required super.child,
  });

  final Animation<double> progress;

  /// La durée que [progress] met à aller de 0 à 1.
  final Duration window;

  @override
  bool updateShouldNotify(_Arrival old) =>
      progress != old.progress || window != old.window;
}

/// Un bloc de la fiche qui monte du bas à sa place quand l'image s'efface,
/// en fondu, sans rebond : il décélère jusqu'à sa position. Sans envol, il est
/// posé tel quel.
///
/// [distance] est la hauteur dont il part, sous sa place. La fiche coupe ce
/// qui dépasse de l'en-tête : un bloc haut semble sortir du bas de l'image.
/// [delay] (au plus [PosterFlight.dropSpread]) fait partir les blocs l'un
/// après l'autre ; tous mettent le même temps à monter.
class FlightDrop extends StatelessWidget {
  const FlightDrop({
    super.key,
    this.delay = Duration.zero,
    this.distance = 96,
    required this.child,
  });

  final Duration delay;
  final double distance;
  final Widget child;

  /// Une décélération longue : le bloc part vite et se pose doucement, sans
  /// dépasser sa place.
  static const Curve _rise = Cubic(0.16, 1, 0.3, 1);

  @override
  Widget build(BuildContext context) {
    final arrival = context.dependOnInheritedWidgetOfExactType<_Arrival>();
    if (arrival == null) return child;
    final progress = arrival.progress;
    final windowMs = arrival.window.inMilliseconds;
    final spreadMs = PosterFlight.dropSpread.inMilliseconds;
    final delayMs = delay.inMilliseconds.clamp(0, spreadMs);
    // Une fenêtre trop courte pour l'écart (mode léger) le réduit d'autant.
    final spare = (windowMs - spreadMs).clamp(windowMs ~/ 2, windowMs);
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        if (progress.value >= 1) return child!;
        final local =
            ((progress.value * windowMs - delayMs) / spare).clamp(0.0, 1.0);
        // Le fondu finit avant la montée : le bloc est net bien avant d'être
        // posé.
        final fade = Curves.easeOut.transform((local / 0.5).clamp(0.0, 1.0));
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, distance * (1 - _rise.transform(local))),
            child: child,
          ),
        );
      },
    );
  }
}

/// L'élément qui voyage : la carte qui se retourne, puis l'image du fond qui
/// va à sa place, s'écrase et se pose.
class _FlightLayer extends StatelessWidget {
  const _FlightLayer({
    required this.timeline,
    required this.a,
    required this.from,
    required this.to,
    required this.radius,
    required this.posterUrl,
    required this.backdropUrl,
  });

  final _Timeline timeline;
  final double a;
  final Rect from;
  final Rect to;
  final double radius;
  final String? posterUrl;
  final String backdropUrl;

  static const _turnCurve = Cubic(0.45, 0, 0.2, 1);
  static const _flightCurve = Cubic(0.5, 0, 0.75, 0.3);

  @override
  Widget build(BuildContext context) {
    final t = timeline;
    final lite = t.turnMs == 0;
    if (!lite && a < t.turnEnd) return _turning(context);
    return _flying(context, lite);
  }

  Widget _backdrop(Size size, double opacity) => AppNetworkImage(
        url: backdropUrl,
        width: size.width,
        height: size.height,
        decodeWidth: to.width,
        fit: BoxFit.cover,
        alignment: PosterFlight.focus,
        fadeInDuration: Duration.zero,
        color: Colors.white.withValues(alpha: opacity),
        colorBlendMode: BlendMode.modulate,
        placeholder: const ColoredBox(color: AppColors.background),
        errorWidget: const ColoredBox(color: AppColors.background),
      );

  Widget _poster(Size size) => AppNetworkImage(
        url: posterUrl,
        width: size.width,
        height: size.height,
        decodeWidth: from.width,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        placeholder: const ColoredBox(color: AppColors.surfaceElevated),
        errorWidget: const ColoredBox(color: AppColors.surfaceElevated),
      );

  /// La carte se soulève et se retourne : l'affiche au recto, le fond au dos.
  Widget _turning(BuildContext context) {
    final p = _turnCurve.transform((a / timeline.turnEnd).clamp(0.0, 1.0));
    final angle = 3.141592653589793 * p;
    final backFace = angle > 3.141592653589793 / 2;
    // Se soulève jusqu'à 1,08 au milieu du retournement, puis se repose.
    final lift = 1 + 0.08 * _bump(a / timeline.turnEnd);
    final size = from.size;
    // Le fond se monte dès le début du retournement, invisible tant que le
    // dos ne s'est pas présenté : sur un titre jamais survolé, son décodage
    // démarre là plutôt qu'au milieu du virage, et n'a plus à rattraper son
    // retard en plein vol.
    final face = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: backFace ? 1 : 0,
            child: Transform(
              alignment: Alignment.center,
              // Le dos est vu par derrière : on le remet à l'endroit.
              transform: Matrix4.identity()..rotateY(3.141592653589793),
              child: _backdrop(size, 1),
            ),
          ),
          if (!backFace) _poster(size),
        ],
      ),
    );
    return Stack(
      children: [
        Positioned.fromRect(
          rect: from,
          child: Transform.scale(
            scale: lift,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(angle),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: 0.5 * _bump(a / timeline.turnEnd)),
                      blurRadius: 36,
                      offset: const Offset(0, 24),
                      spreadRadius: -10,
                    ),
                  ],
                ),
                child: face,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 0 aux deux bouts, 1 vers le milieu (offset 0,55 de `launchFly`).
  static double _bump(double x) {
    final v = x.clamp(0.0, 1.0);
    return v < 0.55
        ? Curves.easeInOut.transform(v / 0.55)
        : Curves.easeInOut.transform(1 - (v - 0.55) / 0.45);
  }

  /// L'image du fond va de la carte à sa place, puis s'écrase et se pose.
  Widget _flying(BuildContext context, bool lite) {
    final t = timeline;
    final flightP = ((a - t.turnEnd) / (t.landing - t.turnEnd)).clamp(0.0, 1.0);
    final p = _flightCurve.transform(flightP);
    final rect = Rect.lerp(from, to, p)!;
    final r = radius * (1 - p);

    // Étirée par la vitesse en route, écrasée à l'arrivée, un rebond, posée.
    final since = ((a - t.landing) / (t.settled - t.landing)).clamp(0.0, 1.0);
    final (sx, sy) = lite ? (1.0, 1.0) : _squash(flightP, since);

    // Le fond finit à l'opacité qu'il a sur la fiche.
    final opacity = 1 - (1 - PosterFlight.backdropOpacity) * p;
    // Le fondu final sur l'image réelle de la fiche, identique dessous.
    final out = Curves.easeOut.transform(
      ((since - _Timeline.fadeAt) / (1 - _Timeline.fadeAt)).clamp(0.0, 1.0),
    );

    Widget image = ColoredBox(
      color: AppColors.background,
      child: lite
          ? Stack(
              fit: StackFit.expand,
              children: [
                _poster(rect.size),
                // L'affiche cède la place au fond au fil du trajet.
                Opacity(
                  opacity: Curves.easeIn.transform(flightP),
                  child: _backdrop(rect.size, opacity),
                ),
              ],
            )
          : _backdrop(rect.size, opacity),
    );
    if (r > 0.5) {
      image = ClipRRect(borderRadius: BorderRadius.circular(r), child: image);
    }
    if (!lite && (sx != 1 || sy != 1)) {
      image = Transform(
        alignment: Alignment.topCenter,
        transform: Matrix4.diagonal3Values(sx, sy, 1),
        child: image,
      );
    }
    if (out > 0) image = Opacity(opacity: 1 - out, child: image);
    return Stack(children: [Positioned.fromRect(rect: rect, child: image)]);
  }

  /// Étirement verticale en route (jusqu'à 1,035), puis écrasement (1,024 ×
  /// 0,952), léger rebond (0,996 × 1,012), pose : les valeurs de `launchFly`.
  static (double, double) _squash(double flightP, double since) {
    if (since <= 0) {
      final k = Curves.easeIn.transform(flightP);
      return (1 - 0.01 * k, 1 + 0.035 * k);
    }
    const keys = [
      (0.0, 0.99, 1.035),
      (0.27, 1.024, 0.952),
      (0.56, 0.996, 1.012),
      (1.0, 1.0, 1.0),
    ];
    for (var i = 1; i < keys.length; i++) {
      final (end, ex, ey) = keys[i];
      final (begin, bx, by) = keys[i - 1];
      if (since <= end) {
        final k = Curves.easeInOut.transform((since - begin) / (end - begin));
        return (bx + (ex - bx) * k, by + (ey - by) * k);
      }
    }
    return (1.0, 1.0);
  }
}
