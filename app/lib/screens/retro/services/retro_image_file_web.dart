import 'dart:typed_data';

/// Le navigateur n'écrit pas de fichier lui-même : `RetroShare` y passe par
/// le partage, qui télécharge l'image quand le navigateur ne sait pas
/// partager.
Future<String> saveRetroImage(Uint8List bytes, String fileName) =>
    throw UnsupportedError(
        'Le navigateur partage l’image au lieu de l’écrire.');
