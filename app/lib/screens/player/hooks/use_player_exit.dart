import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/playback_access.dart';

/// Quitter le lecteur maintenant ne doit rien attendre ([PlayerExit]) : sans
/// film qui joue, ce qui tarde est justement le serveur ou le moteur.
///
/// Un démarrage au délai dépassé compte, anneau ou pas. Un démarrage inachevé
/// aussi ([startupDone] faux), première image ou pas : le moteur peut
/// l'annoncer avant que la lecture ne parte, et ce qui est encore en vol ne
/// doit pas aboutir derrière la sortie.
bool playerExitCannotWait({
  required bool startupDone,
  required bool hasFirstFrame,
  required bool awaitingPicture,
}) =>
    !startupDone || !hasFirstFrame || awaitingPicture;

/// La sortie du lecteur : une seule fois, et sans attendre ce qui tarde.
///
/// Quitter un film qui joue garde son ordre : la dernière position part au
/// serveur, puis l'écran se dépile, pour que l'accueil qu'on rejoint relise
/// une progression à jour.
///
/// Quitter pendant une attente ([isWaiting] : la première image, un
/// changement de qualité, un tampon vide) ne peut pas attendre : ce qui tarde
/// est justement le serveur ou le moteur. Deux défauts venaient de là.
///
/// - L'écran restait figé jusqu'à la réponse du serveur à l'envoi de la
///   position, et un second Retour, donné par impatience, dépilait le lecteur
///   puis, la réponse venue, l'écran d'en dessous.
/// - Rien n'arrêtait ce qui était en vol : une session HLS demandée avant le
///   Retour s'ouvrait après lui et lançait la lecture (`open(play: true)`), du
///   son sans image jusqu'à la destruction de l'écran.
///
/// Pendant une attente, la sortie annule donc d'abord ce qui est en vol
/// ([cancelPending] : le contrôleur s'arrête à son prochain point de
/// contrôle, la session HLS et le ticket sont rendus tout de suite), arrête le
/// moteur, dépile, et laisse la progression partir derrière.
class PlayerExit {
  PlayerExit({
    required this.isWaiting,
    required this.cancelPending,
    required this.stopEngine,
    required this.onLeaving,
    required this.syncProgress,
    required this.pop,
  });

  /// Relu au moment de partir : le lecteur attend quelque chose.
  final bool Function() isWaiting;

  /// Arrête ce que le contrôleur a en vol et rend ce qu'il tient au serveur.
  final VoidCallback cancelPending;

  /// Arrête le moteur. Jamais attendu : rendre le décodeur matériel est la
  /// partie chère du démontage, et elle tombe pendant le fondu de sortie.
  final Future<void> Function() stopEngine;

  /// L'écran note qu'il s'en va (l'image retirée, la séance quittée).
  final VoidCallback onLeaving;

  /// Envoie la dernière position et rafraîchit ce qui la montre.
  final Future<void> Function() syncProgress;

  /// Dépile l'écran.
  final VoidCallback pop;

  Future<void>? _leaving;

  /// Quitte le lecteur. Une seconde demande rejoint la première : elle ne
  /// dépile rien de plus.
  Future<void> leave() => _leaving ??= _leave();

  Future<void> _leave() async {
    final waiting = isWaiting();
    // Avant l'arrêt du moteur : sans cela, une ouverture en vol repasserait
    // derrière lui.
    if (waiting) cancelPending();
    unawaited(stopEngine().catchError(_logFailure));
    onLeaving();
    final synced = syncProgress().catchError(_logFailure);
    if (!waiting) await synced;
    pop();
  }

  /// Un échec ici ne retient pas la sortie : l'écran ne reste jamais figé
  /// sur un film qu'on a quitté.
  void _logFailure(Object error) {
    debugPrint('Player: sortie incomplète '
        '(${redactPlaybackDiagnostic(error)})');
  }
}
