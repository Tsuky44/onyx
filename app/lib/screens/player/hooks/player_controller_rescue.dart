part of 'use_player_controller.dart';

/// Le rattrapage d'une lecture figée après sa première image. La décision et
/// l'attente sont dans [PlaybackRescue] ; ici, seulement ce que fait chaque
/// échelon.
extension PlayerControllerRescue on PlayerController {
  PlaybackRescue _newRescue() => PlaybackRescue(
        waiting: () => isBuffering,
        // Avant la première image, c'est le délai de démarrage qui veille.
        busy: () =>
            !hasFirstFrame ||
            isSwitchingQuality ||
            _hlsSwapInFlight ||
            (_cuts?.isRecovering ?? false),
        positionSeconds: () => position.inSeconds,
        alive: () => !_disposed,
        run: _runRescue,
      );

  /// Une panne du moteur après la première image, qui n'est pas une source
  /// coupée : elle n'allait qu'au journal, sous un écran noir.
  void _rescueAfterFailure(PlaybackFailure failure) {
    ClientLog.error('Player: panne en cours de lecture — $failure');
    _rescueFailure = failure;
    _rescue?.noteFailure(
      position.inSeconds,
      undecodable: failure.kind == PlaybackFailureKind.unsupported,
    );
  }

  Future<bool> _runRescue(RescueStep step, int seconds) async {
    switch (step) {
      case RescueStep.reopen:
        // Un téléchargement n'a pas de flux à redemander au serveur.
        if (_localFilePath != null) return false;
        ClientLog.error('Player: lecture figée à ${seconds}s — flux rouvert');
        try {
          return await _reopenAfterCut(seconds);
        } catch (_) {
          // L'anneau du changement de qualité ne doit pas rester allumé sur
          // une réouverture qui n'a pas eu lieu.
          isSwitchingQuality = false;
          _onQualitySwitchingChanged?.call();
          rethrow;
        }
      case RescueStep.transcode:
        // Déjà transcodé, ou un fichier local que le serveur n'a pas : rien
        // d'autre à ouvrir.
        if (currentQuality != null || _localFilePath != null) return false;
        final quality = qualityForSourceHeight(mediaTracks?.video?.height ?? 0);
        ClientLog.error('Player: lecture figée à ${seconds}s — repli HLS '
            '$quality');
        _directPlayRuledOut = true;
        _autoCeilingKey = quality;
        await switchToQuality(quality, startSeconds: seconds);
        return true;
      case RescueStep.giveUp:
        ClientLog.error('Player: lecture figée à ${seconds}s — abandon');
        // Pendant que la séance est encore vivante côté serveur — voir
        // [PlaybackReporter.flushLogs].
        final api = _apiClient;
        if (api != null) _reporter.flushLogs(api);
        rescueExhausted = true;
        _onFailure?.call();
        return true;
    }
  }
}
