import 'dart:math' as math;
import 'dart:ui';

/// Où et à quelle taille poser la petite fenêtre d'un film dans l'écran.
///
/// Pure, pour être testée sans fenêtre : [DesktopPictureInPicture] (version
/// native) lui donne l'écran visible — celui où se trouve la fenêtre, barre des
/// tâches déduite — et le rapport d'image du film.
abstract final class DesktopPipPlacement {
  const DesktopPipPlacement._();

  /// La plus grande fenêtre qu'on pose : assez pour suivre un film, assez peu
  /// pour ne pas masquer ce qu'on fait à côté.
  static const double maxWidth = 480;
  static const double maxHeight = 300;

  /// Distance au bord de l'écran.
  static const double margin = 24;

  /// Un rapport inconnu ou absurde (film pas encore ouvert) retombe sur 16:9 ;
  /// un rapport extrême est ramené dans ce qu'une fenêtre peut raisonnablement
  /// porter, comme `PictureInPicture.shapeFor` le fait pour Android.
  static double sanitizeAspect(double aspect) {
    if (!aspect.isFinite || aspect <= 0) return 16 / 9;
    return aspect.clamp(0.5, 2.5);
  }

  /// Le rectangle de la petite fenêtre, calé en bas à droite de [screen].
  static Rect cornerRect({required Rect screen, required double aspect}) {
    final ratio = sanitizeAspect(aspect);
    var width = maxWidth;
    var height = width / ratio;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * ratio;
    }

    // Un écran plus petit que la fenêtre (rare) : on la contient plutôt que de
    // la laisser déborder.
    final room = Size(screen.width - 2 * margin, screen.height - 2 * margin);
    if (width > room.width || height > room.height) {
      final scale = math.min(room.width / width, room.height / height);
      width *= scale;
      height *= scale;
    }

    return Rect.fromLTWH(
      screen.right - margin - width,
      screen.bottom - margin - height,
      width,
      height,
    );
  }
}
