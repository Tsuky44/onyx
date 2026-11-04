/// Image dans l'image sur ordinateur : navigateur et fenêtre native.
///
/// Façade — deux implémentations, car le système ne fournit pas la même chose
/// partout :
///
///  * **Navigateur** (`_web`) : le PiP natif du navigateur sur la balise
///    `<video>` de media_kit. L'image sort dans une fenêtre flottante gérée par
///    le navigateur, et la page reste utilisable.
///  * **Windows, macOS, Linux** (`_io`) : il n'y a pas de PiP système pour une
///    texture Flutter. La fenêtre de l'app se réduit en une petite fenêtre
///    toujours au premier plan, dans un coin de l'écran.
///
/// Même interface des deux côtés : [supported], [active], [toggle], [exit].
library;

export 'desktop_picture_in_picture_io.dart'
    if (dart.library.js_interop) 'desktop_picture_in_picture_web.dart';
