import 'package:flutter/widgets.dart';

import '../tv_deferred_keyboard.dart';
import '../tv_mode.dart';

/// D'où vient un Retour.
enum TvBackOrigin {
  /// Le système : Menu ou ‹ de la Siri Remote, Retour d'Android TV. Le moteur
  /// l'envoie en `popRoute`, pas en touche, et dpad ne le voit donc jamais
  /// (constat C1).
  popRoute,

  /// Une touche : Échap d'un clavier, B d'une manette, Retour d'un téléviseur
  /// LG (réécrit en Échap), et peut-être Menu sur Apple TV. Elle arrive par
  /// l'`onBack` de dpad, ou par [TvBackKeyAction] quand dpad se tait (champ
  /// de saisie focalisé).
  key,
}

/// Le seul endroit qui décide de ce que fait Retour sur un téléviseur, sous
/// dpad (ADR-0110).
///
/// Deux entrées pour une seule décision : [WidgetsBindingObserver.didPopRoute]
/// et les touches Retour (l'`onBack` de dpad par `OnyxDpad`, et
/// [TvBackKeyAction] quand dpad se tait). Elles se recouvrent : Android 16
/// envoie la touche `goBack` *puis* `popRoute` pour le même appui, et l'Apple
/// TV peut envoyer Menu en `popRoute`, en Échap ou les deux (pas encore
/// mesuré sur machine réelle, rapport de phase 0 §5.1). Deux Retours
/// d'origines différentes à moins de [window] d'écart sont donc **un seul**
/// appui : le second est absorbé. Deux appuis de même origine restent deux
/// appuis, aussi rapides soient-ils.
///
/// La règle, dans l'ordre (plan §5, phase 5) :
///
/// 1. ce qui peut se fermer se ferme : le clavier d'un champ différé, puis le
///    dialogue, la feuille ou le menu du dessus ;
/// 2. ce qui est poussé se dépile. 1 et 2 passent par le `maybePop` du
///    navigateur racine, qui consulte les `PopScope` comme le ferait Flutter :
///    celui d'un navigateur imbriqué (les fiches de la coquille) dépile chez
///    lui, celui du lecteur garde son Retour ;
/// 3. les marches des écrans ([TvBackStep]), la plus récente d'abord : dans le
///    contenu d'un onglet, le focus remonte à l'en-tête, sur l'onglet affiché ;
/// 4. sinon, c'est la racine : Retour est rendu au système. `didPopRoute`
///    rend faux, la touche n'est pas consommée, et l'appareil revient à son
///    écran d'accueil. **On ne retient jamais Menu à la racine** (règle de
///    l'App Review tvOS), quel que soit l'onglet affiché (ADR-0110, phase 5).
///
/// Hors téléviseur, [TvBack] ne décide de rien : le téléphone et le bureau
/// gardent le Retour de Flutter.
///
/// **Se monte au-dessus de `MaterialApp`.** Flutter consulte les
/// observateurs dans leur ordre d'inscription, et celui de `WidgetsApp`
/// dépile sans rien demander à personne : posé plus bas, [TvBack] ne verrait
/// `popRoute` qu'à la racine.
class TvBack extends StatefulWidget {
  const TvBack({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.window = defaultWindow,
  });

  /// Le navigateur racine de l'app.
  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  /// L'écart sous lequel deux Retours d'origines différentes sont le même
  /// appui. Sur l'émulateur Android TV 16, `popRoute` suit la touche de
  /// quelques millisecondes ; un humain n'appuie pas deux fois en moins de
  /// 300 ms sur deux boutons différents.
  final Duration window;

  static const Duration defaultWindow = Duration(milliseconds: 300);

  /// Remplace l'horloge dans les tests.
  @visibleForTesting
  static Duration Function()? debugClock;

  static TvBackState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<TvBackState>();

  /// Pour un écran qui traite lui-même une touche Retour (le lecteur, jusqu'à
  /// sa migration en phase 7) : vrai si l'appui est neuf et qu'il doit agir,
  /// faux si c'est la seconde moitié d'un appui que `popRoute` a déjà traité.
  /// L'appui est noté, pour que le `popRoute` qui le suivrait soit absorbé.
  ///
  /// Sans [TvBack] au-dessus (l'ancien système), toujours vrai.
  static bool claimKey(BuildContext context) =>
      maybeOf(context)?.claim(TvBackOrigin.key) ?? true;

  @override
  State<TvBack> createState() => TvBackState();
}

class TvBackState extends State<TvBack> with WidgetsBindingObserver {
  final Stopwatch _stopwatch = Stopwatch()..start();

  /// Le dernier Retour traité : son origine et son heure.
  (TvBackOrigin, Duration)? _last;

  /// Les marches montées, dans l'ordre de montage.
  final List<TvBackStepState> _steps = <TvBackStepState>[];

  Duration _now() => TvBack.debugClock?.call() ?? _stopwatch.elapsed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async => handle(TvBackOrigin.popRoute);

  /// L'entrée des touches : vrai quand la touche a servi, faux pour la
  /// laisser filer jusqu'au système.
  bool handleKey() => handle(TvBackOrigin.key);

