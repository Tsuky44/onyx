import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../theme/app_motion.dart';
import '../../../theme/retro_motion.dart';

/// Le passage d'un écran du Rétro à l'autre : le nouveau s'ouvre en cercle
/// depuis l'endroit touché, l'ancien recule et s'assombrit dessous.
///
/// Sous « réduire les animations » ou en mode léger, le nouvel écran se pose
/// d'un fondu court, sans cercle ni recul.
class RetroSlideTransition extends StatefulWidget {
  const RetroSlideTransition({
    super.key,
    required this.index,
    required this.origin,
    required this.child,
  });

  /// Change à chaque écran : c'est lui qui lance la transition.
  final int index;

  /// D'où part le cercle, en part de l'écran (0 à 1).
  final Offset origin;
  final Widget child;

  @override
  State<RetroSlideTransition> createState() => _RetroSlideTransitionState();
}

class _RetroSlideTransitionState extends State<RetroSlideTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress =
      AnimationController(vsync: this, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && _previous != null) {
            setState(() => _previous = null);
          }
        });

  ({int index, Widget child})? _previous;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = RetroMotion.still(context);
  }

  @override
  void didUpdateWidget(RetroSlideTransition old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    _previous = (index: old.index, child: old.child);
    _progress.duration = _still
        ? AppMotion.fade(context, AppMotion.reveal)
        : RetroMotion.transition;
    _progress.forward(from: 0);
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previous = _previous;
    final t = CurvedAnimation(parent: _progress, curve: RetroMotion.inOut);
    // Chaque écran garde sa clé et la même forme d'un rôle à l'autre : celui
    // qui part reste le même widget, ses fonds continuent sans repartir.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (previous != null)
          KeyedSubtree(
            key: ValueKey(previous.index),
            child: _Layer(
              progress: t,
              leaving: true,
              still: _still,
              origin: widget.origin,
              child: previous.child,
            ),
          ),
        KeyedSubtree(
          key: ValueKey(widget.index),
          child: _Layer(
            progress: t,
            leaving: false,
            still: _still,
            origin: widget.origin,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _Layer extends StatelessWidget {
  const _Layer({
    required this.progress,
    required this.leaving,
    required this.still,
    required this.origin,
    required this.child,
  });

  final Animation<double> progress;
  final bool leaving;
  final bool still;
  final Offset origin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final t = progress.value;
        if (still) {
          return Opacity(opacity: leaving ? 1 : t, child: child);
        }
        if (leaving) {
          return Transform.scale(
            scale: 1 - 0.1 * t,
            child: Stack(
              fit: StackFit.expand,
              children: [
                child!,
                ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.55 * t)),
              ],
            ),
          );
        }
        return ClipPath(
          clipper: t >= 1 ? null : _CircleClipper(origin: origin, t: t),
          child: child,
        );
      },
    );
  }
}

class _CircleClipper extends CustomClipper<Path> {
  const _CircleClipper({required this.origin, required this.t});
  final Offset origin;
  final double t;

  @override
  Path getClip(Size size) {
    final center = Offset(origin.dx * size.width, origin.dy * size.height);
    // Jusqu'au coin le plus loin, pour que le cercle couvre tout l'écran.
    final reach = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((corner) => (corner - center).distance).reduce(math.max);
    return Path()..addOval(Rect.fromCircle(center: center, radius: reach * t));
  }

  @override
  bool shouldReclip(_CircleClipper old) => old.t != t || old.origin != origin;
}
