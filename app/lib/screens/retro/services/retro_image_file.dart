/// Enregistre l'image de récap dans un fichier, sur un PC. Le web n'écrit pas
/// de fichier : il passe par le partage du navigateur (`RetroShare`).
library;

export 'retro_image_file_io.dart'
    if (dart.library.js_interop) 'retro_image_file_web.dart';
