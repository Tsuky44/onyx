import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../utils/app_platform.dart';
import 'input/tv_dpad_log.dart';
import 'siri_remote_touches.dart';
import 'touchpad_motion.dart';
import 'tv_key_repeat.dart';
import 'tv_mode.dart';
import 'tv_touchpad_pace.dart';

/// Le trackpad de la Siri Remote, lu comme le fait l'interface d'Apple
/// (ADR-0116, qui remplace le point 3 de l'ADR-0039).
///
/// Le moteur de flutter-tvos fait de chaque glissé une flèche, la même que le
/// doigt ait effleuré la surface ou l'ait balayée d'un coup sec : chaque geste
/// avançait d'une affiche. Ici, c'est le doigt qui pilote :
///
/// - **le trajet fait les pas** : le focus avance d'un élément chaque fois que
///   le doigt a parcouru un pas de surface, plus vite quand il va vite
///   ([TouchpadMotion.takeStep]) ;
/// - **le lâcher garde son élan** : un doigt levé en plein mouvement laisse la
///   liste continuer en ralentissant ([TouchpadCoast]). Poser le doigt, cliquer
///   ou appuyer sur une touche l'arrête net ;
/// - **les flèches que le moteur tire du même glissé sont retenues**
///   ([_holdEngineArrow]) : elles compteraient le geste deux fois.
///
/// - **le rythme suit ce que le focus désigne** ([paceOf], ADR-0122) : une
///   rangée d'affiches se traverse vite, une barre d'onglets ou une liste de
///   réglages se parcourt cran par cran, sans accélération ni lancée.
///
/// Un pas est une flèche comme une autre : il parcourt l'arbre de focus par
/// les mêmes `onKeyEvent` et les mêmes raccourcis qu'une touche du pavé
/// directionnel ([_pressArrow]), donc tout ce qui réagit aux flèches (rangées,
/// grilles, menus, curseurs, chrome du lecteur) réagit au doigt sans le savoir.
///
/// Si le flux tactile n'arrive jamais (poignée de main `configure` perdue),
/// rien n'est retenu et les flèches du moteur font tout, comme avant.
///
/// Le lecteur, lui, suit le doigt directement ([addMoveListener]) : la barre
/// de lecture avance avec lui, et d'autant plus loin qu'il va vite.
///
/// Hors Apple TV, rien de tout cela ne s'installe.
abstract final class TvTouchpad {
  static TouchpadMotion _motion = TouchpadMotion();

  /// Le pavé de la Siri Remote est enfoncé en ce moment, d'après le clic
  /// physique (`click_s` / `click_e`) du canal du pavé, et non les touches.
  ///
  /// Les touches mentent sur la durée d'un appui : après un menu ouvert par
  /// un appui long, le simulateur ne rend le relâchement qu'au Retour, puis
  /// envoie l'appui long suivant sur la même carte en « enfoncé, relâché
  /// 1 ms après », sans rien de plus tant que le doigt reste appuyé (vu dans
  /// les journaux du simulateur). Pris pour un appui court, il lançait la
  /// lecture au lieu de rouvrir le menu. Le clic physique, lui, dit vrai.
  static final ValueNotifier<bool> clickHeld = ValueNotifier<bool>(false);
  static final Stopwatch _clock = Stopwatch()..start();
  static bool _installed = false;

  /// Remplace l'horloge dans les tests.
  @visibleForTesting
  static Duration Function()? debugClock;

  static Duration get _now => debugClock?.call() ?? _clock.elapsed;

  /// La flèche du geste lui-même peut arriver juste après que le doigt s'est
  /// levé : elle est encore la sienne. À valider sur vraie Apple TV.
  static const Duration _arrowGrace = Duration(milliseconds: 120);

  /// Après un pas, la rangée suit au plus court pendant ce temps : le pas
  /// suivant du même geste arrive avant la fin d'un défilement posé.
  static const Duration _trackingFor = Duration(milliseconds: 260);

