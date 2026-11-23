import 'dart:async';

/// Garde une seule ressource coûteuse prête à resservir, mais pas pour toujours.
///
/// Le pool du lecteur gardait son moteur mpv de côté pour toute la vie de
/// l'app : préparé trois secondes après le lancement, puis rendu après chaque
/// film. Un contexte libmpv, ses fils de décodage et, après un film, ses
/// surfaces vidéo restaient en mémoire des heures pour une lecture qui ne
/// venait peut-être jamais. Passé [limit] sans que personne ne la reprenne, la
/// ressource est jetée par [discard] ; la suivante se reconstruit à la demande.
class IdleHold<T extends Object> {
  IdleHold({required this.limit, required this.discard});

  /// Le temps qu'une ressource posée ici attend d'être reprise.
  final Duration limit;

  /// Libère une ressource que personne n'a reprise à temps.
  final void Function(T) discard;

  T? _held;
  Timer? _timer;

  /// Vrai quand une ressource attend.
  bool get isHolding => _held != null;

  /// La ressource qui attend, sans la reprendre.
  T? get peek => _held;

  /// Pose [value] et relance le délai. L'appelant s'assure de n'en poser
  /// qu'une : une ressource déjà là serait remplacée sans être libérée.
  void put(T value) {
    _held = value;
    _timer?.cancel();
    _timer = Timer(limit, _expire);
  }

  /// Reprend la ressource qui attend, s'il y en a une.
  T? take() {
    _timer?.cancel();
    _timer = null;
    final value = _held;
    _held = null;
    return value;
  }

  void _expire() {
    _timer = null;
    final value = _held;
    _held = null;
    if (value != null) discard(value);
  }
}
