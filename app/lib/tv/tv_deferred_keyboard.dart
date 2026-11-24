import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'nav/onyx_dpad.dart' show TvNavScope;
import 'tv_focus.dart';
import 'tv_mode.dart';

/// Un champ de saisie qu'une télécommande ne réveille qu'à la demande.
///
/// Sur Android, un champ qui prend le focus fait ouvrir le clavier virtuel — et
/// sur un téléviseur ce clavier est plein écran. Un champ posé sur le chemin du
/// parcours du focus devient donc un mur : la croix directionnelle le traverse,
/// le clavier s'ouvre par-dessus tout, et ce qui se trouve après lui est
/// inatteignable. C'est ce qui rendait l'avatar du compte impossible à
/// atteindre dans l'en-tête, la barre de recherche étant juste avant lui — puis
/// chaque champ des Réglages, l'un après l'autre.
///
/// Le champ se comporte donc comme un bouton : il est **hors du parcours**
/// jusqu'à ce qu'on appuie sur OK dessus, et il en ressort dès que le clavier se
/// referme. Hors téléviseur, ce widget est transparent : le champ prend le focus
/// au clic, exactement comme avant.
///
/// ```dart
/// TvDeferredKeyboard(
///   builder: (context, focusNode, canRequestFocus) => TextField(
///     focusNode: focusNode,
///     canRequestFocus: canRequestFocus,
///     decoration: const InputDecoration(labelText: 'Adresse'),
///   ),
/// )
/// ```
///
/// Sur un écran tactile (iPhone, iPad, téléphone Android, et leur navigateur),
/// il donne au champ ce que Flutter ne fait pas de lui-même (ADR-0141) : un
/// toucher hors du champ referme le clavier, et un champ que recouvre une
/// autre page ne reprend pas le focus quand on y revient. Sans cela, le
/// clavier d'iOS ne partait jamais : rien ne le fermait, et chaque retour sur
/// la page le rouvrait.
///
/// Le nœud est fourni par le widget, parce que sans cela chaque champ de l'app
/// aurait dû s'en créer un — quinze déclarations et quinze `dispose` dont
/// l'oubli ne se voit pas. Les rares champs qui en possèdent déjà un (la barre
/// de recherche, le formulaire de connexion qui enchaîne ses champs) le passent
/// par [fieldFocusNode].
class TvDeferredKeyboard extends StatefulWidget {
  const TvDeferredKeyboard({
    super.key,
    required this.builder,
    this.fieldFocusNode,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.autofocus = false,
  });

  /// Construit le champ. Reçoit le nœud à lui donner, et ce qu'il doit passer à
  /// son `canRequestFocus`.
  final Widget Function(
    BuildContext context,
    FocusNode focusNode,
    bool canRequestFocus,
  ) builder;

  /// Pour un appelant qui possède déjà le nœud — parce qu'il l'observe, ou
  /// parce qu'il enchaîne le focus d'un champ au suivant. Sinon ce widget en
  /// crée un et s'en occupe.
  final FocusNode? fieldFocusNode;

  /// Épouse la forme du champ, pour que l'anneau de focus le suive.
  final BorderRadius borderRadius;

  /// Si vrai, le champ réclame directement le focus et l'ouverture du clavier
  /// dès l'affichage du widget.
  final bool autofocus;

  /// Un clavier à l'écran, qu'un doigt ouvre et doit pouvoir refermer : un
  /// téléphone ou une tablette, app installée ou navigateur. Jamais un
  /// téléviseur, dont le clavier se gère à la télécommande.
  ///
  /// Lu de [defaultTargetPlatform] plutôt que du système : un navigateur
  /// d'iPhone y répond iOS, et un test peut le choisir.
  static bool usesTouchKeyboard(BuildContext context) {
    if (TvScope.of(context)) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
  }

  @override
  State<TvDeferredKeyboard> createState() => TvDeferredKeyboardState();
}

class TvDeferredKeyboardState extends State<TvDeferredKeyboard> {
  /// Où se pose la télécommande tant que le champ est un bouton.
  final FocusNode _remoteNode = FocusNode(debugLabel: 'tv-deferred-keyboard');

  /// Créé ici quand l'appelant n'en fournit pas — et détruit ici seulement
  /// dans ce cas : celui de l'appelant ne nous appartient pas.
  FocusNode? _ownedNode;

  late bool _keyboardRequested = widget.autofocus;

  /// Sur un écran tactile, la page du champ est recouverte par une autre : le
  /// champ ne peut plus prendre le focus. Flutter le lui rend au retour, dès
  /// la première image, et le clavier se rouvrait sur une page qu'on
  /// regardait seulement (ADR-0141).
  bool _parked = false;

  /// La page du champ était au premier plan à la dernière lecture.
  bool? _routeWasCurrent;

