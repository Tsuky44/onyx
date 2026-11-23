/// Le point de reprise au moment de lancer la lecture, sans faire attendre
/// l'image derrière un serveur lent.
///
/// Le contrôleur a déjà ouvert le flux à [openedAt] : la seconde que l'accueil
/// connaissait, après avoir laissé au serveur un court délai pour la
/// confirmer. L'écran attendait ensuite la réponse du serveur, sans borne,
/// avant d'appeler `play` : un serveur qui interroge Emby pouvait tenir
/// plusieurs secondes une image déjà prête, en pause sous son cache.
///
/// Flux ouvert à un point connu : la réponse déjà arrivée l'emporte, sinon on
/// part de [openedAt] et [resumeNeedsLateCorrection] rattrape l'écart.
/// Flux ouvert sans point connu ([openedAt] négatif) : la réponse reste
/// attendue, parce que partir du début puis sauter ferait entendre les
/// premières secondes du film.
Future<int> settledResumePoint(Future<int> server, {required int openedAt}) {
  if (openedAt < 0) return server;
  return server.timeout(Duration.zero, onTimeout: () => openedAt);
}

/// À combien de secondes du point de départ la réponse du serveur vaut un
/// saut. La même tolérance que l'ouverture : en dessous, on ne refait pas un
/// démarrage pour quelques secondes.
const resumeToleranceSeconds = 5;

/// Jusqu'où la lecture peut avoir avancé depuis son départ pour qu'une
/// réponse tardive la déplace encore. Au-delà, ou en arrière du départ,
/// quelqu'un a déjà choisi sa place.
const _lateCorrectionWindowSeconds = 30;

/// Si la réponse du serveur, arrivée après le départ, doit déplacer la
/// lecture.
///
/// [startedAt] est la seconde d'où la lecture est partie, [serverSeconds] ce
/// que le serveur a fini par répondre, [positionSeconds] où en est la lecture.
bool resumeNeedsLateCorrection({
  required int startedAt,
  required int serverSeconds,
  required int positionSeconds,
}) {
  if ((serverSeconds - startedAt).abs() <= resumeToleranceSeconds) return false;
  final progressed = positionSeconds - startedAt;
  return progressed >= 0 && progressed <= _lateCorrectionWindowSeconds;
}
