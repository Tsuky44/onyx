import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Version navigateur — voir `desktop_picture_in_picture.dart`.
///
/// C'est le PiP du navigateur sur la balise `<video>` de media_kit : une
/// fenêtre flottante gérée par le navigateur, avec lecture/pause. Les
/// sous-titres y sont ceux de `WebPlayback.showSubtitleVtt`, des pistes natives
/// du `<video>`, donc ils suivent l'image dans la fenêtre (ceux dessinés par
/// Flutter n'y seraient pas, ADR-0031).
abstract final class DesktopPictureInPicture {
  const DesktopPictureInPicture._();

  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// Ici la fenêtre de la page reste entière : le chrome du lecteur aussi.
  static const bool shrinksWindow = false;

  /// L'API existe (Chrome, Edge, Safari) et le pointeur principal est une
  /// souris : sur téléphone ou tablette le PiP est celui du système, déclenché
  /// par le geste de sortie, et un bouton de plus n'y a pas sa place.
  static bool get supported {
    try {
      return web.document.pictureInPictureEnabled &&
          web.window.matchMedia('(hover: hover) and (pointer: fine)').matches;
    } catch (_) {
      // Une API absente ou refusée se lit « non pris en charge » : le bouton
      // n'apparaît pas, il n'y a rien d'autre à faire.
      return false;
    }
  }

  static web.HTMLVideoElement? _video() =>
      web.document.querySelector('video') as web.HTMLVideoElement?;

  static Future<void> toggle({required double aspect}) async {
    try {
      if (web.document.pictureInPictureElement != null) {
        await web.document.exitPictureInPicture().toDart;
        active.value = false;
        return;
      }
      final video = _video();
      if (video == null) return;
      await video.requestPictureInPicture().toDart;
      active.value = true;
      video.addEventListener(
        'leavepictureinpicture',
        ((web.Event _) => active.value = false).toJS,
        web.AddEventListenerOptions(once: true),
      );
    } catch (error) {
      // Refus du navigateur (hors geste de l'utilisateur, flux sans piste
      // vidéo, PiP désactivé par une politique) : le bouton ne fait rien.
      debugPrint('Picture-in-picture: refused by the browser ($error)');
    }
  }

  static Future<void> exit() async {
    if (web.document.pictureInPictureElement == null) return;
    try {
      await web.document.exitPictureInPicture().toDart;
    } catch (error) {
      debugPrint('Picture-in-picture: cannot leave ($error)');
    }
    active.value = false;
  }
}
