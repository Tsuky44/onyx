import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import 'onyx/onyx_capsule_button.dart';
import 'player_chrome_fade.dart';

/// « Annuler », sous l'anneau d'un lancement qui se fait attendre.
///
/// Sur un téléviseur, rien à l'écran ne dit qu'on peut renoncer : son chrome
/// n'a pas de bouton Retour (ADR-0124), et devant un écran noir la
/// télécommande ne tient aucune commande. Passé [delay], une capsule de verre
/// arrive en fondu sous l'anneau et prend la télécommande si elle n'était
/// posée sur rien ([parkedOn]) : OK annule, comme Retour le fait depuis le
/// début.
///
/// Elle ne prend jamais le focus à une commande du chrome : celui qui y
/// choisit une piste pendant l'attente garde sa place, et retrouve
/// « Annuler » en rangeant la barre.
///
/// Seul le lancement la montre. Devant un tampon vide ou un changement de
/// qualité le film a commencé : « Annuler » y voudrait dire autre chose, et
/// OK doit y rester la commande de lecture.
class PlayerWaitCancel extends StatefulWidget {
  const PlayerWaitCancel({
    super.key,
    required this.onCancel,
    this.focusNode,
    this.parkedOn,
    this.delay = defaultDelay,
  });

  /// Ce qu'un lancement peut durer avant qu'on propose d'y renoncer. Un
  /// départ ordinaire tient dessous et ne montre rien ; au-delà, on se
  /// demande déjà si l'écran répond encore.
  static const Duration defaultDelay = Duration(seconds: 4);

  /// Le temps de lire la capsule avant qu'elle réponde : un appui parti avant
  /// qu'elle soit lisible n'était pas pour elle, et ne doit pas faire quitter
  /// le film à qui voulait seulement réveiller les commandes.
  static const Duration armDelay = Duration(milliseconds: 600);

  final VoidCallback onCancel;

  /// Le nœud de la capsule. L'écran le donne pour savoir que la télécommande
  /// est sur « Annuler », pas dans la barre de commandes.
  final FocusNode? focusNode;

  /// Où la télécommande est garée quand elle ne tient aucune commande : le
  /// lecteur lui-même. Tant que l'offre est à l'écran, une télécommande garée
  /// là passe sur « Annuler ». Nul : la capsule ne prend jamais le focus.
  final FocusNode? parkedOn;

  final Duration delay;

  @override
  State<PlayerWaitCancel> createState() => _PlayerWaitCancelState();
}

class _PlayerWaitCancelState extends State<PlayerWaitCancel> {
  FocusNode? _ownedNode;
  Timer? _offer;
  Timer? _arm;
  bool _offered = false;
  bool _armed = false;

  FocusNode get _node =>
      widget.focusNode ??
      (_ownedNode ??= FocusNode(debugLabel: 'player-wait-cancel'));

  @override
  void initState() {
    super.initState();
    widget.parkedOn?.addListener(_claimParkedRemote);
    _offer = Timer(widget.delay, _show);
  }

  @override
  void didUpdateWidget(PlayerWaitCancel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.parkedOn, widget.parkedOn)) return;
    oldWidget.parkedOn?.removeListener(_claimParkedRemote);
    widget.parkedOn?.addListener(_claimParkedRemote);
  }

  @override
  void dispose() {
    widget.parkedOn?.removeListener(_claimParkedRemote);
    _offer?.cancel();
    _arm?.cancel();
    _ownedNode?.dispose();
    super.dispose();
  }

  void _show() {
    if (!mounted) return;
    setState(() => _offered = true);
    _arm = Timer(PlayerWaitCancel.armDelay, () => _armed = true);
    // Après l'image : jusque-là la capsule est exclue du focus, et il n'y a
    // rien où le poser.
    WidgetsBinding.instance.addPostFrameCallback((_) => _claimParkedRemote());
  }

  /// La télécommande garée sur le lecteur passe sur « Annuler ». Rappelé à
  /// chaque fois qu'elle y revient (la barre rangée par Retour, ou par son
  /// compte à rebours).
  void _claimParkedRemote() {
    if (!mounted || !_offered) return;
    if (widget.parkedOn?.hasPrimaryFocus ?? false) _node.requestFocus();
  }

  void _press() {
    if (_armed) widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerChromeFade(
      visible: _offered,
      child: OnyxCapsuleButton(
        label: tr('Annuler'),
        onPressed: _press,
        focusNode: _node,
      ),
    );
  }
}
