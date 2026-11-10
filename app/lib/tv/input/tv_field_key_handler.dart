import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tv_mode.dart';

/// Intercepte les touches de validation (Select / OK / Entrée / A de manette)
/// sur un champ de saisie afin de déclencher la soumission directement sur TV,
/// ou de réclamer l'ouverture du clavier virtuel si le texte est vide.
class TvFieldKeyHandler extends StatelessWidget {
  const TvFieldKeyHandler({
    super.key,
    required this.child,
    required this.controller,
    this.onSubmitted,
    this.canRequestFocus = true,
  });

  final Widget child;
  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;
  final bool canRequestFocus;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: canRequestFocus,
      skipTraversal: !canRequestFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final isSelectOrEnter = key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.gameButtonA;
        if (isSelectOrEnter) {
          final query = controller.text.trim();
          if (query.isNotEmpty) {
            onSubmitted?.call(query);
            return KeyEventResult.handled;
          } else if (TvMode.isTv || TvScope.of(context)) {
            SystemChannels.textInput.invokeMethod('TextInput.show');
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
