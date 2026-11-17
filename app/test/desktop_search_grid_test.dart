import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/search/desktop/desktop_search_hits.dart';

/// Les flèches de la recherche du bureau dans ses grilles empilées : la
/// bibliothèque (7 titres) puis les titres absents (3), sur 4 colonnes.
///
///     0  1  2  3
///     4  5  6
///     ----------
///     7  8  9
int? _step(int index, TraversalDirection direction) => stepSelection(
      sections: const [7, 3],
      columns: 4,
      index: index,
      direction: direction,
    );

void main() {
  test('Gauche et Droite suivent l’ordre de lecture, d’une grille à l’autre',
      () {
    expect(_step(1, TraversalDirection.right), 2);
    expect(_step(6, TraversalDirection.right), 7);
    expect(_step(7, TraversalDirection.left), 6);
    expect(_step(0, TraversalDirection.left), 0);
    expect(_step(9, TraversalDirection.right), 9);
  });

  test('Bas garde la colonne, et tombe sur le dernier d’une ligne incomplète',
      () {
    expect(_step(1, TraversalDirection.down), 5);
    expect(_step(3, TraversalDirection.down), 6,
        reason: 'rien sous la quatrième colonne : le dernier titre');
  });

  test('Bas passe de la bibliothèque aux titres absents, même colonne', () {
    expect(_step(5, TraversalDirection.down), 8);
    expect(_step(6, TraversalDirection.down), 9);
    expect(_step(9, TraversalDirection.down), 9, reason: 'la fin, on y reste');
  });

  test('Haut remonte dans la grille d’au-dessus, même colonne', () {
    expect(_step(8, TraversalDirection.up), 5);
    expect(_step(5, TraversalDirection.up), 1);
  });

  test('Haut depuis la première ligne rend la main au champ', () {
    expect(_step(2, TraversalDirection.up), isNull);
  });

  test('une grille vide est sautée', () {
    expect(
      stepSelection(
        sections: const [0, 3],
        columns: 4,
        index: 1,
        direction: TraversalDirection.up,
      ),
      isNull,
    );
    expect(
      stepSelection(
        sections: const [2, 0, 2],
        columns: 4,
        index: 1,
        direction: TraversalDirection.down,
      ),
      3,
    );
  });
}
