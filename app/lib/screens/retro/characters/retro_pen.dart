import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../theme/app_theme.dart';

/// Le crayon des personnages du Rétro : quelques gestes de dessin vectoriel
/// (formes pleines, traits, textes, rotations) dans l'espace de la maquette
/// (`design-plans/onyx-retro-personnages.html`), dont les tracés sont repris
/// tels quels.
class RetroPen {
  RetroPen(this.canvas);
  final Canvas canvas;

  Path rect(double x, double y, double w, double h, [double r = 0]) =>
      Path()..addRRect(RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(r)));

  Path ellipse(double cx, double cy, double rx, double ry) => Path()
    ..addOval(
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2));

  Path circle(double cx, double cy, double r) => ellipse(cx, cy, r, r);

  /// Une forme pleine, et son contour s'il en a un.
  void shape(Path path, {Color? fill, Color? stroke, double width = 3}) {
    if (fill != null) canvas.drawPath(path, Paint()..color = fill);
    if (stroke != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round
          ..color = stroke,
      );
    }
  }

  /// Un tracé de la maquette, plein et éventuellement cerné.
  void fill(String d, Color color, {Color? stroke, double width = 3}) =>
      shape(svgPath(d), fill: color, stroke: stroke, width: width);

  /// Un trait de la maquette, aux bouts ronds.
  void line(String d, Color color, double width,
      {bool round = true, double dash = 0}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = round ? StrokeCap.round : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final path = svgPath(d);
    if (dash <= 0) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash * 2) {
        canvas.drawPath(
            metric.extractPath(at, math.min(at + dash, metric.length)), paint);
      }
    }
  }

  /// Un bras : un trait épais de l'encre sombre, et la couleur du corps
  /// dedans, pour un contour comme celui du corps.
  void arm(String d, Color body, Color outline) {
    line(d, outline, 17);
    line(d, body, 10);
  }

  /// Un texte centré sur [x], posé sur la ligne de base [baseline].
  void text(String value, double x, double baseline, double size, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: size,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final ascent =
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.paint(canvas, Offset(x - painter.width / 2, baseline - ascent));
  }

  /// Dessine [draw] tourné de [degrees] autour de ([cx], [cy]).
  void rotated(double degrees, double cx, double cy, VoidCallback draw) {
    canvas
      ..save()
      ..translate(cx, cy)
      ..rotate(degrees * math.pi / 180)
      ..translate(-cx, -cy);
    draw();
    canvas.restore();
  }

  /// Dessine [draw] sans déborder de [clip].
  void clipped(Path clip, VoidCallback draw) {
    canvas
      ..save()
      ..clipPath(clip);
    draw();
    canvas.restore();
  }
}

final RegExp _token = RegExp(r'[MmLlQqZz]|-?(?:\d+\.?\d*|\.\d+)');
final Map<String, Path> _paths = {};

/// Les tracés de la maquette (M, L, Q, Z, absolus ou relatifs, avec les
/// répétitions implicites), une fois lus, gardés en mémoire.
Path svgPath(String d) => _paths[d] ??= _parse(d);

Path _parse(String d) {
  final tokens = [for (final m in _token.allMatches(d)) m.group(0)!];
  final path = Path();
  var i = 0;
  var command = 'M';
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    final token = tokens[i];
    if (token.length == 1 && RegExp('[A-Za-z]').hasMatch(token)) {
      command = token;
      i++;
      if (command == 'Z' || command == 'z') {
        path.close();
        x = startX;
        y = startY;
        continue;
      }
    }
    switch (command) {
      case 'M':
        x = next();
        y = next();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        command = 'L';
      case 'm':
        x += next();
        y += next();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        command = 'l';
      case 'L':
        x = next();
        y = next();
        path.lineTo(x, y);
      case 'l':
        x += next();
        y += next();
        path.lineTo(x, y);
      case 'Q':
        final cx = next(), cy = next();
        x = next();
        y = next();
        path.quadraticBezierTo(cx, cy, x, y);
      case 'q':
        final cx = x + next(), cy = y + next();
        x += next();
        y += next();
        path.quadraticBezierTo(cx, cy, x, y);
      default:
        i++;
    }
  }
  return path;
}
