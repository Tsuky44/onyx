import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/models.dart';
import '../../../services/playback_capabilities.dart';
import '../web_quality.dart';
import 'native_tv_decoding.dart';

/// La source d'une lecture que l'écran natif d'Apple TV doit pouvoir montrer
/// (ADR-0106).
///
/// Le fichier tel quel va à AetherEngine, qui le confie à `AVPlayer` quand la
/// puce le décode. Sinon le moteur prend sa route logicielle, sans `AVPlayer`
/// ni écran natif. Pour ces sources-là, la lecture part dans une session HLS
/// que le serveur produit dans ce qu'AVPlayer décode en matériel : le moteur
/// la passe à AVPlayer tel quel (route `remoteBypass`), et l'écran natif
/// tient.
///
/// Décidé avant d'ouvrir quoi que ce soit : ouvrir le fichier d'abord
/// présenterait l'écran natif sur la route logicielle, qui le refuse pour de
/// bon (`unavailable/softwareRoute`), et paierait un démarrage pour rien. La
/// liste des pistes part donc avec le ticket, et la décision l'attend au plus
/// [decisionBudget].
class NativeTvSource {
  NativeTvSource({required this.eligible});

  /// L'écran natif servira : Apple TV, réglage Natif, moteur AetherEngine.
  final bool eligible;

  /// Ce que l'ouverture attend la liste des pistes. Au-delà, le fichier est
  /// ouvert tel quel, comme avant : la lecture prime sur l'écran.
  static const decisionBudget = Duration(milliseconds: 1500);

  Future<MediaTracks?>? _prefetch;
  NativeTvDecodeObstacle? _obstacle;
  bool _gaveUp = false;

  /// Ce qui a fait choisir le transcodage, ou null.
  NativeTvDecodeObstacle? get obstacle => _gaveUp ? null : _obstacle;

  /// Les sessions de cette lecture se demandent avec les capacités de
  /// l'écran natif.
  bool get transcodes => obstacle != null;

  /// Les capacités à déclarer au serveur, ou null pour celles de l'appareil.
  PlaybackCapabilities? get capabilities =>
      transcodes ? PlaybackCapabilities.aetherNativeTv : null;

  /// Lance la liste des pistes avec le ticket, là seulement où elle servira
  /// à décider. [streaming] : un fichier téléchargé se lit tel quel.
  void prefetch(Future<MediaTracks?> Function() load,
      {required bool streaming}) {
    if (!eligible || !streaming) return;
    final pending = load();
    // Relue plus bas ; sans preneur si l'écran se ferme avant.
    pending.ignore();
    _prefetch = pending;
  }

  /// Si le fichier ne doit pas être ouvert : une session HLS partira quand la
  /// liste des pistes sera lue par le contrôleur.
  Future<bool> defersOpen() async {
    final pending = _prefetch;
    if (pending == null) return false;
    try {
      final video = (await pending.timeout(decisionBudget))?.video;
      _obstacle = video == null ? null : avKitDecodeObstacle(video);
    } catch (e) {
      // Liste en retard ou en échec : le fichier s'ouvre tel quel.
      debugPrint('Lecteur natif : pistes pas lues à temps ($e), fichier '
          'ouvert tel quel');
      return false;
    }
    return _obstacle != null;
  }

  /// La liste des pistes : celle qui est déjà partie, sinon [load]. Un
  /// préchargement en échec ne prive pas le lecteur de ses menus.
  Future<MediaTracks?> tracks(Future<MediaTracks?> Function() load) {
    final pending = _prefetch;
    if (pending == null) return load();
    return pending.catchError((Object _) => load());
  }

  /// Le barreau de la session : celui de la résolution d'origine, au plus
  /// 1080p. L'image est réencodée de toute façon, et un serveur sans GPU ne
  /// tient pas ce réencodage en 4K (le même plafond que l'ADR-0060).
  String quality(int sourceHeight) =>
      qualityForSourceHeight(sourceHeight > 1080 ? 1080 : sourceHeight);

  /// La session n'a pas pu s'ouvrir : le fichier est lu tel quel, sur la
  /// route logicielle et l'interface Onyx, et les sessions suivantes
  /// reprennent les capacités de l'appareil.
  void giveUp() => _gaveUp = true;
}
