import 'dart:math' as math;

import 'package:flutter/widgets.dart' show TraversalDirection;

/// Ce que la surface tactile de la Siri Remote raconte, réduit à ce qui sert.
enum TouchpadPhase { began, moved, ended, clickDown, clickUp }

/// Un déplacement du doigt : ce qu'il a parcouru depuis le point précédent, et
/// à quelle vitesse il va (en unités de surface par seconde, sur l'axe du
/// déplacement horizontal).
typedef TouchpadMove = ({double dx, double dy, double speed});

/// Un doigt qui quitte la surface en mouvement : dans quel sens il allait, à
/// quelle vitesse (unités de surface par seconde), et si le geste était franc
/// sans avoir encore fait un seul pas ([flick]) : un coup de pouce vaut un pas.
typedef TouchpadRelease = ({
  TraversalDirection direction,
  double speed,
  bool flick,
});

/// Le rythme du pavé, selon ce que le focus désigne (ADR-0122).
enum TouchpadPace {
  /// Des affiches, des vignettes : on parcourt. Le trajet fait les pas, la
  /// vitesse les allonge et le lâcher garde son élan.
  browse,

  /// Des commandes (onglets, boutons, lignes de réglage) : on choisit. Plus
  /// de trajet par pas, ni accélération ni lancée : un glissé ordinaire avance
  /// d'un cran, et le focus s'arrête avec le doigt.
  precise,
}

/// Les réglages d'un axe du pavé.
///
/// Des estimations écrites sans appareil (ADR-0116) : tout se règle ici, sur
/// une vraie Apple TV.
class TouchpadAxisTuning {
  const TouchpadAxisTuning({
    required this.firstStep,
    required this.step,
    required this.gainFrom,
    required this.gainTo,
    required this.maxGain,
    required this.coastFrom,
    required this.coastDecay,
    required this.maxCoastSteps,
    required this.minStepInterval,
  });

  /// Une rangée d'affiches : elle se traverse vite et garde son élan.
  ///
  /// Réglage du 2026-11-12, après le premier essai sur Apple TV (« un peu
  /// rapide ») : un quart de pas en moins par trajet, un gain plafonné à 2 au
  /// lieu de 2,6, une lancée presque deux fois plus courte.
  static const TouchpadAxisTuning horizontal = TouchpadAxisTuning(
    firstStep: 0.26,
    step: 0.50,
    gainFrom: 3.5,
    gainTo: 12,
    maxGain: 2.0,
    coastFrom: 6,
    coastDecay: 0.20,
    maxCoastSteps: 10,
    minStepInterval: Duration(milliseconds: 55),
  );

  /// La verticale change de rangée entière, ou de ligne de réglage. Au premier
  /// essai sur appareil (ADR-0039), une verticale accélérée « sautait des
  /// rangées entières » : elle suit donc le doigt presque sans gain, et sa
  /// lancée ne dépasse jamais deux éléments.
  static const TouchpadAxisTuning vertical = TouchpadAxisTuning(
    firstStep: 0.32,
    step: 0.65,
    gainFrom: 5,
    gainTo: 13,
    maxGain: 1.25,
    coastFrom: 9,
    coastDecay: 0.18,
    maxCoastSteps: 2,
    minStepInterval: Duration(milliseconds: 100),
  );

  /// Une barre d'onglets, une rangée de boutons ([TouchpadPace.precise]).
  ///
  /// Réglage du 2026-11-12, après l'essai de la 1.1.42 (« super rapide » sur
  /// les onglets et les réglages, alors que les affiches étaient « parfaites »)
  /// : les onglets défilent dans leur pilule, ils prenaient donc le gain et la
  /// lancée d'une rangée d'affiches, jusqu'à dix onglets pour un coup de
  /// pouce. Ici un glissé ordinaire (la moitié de la surface) avance d'un
  /// cran, un balayage d'un bord à l'autre de deux ou trois, et rien ne
  /// continue une fois le doigt levé. 160 ms entre deux pas : la capsule du
  /// focus (180 ms) a le temps de se poser.
  static const TouchpadAxisTuning preciseHorizontal = TouchpadAxisTuning(
    firstStep: 0.30,
    step: 0.80,
    gainFrom: double.infinity,
    gainTo: double.infinity,
    maxGain: 1,
    coastFrom: double.infinity,
    coastDecay: 0.20,
    maxCoastSteps: 0,
    minStepInterval: Duration(milliseconds: 160),
  );

