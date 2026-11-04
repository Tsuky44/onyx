
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/app_platform.dart';
import 'desktop_pip_placement.dart';

/// Version native — voir `desktop_picture_in_picture.dart`.
///
/// La fenêtre de l'app se réduit sur place : c'est la même vue Flutter dessinée
/// plus petit, donc l'image et le son continuent sans interruption, comme avec
/// la petite fenêtre d'Android. Ce que la fenêtre était (taille, place, agrandie
/// ou plein écran) est gardé pour la rendre telle quelle.
abstract final class DesktopPictureInPicture {
  const DesktopPictureInPicture._();

  /// Vrai tant que le film vit dans la petite fenêtre. Le lecteur écoute : il
  /// n'y a pas de place pour son chrome.
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// Si la fenêtre elle-même rétrécit (vrai ici, faux dans le navigateur où la
  /// fenêtre flottante est celle du navigateur et la page reste entière).
  static const bool shrinksWindow = true;

  static bool get supported => AppPlatform.isDesktop;

  static _Restore? _restore;

  /// Une bascule en cours : fenêtre, plein écran et agrandissement répondent
  /// de façon asynchrone, et un second appui au milieu laisserait la fenêtre
  /// dans un état qui n'est ni l'ancien ni le nouveau.
  static bool _busy = false;

  static Future<void> toggle({required double aspect}) =>
      active.value ? exit() : _enter(aspect);

  static Future<void> _enter(double aspect) async {
    if (!supported || _busy) return;
    _busy = true;
    try {
      final wasFullScreen = await windowManager.isFullScreen();
      if (wasFullScreen) await _leaveFullScreen();
      final wasMaximized = await windowManager.isMaximized();
      if (wasMaximized) await windowManager.unmaximize();

      final bounds = await windowManager.getBounds();
      _restore = _Restore(
        bounds: bounds,
        wasMaximized: wasMaximized,
        wasFullScreen: wasFullScreen,
      );

      final target = DesktopPipPlacement.cornerRect(
        screen: await _screenAround(bounds),
        aspect: aspect,
      );
      // Le rapport verrouillé d'abord : la taille qui suit doit le respecter,
      // et l'utilisateur qui étire le coin garde l'image sans bandes.
      await windowManager.setAspectRatio(target.width / target.height);
      await windowManager.setBounds(target);
      await windowManager.setAlwaysOnTop(true);
      await _followUserAcrossSpaces(true);
      active.value = true;
    } catch (error) {
      debugPrint('Picture-in-picture: cannot shrink the window ($error)');
      await _putBack();
    } finally {
      _busy = false;
    }
  }

  /// Rend la fenêtre telle qu'elle était. Sans effet hors de l'image dans
  /// l'image : le lecteur l'appelle en quittant, qu'elle soit active ou non.
  static Future<void> exit() async {
    if (!active.value || _busy) return;
    _busy = true;
    try {
      await _putBack();
    } finally {
      _busy = false;
    }
  }

  static Future<void> _putBack() async {
    final restore = _restore;
    _restore = null;
    active.value = false;
    try {
      await windowManager.setAlwaysOnTop(false);
      await _followUserAcrossSpaces(false);
      // Rapport libéré avant de redonner la taille, sans quoi la fenêtre
      // restaurée serait contrainte à celui du film.
      await windowManager.setAspectRatio(0);
      if (restore == null) return;
      await windowManager.setBounds(restore.bounds);
      if (restore.wasMaximized) await windowManager.maximize();
      if (restore.wasFullScreen) await windowManager.setFullScreen(true);
    } catch (error) {
      debugPrint('Picture-in-picture: cannot restore the window ($error)');
    }
  }

  /// Sur macOS, la petite fenêtre suit l'utilisateur d'un bureau à l'autre et
  /// reste visible au-dessus d'une app en plein écran : c'est ce qui fait d'elle
  /// une image dans l'image plutôt qu'une fenêtre oubliée sur le bureau où elle
  /// a été ouverte. `window_manager.setVisibleOnAllWorkspaces` ne le fait pas
  /// pour une app qui a une icône dans le Dock (essayé : la fenêtre restait sur
  /// son bureau), d'où le canal natif de `MainFlutterWindow.swift`, qui rend
  /// l'app « accessoire » le temps de l'image dans l'image. Ailleurs, « toujours
  /// au premier plan » suffit.
  static Future<void> _followUserAcrossSpaces(bool follow) async {
    if (!AppPlatform.isMacOS) return;
    try {
      await _floatingWindow.invokeMethod<void>(
        'setFloating',
        <String, bool>{'floating': follow},
      );
    } catch (error) {
      // Sans cela la fenêtre reste au premier plan du bureau courant : moins
      // pratique, pas cassé.
      debugPrint('Picture-in-picture: cannot follow the desktops ($error)');
    }
  }

  static const MethodChannel _floatingWindow = MethodChannel(
    'onyx/floating_window',
  );

  /// Sort du plein écran et attend que ce soit fait. Sur macOS la sortie est
  /// animée et `setFullScreen(false)` rend la main au début : lire la taille de
  /// la fenêtre à ce moment-là donne celle d'une fenêtre en plein vol.
  static Future<void> _leaveFullScreen() async {
    await windowManager.setFullScreen(false);
    for (var i = 0; i < 30; i++) {
      if (!await windowManager.isFullScreen()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // Plein écran toujours annoncé après 1,5 s : on continue, la taille lue
    // sera approximative mais la bascule ne doit pas rester bloquée.
  }

  /// La zone visible de l'écran qui porte [bounds] (barre des tâches ou Dock
  /// exclus), ou à défaut celle de l'écran principal.
  static Future<Rect> _screenAround(Rect bounds) async {
    final retriever = ScreenRetriever.instance;
    try {
      final displays = await retriever.getAllDisplays();
      for (final display in displays) {
        final rect = _visibleRect(display);
        if (rect.contains(bounds.center)) return rect;
      }
      return _visibleRect(await retriever.getPrimaryDisplay());
    } catch (error) {
      debugPrint('Picture-in-picture: cannot read the screen ($error)');
      // Faute de savoir, le coin de la fenêtre elle-même : au moins visible.
      return bounds;
    }
  }

  static Rect _visibleRect(Display display) {
    final origin = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    return origin & size;
  }
}

class _Restore {
  const _Restore({
    required this.bounds,
    required this.wasMaximized,
    required this.wasFullScreen,
  });

  final Rect bounds;
  final bool wasMaximized;
  final bool wasFullScreen;
}
