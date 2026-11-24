part of 'use_player_controller.dart';

/// Lecture et pause, telles qu'on les a demandées. Toute demande passe par
/// ici : l'appui de l'écran, la minuterie de veille, l'autre appareil, la
/// séance partagée. Personne d'autre n'appelle `session.play()` ni
/// `session.pause()` une fois la lecture lancée, sans quoi la demande et le
/// moteur se contrediraient à la prochaine bascule.
extension PlayerControllerTransport on PlayerController {
  /// Vrai tant que la dernière demande est « lire », y compris pendant que le
  /// moteur charge, cherche ou remplit son tampon. C'est ce que montre le
  /// bouton, et l'état dans lequel une source se rouvre : changement de
  /// qualité, recherche hors de la session HLS, reprise après une coupure.
  bool get wantsPlay => _intent.wantsPlay;

  /// Un appui sur lecture/pause. Voir [PlaybackIntent.toggle].
  void togglePlayPause() =>
      _carry(_intent.toggle(EngineActivity.of(session)));

  /// Lire, voulu comme tel. Se redemande sans risque : un moteur qui lit déjà
  /// n'en fait rien, et un moteur arrêté dans notre dos repart.
  void play() {
    _intent.ask(play: true);
    _carry(true);
  }

  /// Mettre en pause, voulu comme tel. Porté au moteur même s'il ne lit pas :
  /// une pause demandée pendant un chargement doit tenir quand il se termine.
  void pause() {
    _intent.ask(play: false);
    _carry(false);
  }

  void _carry(bool play) {
    final mirrored = isPlaying != play;
    _setPlaying(play);
    // Le bouton suit la demande, pas ce que le moteur rapporte : l'écran se
    // redessine aussi quand ce rapport n'a pas bougé.
    if (!mirrored) _onPlayingChanged?.call();
    if (play) {
      // Une reprise regarnit le tampon : ce n'est pas la ligne qui cale.
      _noteDisturbance();
      session.play();
    } else {
      session.pause();
    }
  }
}
