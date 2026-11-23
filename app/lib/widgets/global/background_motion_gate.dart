import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../services/player_presence.dart';
import '../../utils/app_platform.dart';
import '../../utils/on_screen.dart';

/// Fige toute animation de l'app tant que sa fenêtre n'a pas le focus, sur
/// bureau.
///
/// La panne d'origine : une fenêtre qu'une autre recouvre est `inactive`, pas
/// `hidden`. Flutter y dessine chaque image comme si on la regardait, et le
/// carrousel de l'accueil, les squelettes ou la pastille « en cours » gardent
/// le processeur et la carte graphique occupés derrière un navigateur. Un seul
/// [TickerMode] ici suspend tous les `AnimationController` de l'arbre, comme le
/// fait déjà `ShellTabStack` pour un onglet caché ; les widgets qui lisent
/// [OnScreenState] suivent le même signal et arrêtent leurs sondages avec
/// (voir ADR-0166).
///
/// Deux exceptions : un lecteur ouvert (le chrome se fond et se cache pendant
/// qu'on regarde dans une autre fenêtre ; figé à mi-fondu, il resterait sur le
/// film) et tout ce qui n'est pas un ordinateur (sur téléphone, `inactive` veut
/// dire une fenêtre partagée ou une boîte système, l'app est bien regardée).
class BackgroundMotionGate extends StatefulWidget {
  const BackgroundMotionGate({super.key, required this.child, this.desktop});

  final Widget child;

  /// Remplace la plateforme réelle, pour les tests.
  final bool? desktop;

  @override
  State<BackgroundMotionGate> createState() => _BackgroundMotionGateState();
}

class _BackgroundMotionGateState extends State<BackgroundMotionGate> {
  late final Listenable _signals = Listenable.merge(
    [AppForeground.focused, PlayerPresence.open],
  );

  bool get _motionAllowed =>
      !(widget.desktop ?? AppPlatform.isDesktop) ||
      AppForeground.focused.value ||
      PlayerPresence.open.value;

  late bool _enabled = _motionAllowed;

  @override
  void initState() {
    super.initState();
    _signals.addListener(_changed);
  }

  @override
  void dispose() {
    _signals.removeListener(_changed);
    super.dispose();
  }

  // Le lecteur s'annonce depuis `initState` et `dispose` : reconstruire sur
  // place ferait « setState pendant la construction ».
  void _changed() {
    scheduleMicrotask(() {
      if (!mounted || _motionAllowed == _enabled) return;
      setState(() => _enabled = _motionAllowed);
    });
  }

  @override
  Widget build(BuildContext context) =>
      TickerMode(enabled: _enabled, child: widget.child);
}
