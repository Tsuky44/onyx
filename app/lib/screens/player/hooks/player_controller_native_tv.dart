part of 'use_player_controller.dart';

/// L'écran natif d'Apple TV face à une source que sa puce ne décode pas
/// (ADR-0106) : la lecture part en HLS, réencodée dans ce qu'AVPlayer décode,
/// plutôt que sur la route logicielle d'AetherEngine, qui n'a pas d'écran
/// natif. Voir [NativeTvSource].
extension PlayerControllerNativeTv on PlayerController {
  /// La session n'est pas encore ouverte : rien n'est chargé dans le moteur,
  /// comme sur le web avant sa première session.
  bool get _awaitsNativeTvSession =>
      _nativeTvSource.transcodes && currentQuality == null;

  /// La liste des pistes, sans la redemander quand l'ouverture l'a déjà fait
  /// partir pour décider de la source.
  Future<MediaTracks?> _loadTracksOnce(ApiClient api, int mediaId) =>
      _nativeTvSource.tracks(() => _loadTracks(api, mediaId));

  /// Les lectures qui ne s'ouvrent qu'en HLS, une fois la piste audio
  /// choisie : le web, et l'écran natif face à une source sans décodeur.
  Future<bool> _startHlsFirst() async =>
      await _startWebTranscode() || await _startNativeTvTranscode();

  /// Ouvre la première session de cette lecture, une fois la piste audio
  /// choisie. Faux quand il n'y a rien à faire, ou quand la session a échoué
  /// et que le fichier a été ouvert tel quel à la place : la suite du
  /// chargement des pistes vaut alors comme pour tout Direct Play.
  Future<bool> _startNativeTvTranscode() async {
    if (!_awaitsNativeTvSession || _hlsSwapInFlight) return false;
    final quality = _nativeTvSource.quality(mediaTracks?.video?.height ?? 0);
    // La reprise fait partie de la session, comme sur le web : le reste du
    // film n'existe pas encore pour qu'on y cherche.
    final startSeconds = await _resolveWebResumeSeconds();
    if (_disposed) return true;
    debugPrint('Lecteur natif : ${mediaTracks?.video?.codec} '
        '(${_nativeTvSource.obstacle?.name}) sans décodeur matériel — '
        'HLS $quality depuis ${startSeconds}s');
    // L'Auto ne ramènera pas la lecture sur la route logicielle.
    _directPlayRuledOut = true;
    _autoCeilingKey = quality;
    await switchToQuality(quality, startSeconds: startSeconds);
    if (_disposed || currentQuality != null) return true;

    ClientLog.error('Lecteur natif : session transcodée impossible, '
        'fichier ouvert tel quel');
    _nativeTvSource.giveUp();
    _directPlayRuledOut = false;
    _autoCeilingKey = null;
    final api = _apiClient;
    final media = _media;
    if (api == null || media == null) return true;
    try {
      await session.open(
        _directPlaySource(api, media.id),
        start: startSeconds > 0 ? Duration(seconds: startSeconds) : null,
        play: _playbackStarted,
      );
      _openedAtSeconds = startSeconds;
      position = Duration(seconds: startSeconds);
    } catch (e) {
      ClientLog.error(
          'Player: failed to open stream: ${redactPlaybackDiagnostic(e)}');
    }
    return false;
  }
}
