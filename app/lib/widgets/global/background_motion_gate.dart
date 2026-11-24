import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../services/player_presence.dart';
import '../../utils/app_platform.dart';
import '../../utils/on_screen.dart';

/// Fige toute animation de l'app tant que sa fenêtre n'a pas le focus, sur
/// bureau.
///
/// La panne d'origine : une fenêtre qu'une autre recouvre est `inactive`, pas
/// `hidden`. Flutter y dessine chaque image comme si on la regardait, et le
/// carrousel de l'accueil, les squelettes ou la pastille « en cours » gardent
/// le processeur et la carte graphique occupés derrière un navigateur. Un seul
/// [TickerMode] ici suspend tous les `AnimationController` de l'arbre, comme le
/// fait déjà `ShellTabStack` pour un onglet caché ; les widgets qui lisent
/// [OnScreenState] suivent le même signal et arrêtent leurs sondages avec
/// (voir ADR-0166).
///
/// Trois exceptions : un lecteur ouvert (le chrome se fond et se cache pendant
/// qu'on regarde dans une autre fenêtre ; figé à mi-fondu, il resterait sur le
/// film), tout ce qui n'est pas un ordinateur (sur téléphone, `inactive` veut
/// dire une fenêtre partagée ou une boîte système, l'app est bien regardée) et
/// la souris au-dessus de la fenêtre. Ce dernier cas sépare ce qu'on ne voit
/// vraiment pas (fenêtre recouverte, curseur ailleurs : tout reste figé) de ce
/// qu'on regarde sans avoir cliqué dedans : le curseur y est, la carte survolée
/// doit se mettre en avant, sinon on choisit un film sans voir lequel est
/// sélectionné.
class BackgroundMotionGate extends StatefulWidget {
  const BackgroundMotionGate({super.key, required this.child, this.desktop});

  final Widget child;

  /// Remplace la plateforme réelle, pour les tests.
  final bool? desktop;

  @override
  State<BackgroundMotionGate> createState() => _BackgroundMotionGateState();
}

class _BackgroundMotionGateState extends State<BackgroundMotionGate> {
  /// Un pointeur de souris est au-dessus de la fenêtre. Une fenêtre qu'une
  /// autre recouvre ne reçoit plus ses déplacements : le signal retombe seul.
  final ValueNotifier<bool> _pointerInside = ValueNotifier<bool>(false);

  late final Listenable _signals = Listenable.merge(
    [AppForeground.focused, PlayerPresence.open, _pointerInside],
  );

  bool get _motionAllowed =>
      !(widget.desktop ?? AppPlatform.isDesktop) ||
      AppForeground.focused.value ||
      PlayerPresence.open.value ||
      _pointerInside.value;

  late bool _enabled = _motionAllowed;

  @override
  void initState() {
    super.initState();
    _signals.addListener(_changed);
  }

  @override
  void dispose() {
    _signals.removeListener(_changed);
    _pointerInside.dispose();
    super.dispose();
  }

  // Le lecteur s'annonce depuis `initState` et `dispose` : reconstruire sur
  // place ferait « setState pendant la construction ».
  void _changed() {
    scheduleMicrotask(() {
      if (!mounted || _motionAllowed == _enabled) return;
      setState(() => _enabled = _motionAllowed);
    });
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        opaque: false,
        onEnter: (_) => _pointerInside.value = true,
        onExit: (_) => _pointerInside.value = false,
        child: _MotionFrozen(
          frozen: !_enabled,
          child: TickerMode(enabled: _enabled, child: widget.child),
        ),
      );
}

/// Dit aux widgets sous la porte que leur [TickerMode] est coupé par elle, et
/// non par une page opaque qui les couvre.
///
/// Sans cela, un widget qui lit [TickerMode] pour savoir s'il est « à l'écran »
/// (l'en-tête qui porte les contrôles de la fenêtre) prend la perte du focus
/// pour une page poussée par-dessus : la bande du haut revenait à chaque clic
/// dans une autre fenêtre.
class _MotionFrozen extends InheritedWidget {
  const _MotionFrozen({required this.frozen, required super.child});

  final bool frozen;

  @override
  bool updateShouldNotify(_MotionFrozen oldWidget) =>
      frozen != oldWidget.frozen;
}

extension BackgroundMotionFrozen on BuildContext {
  /// Vrai tant que [BackgroundMotionGate] fige les animations sous ce
  /// contexte. Le [TickerMode] lu au même endroit ne dit alors rien de la
  /// page : garder la dernière valeur connue. Se reconstruit au changement.
  bool get motionFrozenByGate =>
      dependOnInheritedWidgetOfExactType<_MotionFrozen>()?.frozen ?? false;
}
