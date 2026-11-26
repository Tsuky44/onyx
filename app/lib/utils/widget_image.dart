import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Dessine [widget] hors de l'écran, à [size] points, et en rend un PNG de
/// [size] × [pixelRatio] pixels.
///
/// Pour une image à partager, construite à part de ce qui est affiché : elle
/// sort pareille quel que soit l'état de l'écran (une animation en cours, un
/// mode « réduire les animations », une autre taille de fenêtre). Le widget
/// ne doit rien attendre du réseau : il est dessiné en une seule passe.
Future<Uint8List> renderWidgetToPng(
  Widget widget, {
  required Size size,
  required ui.FlutterView view,
  double pixelRatio = 3,
}) async {
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(child: boundary),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      physicalConstraints: BoxConstraints.tight(size),
    ),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final focus = FocusManager();
  final build = BuildOwner(focusManager: focus);
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(textDirection: TextDirection.ltr, child: widget),
    ),
  ).attachToRenderTree(build);
  try {
    build
      ..buildScope(root)
      ..finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG vide');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    // Démonte l'arbre pour libérer ce qu'il tenait (textes mis en page,
    // peintres), puis le reste.
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
        .attachToRenderTree(build, root);
    build.finalizeTree();
    focus.dispose();
    pipeline
      ..rootNode = null
      ..dispose();
  }
}
