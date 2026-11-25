part of 'use_player_controller.dart';

/// Ce que l'appareil ne décode pas en Direct Play passe par le serveur : une
/// piste audio que le moteur laisserait muette, et une image que la puce ne
/// décode pas en matériel.
///
/// Pour l'image, le cas visé est l'Apple TV HD, sans décodeur HEVC :
/// AetherEngine y lit le fichier en logiciel et l'image saccade. Elle se
/// décide avant d'ouvrir le fichier. Voir [serverQualityForUndecodableVideo].
extension PlayerControllerDirectPlayGate on PlayerController {
  /// Ce qu'on laisse à la liste des pistes pour arriver avant d'ouvrir. Elle
  /// part en même temps que le ticket et revient d'ordinaire avec lui ; au-delà,
  /// le fichier s'ouvre tel quel et la liste, à son arrivée, tranche encore.
  static const _videoGateWait = Duration(milliseconds: 1500);

  /// La qualité à demander au serveur, ou null si le fichier se lit tel quel.
  /// Un fichier téléchargé reste lu tel quel : hors ligne, il n'y a pas de
  /// serveur pour le transcoder.
  String? get _serverQualityForVideo => _hlsOnly || _localFilePath != null
      ? null
      : serverQualityForUndecodableVideo(
          PlaybackCapabilitiesResolver.current, mediaTracks?.video);

  bool _directPlayCannotDecodeVideo() =>
      currentQuality == null && _serverQualityForVideo != null;

  /// Si l'ouverture du fichier est à sauter : la puce ne le décoderait qu'en
  /// logiciel. Sans attente sur un appareil qui lit tout ; sur les autres,
  /// [tracks] est déjà en route depuis le début de `init`.
  Future<bool> _mustStartOnServer(Future<MediaTracks?> tracks) async {
    if (_hlsOnly || _localFilePath != null) return false;
    final capabilities = PlaybackCapabilitiesResolver.current;
    if (capabilities.directPlayVideo == null) return false;
    try {
      final known = await tracks.timeout(_videoGateWait);
      return serverQualityForUndecodableVideo(capabilities, known?.video) !=
          null;
    } catch (_) {
      // Liste pas venue à temps, ou serveur muet : le fichier s'ouvre tel
      // quel, ce qui marchait avant ce garde.
      return false;
    }
  }

  /// Passe en HLS pour que le serveur rende l'image en H.264, à la seconde où
  /// en est [position] : le point de reprise quand rien n'a encore été ouvert.
  ///
  /// [openFileOnFailure] : rien d'autre n'est ouvert. Si le serveur refuse la
  /// session, le fichier s'ouvre quand même : une image qui saccade vaut mieux
  /// qu'une attente sans fin.
  Future<void> _transcodeForUndecodableVideo(
      {bool openFileOnFailure = false}) async {
    final quality = _serverQualityForVideo;
    if (quality == null) return;
    final video = mediaTracks?.video;
    debugPrint('Player: ${video?.codec} ${video?.height}p sans décodeur '
        'matériel (${PlaybackCapabilitiesResolver.current.label}) : '
        'HLS $quality');
    // L'Auto ne ramènera pas la lecture sur une image qui saccade.
    _directPlayRuledOut = true;
    _autoCeilingKey = quality;
    await switchToQuality(quality);
    if (!openFileOnFailure) return;
    if (_disposed || currentQuality != null || _hlsSwapInFlight) return;
    final api = _apiClient;
    final media = _media;
    if (api == null || media == null) return;
    debugPrint('Player: session du serveur refusée, ouverture du fichier');
    await _openDirect(_directPlaySource(api, media.id), position.inSeconds,
        play: true);
  }

  /// Si la piste [index] serait muette en Direct Play.
  ///
  /// Le moteur local la liste et la sélectionne sans broncher — le démuxeur la
  /// connaît — puis n'a rien pour la décoder : l'image défile, sans son et sans
  /// erreur. C'est le cas du TrueHD (Atmos compris) sous mpv, et du TrueHD, du
  /// DTS ou de l'(E-)AC-3 sous ExoPlayer quand l'appareil n'a ni décodeur ni
  /// passthrough pour eux.
  bool _directPlayCannotDecodeAudio(int index) {
    if (_hlsOnly || currentQuality != null) return false;
    final audio = mediaTracks?.audio ?? const <MediaAudioTrack>[];
    if (index < 0 || index >= audio.length) return false;
    return !PlaybackCapabilitiesResolver.current
        .decodesInDirectPlay(audio[index].codec);
  }

  /// Passe en HLS à la résolution de la source, pour que le serveur décode la
  /// piste que le moteur local ne sait pas lire.
  ///
  /// La résolution d'origine est ce qui laisse l'image recopiée plutôt que
  /// ré-encodée : seul l'audio coûte alors quelque chose au serveur.
  Future<void> _transcodeForUndecodableAudio() async {
    final track = mediaTracks!.audio[_selectedAudioIndex];
    final quality = nativeTierKey(mediaTracks!.video?.height ?? 0);
    debugPrint("Player: ${track.codec} illisible en Direct Play "
        "(${PlaybackCapabilitiesResolver.current.label}) — HLS $quality");
    // L'Auto ne ramènera pas la lecture sur une piste muette.
    _directPlayRuledOut = true;
    _autoCeilingKey = quality;
    await switchToQuality(quality);
  }
}
