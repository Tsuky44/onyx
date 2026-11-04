import 'package:flutter/services.dart';

import '../../utils/app_platform.dart';

/// Le droit de lire les vidéos du stockage partagé.
///
/// Seul Android le demande : `READ_MEDIA_VIDEO` depuis Android 13,
/// `READ_EXTERNAL_STORAGE` avant. Le dialogue est posé par `MainActivity`, sur
/// le canal `onyx/device` qu'il sert déjà, plutôt que par un plugin de
/// permissions qui en couvrirait vingt autres. Ailleurs, le dossier choisi par
/// l'utilisateur est lisible tel quel.
abstract final class DeviceVideoAccess {
  static const MethodChannel _channel = MethodChannel('onyx/device');

  static Future<bool> ensure() async {
    if (!AppPlatform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestVideoAccess') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Une version du code natif qui ne connaît pas la question : on tente
      // la lecture, et le dossier vide dira ce qui manque.
      return true;
    }
  }
}