  /// Une liste de réglages, un menu ([TouchpadPace.precise]) : comme
  /// [preciseHorizontal], avec le trajet un peu plus long de la verticale.
  static const TouchpadAxisTuning preciseVertical = TouchpadAxisTuning(
    firstStep: 0.34,
    step: 0.90,
    gainFrom: double.infinity,
    gainTo: double.infinity,
    maxGain: 1,
    coastFrom: double.infinity,
    coastDecay: 0.18,
    maxCoastSteps: 0,
    minStepInterval: Duration(milliseconds: 160),
  );

  static TouchpadAxisTuning of(
    TraversalDirection direction, {
    TouchpadPace pace = TouchpadPace.browse,
  }) {
    final sideways = direction == TraversalDirection.left ||
        direction == TraversalDirection.right;
    return switch (pace) {
      TouchpadPace.browse => sideways ? horizontal : vertical,
      TouchpadPace.precise => sideways ? preciseHorizontal : preciseVertical,
    };
  }

  /// Trajet du doigt, en unités de surface, avant le premier pas d'un geste.
  /// Plus court que les suivants : un coup de pouce répond tout de suite (le
  /// moteur de flutter-tvos tirait sa flèche à 0,3).
  final double firstStep;

  /// Trajet par pas ensuite, à vitesse posée. La surface fait 2 unités de
  /// large : un balayage lent d'un bord à l'autre vaut `2 / step` éléments.
  final double step;

  /// Entre ces deux vitesses (u/s), le même trajet vaut de 1 à [maxGain] fois
  /// plus de pas, comme l'accélération d'une souris.
  final double gainFrom;
  final double gainTo;
  final double maxGain;

  /// Vitesse de lâcher à partir de laquelle la liste continue sur sa lancée.
  final double coastFrom;

  /// Temps, en secondes, au bout duquel la lancée a perdu 63 % de sa vitesse.
  final double coastDecay;

  /// Le focus ne part jamais plus loin que cela après le lâcher.
  final int maxCoastSteps;

  /// Deux pas ne se suivent jamais de plus près : le focus doit avoir le
  /// temps de se poser et la liste de défiler. À l'horizontale, 55 ms : en
  /// dessous les cartes ne se distinguent plus. À la verticale, 100 ms : le
  /// parcours des fiches fait défiler puis réessaie, et perdait des pas sous
  /// 80 ms (ADR-0110, constat C6).
  final Duration minStepInterval;

  double gainAt(double speed) {
    if (speed <= gainFrom) return 1;
    if (speed >= gainTo) return maxGain;
    return 1 + (maxGain - 1) * (speed - gainFrom) / (gainTo - gainFrom);
  }
}

/// Le doigt sur le trackpad de la Siri Remote, traduit en pas de focus.
///
/// Le moteur de flutter-tvos fait d'un glissé une flèche, la même que le doigt
/// ait effleuré la surface ou l'ait balayée : une rangée de quarante films se
/// traversait à coups de pouce répétés (ADR-0039, puis ADR-0116). Ce modèle
/// lit le doigt lui-même, comme le fait l'interface d'Apple :
///
/// - **le trajet fait les pas.** Le focus avance d'un élément chaque fois que
///   le doigt a parcouru [TouchpadAxisTuning.step] ; un geste lent se pose
///   exactement où l'on veut ([takeStep]) ;
/// - **la vitesse allonge le trajet.** Le même centimètre parcouru vite vaut
///   plus de pas ([TouchpadAxisTuning.gainAt]) ;
/// - **le lâcher garde son élan.** Un doigt levé en plein mouvement rend un
///   [TouchpadRelease], dont [TouchpadCoast] tire une lancée qui ralentit.
///
/// Les coordonnées sont celles du moteur : normalisées dans `[-1, 1]`, y vers
/// le bas. Aucune dépendance au temps réel : l'horloge est passée à chaque
/// appel, ce qui rend le modèle testable à la milliseconde.
class TouchpadMotion {
  /// La fenêtre sur laquelle la vitesse est mesurée. Plus courte, un seul
  /// échantillon bruité fait la vitesse ; plus longue, un geste qui ralentit
  /// garde la vitesse de son début.
  static const Duration _window = Duration(milliseconds: 100);

