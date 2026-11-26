import 'dart:math' as math;

import 'package:flutter/widgets.dart';

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

/// Un ticket de séance : ce qu'on a regardé à gauche, la date et l'heure sur
/// le talon, séparé par un pointillé et deux encoches.
class RetroTicket extends StatelessWidget {
  const RetroTicket({
    super.key,
    required this.label,
    required this.title,
    required this.date,
    required this.time,
  });

  final String label;
  final String title;

  /// « 1 janv. » et « 11:02 », sur le talon.
  final String date;
  final String time;

  @override
  Widget build(BuildContext context) {
    final u = RetroUnits.of(context).u;
    final ink =
        DefaultTextStyle.of(context).style.color ?? const Color(0xFFFFFFFF);
    final paper = Color.alphaBlend(
        ink.withValues(alpha: 0.13), RetroBackground.of(context));
    final stubWidth = math.max(84.0, u * 23);
    final notch = math.max(7.0, u * 2.6);
    return ClipPath(
      clipper: _TicketClipper(stubWidth: stubWidth, notch: notch),
      child: ColoredBox(
        color: paper,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: math.max(14, u * 4.5),
                    vertical: math.max(12, u * 5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RetroKicker(label),
                      SizedBox(height: u * 1.2),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: RetroBig.styleOf(context, 9)
                            .copyWith(height: 1, letterSpacing: -u * 0.2),
                      ),
                    ],
                  ),
                ),
              ),
              CustomPaint(
                painter: _DashPainter(ink.withValues(alpha: 0.35)),
                child: SizedBox(
                  width: stubWidth,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        date,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: math.max(13, u * 5.4),
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                      SizedBox(height: u),
                      Opacity(
                        opacity: 0.8,
                        child: Text(
                          time,
                          style: TextStyle(fontSize: math.max(11, u * 3.2)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le contour du ticket : coins arrondis, et une encoche en haut et en bas à
/// la frontière du talon.
class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper({required this.stubWidth, required this.notch});
  final double stubWidth;
  final double notch;

  @override
  Path getClip(Size size) {
    final x = size.width - stubWidth;
    final shape = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(notch * 1.2)));
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(x, 0), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(x, size.height), radius: notch));
    return Path.combine(PathOperation.difference, shape, holes);
  }

  @override
  bool shouldReclip(_TicketClipper old) =>
      old.stubWidth != stubWidth || old.notch != notch;
}

/// Le pointillé entre le ticket et son talon.
class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 6.0;
    for (var y = dash * 2; y < size.height - dash * 2; y += dash * 2) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dash), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
