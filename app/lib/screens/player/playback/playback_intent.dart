import 'playback_session.dart';

/// Ce que le moteur fait à l'instant où l'on appuie sur lecture/pause.
enum EngineActivity {
  /// L'image défile.
  playing,

  /// Il charge, cherche ou remplit son tampon : il ne lit pas, et personne
  /// ne l'a mis en pause pour autant.
  waiting,

  /// Il ne lit pas et n'attend rien : en pause, à l'arrêt, ou tombé.
  atRest;

  static EngineActivity of(PlaybackSession session) {
    if (session.isPlaying) return EngineActivity.playing;
    return session.isBuffering ? EngineActivity.waiting : EngineActivity.atRest;
  }
}

/// La dernière demande faite au lecteur : lire, ou rester en pause.
///
/// Retenue ici, jamais relue du moteur (ADR du 2026-11-23). AetherEngine et
/// ExoPlayer ne disent « je lis » que lorsque l'image défile : pendant un
/// chargement, une recherche, une remise en tampon ou une bascule de qualité,
/// ils rapportent `isPlaying = false` alors que personne n'a mis en pause.
/// Le lecteur recopiait ce rapport et en tirait le sens du prochain appui.
/// Sur une Apple TV, un appui pendant l'attente envoyait donc « lecture » à
/// qui voulait mettre en pause, le suivant « pause » à qui voulait lire, et
/// une bascule rouvrait toujours en lecture, même derrière une pause.
///
/// Seules les demandes la changent : un appui, une décision du lecteur
/// (minuterie, autre appareil, séance partagée). Ce que le moteur rapporte
/// ne sert qu'à lire un appui quand il est stable, voir [toggle].
class PlaybackIntent {
  PlaybackIntent({bool wantsPlay = true}) : _wantsPlay = wantsPlay;

  bool _wantsPlay;

  /// Vrai tant que la dernière demande est « lire ». C'est ce que montre le
  /// bouton lecture/pause, et l'état dans lequel une source se rouvre.
  bool get wantsPlay => _wantsPlay;

  /// Une demande explicite : lire ([play] vrai) ou mettre en pause.
  void ask({required bool play}) => _wantsPlay = play;

  /// Un appui sur lecture/pause. Retient et rend ce qu'il demande.
  ///
  /// Un moteur stable dit vrai, et l'appui fait ce que l'écran montre : il
  /// met en pause une image qui défile, il relance un moteur au repos (une
  /// pause, ou une lecture que le système a arrêtée sans prévenir). Un moteur
  /// qui attend ne dit rien de ce qu'on lui a demandé : l'appui inverse alors
  /// la dernière demande, celle que le bouton affiche.
  bool toggle(EngineActivity engine) {
    _wantsPlay = switch (engine) {
      EngineActivity.playing => false,
      EngineActivity.atRest => true,
      EngineActivity.waiting => !_wantsPlay,
    };
    return _wantsPlay;
  }
}