  /// Au-delà, le doigt s'est arrêté (ou a quitté la surface) : une flèche qui
  /// arrive ne vient plus d'un glissé, elle vient du pavé directionnel ou d'un
  /// autre appareil.
  static const Duration _stale = Duration(milliseconds: 150);

  /// Un doigt posé qui tremble ne glisse pas : sous ce trajet depuis le point
  /// de contact, ou sous cette vitesse, une flèche du moteur reste la sienne
  /// (clic sur l'anneau de la télécommande, tape sur un bord).
  static const double _panTravel = 0.06;
  static const double _panSpeed = 0.8;

  /// Un coup de pouce plus court que le premier pas en vaut quand même un,
  /// s'il a parcouru ceci et quitté la surface à cette vitesse.
  static const double _flickTravel = 0.10;
  static const double _flickSpeed = 1.5;

  final List<({double x, double y, Duration at})> _samples =
      <({double x, double y, Duration at})>[];
  bool _clicking = false;
  bool _touching = false;
  TouchpadMove? _lastMove;

  // Le trajet, déjà multiplié par le gain, qui n'a pas encore fait de pas.
  double _pendingX = 0;
  double _pendingY = 0;
  double _startX = 0;
  double _startY = 0;
  double _reach = 0;
  int _stepsThisGesture = 0;
  Duration? _lastStepAt;
  Duration? _endedAt;
  bool _endedPanning = false;

  /// Le dernier déplacement reçu par [add], nul hors d'un glissé.
  TouchpadMove? get lastMove => _lastMove;

  /// Ajoute un événement du trackpad. Renvoie le lâcher du geste quand le
  /// doigt quitte la surface en mouvement, nul sinon.
  ///
  /// [accelerates] dit si un geste vers cette direction peut valoir plus que
  /// son trajet (une rangée qui défile) ; sans lui, un trajet vaut toujours
  /// ses pas, jamais plus. [pace] est le rythme de ce que le focus désigne à
  /// cet instant : il peut changer d'un événement à l'autre, quand un pas
  /// fait passer d'un bouton à une affiche.
  TouchpadRelease? add(
    TouchpadPhase phase,
    double x,
    double y,
    Duration at, {
    bool Function(TraversalDirection direction)? accelerates,
    TouchpadPace pace = TouchpadPace.browse,
  }) {
    switch (phase) {
      case TouchpadPhase.began:
        _lastMove = null;
        _touching = true;
        _samples
          ..clear()
          ..add((x: x, y: y, at: at));
        _pendingX = 0;
        _pendingY = 0;
        _startX = x;
        _startY = y;
        _reach = 0;
        _stepsThisGesture = 0;
        _endedAt = null;
        return null;
      case TouchpadPhase.moved:
        final previous = _samples.isEmpty ? null : _samples.last;
        _samples.add((x: x, y: y, at: at));
        _samples.removeWhere((s) => at - s.at > _window * 2);
        if (previous == null || _clicking) {
          _lastMove = null;
          return null;
        }
        final velocity = _velocityAt(at);
        final dx = x - previous.x;
        final dy = y - previous.y;
        _lastMove = (dx: dx, dy: dy, speed: (velocity?.dx ?? 0).abs());
        _reach = math.max(
          _reach,
          math.max((x - _startX).abs(), (y - _startY).abs()),
        );
        _pendingX +=
            dx * _gain(dx, velocity?.dx, accelerates, pace, horizontal: true);
        _pendingY +=
            dy * _gain(dy, velocity?.dy, accelerates, pace, horizontal: false);
        return null;
      case TouchpadPhase.clickDown:
        _clicking = true;
        _lastMove = null;
        _pendingX = 0;
        _pendingY = 0;
        return null;
      case TouchpadPhase.clickUp:
        _clicking = false;
        return null;
      case TouchpadPhase.ended:
        final release = _clicking || !_touching ? null : _releaseAt(at, pace);
        _endedPanning = _panningAt(at);
        _endedAt = at;
        _touching = false;
        _samples.clear();
        _lastMove = null;
        _pendingX = 0;
        _pendingY = 0;
        return release;
    }
  }

