/// Bibliothèque des vidéos de l'appareil — voir `device_library_io.dart` et
/// l'ADR-0104.
library;

/// Un navigateur n'a pas de dossier à parcourir : le web se résout vers un
/// stub qui déclare la fonctionnalité indisponible, et les entrées
/// disparaissent d'elles-mêmes.
export 'device_library_io.dart'
    if (dart.library.js_interop) 'device_library_web.dart';
