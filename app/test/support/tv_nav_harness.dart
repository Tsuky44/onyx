import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/onyx_dpad.dart';
import 'package:onyx/tv/nav/tv_back.dart';
import 'package:onyx/tv/tv_mode.dart';

/// Le banc commun des tests de navigation TV (plan de refonte §6.1).
///
/// Il monte un écran comme l'app le fera après la phase 2 : [TvBack] au-dessus
/// de `MaterialApp`, [OnyxDpad] dans son `builder`, sur une surface de
/// 1920 × 1080. dpad raisonne en rectangles globaux : sur la surface de
/// 800 × 600 des tests, les voisins ne sont plus les mêmes qu'à l'écran.
/// Les animations sont coupées (`disableAnimations`) : dpad saute au lieu de
/// défiler, et un test ne dépend pas du nombre d'images pompées.
class TvNavHarness {
  TvNavHarness._(this.tester, this.navigatorKey);

  final WidgetTester tester;

  /// Le navigateur racine, pour pousser une route depuis un test.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Monte [home] et rend le banc.
  ///
  /// [isTv] règle [TvMode.enabled] pour la durée du test ; [android] fait
  /// croire à `OnyxDpad` qu'il tourne sur Android (le jeu de touches en
  /// dépend, constat C2). [profileKey] est le profil qui navigue.
  static Future<TvNavHarness> pump(
    WidgetTester tester,
    Widget home, {
    bool isTv = true,
    bool android = false,
    String? profileKey = 'test-profile',
    List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final previousTv = TvMode.enabled.value;
    TvMode.enabled.value = isTv;
    addTearDown(() => TvMode.enabled.value = previousTv);

    OnyxDpad.debugIsAndroidOverride = android;
    addTearDown(() => OnyxDpad.debugIsAndroidOverride = null);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      TvNavHarnessApp(
        navigatorKey: navigatorKey,
        profileKey: profileKey,
        navigatorObservers: navigatorObservers,
        home: home,
      ),
    );
    await settle(tester);
    return TvNavHarness._(tester, navigatorKey);
  }

  /// Laisse passer la restauration de focus de dpad, qui se fait en fin
  /// d'image puis en microtâche, et la parade de reprise d'`OnyxDpad`, une
  /// image plus tard encore.
  static Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  /// Une flèche, appuyée et relâchée.
  Future<void> press(TraversalDirection direction) async {
    await tester.sendKeyEvent(arrowKeyFor(direction));
    await settle(tester);
  }

  /// OK de la télécommande.
  Future<void> select({
    LogicalKeyboardKey key = LogicalKeyboardKey.select,
  }) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  /// Une touche Retour (Échap par défaut : clavier, Menu vu comme touche).
  Future<void> back(
      {LogicalKeyboardKey key = LogicalKeyboardKey.escape}) async {
    await sendKey(tester, key);
    await settle(tester);
  }

  /// Envoie [key], y compris celles que `flutter_test` ne sait pas simuler
  /// (`goBack`, le Retour d'une télécommande Android, n'a pas de touche
  /// physique connue) : l'évènement entre alors directement dans
  /// [HardwareKeyboard], le chemin que suit toute touche venue du moteur.
  static Future<void> sendKey(
      WidgetTester tester, LogicalKeyboardKey key) async {
    if (key != LogicalKeyboardKey.goBack) {
      await tester.sendKeyEvent(key);
      return;
    }
    const physical = PhysicalKeyboardKey.browserBack;
    HardwareKeyboard.instance.handleKeyEvent(
      KeyDownEvent(
        physicalKey: physical,
        logicalKey: key,
        timeStamp: Duration.zero,
      ),
    );
    HardwareKeyboard.instance.handleKeyEvent(
      KeyUpEvent(
        physicalKey: physical,
        logicalKey: key,
        timeStamp: Duration.zero,
      ),
    );
    await tester.pump();
  }

  /// Le Retour du système : ce que le moteur envoie pour Menu/‹ sur Apple TV
  /// et pour Retour sur Android, sur le canal `flutter/navigation`.
  Future<void> popRoute() async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      SystemChannels.navigation.codec.encodeMethodCall(
        const MethodCall('popRoute'),
      ),
      (_) {},
    );
    await settle(tester);
  }

  /// L'app passe en arrière-plan, puis [whilePaused] s'exécute.
  Future<void> pause({Future<void> Function()? whilePaused}) async {
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await whilePaused?.call();
  }

  /// L'app revient au premier plan.
  Future<void> resume() async {
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
  }

  /// Le texte de l'élément focalisé : son premier [Text], ou le libellé de
  /// son nœud à défaut. Nul quand rien de réel n'a le focus (une portée).
  String? get focusedLabel =>
      focusedLabelOf(FocusManager.instance.primaryFocus);

  /// Les touches flèche du clavier pour une direction.
  static LogicalKeyboardKey arrowKeyFor(TraversalDirection direction) =>
      switch (direction) {
        TraversalDirection.up => LogicalKeyboardKey.arrowUp,
        TraversalDirection.down => LogicalKeyboardKey.arrowDown,
        TraversalDirection.left => LogicalKeyboardKey.arrowLeft,
        TraversalDirection.right => LogicalKeyboardKey.arrowRight,
      };
}

/// Le libellé lisible de [node] : voir [TvNavHarness.focusedLabel].
String? focusedLabelOf(FocusNode? node) {
  if (node == null || node is FocusScopeNode) return null;
  final context = node.context;
  if (context == null) return node.debugLabel;
  String? text;
  void visit(Element element) {
    if (text != null) return;
    final widget = element.widget;
    if (widget is Text) {
      text = widget.data ?? widget.textSpan?.toPlainText();
      return;
    }
    element.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return text ?? node.debugLabel;
}

/// L'app du banc : [TvBack] au-dessus de `MaterialApp` (il doit voir
/// `popRoute` avant le navigateur), [OnyxDpad] dans le `builder`.
class TvNavHarnessApp extends StatelessWidget {
  const TvNavHarnessApp({
    super.key,
    required this.navigatorKey,
    required this.home,
    this.profileKey,
    this.navigatorObservers = const <NavigatorObserver>[],
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget home;
  final String? profileKey;
  final List<NavigatorObserver> navigatorObservers;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: TvMode.enabled,
      builder: (context, isTv, _) => TvScope(
        isTv: isTv,
        child: TvBack(
          navigatorKey: navigatorKey,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: navigatorObservers,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: OnyxDpad(
                profileKey: profileKey,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            home: home,
          ),
        ),
      ),
    );
  }
}

/// Le contenu d'une carte de test : un bloc de taille fixe qui porte son
/// libellé, que [TvNavHarness.focusedLabel] relit.
class TvTestTile extends StatelessWidget {
  const TvTestTile(this.label,
      {super.key, this.width = 200, this.height = 120});

  final String label;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: width, height: height, child: Center(child: Text(label)));
}
