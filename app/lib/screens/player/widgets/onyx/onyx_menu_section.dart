/// Quelle liste un menu du Chrome Onyx montre. [root] est l'index des
/// réglages, que les arrangements à souris et à doigt ouvrent par leur roue
/// crantée ; sur un téléviseur, chaque réglage a son bouton et son menu
/// (ADR-0130).
///
/// Dans son propre fichier pour que le chrome puisse nommer un menu sans
/// tirer à lui tout ce que le menu importe.
enum OnyxMenuSection {
  root,
  quality,
  audio,
  subtitles,
  speed,
  display,
  sleep,
  chapters,
}
