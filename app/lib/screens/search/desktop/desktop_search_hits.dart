import 'package:flutter/widgets.dart';

/// Le titre où mène une flèche, dans des grilles empilées de [columns]
/// colonnes dont [sections] donne les longueurs.
///
/// Gauche et Droite suivent l'ordre de lecture et passent d'une grille à
/// l'autre ; Haut et Bas gardent la colonne, et tombent sur le dernier titre
/// d'une ligne incomplète plutôt que de ne rien faire. Null quand Haut part de
/// la première ligne : la sélection rend la main au champ.
int? stepSelection({
  required List<int> sections,
  required int columns,
  required int index,
  required TraversalDirection direction,
}) {
  final total = sections.fold<int>(0, (sum, length) => sum + length);
  if (total == 0) return null;
  final cols = columns < 1 ? 1 : columns;
  final current = index.clamp(0, total - 1);

  switch (direction) {
    case TraversalDirection.left:
      return current == 0 ? 0 : current - 1;
    case TraversalDirection.right:
      return current == total - 1 ? current : current + 1;
    case TraversalDirection.up:
    case TraversalDirection.down:
      break;
  }

  // La grille de [current], et sa place dans cette grille.
  var section = 0;
  var start = 0;
  while (current >= start + sections[section]) {
    start += sections[section];
    section++;
  }
  final local = current - start;
  final column = local % cols;
  final length = sections[section];

  if (direction == TraversalDirection.down) {
    if (local + cols < length) return current + cols;
    final lastRowStart = (length - 1) ~/ cols * cols;
    if (local < lastRowStart) return start + length - 1;
    var nextStart = start + length;
    for (var s = section + 1; s < sections.length; s++) {
      if (sections[s] > 0) {
        return nextStart + (column < sections[s] ? column : sections[s] - 1);
      }
      nextStart += sections[s];
    }
    return current;
  }

  if (local - cols >= 0) return current - cols;
  var previousEnd = start;
  for (var s = section - 1; s >= 0; s--) {
    final previousStart = previousEnd - sections[s];
    if (sections[s] > 0) {
      final lastRowStart = (sections[s] - 1) ~/ cols * cols;
      final target = lastRowStart + column;
      return previousStart + (target < sections[s] ? target : sections[s] - 1);
    }
    previousEnd = previousStart;
  }
  return null;
}
