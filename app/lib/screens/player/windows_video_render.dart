import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/client_log.dart';
import '../../utils/app_platform.dart';

/// Le rendu vidéo choisi sous Windows (ADR-0158, phase 2).
///
/// Les deux rendus cohabitent. Le réglage est ouvert à tous, et vaut
/// Automatique par défaut, y compris pour qui ne l'a jamais touché
/// (décisions de Tsuky, pour un essai à grande échelle).
enum WindowsVideoRenderChoice {
  /// ANGLE et la recopie `d3d11va-copy` : le chemin d'avant (ADR-0095).
  legacy,

  /// Le rendu D3D11 de libmpv, toujours sans copie. Retombe sur ANGLE
  /// seulement si mpv refuse de créer le contexte ; une panne en lecture est
  /// journalisée, pas rattrapée : c'est le choix qui force D3D11.
  d3d11,

  /// D3D11, puis ANGLE, puis le logiciel. Une texture D3D11 qui ne montre
  /// rien, ou un périphérique perdu, fait passer la lecture en cours sur
  /// ANGLE, et une machine prise en défaut le reste jusqu'au prochain pilote.
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

/// Le choix du rendu vidéo sous Windows, et ce que l'app sait des pannes du
/// nouveau chemin sur cette machine.
abstract final class WindowsVideoRender {
  static const String _preferenceKey = 'windows_video_render';

  /// L'adaptateur et le pilote sur lesquels D3D11 n'a rien montré.
  static const String _failedAdapterKey = 'windows_d3d11_failed_adapter';

  static WindowsVideoRenderChoice _stored = WindowsVideoRenderChoice.auto;

  /// D3D11 a été pris en défaut sur cette machine : pendant cette session, ou
  /// lors d'une précédente avec le même adaptateur et le même pilote.
  static bool _d3d11Failed = false;

  /// L'échec vient du disque, pas de cette session.
  static bool _failureRemembered = false;

  /// `vendeur:appareil:pilote`, null tant que l'adaptateur n'est pas connu.
  static String? _adapterKey;

  /// L'adaptateur et son pilote, pour les journaux.
  static String adapterLabel = 'adaptateur inconnu';

  static bool get d3d11Failed => _d3d11Failed;

  /// Ce qui est enregistré : la valeur que montre le réglage.
  static WindowsVideoRenderChoice get stored => _stored;

  /// Ce qui s'applique vraiment à la prochaine lecture.
  static WindowsVideoRenderChoice get effective =>
      effectiveChoice(stored: _stored, isWindows: AppPlatform.isWindows);

  /// Ce que la sortie native doit essayer d'abord (`d3d11` ou `angle`), null
  /// hors de Windows.
  static String? get nativeRequest => requestFor(
        choice: effective,
        isWindows: AppPlatform.isWindows,
        d3d11Failed: _d3d11Failed,
      );

  /// Vrai quand une panne de D3D11 en pleine lecture doit faire passer cette
  /// lecture sur ANGLE : en Automatique seulement.
  static bool get fallsBackLive => effective == WindowsVideoRenderChoice.auto;

  /// Hors de Windows, rien ne change : l'ancien chemin, le seul qui existe.
  static WindowsVideoRenderChoice effectiveChoice({
    required WindowsVideoRenderChoice stored,
    required bool isWindows,
  }) =>
      isWindows ? stored : WindowsVideoRenderChoice.legacy;

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

  /// La clé sous laquelle un échec est retenu : l'adaptateur et la version de
  /// son pilote. Un pilote mis à jour change la clé, et D3D11 est retenté.
  /// Null si la réponse du plugin ne suffit pas à la former.
  static String? adapterKeyFor(Map<String, Object?>? adapter) {
    if (adapter == null) return null;
    final vendor = adapter['vendorId'];
    final device = adapter['deviceId'];
    final driver = adapter['driverVersion'];
    if (vendor is! int || device is! int || driver is! String) return null;
    if (driver.isEmpty) return null;
    String hex(int v) => v.toRadixString(16).padLeft(4, '0');
    return '${hex(vendor)}:${hex(device)}:$driver';
  }

