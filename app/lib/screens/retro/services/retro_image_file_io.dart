import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Écrit [bytes] sous [fileName] dans le dossier Téléchargements (Documents
/// s'il n'y en a pas), sans écraser une image d'avant : « onyx-retro-2026
/// (2).png ». Rend le chemin écrit.
Future<String> saveRetroImage(Uint8List bytes, String fileName) async {
  final folder =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final stem = p.basenameWithoutExtension(fileName);
  final extension = p.extension(fileName);
  var file = File(p.join(folder.path, fileName));
  for (var n = 2; await file.exists(); n++) {
    file = File(p.join(folder.path, '$stem ($n)$extension'));
  }
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