  /// Le pas que le trajet accumulé doit maintenant, ou nul. À rappeler après
  /// chaque déplacement : un seul pas par appel, et jamais deux à moins de
  /// [TouchpadAxisTuning.minStepInterval]. [pace] fixe le trajet d'un pas et
  /// cet intervalle : ceux de ce que le focus désigne maintenant.
  TraversalDirection? takeStep(
    Duration at, {
    TouchpadPace pace = TouchpadPace.browse,
  }) {
    if (_clicking || !_touching) return null;
    final horizontalTuning =
        TouchpadAxisTuning.of(TraversalDirection.right, pace: pace);
    final verticalTuning =
        TouchpadAxisTuning.of(TraversalDirection.down, pace: pace);
    final needX = _threshold(horizontalTuning);
    final needY = _threshold(verticalTuning);
    final horizontal = _pendingX.abs() / needX >= _pendingY.abs() / needY;
    final tuning = horizontal ? horizontalTuning : verticalTuning;
    final last = _lastStepAt;
    if (last != null && at >= last && at - last < tuning.minStepInterval) {
      // Le doigt va plus vite que le focus ne peut suivre : ce qui dépasse
      // deux pas d'avance est perdu, la lancée du lâcher le rendra.
      _pendingX = _pendingX.clamp(
          -2 * horizontalTuning.step, 2 * horizontalTuning.step);
      _pendingY =
          _pendingY.clamp(-2 * verticalTuning.step, 2 * verticalTuning.step);
      return null;
    }
    if (horizontal) {
      if (_pendingX.abs() < needX) return null;
      final right = _pendingX > 0;
      _pendingX -= right ? needX : -needX;
      // Un geste à peine de travers ne change pas de rangée en chemin.
      _pendingY = 0;
      return _stepped(
        right ? TraversalDirection.right : TraversalDirection.left,
        at,
      );
    }
    if (_pendingY.abs() < needY) return null;
    final down = _pendingY > 0;
    _pendingY -= down ? needY : -needY;
    _pendingX = 0;
    return _stepped(down ? TraversalDirection.down : TraversalDirection.up, at);
  }

  /// Oublie le trajet en attente : quelqu'un d'autre suit le doigt (la barre
  /// de lecture), et ce déplacement ne doit pas aussi faire de pas. Les deux
  /// axes : un glissé horizontal un peu de travers ferait sinon, à la longue,
  /// un pas vertical.
  void dropPending() {
    _pendingX = 0;
    _pendingY = 0;
  }

  /// Vrai quand le doigt glisse en ce moment sur la surface.
  bool swipingAt(Duration now) => !_clicking && _velocityAt(now) != null;

  /// Vrai quand une flèche reçue à [now] est née d'un glissé du doigt : le
  /// modèle fait lui-même les pas de ce glissé, la flèche du moteur le
  /// compterait deux fois.
  ///
  /// Une flèche sans doigt en mouvement (anneau cliquable, tape sur un bord,
  /// manette, app Remote de l'iPhone) n'est jamais concernée. [grace] couvre
  /// la flèche que le moteur tire juste après que le doigt s'est levé.
  bool ownsArrowAt(Duration now, {Duration grace = Duration.zero}) {
    if (_clicking) return false;
    if (_touching) return _panningAt(now);
    final ended = _endedAt;
    return _endedPanning && ended != null && now - ended <= grace;
  }

  bool _panningAt(Duration now) {
    if (_reach < _panTravel) return false;
    final velocity = _velocityAt(now);
    if (velocity == null) return false;
    return math.max(velocity.dx.abs(), velocity.dy.abs()) >= _panSpeed;
  }

  double _threshold(TouchpadAxisTuning tuning) =>
      _stepsThisGesture == 0 ? tuning.firstStep : tuning.step;

  TraversalDirection _stepped(TraversalDirection direction, Duration at) {
    _stepsThisGesture++;
    _lastStepAt = at;
    return direction;
  }