  /// Un Retour, d'où qu'il vienne. Vrai quand il a été consommé.
  bool handle(TvBackOrigin origin) {
    if (!TvMode.isTv) return false;
    if (_isSecondHalf(origin)) return true;
    final handled = _back();
    _last = handled ? (origin, _now()) : null;
    return handled;
  }

  /// Voir [TvBack.claimKey].
  bool claim(TvBackOrigin origin) {
    if (!TvMode.isTv) return true;
    if (_isSecondHalf(origin)) return false;
    _last = (origin, _now());
    return true;
  }

  /// Vrai, et l'appui précédent oublié, quand [origin] est la seconde moitié
  /// d'un appui déjà traité. L'absorber : sans quoi le même appui défait deux
  /// couches (constat C2).
  bool _isSecondHalf(TvBackOrigin origin) {
    final last = _last;
    if (last == null || last.$1 == origin) return false;
    if (_now() - last.$2 >= widget.window) return false;
    _last = null;
    return true;
  }

  bool _back() {
    // 1. Le clavier d'un champ : Retour le referme sur Android TV sans
    // retirer le focus au champ, et le Retour suivant doit d'abord rendre la
    // télécommande au cadre du champ plutôt que quitter l'écran.
    if (TvDeferredKeyboardState.releaseFocused()) return true;
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return false;
    // 1 et 2. Le `maybePop` est lancé sans être attendu : même refusé par un
    // `PopScope`, l'appui a été lu, et le rendre au système le ferait sortir
    // de l'app.
    if (_topRouteTakesBack(navigator)) {
      navigator.maybePop();
      return true;
    }
    // 3. Les marches des écrans, la plus récente d'abord.
    for (final step in _steps.reversed.toList()) {
      if (step.isCurrent && step.widget.onBack()) return true;
    }
    // 4. La racine.
    return false;
  }

  /// Vrai quand la route du dessus du navigateur racine prend Retour : elle
  /// se dépile, ou un `PopScope` la retient pour le traiter (navigateur
  /// imbriqué, lecteur). Faux pour la première route sans `PopScope`, que
  /// Flutter rendrait au système (`bubble`).
  ///
  /// `popUntil` dont le prédicat accepte la première route est la seule façon
  /// publique et synchrone de lire la route du dessus : il ne dépile rien.
  /// `maybePop` répond aussi, mais trop tard pour une touche, qui doit savoir
  /// tout de suite si elle est consommée.
  static bool _topRouteTakesBack(NavigatorState navigator) {
    Route<Object?>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    final route = top;
    return route != null && route.popDisposition != RoutePopDisposition.bubble;
  }

  void _register(TvBackStepState step) => _steps.add(step);

  void _unregister(TvBackStepState step) => _steps.remove(step);

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Une marche du Retour propre à un écran, que [TvBack] consulte une fois la
/// pile des routes vide (règle 3) : la coquille y fait remonter le focus du
/// contenu d'un onglet vers l'en-tête.
///
/// [onBack] rend vrai quand il a consommé l'appui ; faux le laisse à la
/// marche suivante, puis au système. Une marche n'est consultée que si sa
/// route est au premier plan.
///
/// Sans [TvBack] au-dessus (l'ancien système, hors téléviseur), la marche ne
/// fait rien : le Retour de Flutter ne la voit pas.
class TvBackStep extends StatefulWidget {
  const TvBackStep({super.key, required this.onBack, required this.child});

  final bool Function() onBack;
  final Widget child;

  @override
  State<TvBackStep> createState() => TvBackStepState();
}

class TvBackStepState extends State<TvBackStep> {
  TvBackState? _owner;

  /// Vrai quand la route de la marche est au premier plan.
  bool get isCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = TvBack.maybeOf(context);
    if (identical(owner, _owner)) return;
    _owner?._unregister(this);
    _owner = owner?.._register(this);
  }

  @override
  void dispose() {
    _owner?._unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Ce que demande une touche Retour quand dpad ne l'a pas prise : `OnyxDpad`
/// se tait pendant qu'un champ de saisie a le focus, et la touche remonte
/// alors aux raccourcis de `MaterialApp` (`TvNavRoot.shortcuts`).
class TvBackKeyIntent extends Intent {
  const TvBackKeyIntent();
}

/// Sur téléviseur, la touche va à [TvBack] et n'est consommée que s'il l'a
/// prise : à la racine, elle file jusqu'au système. Ailleurs, Échap garde son
/// sens de bureau, celui que `WidgetsApp` lui donne : fermer ce qui se ferme
/// ([DismissIntent]).
class TvBackKeyAction extends Action<TvBackKeyIntent> {
  @override
  Object? invoke(TvBackKeyIntent intent) {
    final context = primaryFocus?.context;
    if (context == null) return false;
    if (TvMode.isTv) return TvBack.maybeOf(context)?.handleKey() ?? false;
    const dismiss = DismissIntent();
    final action = Actions.maybeFind<DismissIntent>(context, intent: dismiss);
    if (action == null || !action.isEnabled(dismiss)) return false;
    Actions.invoke(context, dismiss);
    return true;
  }

  @override
  KeyEventResult toKeyEventResult(
    TvBackKeyIntent intent,
    covariant Object? invokeResult,
  ) =>
      invokeResult == true ? KeyEventResult.handled : KeyEventResult.ignored;
}