  /// Sous cette hauteur, en pixels de la page, ce que le focus désigne est
  /// une commande : un onglet (36), un bouton (36 à 56), une ligne de menu
  /// (50). Au-dessus, c'est une carte : la plus basse, la vignette d'un
  /// épisode, en fait 101.
  static const double _controlHeight = 64;

  /// Qui fait un pas de lancée, et dit si le focus a bougé.
  ///
  /// Sous dpad, `TvArrowGate` s'inscrit ici : le pas passe par `StepTarget`
  /// et reste dans la rangée (ADR-0110, phase 6). Nul avec l'ancien système,
  /// où le pas est une flèche comme une autre ([_pressArrow]).
  static bool Function(TraversalDirection direction)? glideStepper;

  static Timer? _coastTimer;
  static TouchpadCoast? _coast;
  static Duration? _lastStepAt;

  /// Les pas de la lancée restés sans effet à la suite. Un seul ne dit pas
  /// « bout de la rangée » : la carte suivante peut ne pas être construite
  /// encore, le défilement a un pas de retard sur le focus.
  static int _coastMisses = 0;

  /// Les flèches du moteur retenues à l'appui : leur répétition et leur
  /// relâchement le sont aussi.
  static final Set<LogicalKeyboardKey> _heldBack = <LogicalKeyboardKey>{};

  /// Vrai quand un écouteur s'est servi du geste en cours ([addMoveListener]) :
  /// son coup de pouce final n'est alors pas un pas de focus.
  static bool _gestureUsed = false;

  static final List<bool Function(TouchpadMove move)> _moveListeners =
      <bool Function(TouchpadMove move)>[];

  /// Vrai tant qu'une rangée de cartes avance sous le doigt ou sur sa lancée.
  /// Le défilement suit alors au plus court, comme pour une flèche maintenue.
  /// Un pas posé ([TouchpadPace.precise]) n'en est pas : la page défile à
  /// son rythme ordinaire.
  ///
  /// Un pas vers le haut ou le bas non plus. Il n'y en a qu'un par geste, et
  /// un de lancée au plus : rien à rattraper. Et la page qui parcourt une
  /// rangée entière d'affiches au rythme d'une rangée qui file saute au lieu
  /// de défiler (retour d'essai du 2026-11-13 : « trop brut », ADR-0125).
  static bool get isGliding {
    final coast = _coast;
    if (_coastTimer != null && coast != null) return _alongRow(coast.direction);
    final last = _lastStepAt;
    return last != null && _now - last < _trackingFor;
  }

  static bool _alongRow(TraversalDirection direction) =>
      direction == TraversalDirection.left ||
      direction == TraversalDirection.right;

  /// Branché une fois au démarrage, sur Apple TV seulement.
  static void install() {
    if (_installed || !AppPlatform.isTvOS) return;
    _installed = true;
    listenToSiriRemote(handleTouch);
    _installKeyHandlers();
  }

  static void _installKeyHandlers() {
    HardwareKeyboard.instance.removeHandler(_observeKey);
    HardwareKeyboard.instance.addHandler(_observeKey);
    FocusManager.instance.removeEarlyKeyEventHandler(_holdEngineArrow);
    FocusManager.instance.addEarlyKeyEventHandler(_holdEngineArrow);
  }

  /// Vrai quand le doigt glisse en ce moment sur le trackpad.
  static bool get isSwiping => _motion.swipingAt(_now);

  /// Reçoit chaque déplacement du doigt pendant un glissé, et répond vrai
  /// quand il s'en est servi : ce déplacement ne fait alors pas de pas de
  /// focus en plus (la barre de lecture suit déjà le doigt).
  static void addMoveListener(bool Function(TouchpadMove move) listener) {
    _moveListeners.add(listener);
  }

  static void removeMoveListener(bool Function(TouchpadMove move) listener) {
    _moveListeners.remove(listener);
  }

