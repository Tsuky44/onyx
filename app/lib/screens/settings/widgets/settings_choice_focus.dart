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
  bool _inside = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _onFocusChange(bool hasFocus) {
    if (hasFocus && _node.hasPrimaryFocus) {
      final choices = _node.traversalDescendants.toList();
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
        child: widget.child,
      );
}