  /// Retient l'échec de D3D11, et le dit dans le journal de la lecture, que
  /// le serveur reçoit (voir `PlaybackReporter`).
  ///
  /// [remember] l'écrit sur disque pour cet adaptateur et ce pilote : une
  /// machine qui ne montre rien en D3D11 ne doit pas redonner un écran noir à
  /// la première lecture de chaque lancement. Un périphérique perdu en cours
  /// de route (TDR) ne l'est que pour la session : la cause peut être
  /// passagère.
  static Future<void> noteD3D11Failure(String reason,
      {required bool remember}) async {
    _d3d11Failed = true;
    final next = requestFor(
      choice: effective,
      isWindows: AppPlatform.isWindows,
      d3d11Failed: true,
    );
    ClientLog.error('Rendu vidéo : échec D3D11 — $reason · $adapterLabel · '
        'réglage ${effective.name}, lectures suivantes en $next'
        '${remember ? ', retenu pour ce pilote' : ''}');
    final key = _adapterKey;
    if (!remember || key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_failedAdapterKey, key);
    } catch (e) {
      // L'échec reste connu pour la session ; seul le prochain lancement le
      // redécouvrira.
      debugPrint('WindowsVideoRender: échec non retenu: $e');
    }
  }

  /// Le chemin de la lecture en cours, pour le diagnostic.
  static VideoRenderPath? active;

  /// Lit le réglage, l'adaptateur et l'échec retenu. Une fois, au lancement,
  /// avant la première lecture.
  static Future<void> initialize() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_preferenceKey);
      _stored = WindowsVideoRenderChoice.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => WindowsVideoRenderChoice.auto,
      );
    } catch (e) {
      // Préférences illisibles : le défaut de tout le monde.
      debugPrint('WindowsVideoRender: réglage illisible: $e');
      _stored = WindowsVideoRenderChoice.auto;
    }
    if (!AppPlatform.isWindows) return;
    try {
      final adapter = await VideoController.windowsGraphicsAdapter()
          .timeout(const Duration(seconds: 2));
      _adapterKey = adapterKeyFor(adapter);
      if (adapter != null) {
        adapterLabel = '${adapter['description'] ?? '?'} '
            '(pilote ${adapter['driverVersion'] ?? '?'})';
      }
    } catch (e) {
      // Sans adaptateur connu, rien n'est retenu ni relu : D3D11 est essayé,
      // et la retombée en lecture reste là.
      debugPrint('WindowsVideoRender: adaptateur inconnu: $e');
    }
    final key = _adapterKey;
    if (key != null && prefs?.getString(_failedAdapterKey) == key) {
      _d3d11Failed = true;
      _failureRemembered = true;
    }
    debugPrint('WindowsVideoRender: ${describe()}');
  }

  static Future<void> setChoice(WindowsVideoRenderChoice value) async {
    _stored = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, value.name);
  }

  /// `auto → d3d11 · NVIDIA GeForce… (pilote 32.0.15.6094)` : le réglage, le
  /// chemin demandé, l'adaptateur, et un échec connu.
  static String describe() => '${effective.name} → ${nativeRequest ?? '-'} · '
      '$adapterLabel'
      '${_failureRemembered ? ' · D3D11 en échec retenu pour ce pilote' : _d3d11Failed ? ' · D3D11 en échec' : ''}';

  @visibleForTesting
  static void reset({
    WindowsVideoRenderChoice stored = WindowsVideoRenderChoice.auto,
    bool d3d11Failed = false,
  }) {
    _stored = stored;
    _d3d11Failed = d3d11Failed;
    _failureRemembered = false;
    _adapterKey = null;
    adapterLabel = 'adaptateur inconnu';
    active = null;
  }
}
