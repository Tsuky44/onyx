import '../../../models/models.dart';

/// Ce qui empêche la puce d'une Apple TV de décoder une image, et donc
/// AetherEngine de la confier à `AVPlayer` : sans décodeur matériel, le moteur
/// prend sa route logicielle, sans `AVPlayer` ni écran natif (spike Apple TV,
/// correction 1).
enum NativeTvDecodeObstacle {
  /// VC-1, MPEG-2, MPEG-4 Part 2, AV1 (sans décodeur sur l'Apple TV 4K
  /// actuelle), VP9…
  codec,

  /// Du H.264 au-delà de 8 bits, ou du HEVC au-delà de 10.
  bitDepth,

  /// Une chrominance en 4:2:2 ou en 4:4:4.
  chroma,

  /// Une image en deux trames.
  interlaced,

  /// Un Dolby Vision double couche (profil 7) quand le moteur est réglé pour
  /// lire sa couche d'amélioration, qu'il ne décode qu'en logiciel.
  dualLayerDolbyVision,
}

/// Ce qui empêche AVKit de décoder [video] en matériel, ou null quand il le
/// décode : du H.264 8 bits, du HEVC 8 ou 10 bits, en 4:2:0 progressif. Le
/// Dolby Vision 5, 8.1 et 8.4 est du HEVC ; le profil 7 se lit sur sa couche
/// de base, sauf si [dualLayerDolbyVision] demande la double couche.
///
/// Le doute laisse passer : un champ que le serveur ne dit pas (un serveur
/// d'avant, une sonde ancienne) ne fait pas transcoder un fichier qui se
/// lisait.
NativeTvDecodeObstacle? avKitDecodeObstacle(
  MediaVideoTrack video, {
  bool dualLayerDolbyVision = false,
}) {
  final codec = _canonicalCodec(video.codec);
  final maxDepth = switch (codec) {
    'h264' => 8,
    'hevc' => 10,
    _ => null,
  };
  if (maxDepth == null) return NativeTvDecodeObstacle.codec;
  if (_bitDepth(video) > maxDepth) return NativeTvDecodeObstacle.bitDepth;
  if (!_chroma420(video)) return NativeTvDecodeObstacle.chroma;
  if (video.interlaced) return NativeTvDecodeObstacle.interlaced;
  if (dualLayerDolbyVision && video.doviProfile == 7) {
    return NativeTvDecodeObstacle.dualLayerDolbyVision;
  }
  return null;
}

/// Un codec vidéo vide est inconnu, donc laissé passer : le moteur en
/// jugera. Les autres noms sont ceux de ffprobe.
String _canonicalCodec(String codec) {
  switch (codec.trim().toLowerCase()) {
    case '':
    case 'h264':
    case 'avc':
    case 'avc1':
      return 'h264';
    case 'hevc':
    case 'h265':
    case 'hvc1':
    case 'hev1':
    case 'dvh1':
    case 'dvhe':
      return 'hevc';
    default:
      return codec;
  }
}

/// La profondeur de [video] : celle du serveur, relue dans le format d'image
/// et le profil quand ils en disent plus (`yuv420p10le`, `High 10`).
int _bitDepth(MediaVideoTrack video) {
  final pixFmt = video.pixFmt.toLowerCase();
  final profile = video.profile.toLowerCase();
  var depth = video.bitDepth;
  if (pixFmt.contains('12le') ||
      pixFmt.contains('12be') ||
      profile.contains('12')) {
    depth = depth < 12 ? 12 : depth;
  } else if (pixFmt.contains('10le') ||
      pixFmt.contains('10be') ||
      pixFmt.startsWith('p010') ||
      profile.contains('10')) {
    depth = depth < 10 ? 10 : depth;
  }
  return depth;
}

/// Vrai pour le 4:2:0, et pour un format que le serveur n'a pas dit. Le
/// profil couvre une sonde sans format d'image (`High 4:2:2`, `Main 4:4:4`).
bool _chroma420(MediaVideoTrack video) {
  final pixFmt = video.pixFmt.toLowerCase();
  final profile = video.profile.toLowerCase();
  if (profile.contains('4:2:2') || profile.contains('4:4:4')) return false;
  if (pixFmt.isEmpty || pixFmt == 'unknown') return true;
  return pixFmt.startsWith('yuv420') ||
      pixFmt.startsWith('yuvj420') ||
      pixFmt.startsWith('nv12') ||
      pixFmt.startsWith('nv21') ||
      pixFmt.startsWith('p010') ||
      pixFmt.startsWith('p016');
}
