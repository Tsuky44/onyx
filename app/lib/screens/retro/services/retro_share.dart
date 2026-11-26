import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/retro.dart';
import '../../../utils/app_platform.dart';
import '../../../utils/widget_image.dart';
import '../widgets/retro_recap_ticket.dart';
import 'retro_image_file.dart';

/// Partage l'image de récap du Rétro (ADR 2026-11-26-tsuky-retro-annuel,
/// décision 13) : le ticket du dernier écran, rendu à part en 1080 × 1920.
///
/// Sur un téléphone, une tablette, un Mac et dans un navigateur, il part par
/// le menu de partage du système (le navigateur le télécharge s'il ne sait pas
/// partager). Sur un PC Windows ou Linux, il s'enregistre dans Téléchargements :
/// on l'envoie ensuite d'où l'on veut. Un téléviseur ne propose rien.
abstract final class RetroShare {
  /// Enregistrer plutôt que partager.
  static bool get savesFile => AppPlatform.isWindows || AppPlatform.isLinux;

  /// Trois fois la taille du ticket : 1080 × 1920, le format d'une story.
  static const double pixelRatio = 3;

  static String fileName(int year) => 'onyx-retro-$year.png';

  /// L'image, en PNG.
  static Future<Uint8List> image(
    ui.FlutterView view, {
    required RetroReport report,
    required String name,
  }) =>
      renderWidgetToPng(
        RetroRecapTicket(report: report, name: name),
        size: RetroRecapTicket.size,
        view: view,
        pixelRatio: pixelRatio,
      );

  /// Partage ou enregistre l'image. Rend le chemin du fichier quand elle a
  /// été enregistrée, null quand elle est partie par le menu de partage.
  /// [origin] est le bouton touché : la feuille de partage d'un iPad et d'un
  /// Mac s'y accroche.
  static Future<String?> share(
    ui.FlutterView view, {
    required RetroReport report,
    required String name,
    Rect? origin,
  }) async {
    final bytes = await image(view, report: report, name: name);
    final file = fileName(report.year);
    if (savesFile) return saveRetroImage(bytes, file);
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png', name: file)],
      fileNameOverrides: [file],
      sharePositionOrigin: origin,
    ));
    return null;
  }
}
