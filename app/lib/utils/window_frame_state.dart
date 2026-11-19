import 'package:flutter/foundation.dart';

/// Ce que les contrôles maison de la fenêtre dessinent d'elle : agrandie
/// (« Restaurer » à la place d'« Agrandir ») et au premier plan (symboles
/// éteints sinon, comme les fenêtres de Windows).
@immutable
class WindowFrameState {
  final bool maximized;
  final bool focused;

  const WindowFrameState({this.maximized = false, this.focused = true});

  WindowFrameState copyWith({bool? maximized, bool? focused}) =>
      WindowFrameState(
        maximized: maximized ?? this.maximized,
        focused: focused ?? this.focused,
      );

  @override
  bool operator ==(Object other) =>
      other is WindowFrameState &&
      other.maximized == maximized &&
      other.focused == focused;

  @override
  int get hashCode => Object.hash(maximized, focused);
}