  /// Vrai quand un geste peut accélérer et garder son élan depuis [node] vers
  /// [direction] : le nœud est dans quelque chose qui défile sur cet axe (une
  /// rangée d'affiches, une grille, une liste). Ailleurs (rangée de boutons,
  /// menu court), un trajet vaut ses pas et rien de plus.
  ///
  /// Ne dit rien du rythme : la pilule des onglets défile elle aussi, et
  /// c'est [paceOf] qui l'écarte.
  static bool acceleratesFrom(FocusNode node, TraversalDirection direction) {
    final context = node.context;
    if (context == null) return false;
    final axis = direction == TraversalDirection.left ||
            direction == TraversalDirection.right
        ? Axis.horizontal
        : Axis.vertical;
    return Scrollable.maybeOf(context, axis: axis) != null;
  }

  static bool _accelerates(TraversalDirection direction) {
    final focus = FocusManager.instance.primaryFocus;
    return focus != null &&
        paceOf(focus) == TouchpadPace.browse &&
        acceleratesFrom(focus, direction);
  }

  /// Le rythme du pavé pour ce que [node] désigne (ADR-0122) :
  ///
  /// 1. celui que sa zone a déclaré ([TvTouchpadPace]), les réglages par
  ///    exemple ;
  /// 2. sinon posé pour une cible basse ([_controlHeight]) : onglet, bouton,
  ///    puce, ligne de menu ;
  /// 3. sinon vif : une affiche, une vignette, une carte.
  ///
  /// La hauteur est celle de la mise en page, pas celle de l'écran : ni
  /// l'échelle du téléviseur ni le soulèvement d'une affiche ne la changent.
  static TouchpadPace paceOf(FocusNode node) {
    final context = node.context;
    if (context == null) return TouchpadPace.browse;
    final declared = TvTouchpadPace.maybeOf(context);
    if (declared != null) return declared;
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize && box.size.height < _controlHeight) {
      return TouchpadPace.precise;
    }
    return TouchpadPace.browse;
  }

  static TouchpadPace get _pace {
    final focus = FocusManager.instance.primaryFocus;
    return focus == null ? TouchpadPace.browse : paceOf(focus);
  }

  /// Vrai quand le focus est dans un champ de texte. Le doigt n'y pilote
  /// rien : clavier ouvert, c'est lui qui a la télécommande ; fermé, la
  /// flèche du moteur sort du champ par `WebTvFieldExit`, qui la lit avant
  /// tout le monde et ferait un second pas à côté du nôtre.
  static bool get _inTextField =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  /// Un événement du trackpad. Public pour les tests, qui n'ont pas de
  /// Siri Remote.
  @visibleForTesting
  static void handleTouch(TouchpadPhase phase, double x, double y) {
    // Poser le doigt, ou cliquer, arrête la liste là où elle est : c'est le
    // geste que l'Apple TV apprend à ses utilisateurs.
    if (phase == TouchpadPhase.began || phase == TouchpadPhase.clickDown) {
      _stopCoast('doigt posé');
    }
    if (phase == TouchpadPhase.clickDown || phase == TouchpadPhase.clickUp) {
      debugPrint(
          'ONYXCLICK ${DateTime.now().millisecondsSinceEpoch} ${phase.name}');
    }
    if (phase == TouchpadPhase.clickDown) clickHeld.value = true;
    if (phase == TouchpadPhase.clickUp) clickHeld.value = false;
    if (phase == TouchpadPhase.began) _gestureUsed = false;
    final now = _now;
    // Le rythme de ce que le focus désigne à cet instant : il change en
    // cours de geste quand un pas passe d'un bouton à une affiche.
    final pace = _pace;
    final browsing = pace == TouchpadPace.browse;
    final release = _motion.add(
      phase,
      x,
      y,
      now,
      accelerates: _accelerates,
      pace: pace,
    );

    if (phase == TouchpadPhase.moved) {
      final move = _motion.lastMove;
      if (move == null) return;
      var used = false;
      for (final listener in List.of(_moveListeners)) {
        used = listener(move) || used;
      }
      if (used) {
        _gestureUsed = true;
        _motion.dropPending();
      }
      if (!TvMode.isTv || _inTextField) return;
      final step = _motion.takeStep(now, pace: pace);
      if (step != null) _step(step, gliding: browsing);
      return;
    }

    if (release == null || !TvMode.isTv || _gestureUsed || _inTextField) {
      return;
    }
    if (release.flick) _step(release.direction, gliding: browsing);
    // Parti d'une commande, le geste ne prend pas l'élan d'une rangée, même
    // si son dernier pas vient de poser le focus sur des affiches : il ne
    // rend que les crans que son trajet a gagnés.
    if (browsing && _accelerates(release.direction)) {
      _startCoast(TouchpadCoast(release));
    } else if (release.owed > 0) {
      _startCoast(TouchpadCoast.owed(
        release,
        TouchpadAxisTuning.of(release.direction, pace: pace),
      ));
    }
  }

  static void stopGlide() => _stopCoast('demandé');

  static void _stopCoast(String reason) {
    if (_coastTimer != null && glideStepper != null) {
      TvDpadLog.log(() => 'élan coupé : $reason');
    }
    _coastTimer?.cancel();
    _coastTimer = null;
    _coast = null;
    _coastMisses = 0;
  }

  static void _startCoast(TouchpadCoast coast) {
    _stopCoast('nouveau glissé');
    final delay = coast.next();
    if (delay == null) return;
    _coast = coast;
    _coastTimer = Timer(delay, _coastStep);
    if (glideStepper != null) {
      TvDpadLog.log(() => 'élan : ${coast.direction.name}, premier pas dans '
          '${delay.inMilliseconds} ms');
    }
  }

  static void _coastStep() {
    final coast = _coast;
    if (coast == null ||
        !TvMode.isTv ||
        (coast.momentum && !_accelerates(coast.direction))) {
      _stopCoast('hors rangée');
      return;
    }
    // Le focus n'a pas bougé deux fois de suite : bout de la rangée, la
    // lancée s'arrête là. Un pas dû est une flèche ordinaire : sous dpad, il
    // ne passe pas par le pas de lancée, qui reste dans sa rangée.
    if (_step(coast.direction, coasting: coast.momentum)) {
      _coastMisses = 0;
    } else if (++_coastMisses > 1) {
      _stopCoast('bout de la rangée');
      return;
    }
    final delay = coast.next();
    if (delay == null) {
      _stopCoast('fini');
      return;
    }
    _coastTimer = Timer(delay, _coastStep);
  }

  /// Fait un pas vers [direction], et dit si le focus a bougé. [gliding] faux
  /// pour un pas posé : le défilement qui le suit n'est pas pressé
  /// ([isGliding]).
  static bool _step(
    TraversalDirection direction, {
    bool coasting = false,
    bool gliding = true,
  }) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    _lastStepAt = gliding && _alongRow(direction) ? _now : null;
    final stepper = glideStepper;
    if (coasting && stepper != null) {
      stepper(direction);
    } else {
      _pressArrow(focus, direction);
    }
    // Le focus demandé ne se pose qu'à la microtâche suivante.
    FocusManager.instance.applyFocusChangesIfNeeded();
    return !identical(FocusManager.instance.primaryFocus, focus);
  }

  /// Fait parcourir à l'arbre de focus une flèche vers [direction], appuyée
  /// puis relâchée, exactement comme `FocusManager` le fait d'une touche : du
  /// nœud focalisé vers la racine, jusqu'au premier `onKeyEvent` qui la
  /// prend. Les raccourcis de l'app en font un `DirectionalFocusIntent`.
  ///
  /// Écartée : rejouer la touche par le canal `flutter/keyevent`. Elle
  /// passerait par `HardwareKeyboard`, dont l'état (« flèche enfoncée ») se
  /// mêlerait à celui des vraies flèches du moteur, retenues au même moment.
  static void _pressArrow(FocusNode from, TraversalDirection direction) {
    final key = _arrowKey(direction);
    final physical = _physicalArrow(direction);
    final timeStamp = _now;
    // Une flèche synthétique n'est jamais la répétition d'une touche tenue.
    TvKeyRepeat.noteFreshPress();
    for (final event in <KeyEvent>[
      KeyDownEvent(
        physicalKey: physical,
        logicalKey: key,
        timeStamp: timeStamp,
        synthesized: true,
      ),
      KeyUpEvent(
        physicalKey: physical,
        logicalKey: key,
        timeStamp: timeStamp,
        synthesized: true,
      ),
    ]) {
      for (final node in <FocusNode>[from, ...from.ancestors]) {
        final result = node.onKeyEvent?.call(node, event);
        if (result == KeyEventResult.handled ||
            result == KeyEventResult.skipRemainingHandlers) {
          break;
        }
      }
    }
  }

  /// Retient les flèches que le moteur tire d'un glissé : le modèle fait déjà
  /// les pas de ce geste. Passe avant tout l'arbre de focus.
  static KeyEventResult _holdEngineArrow(KeyEvent event) {
    final key = event.logicalKey;
    if (_arrowDirection(key) == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      if (!TvMode.isTv ||
          _inTextField ||
          !_motion.ownsArrowAt(_now, grace: _arrowGrace)) {
        _heldBack.remove(key);
        return KeyEventResult.ignored;
      }
      _heldBack.add(key);
      return KeyEventResult.handled;
    }
    if (!_heldBack.contains(key)) return KeyEventResult.ignored;
    if (event is KeyUpEvent) _heldBack.remove(key);
    return KeyEventResult.handled;
  }

  /// Toute touche reprend la main sur la lancée : OK, Retour, une flèche du
  /// pavé directionnel. Seule la flèche que le moteur tire du geste qui l'a
  /// lancée ne la coupe pas.
  static bool _observeKey(KeyEvent event) {
    debugPrint(
        'ONYXHW ${DateTime.now().millisecondsSinceEpoch} ${event.runtimeType} ${event.logicalKey.debugName} focus=${FocusManager.instance.primaryFocus?.debugLabel}');
    if (event is! KeyDownEvent || _coastTimer == null) return false;
    final ownArrow = _arrowDirection(event.logicalKey) != null &&
        _motion.ownsArrowAt(_now, grace: _arrowGrace);
    if (!ownArrow) _stopCoast('touche ${event.logicalKey.keyLabel}');
    return false;
  }

  static TraversalDirection? _arrowDirection(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft) return TraversalDirection.left;
    if (key == LogicalKeyboardKey.arrowRight) return TraversalDirection.right;
    if (key == LogicalKeyboardKey.arrowUp) return TraversalDirection.up;
    if (key == LogicalKeyboardKey.arrowDown) return TraversalDirection.down;
    return null;
  }

  static LogicalKeyboardKey _arrowKey(TraversalDirection direction) =>
      switch (direction) {
        TraversalDirection.left => LogicalKeyboardKey.arrowLeft,
        TraversalDirection.right => LogicalKeyboardKey.arrowRight,
        TraversalDirection.up => LogicalKeyboardKey.arrowUp,
        TraversalDirection.down => LogicalKeyboardKey.arrowDown,
      };

  static PhysicalKeyboardKey _physicalArrow(TraversalDirection direction) =>
      switch (direction) {
        TraversalDirection.left => PhysicalKeyboardKey.arrowLeft,
        TraversalDirection.right => PhysicalKeyboardKey.arrowRight,
        TraversalDirection.up => PhysicalKeyboardKey.arrowUp,
        TraversalDirection.down => PhysicalKeyboardKey.arrowDown,
      };

  /// Installe les gestionnaires de touches hors Apple TV, pour les tests.
  @visibleForTesting
  static void debugInstallKeyObserver() => _installKeyHandlers();

  @visibleForTesting
  static void debugReset() {
    stopGlide();
    _moveListeners.clear();
    _heldBack.clear();
    _gestureUsed = false;
    _lastStepAt = null;
    debugClock = null;
    clickHeld.value = false;
    _motion = TouchpadMotion();
  }
}
