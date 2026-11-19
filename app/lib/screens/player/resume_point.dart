/// Là où ouvrir un média, d'après le point de reprise qu'on en connaît.
///
/// Moins de trois secondes ne valent pas une reprise. Un point dans les
/// [endTolerance] dernières secondes — ou au-delà de la durée — non plus :
/// ouvrir là, c'est faire annoncer la fin au moteur avant la première image.
/// Le journal d'un utilisateur Windows montre un film de 6299 s ouvert à
/// 6300 s puis ramené à 0 deux secondes plus tard ; une durée que le serveur
/// ne connaissait pas l'avait empêché de marquer le film comme vu. On repart
/// du début, comme pour un film vu.
///
/// [durationSeconds] à 0 (inconnue) laisse le point tel quel.
int usableResumePoint(
  int seconds, {
  required int durationSeconds,
  int endTolerance = 30,
}) {
  if (seconds < 3) return 0;
  if (durationSeconds > 0 && seconds >= durationSeconds - endTolerance) {
    return 0;
  }
  return seconds;
}
