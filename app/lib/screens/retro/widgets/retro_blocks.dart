import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../theme/retro_motion.dart';
import 'retro_entrance.dart';
import 'retro_type.dart';

/// Un encart posé sur l'écran : la lecture directe, la place sur le serveur,
/// la carte de fin.
class RetroCard extends StatelessWidget {
  const RetroCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final ink =
        DefaultTextStyle.of(context).style.color ?? const Color(0xFFFFFFFF);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(math.max(14, u * 5)),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(math.max(14, u * 5)),
        border: Border.all(color: ink.withValues(alpha: 0.2)),
      ),
      child: child,
    );
  }
}

/// Un ticket de séance : « Première séance · Slow Horses · 1 janv. · 11:02 ».
class RetroTicket extends StatelessWidget {
  const RetroTicket({
    super.key,
    required this.label,
    required this.title,
    required this.when,
  });

  final String label;
  final String title;
  final String when;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final ink =
        DefaultTextStyle.of(context).style.color ?? const Color(0xFFFFFFFF);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: math.max(12, u * 4),
        vertical: math.max(10, u * 3.4),
      ),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(math.max(12, u * 3.5)),
        border: Border.all(color: ink.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RetroKicker(label),
          SizedBox(height: u),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: math.max(13, u * 4),
              fontWeight: FontWeight.w700,
            ),
          ),
          Opacity(
            opacity: 0.75,
            child: Text(when, style: TextStyle(fontSize: math.max(11, u * 3))),
          ),
        ],
      ),
    );
  }
}

/// Une jauge : « TV du salon · 64 % ».
class RetroMeter extends StatelessWidget {
  const RetroMeter({
    super.key,
    required this.label,
    required this.percent,
    this.delay = Duration.zero,
  });

  final String label;
  final int percent;

  /// Quand la jauge commence à se remplir.
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final ink =
        DefaultTextStyle.of(context).style.color ?? const Color(0xFFFFFFFF);
    final style = TextStyle(
      fontSize: math.max(12, u * 3.8),
      fontWeight: FontWeight.w700,
    );
    final fill = RetroEntrance.slice(
      context,
      delay: delay + const Duration(milliseconds: 150),
      duration: RetroMotion.count,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text('$percent %',
                style: style.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
        SizedBox(height: u * 1.6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: math.max(6, u * 2.4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: ink.withValues(alpha: 0.16)),
                AnimatedBuilder(
                  animation: fill,
                  child: ColoredBox(color: ink),
                  builder: (context, child) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (percent / 100).clamp(0.0, 1.0) * fill.value,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
