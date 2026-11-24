import 'dart:async';

/// Un échelon du rattrapage, du moins coûteux au dernier recours.
enum RescueStep {
  /// Rouvrir le même flux à la seconde visée.
  reopen,

  /// Quitter le Direct Play pour le transcodage du serveur.
  transcode,

  /// Tout a été essayé : l'écran le dit, et propose de réessayer.
  giveUp,
}

/// Ce qu'on fait d'une lecture qui, après sa première image, ne repart plus :
/// une recherche qui n'aboutit pas, ou une panne que le moteur annonce.
///
/// Vu sur une Apple TV : un retour en arrière figeait l'image, l'anneau
/// d'attente tournait sans fin, puis l'écran passait au noir, et il fallait
/// quitter le lecteur pour relancer. Passé la première image, plus rien ne
/// veillait : le délai de démarrage est désarmé, et une panne du moteur qui
/// n'était pas une source coupée (`StreamCutRecovery`) n'allait qu'au journal.
/// Le moteur, lui, retient l'horloge sur la cible d'une recherche qui ne se
/// pose pas et se dit « en tampon », indéfiniment.
///
/// La règle : une recherche encore en attente [patience] plus tard, sans que
/// la position ait quitté sa cible, monte un échelon ([RescueStep]) ; une
/// panne annoncée le monte tout de suite. Une lecture qui a repris remet
/// l'échelle à zéro. La décision est ici, l'exécution chez l'appelant
/// ([run]).
class PlaybackRescue {
  PlaybackRescue({
    required this.waiting,
    required this.busy,
    required this.positionSeconds,
    required this.run,
    required this.alive,
    this.patience = const Duration(seconds: 15),
    this.tolerance = 2,
    Timer Function(Duration delay, void Function() callback)? schedule,
  }) : _schedule = schedule ?? Timer.new;

  /// Le lecteur attend son image : en tampon.
  final bool Function() waiting;

  /// Une ouverture est déjà en cours (changement de qualité, reprise après
  /// une coupure) : on la laisse finir avant de juger.
  final bool Function() busy;

  /// La position affichée, en secondes.
  final int Function() positionSeconds;

  /// Exécute [step] à la seconde [seconds]. Faux quand l'échelon ne
  /// s'applique pas (transcoder ce qui l'est déjà) : on passe au suivant.
  final Future<bool> Function(RescueStep step, int seconds) run;

  /// Faux dès que le lecteur est démonté.
  final bool Function() alive;

  /// Ce qu'on laisse à une recherche, puis à chaque échelon, pour rendre une
  /// image. Une recherche saine se pose en une à trois secondes ; le moteur
  /// d'Apple s'en donne huit avant de réessayer lui-même.
  final Duration patience;

  /// L'écart à la cible, en secondes, sous lequel la position n'a « pas
  /// bougé ».
  final int tolerance;

  final Timer Function(Duration delay, void Function() callback) _schedule;

  Timer? _timer;
  int _target = 0;
  int _step = 0;
  bool _running = false;

  /// L'échelon que prendra le prochain rattrapage. Exposé pour les tests.
  RescueStep get nextStep =>
      RescueStep.values[_step.clamp(0, RescueStep.values.length - 1)];

  bool get _stuck =>
      waiting() && (positionSeconds() - _target).abs() <= tolerance;

  /// Une recherche part vers [seconds].
  ///
  /// Le délai court depuis la première recherche restée sans image : une
  /// télécommande qui insiste sur une lecture figée ne le repousse pas.
  void noteSeek(int seconds) {
    final pending = _timer != null && waiting();
    _target = seconds;
    if (pending || _running) return;
    _arm();
  }

  /// Le moteur annonce une panne à [seconds], après la première image.
  /// [undecodable] : il dit ne pas savoir lire ce fichier, et le rouvrir tel
  /// quel ne changerait rien.
  void noteFailure(int seconds, {bool undecodable = false}) {
    _target = seconds;
    if (undecodable && _step < RescueStep.transcode.index) {
      _step = RescueStep.transcode.index;
    }
    if (_running) return;
    _timer?.cancel();
    _timer = null;
    unawaited(_climb());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void _arm() {
    _timer?.cancel();
    _timer = _schedule(patience, _expire);
  }

  void _expire() {
    _timer = null;
    if (!alive()) return;
    if (busy()) {
      _arm();
      return;
    }
    if (!_stuck) {
      _step = 0;
      return;
    }
    unawaited(_climb());
  }

  /// Monte les échelons jusqu'au premier qui s'applique, puis attend de voir
  /// s'il a rendu l'image.
  Future<void> _climb() async {
    if (_running) return;
    _running = true;
    try {
      while (alive() && _step < RescueStep.values.length) {
        final step = RescueStep.values[_step++];
        var applied = false;
        try {
          applied = await run(step, _target);
        } catch (_) {
          // Un échelon qui échoue (serveur muet, session refusée) vaut un
          // échelon sans effet : le suivant prend le relais, jusqu'à l'écran
          // d'échec, qui le dit à l'utilisateur.
          applied = false;
        }
        if (!alive() || step == RescueStep.giveUp) return;
        if (applied) {
          _arm();
          return;
        }
      }
    } finally {
      _running = false;
    }
  }
}
