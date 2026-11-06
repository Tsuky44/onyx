import 'package:flutter/widgets.dart';

/// La porte d'entrée d'une rangée de puces ([SettingsChoiceTile]) pour la
/// télécommande.
///
/// Sur haut et bas, le parcours directionnel de Flutter préfère les cibles qui
/// chevauchent horizontalement l'élément quitté. Les puces sont alignées à
/// gauche, les lignes de réglage voisines prennent toute la largeur : depuis un
/// interrupteur ou un menu à droite, haut et bas sautaient la rangée entière.
/// « Lecteur Apple TV » (Natif / Onyx) était ainsi inatteignable au D-pad,
/// comme « Épisodes sans intervention » et « Quand la poser ».
///
/// Ce nœud couvre toute la ligne, donc il est toujours dans la bande, et rend
/// aussitôt le focus à la puce choisie. Tant que le focus est dans la rangée,
/// il s'efface du parcours : haut depuis une puce ne retombe pas sur lui.
///
/// Un second nœud, au quart droit de la ligne, fait la même chose pour ce qui
/// est aligné à droite. Sous dpad (ADR-0110), être dans la bande ne suffit
/// pas : entre deux cibles de la bande, la plus proche *en travers* gagne, au
/// centre près. Depuis un menu au bout de la ligne, le centre de la ligne
/// entière était trop loin, et Bas sautait la rangée pour le menu suivant ;
/// celui du quart droit est assez près.
class SettingsChoiceFocus extends StatefulWidget {
  const SettingsChoiceFocus({
    super.key,
    required this.selectedIndex,
    required this.child,
  });

  /// La puce qui reçoit le focus en entrant, dans l'ordre de l'arbre. Hors
  /// bornes (aucune option choisie), la première.
  final int selectedIndex;
  final Widget child;

  @override
  State<SettingsChoiceFocus> createState() => _SettingsChoiceFocusState();
}

class _SettingsChoiceFocusState extends State<SettingsChoiceFocus> {
  final FocusNode _node = FocusNode(debugLabel: 'settings-choice');
  final FocusNode _edge = FocusNode(debugLabel: 'settings-choice-edge');
  bool _inside = false;

  @override
  void dispose() {
    _node.dispose();
    _edge.dispose();
    super.dispose();
  }

  void _onFocusChange(bool hasFocus) {
    if (hasFocus && (_node.hasPrimaryFocus || _edge.hasPrimaryFocus)) {
      final choices = _node.traversalDescendants
          .where((node) => !identical(node, _edge))
          .toList();
      if (choices.isNotEmpty) {
        final index =
            widget.selectedIndex < 0 || widget.selectedIndex >= choices.length
                ? 0
                : widget.selectedIndex;
        choices[index].requestFocus();
      }
    }
    if (_inside != hasFocus) setState(() => _inside = hasFocus);
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _node,
        skipTraversal: _inside,
        onFocusChange: _onFocusChange,
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.25,
                  heightFactor: 1,
                  child: Focus(
                    focusNode: _edge,
                    skipTraversal: _inside,
                    includeSemantics: false,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
