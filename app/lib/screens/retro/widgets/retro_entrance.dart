import 'package:material_ui/material_ui.dart';

import '../../../theme/retro_motion.dart';

/// L'horloge d'entrée d'un écran du Rétro : une seule animation par écran, de
/// 0 à 1 sur [RetroMotion.entrance]. Chaque élément en prend sa tranche
/// ([RetroEntrance.slice]) selon son retard, au lieu d'avoir son propre
/// contrôleur : dix mots qui montent coûtent une animation, pas dix.
///
/// Sans horloge au-dessus (un test qui monte un écran seul) ou sous « réduire
/// les animations », tout est déjà à sa place.
class RetroEntrance extends StatefulWidget {
  const RetroEntrance({super.key, required this.child});
  final Widget child;

  static Animation<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_EntranceScope>()?.animation ??
      kAlwaysCompleteAnimation;

  /// La part de l'entrée qui revient à un élément qui commence après [delay]
  /// et dure [duration], courbe comprise : 0 avant, 1 après.
  static Animation<double> slice(
    BuildContext context, {
    required Duration delay,
    Duration duration = RetroMotion.rise,
    Curve curve = RetroMotion.out,
  }) {
    final total = RetroMotion.entrance.inMicroseconds;
    final start = (delay.inMicroseconds / total).clamp(0.0, 1.0);
    final end = ((delay + duration).inMicroseconds / total).clamp(start, 1.0);
    return CurvedAnimation(
      parent: of(context),
      curve: Interval(start, end, curve: curve),
    );
  }

  @override
  State<RetroEntrance> createState() => _RetroEntranceState();
}

class _RetroEntranceState extends State<RetroEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: RetroMotion.entrance);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (RetroMotion.still(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _EntranceScope(animation: _controller, child: widget.child);
}

class _EntranceScope extends InheritedWidget {
  const _EntranceScope({required this.animation, required super.child});
  final Animation<double> animation;

  @override
  bool updateShouldNotify(_EntranceScope oldWidget) =>
      animation != oldWidget.animation;
}

/// Un élément qui arrive : il monte et apparaît ([RetroReveal.rise]), surgit
/// avec un léger rebond ([RetroReveal.pop]) ou glisse depuis la droite
/// ([RetroReveal.slide]).
class RetroReveal extends StatelessWidget {
  const RetroReveal.rise({super.key, required this.delay, required this.child})
      : _kind = _RevealKind.rise;
  const RetroReveal.pop({super.key, required this.delay, required this.child})
      : _kind = _RevealKind.pop;
  const RetroReveal.slide({super.key, required this.delay, required this.child})
      : _kind = _RevealKind.slide;

  final Duration delay;
  final Widget child;
  final _RevealKind _kind;

  @override
  Widget build(BuildContext context) {
    final t = RetroEntrance.slice(
      context,
      delay: delay,
      curve: _kind == _RevealKind.pop ? RetroMotion.back : RetroMotion.out,
    );
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) {
        final v = t.value;
        final opacity = v.clamp(0.0, 1.0);
        final Widget moved = switch (_kind) {
          _RevealKind.rise => FractionalTranslation(
              translation: Offset(0, 0.4 * (1 - v)), child: child),
          _RevealKind.pop => Transform.scale(
              scale: 0.6 + 0.4 * v,
              child: Transform.rotate(angle: -0.1 * (1 - v), child: child),
            ),
          _RevealKind.slide => FractionalTranslation(
              translation: Offset(0.45 * (1 - v), 0), child: child),
        };
        return Opacity(opacity: opacity, child: moved);
      },
    );
  }
}

enum _RevealKind { rise, pop, slide }
