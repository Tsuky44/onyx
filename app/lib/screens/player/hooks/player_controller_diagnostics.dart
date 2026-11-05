part of 'use_player_controller.dart';

/// Ce que le lecteur journalise de lui-même une fois l'image là, et en
/// partant : le décodeur réellement pris, la cadence, les images perdues.
extension PlayerControllerDiagnostics on PlayerController {
  /// Runs once the picture is actually on screen.
  ///
  /// Two things need the decoder to have committed to a file, and neither can
  /// be answered before it has: which rate the panel should run at, and what
  /// the engine actually chose to decode with.
  Future<void> _onPictureLive() async {
    if (AppPlatform.isWeb || _disposed) return;

    final info = await session.readDiagnostics();
    final fps = info.containerFps ?? 0;
    if (fps > 0) await DisplayFrameRate.matchTo(fps);

    final params = session.videoParams;
    // The one line that says what is really happening. The decoder reported
    // here is the engine's own answer, not what it was asked for: one that
    // failed to start falls back silently, and the setting tells you nothing
    // about whether a frame ever reached the GPU that way.
    debugPrint('Playback: ${params.width}x${params.height} '
        '${info.videoCodec ?? '?'} @ ${fps > 0 ? '${fps.toStringAsFixed(3)}fps' : 'fps inconnu'} '
        '· hwdec=${info.hardwareDecoder} '
        '(asked ${HardwareDecoding.describe()}) · '
        'buffers=${PlaybackProfiles.current.label}'
        '${DisplayFrameRate.requested != null ? ' · display=${DisplayFrameRate.requested}Hz' : ''}');

    // Read, never written. Logged because "the sound is not right" is otherwise
    // unanswerable: this line says whether the device received six channels and
    // folded them itself — the case the dialogue-forward mix levels apply to —
    // or was handed a stereo pair the server had already folded for it.
    debugPrint('Audio: ${info.sourceChannels ?? '?'}ch source → '
        '${info.outputChannels ?? '?'}ch out · ${info.audioCodec ?? '?'}');

    // The engine's own chance to correct what it just observed of itself.
    await session.onPictureLive();
  }

  /// Dropped-frame counters, logged on the way out.
  ///
  /// "It stutters" is otherwise a matter of opinion; these two numbers are not.
  Future<void> _logDropCounters() async {
    if (AppPlatform.isWeb) return;
    final info = await session.readDiagnostics();
    final display = info.droppedByDisplay ?? 0;
    final decoder = info.droppedByDecoder ?? 0;
    if (display == 0 && decoder == 0) return;
    debugPrint('Playback: dropped frames — display=$display decoder=$decoder');
  }
}
