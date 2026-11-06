import 'package:flutter/widgets.dart';

import '../tv_mode.dart';

/// D'où vient un Retour.
enum TvBackOrigin {
  /// Le système : Menu ou ‹ de la Siri Remote, Retour d'Android TV. Le moteur
  /// l'envoie en `popRoute`, pas en touche, et dpad ne le voit donc jamais
  /// (constat C1).
  popRoute,

  /// Une touche que dpad a reconnue : Échap d'un clavier, B d'une manette,
  /// Retour d'un téléviseur LG.
  key,
}

/// Le seul endroit qui décide de ce que fait Retour sur un téléviseur
/// (ADR-0110).
///
/// Deux entrées pour une seule décision : [WidgetsBindingObserver.didPopRoute]
/// et l'`onBack` de dpad (par `OnyxDpad`). Elles se recouvrent : Android 16
/// envoie la touche `goBack` *puis* `popRoute` pour le même appui, et l'Apple
/// TV pourrait faire de même avec Menu (à mesurer sur machine réelle, rapport
/// de phase 0 §5.1). Deux Retours d'origines différentes à moins de
/// [window] d'écart sont donc **un seul** appui : le second est absorbé.
/// Deux appuis de même origine restent deux appuis, aussi rapides soient-ils.
///
/// La règle, dans l'ordre (conventions tvOS) :
///
/// 1. ce qui peut se fermer se ferme, ce qui est poussé se dépile — le
///    `maybePop` du navigateur racine, qui consulte les `PopScope` comme le
///    ferait Flutter ;
/// 2. à la racine, Retour n'est **jamais** retenu : `didPopRoute` rend faux et
///    le système ramène à l'écran d'accueil de l'appareil (règle de l'App
///    Review tvOS).
///
/// La remontée du contenu d'un onglet vers l'en-tête s'y ajoutera en phase 5.
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

  @override
  State<TvBack> createState() => TvBackState();
}

class TvBackState extends State<TvBack> with WidgetsBindingObserver {
  final Stopwatch _stopwatch = Stopwatch()..start();

  /// Le dernier Retour traité : son origine et son heure.
  (TvBackOrigin, Duration)? _last;

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

  /// L'entrée de dpad : vrai quand la touche a servi, faux pour la laisser
  /// au reste de l'app (Échap ferme alors ce que Flutter sait fermer).
  bool handleKey() => handle(TvBackOrigin.key);

  /// Un Retour, d'où qu'il vienne. Vrai quand il a été consommé.
  bool handle(TvBackOrigin origin) {
    if (!TvMode.isTv) return false;
    final now = _now();
    final last = _last;
    if (last != null && last.$1 != origin && now - last.$2 < widget.window) {
      // La seconde moitié d'un appui déjà traité : l'absorber, sans quoi le
      // même appui défait deux couches (constat C2).
      _last = null;
      return true;
    }
    final handled = _back();
    _last = handled ? (origin, now) : null;
    return handled;
  }

  bool _back() {
    final navigator = widget.navigatorKey.currentState;
    // À la racine : rendre la main au système (règle 2).
    if (navigator == null || !navigator.canPop()) return false;
    // Le résultat de `maybePop` ne change rien : même refusé par un
    // `PopScope`, l'appui a été lu, et le laisser au système le ferait
    // sortir de l'app.
    navigator.maybePop();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