  double _gain(
    double delta,
    double? velocity,
    bool Function(TraversalDirection direction)? accelerates,
    TouchpadPace pace, {
    required bool horizontal,
  }) {
    if (velocity == null || accelerates == null || delta == 0) return 1;
    final direction = horizontal
        ? (delta > 0 ? TraversalDirection.right : TraversalDirection.left)
        : (delta > 0 ? TraversalDirection.down : TraversalDirection.up);
    if (!accelerates(direction)) return 1;
    return TouchpadAxisTuning.of(direction, pace: pace).gainAt(velocity.abs());
  }

  TouchpadRelease? _releaseAt(Duration at, TouchpadPace pace) {
    final velocity = _velocityAt(at);
    if (velocity == null) return null;
    final horizontal = velocity.dx.abs() >= velocity.dy.abs();
    final speed = horizontal ? velocity.dx.abs() : velocity.dy.abs();
    final TraversalDirection direction;
    if (horizontal) {
      direction =
          velocity.dx > 0 ? TraversalDirection.right : TraversalDirection.left;
    } else {
      direction =
          velocity.dy > 0 ? TraversalDirection.down : TraversalDirection.up;
    }
    final flick = _stepsThisGesture == 0 &&
        _reach >= _flickTravel &&
        speed >= _flickSpeed;
    if (!flick &&
        speed < TouchpadAxisTuning.of(direction, pace: pace).coastFrom) {
      return null;
    }
    return (direction: direction, speed: speed, flick: flick);
  }

  /// La vitesse moyenne sur la dernière [_window] de mouvement, en unités par
  /// seconde. Nulle quand le doigt est immobile depuis [_stale] ou qu'il n'y a
  /// pas deux points à comparer.
  ({double dx, double dy})? _velocityAt(Duration now) {
    if (_samples.length < 2) return null;
    final last = _samples.last;
    if (now - last.at > _stale) return null;
    final first = _samples.firstWhere(
      (s) => last.at - s.at <= _window,
      orElse: () => last,
    );
    final elapsed = (last.at - first.at).inMicroseconds / 1e6;
    // Deux points arrivés ensemble ne disent rien de la vitesse.
    if (elapsed < 0.008) return null;
    return (
      dx: (last.x - first.x) / elapsed,
      dy: (last.y - first.y) / elapsed,
    );
  }
}

/// La lancée d'une liste après un doigt levé en plein mouvement.
///
/// La vitesse du lâcher décroît de façon exponentielle
/// ([TouchpadAxisTuning.coastDecay]) et la liste fait un pas chaque fois que
/// cette vitesse a couvert un pas de trajet : serrés d'abord, puis de plus en
/// plus espacés, jusqu'à s'arrêter d'elle-même. Pure, comme [TouchpadMotion].
class TouchpadCoast {
  TouchpadCoast(TouchpadRelease release)
      : direction = release.direction,
        _tuning = TouchpadAxisTuning.of(release.direction),
        _speed = release.speed;

  /// Une lancée plus lente que cela n'en est plus une : le pas suivant
  /// arriverait après qu'on a cru la liste arrêtée.
  static const Duration _slowest = Duration(milliseconds: 220);

  final TraversalDirection direction;
  final TouchpadAxisTuning _tuning;
  double _speed;
  int _steps = 0;

  /// Vrai si le lâcher allait assez vite pour lancer la liste.
  bool get isMoving => _speed >= _tuning.coastFrom || _steps > 0;

  /// Le délai avant le pas suivant, ou nul quand la lancée est finie.
  Duration? next() {
    if (_steps == 0 && _speed < _tuning.coastFrom) return null;
    if (_steps >= _tuning.maxCoastSteps) return null;
    final distance = _tuning.step / _tuning.gainAt(_speed);
    var seconds = distance / _speed;
    final floor = _tuning.minStepInterval.inMicroseconds / 1e6;
    if (seconds < floor) seconds = floor;
    if (seconds > _slowest.inMicroseconds / 1e6) return null;
    _speed *= math.exp(-seconds / _tuning.coastDecay);
    _steps++;
    return Duration(microseconds: (seconds * 1e6).round());
  }
}