  FocusNode get _fieldNode =>
      widget.fieldFocusNode ?? (_ownedNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _fieldNode.addListener(_onFieldFocusChanged);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fieldNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TvDeferredKeyboard.usesTouchKeyboard(context)) return;
    final current = ModalRoute.isCurrentOf(context) ?? true;
    final was = _routeWasCurrent;
    _routeWasCurrent = current;
    if (was == null || was == current) return;
    if (!current) {
      // La construction qui suit retire le focus au champ, s'il l'avait.
      _parked = true;
      return;
    }
    // Revenue au premier plan, la page attend que celle qui part ait rendu le
    // focus : il se rend pendant la première image du retour, et les
    // changements de focus s'appliquent après elle. Le champ redevient
    // ensuite focalisable, sans prendre le focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer.run(() {
        if (!mounted || !(ModalRoute.isCurrentOf(context) ?? true)) return;
        setState(() => _parked = false);
      });
    });
  }

  /// Un toucher hors du champ (sur la page, une affiche, un bouton) le quitte
  /// et referme le clavier. Un autre champ n'est pas « hors » : ils partagent
  /// la région de toucher de [EditableText], et le focus passe de l'un à
  /// l'autre sans que le clavier retombe.
  static final Map<Type, Action<Intent>> _touchOutsideActions = {
    EditableTextTapOutsideIntent:
        CallbackAction<EditableTextTapOutsideIntent>(
      onInvoke: (intent) {
        intent.focusNode.unfocus();
        return null;
      },
    ),
  };

  @override
  void didUpdateWidget(TvDeferredKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fieldFocusNode != widget.fieldFocusNode) {
      oldWidget.fieldFocusNode?.removeListener(_onFieldFocusChanged);
      _fieldNode.addListener(_onFieldFocusChanged);
    }
    if (!oldWidget.autofocus && widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (TvScope.of(context)) {
          requestKeyboard();
        } else {
          _fieldNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _fieldNode.removeListener(_onFieldFocusChanged);
    _ownedNode?.dispose();
    _remoteNode.dispose();
    super.dispose();
  }

  void _onFieldFocusChanged() {
    if (!_keyboardRequested || _fieldNode.hasFocus || !mounted) return;
    // Le clavier s'est refermé. Le champ ressort du parcours, sinon le passage
    // suivant de la télécommande le rouvrirait tout seul — et le focus revient
    // sur le champ-bouton, pour ne laisser la télécommande nulle part.
    setState(() => _keyboardRequested = false);
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Sous dpad, une flèche qui sort du champ a déjà posé le focus sur le
      // voisin : le rendre ici l'y reprendrait (ADR-0110, phase 4). Seul un
      // champ qui n'a mené nulle part (le clavier s'est refermé) revient au
      // champ-bouton.
      if (TvNavScope.isActive(context) && _focusWentElsewhere) return;
      _remoteNode.requestFocus();
    });
  }

  /// Le focus est sur une vraie cible hors de ce widget.
  bool get _focusWentElsewhere {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary is FocusScopeNode) return false;
    if (primary.context == null) return false;
    return !identical(primary, _remoteNode) &&
        !identical(primary, _fieldNode) &&
        !primary.ancestors.contains(_remoteNode);
  }

  /// Ouvre le clavier sur ce champ.
  ///
  /// Appelé par OK sur le champ-bouton, et exposé pour les formulaires qui
  /// enchaînent leurs champs : sans cela, passer au champ suivant lui donnerait
  /// le focus sans que le clavier ne s'ouvre.
  ///
  /// Surtout pas nommée `activate` : [State] en a déjà une, que Flutter appelle
  /// quand l'état est réinséré dans l'arbre — le clavier se serait ouvert de
  /// lui-même à chaque fois.
  void requestKeyboard() {
    if (!mounted) return;
    setState(() => _keyboardRequested = true);
    // Après la frame : le champ n'est focusable qu'une fois reconstruit avec
    // `canRequestFocus` à vrai.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fieldNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
      Future.microtask(() {
        if (mounted && _fieldNode.hasFocus) {
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      });
    });
  }

  /// Referme la saisie et rend le focus au champ-bouton, tout de suite.
  ///
  /// Pour une plateforme où le champ garde le focus quand le clavier se ferme
  /// (webOS et Android TV, voir [WebTvFieldExit] et [releaseFocused]). Lâcher simplement le focus le laissait
  /// sans propriétaire le temps d'une frame : [TvFocusGuard] le donnait alors à
  /// l'élément suivant, quelle que soit la flèche.
  void releaseKeyboard() {
    if (!mounted || !_keyboardRequested) return;
    setState(() => _keyboardRequested = false);
    _remoteNode.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  /// Rend à la télécommande le champ qui a le focus, s'il y en a un, et dit
  /// s'il l'a fait.
  ///
  /// Pour le Retour d'un écran qui contient un champ. Retour referme le
  /// clavier d'Android TV sans retirer le focus au champ (constaté sur Android
  /// TV 16, et Android ne déclare aucune hauteur de clavier qui le
  /// trahirait) : le Retour suivant arrive avec le champ encore focalisé, et
  /// doit d'abord le relâcher plutôt que quitter l'écran. Même chemin pour le
  /// Menu de la Siri Remote, qui arrive en touche et passe par
  /// [TvBackAction] jusqu'au même `PopScope`.
  static bool releaseFocused() {
    final state = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<TvDeferredKeyboardState>();
    if (state == null || !state._keyboardRequested) return false;
    state.releaseKeyboard();
    return true;
  }

  /// Pose la télécommande sur le champ-bouton, clavier fermé.
  ///
  /// Pour l'appelant qui a ouvert une page depuis ce champ : au retour, le
  /// focus doit revenir ici et non sur le voisin que le système choisit.
  void focusRemote() {
    if (mounted && TvScope.of(context)) _remoteNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!TvScope.of(context)) {
      if (!TvDeferredKeyboard.usesTouchKeyboard(context)) {
        return widget.builder(context, _fieldNode, true);
      }
      return Actions(
        actions: _touchOutsideActions,
        child: widget.builder(context, _fieldNode, !_parked),
      );
    }

    return TvFocusable(
      focusNode: _remoteNode,
      onSelect: requestKeyboard,
      borderRadius: widget.borderRadius,
      // Pas d'agrandissement : ces champs vivent dans des formulaires serrés,
      // et grandir les ferait chevaucher leurs voisins.
      focusScale: 1.0,
      // Le champ prend le focus quand OK ouvre le clavier ; sous dpad il ne
      // doit pas en être exclu.
      editable: true,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _keyboardRequested ? null : requestKeyboard,
        child: widget.builder(context, _fieldNode, _keyboardRequested),
      ),
    );
  }
}
