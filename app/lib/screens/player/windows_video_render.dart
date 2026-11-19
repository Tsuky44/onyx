import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/client_log.dart';
import '../../utils/app_platform.dart';

/// Ce qu'un admin a choisi pour le rendu vidéo de Windows (ADR-0158, phase 2).
///
/// Les deux chemins cohabitent le temps de les comparer sur de vraies
/// machines : la phase 2 a commencé avant que la phase 1 ait passé sa porte,
/// par choix de Tsuky. Le choix est réservé aux admins, et tout le monde reste
/// sur l'ancien chemin tant qu'un admin n'en a pas décidé autrement.
enum WindowsVideoRenderChoice {
  /// ANGLE et la recopie `d3d11va-copy` : le chemin de toujours (ADR-0095).
  legacy,

  /// Le rendu D3D11 de libmpv et `auto-safe`. Retombe sur ANGLE seulement si
  /// mpv refuse de créer le contexte.
  d3d11,

  /// D3D11, puis ANGLE, puis le logiciel, et la retombée sur panne : une
  /// texture D3D11 sans image fait passer les lectures suivantes sur ANGLE.
  auto,
}

/// Le chemin que la sortie native a réellement retenu.
enum VideoRenderPath {
  d3d11,
  angle,
  software;

  /// Ce que dit le plugin Windows (`d3d11`, `angle`, `sw`) ; null pour toute
  /// autre valeur, y compris d'une plateforme qui ne le dit pas.
  static VideoRenderPath? parse(String? raw) => switch (raw) {
        'd3d11' => VideoRenderPath.d3d11,
        'angle' => VideoRenderPath.angle,
        'sw' => VideoRenderPath.software,
        _ => null,
      };
}

/// Le choix du rendu vidéo sous Windows, et la retombée quand le nouveau
/// chemin ne montre rien.
abstract final class WindowsVideoRender {
  static const String _preferenceKey = 'windows_video_render';

  static WindowsVideoRenderChoice _stored = WindowsVideoRenderChoice.legacy;

  /// Vrai quand le compte connecté est admin. Posé par l'app à chaque
  /// changement de compte (`main.dart`).
  static bool adminAllowed = false;

  /// Une texture D3D11 a été prise sans image pendant cette session.
  ///
  /// Le pendant de [HardwareDecoding.zeroCopyFailed] sur Android, et gardé en
  /// mémoire pour la même raison : c'est une observation, pas le choix de
  /// l'admin. Un pilote mis à jour retrouve sa chance au lancement suivant.
  static bool _d3d11Failed = false;

  static bool get d3d11Failed => _d3d11Failed;

  /// Ce qui est enregistré, admin ou pas : la valeur que montre le réglage.
  static WindowsVideoRenderChoice get stored => _stored;

  /// Ce qui s'applique vraiment à la prochaine lecture.
  static WindowsVideoRenderChoice get effective => effectiveChoice(
        stored: _stored,
        isWindows: AppPlatform.isWindows,
        isAdmin: adminAllowed,
      );

  /// Ce que la sortie native doit essayer d'abord (`d3d11` ou `angle`), null
  /// hors de Windows.
  static String? get nativeRequest => requestFor(
        choice: effective,
        isWindows: AppPlatform.isWindows,
        d3d11Failed: _d3d11Failed,
      );

  /// Un non-admin, ou un appareil qui n'est pas sous Windows, reste sur
  /// l'ancien chemin quoi qu'il y ait d'enregistré : seul un admin qui change
  /// le réglage passe sur le nouveau.
  static WindowsVideoRenderChoice effectiveChoice({
    required WindowsVideoRenderChoice stored,
    required bool isWindows,
    required bool isAdmin,
  }) =>
      isWindows && isAdmin ? stored : WindowsVideoRenderChoice.legacy;

  /// Le chemin demandé à la sortie native pour [choice].
  static String? requestFor({
    required WindowsVideoRenderChoice choice,
    required bool isWindows,
    bool d3d11Failed = false,
  }) {
    if (!isWindows) return null;
    return switch (choice) {
      WindowsVideoRenderChoice.legacy => 'angle',
      WindowsVideoRenderChoice.d3d11 => 'd3d11',
      WindowsVideoRenderChoice.auto => d3d11Failed ? 'angle' : 'd3d11',
    };
  }

  /// Vrai quand ce que la sortie a rendu montre une texture D3D11 restée
  /// vide : aucun rendu de mpv n'y a réussi. [info] est la réponse de
  /// `VideoOutputManager.GetRenderInfo`.
  static bool isBlankD3D11(Map<String, Object?>? info) {
    if (info == null) return false;
    if (VideoRenderPath.parse(info['renderApi'] as String?) !=
        VideoRenderPath.d3d11) {
      return false;
    }
    final rendered = info['renderedFrames'];
    return rendered is int && rendered == 0;
  }

  /// Le délai laissé à la texture, après la première image annoncée, pour
  /// avoir rendu quelque chose. mpv rend avant même que l'horloge tourne :
  /// passé ce délai, une texture vide est une panne, pas une attente.
  static const Duration startupGrace = Duration(seconds: 3);

  /// Lit ce que la sortie a rendu une fois [startupGrace] écoulé, et marque
  /// l'appareil si la texture D3D11 est restée vide.
  static Future<void> verifyFirstFrames(
      Future<Map<String, Object?>?> Function() renderInfo) async {
    if (!AppPlatform.isWindows) return;
    await Future<void>.delayed(startupGrace);
    Map<String, Object?>? info;
    try {
      info = await renderInfo();
    } catch (e) {
      // Une sortie déjà détruite (lecture fermée entre-temps) ne répond plus :
      // il n'y a rien à juger.
      debugPrint('WindowsVideoRender: rendus illisibles: $e');
      return;
    }
    if (!isBlankD3D11(info)) return;
    noteD3D11Failure('aucune image rendue en ${startupGrace.inSeconds}s '
        '(${info?['failedFrames'] ?? '?'} rendus ratés)');
  }

  /// Marque l'appareil. En automatique, les lectures suivantes de la session
  /// prennent ANGLE ; en « Nouveau », l'admin a demandé D3D11 et le garde.
  static void noteD3D11Failure(String reason) {
    _d3d11Failed = true;
    final next = requestFor(
      choice: effective,
      isWindows: AppPlatform.isWindows,
      d3d11Failed: true,
    );
    ClientLog.error('Rendu vidéo : texture D3D11 sans image — $reason · '
        'réglage ${effective.name}, lecture suivante en $next');
  }

  /// Le chemin de la lecture en cours, pour le diagnostic.
  static VideoRenderPath? active;

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_preferenceKey);
      _stored = WindowsVideoRenderChoice.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => WindowsVideoRenderChoice.legacy,
      );
    } catch (e) {
      // Préférences illisibles : l'ancien chemin, celui de tout le monde.
      debugPrint('WindowsVideoRender: réglage illisible: $e');
      _stored = WindowsVideoRenderChoice.legacy;
    }
  }

  static Future<void> setChoice(WindowsVideoRenderChoice value) async {
    _stored = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, value.name);
  }

  /// `auto → d3d11` : le réglage qui s'applique et le chemin demandé.
  static String describe() => '${effective.name} → ${nativeRequest ?? '-'}'
      '${_d3d11Failed ? ' (D3D11 en panne)' : ''}';

  @visibleForTesting
  static void reset({
    WindowsVideoRenderChoice stored = WindowsVideoRenderChoice.legacy,
    bool admin = false,
  }) {
    _stored = stored;
    adminAllowed = admin;
    _d3d11Failed = false;
    active = null;
  }
}
