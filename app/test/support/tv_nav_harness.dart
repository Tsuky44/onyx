import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/input/tv_dpad_log.dart';
import 'package:onyx/tv/nav/onyx_dpad.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/nav/tv_nav_root.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/tv/tv_focus_entry.dart';
import 'package:onyx/tv/tv_focus_guard.dart';
import 'package:onyx/tv/tv_key_repeat.dart';
import 'package:onyx/tv/tv_mode.dart';

/// Le banc commun des tests de navigation TV (plan de refonte §6.1).
///
/// Il monte un écran comme `main.dart` monte l'app, avec l'un ou l'autre
/// système de navigation ([TvNavEngine]) :
///
/// - **dpad** (défaut) : `TvBack` au-dessus de `MaterialApp`, [OnyxDpad] et
///   `TvArrowGate` dans son `builder`, les raccourcis et actions de
///   [TvNavRoot] — les mêmes appels que `main.dart` ;
/// - **legacy** : l'ancien système tel que `main.dart` le monte sans le
///   drapeau — `TvFocusGuard`, `TvTraversalPolicy`, `TvDirectionalFocusAction`,
///   `tvSelectShortcuts`. Recopié ici : `main.dart` ne s'importe pas dans un
///   test. Il disparaît avec le drapeau `ONYX_TV_NAV`.
///
/// Un test qui porte un comportement le fait tourner sur les deux
/// ([forEachEngine]) tant que le drapeau existe.
///
/// La surface fait 1920 × 1080. dpad raisonne en rectangles globaux : sur la surface de
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
  /// dépend, constat C2). [profileKey] est le profil qui navigue. [browser]
  /// monte les raccourcis qu'a une page web (`WidgetsApp.defaultShortcuts` sous
  /// `kIsWeb`) : un test tourne hors navigateur et aurait sinon ceux du natif.
  /// C'est l'app d'un téléviseur LG (ADR-0076). [around] enveloppe l'app
  /// entière, au-dessus de `MaterialApp` : les fournisseurs que toutes les
  /// routes lisent, comme `main.dart` les pose.
  static Future<TvNavHarness> pump(
    WidgetTester tester,
    Widget home, {
    TvNavEngine engine = TvNavEngine.dpad,
    bool isTv = true,
    bool android = false,
    String? profileKey = 'test-profile',
    List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
    bool browser = false,
    Widget Function(Widget app)? around,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final previousTv = TvMode.enabled.value;
    TvMode.enabled.value = isTv;
    addTearDown(() => TvMode.enabled.value = previousTv);

    OnyxDpad.debugIsAndroidOverride = android;
    addTearDown(() => OnyxDpad.debugIsAndroidOverride = null);

    TvKeyRepeat.debugReset();
    addTearDown(TvKeyRepeat.debugReset);
    // Les traces `[DPAD]` du portail ne vont pas dans la sortie des tests ;
    // un test qui les lit pose son propre réceptacle avant de monter.
    if (TvDpadLog.debugSink == null) {
      TvDpadLog.debugSink = <String>[];
      addTearDown(() => TvDpadLog.debugSink = null);
    }
    // La mémoire persistante de dpad est une table statique (constat C7) :
    // sans ce vidage, un test reprendrait la carte où le précédent s'était
    // arrêté.
    DpadRegionState.clearPersistentMemory();
    addTearDown(DpadRegionState.clearPersistentMemory);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      TvNavHarnessApp(
        engine: engine,
        navigatorKey: navigatorKey,
        profileKey: profileKey,
        navigatorObservers: navigatorObservers,
        browser: browser,
        around: around,
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

  /// Déclare [body] une fois par système de navigation, dans un groupe qui
  /// porte son nom : `legacy` et `dpad` doivent tenir la même promesse.
  static void forEachEngine(void Function(TvNavEngine engine) body) {
    for (final engine in TvNavEngine.values) {
      group(engine.name, () => body(engine));
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
  /// physique connue). Rend vrai si la touche a été consommée.
  ///
  /// Pour celles-là, l'évènement suit le chemin d'une touche venue du
  /// moteur : [HardwareKeyboard] (l'état des touches enfoncées), puis le
  /// `keyMessageHandler` de `KeyEventManager`, par où le `FocusManager` la
  /// reçoit. [HardwareKeyboard] seul ne la fait voir à personne : jusqu'à la
  /// phase 5, les tests de `goBack` passaient sans que la touche arrive
  /// nulle part.
  static Future<bool> sendKey(
      WidgetTester tester, LogicalKeyboardKey key) async {
    if (key != LogicalKeyboardKey.goBack) return tester.sendKeyEvent(key);
    const physical = PhysicalKeyboardKey.browserBack;
    // Déprécié depuis Flutter 3.18, mais c'est encore par là que le
    // `FocusManager` reçoit les touches, et `flutter_test` lui-même y passe
    // (`simulateKeyDownEvent`) ; il ne sait simplement pas nommer `goBack`
    // (« result != null », sur toutes les plateformes).
    // ignore: deprecated_member_use
    final handler = ServicesBinding.instance.keyEventManager.keyMessageHandler!;
    bool send(KeyEvent event) {
      HardwareKeyboard.instance.handleKeyEvent(event);
      // ignore: deprecated_member_use
      return handler(KeyMessage(<KeyEvent>[event], null));
    }

    final handled = send(KeyDownEvent(
      physicalKey: physical,
      logicalKey: key,
      timeStamp: Duration.zero,
    ));
    send(KeyUpEvent(
      physicalKey: physical,
      logicalKey: key,
      timeStamp: Duration.zero,
    ));
    await tester.pump();
    return handled;
  }

  /// Une **rafale** : [count] flèches vers [direction], appuyées et relâchées
  /// dans la même tâche, sans laisser passer une microtâche entre elles.
  ///
  /// C'est le cas du constat N2 (phase 0) : des flèches qui arrivent avant
  /// que le focus de la précédente soit posé. `tester.sendKeyEvent` attend
  /// entre deux touches, ce qui laisse le focus se poser : il ne sait pas
  /// fabriquer une rafale.
  Future<void> burst(TraversalDirection direction, int count) async {
    final logical = arrowKeyFor(direction);
    final physical = switch (direction) {
      TraversalDirection.up => PhysicalKeyboardKey.arrowUp,
      TraversalDirection.down => PhysicalKeyboardKey.arrowDown,
      TraversalDirection.left => PhysicalKeyboardKey.arrowLeft,
      TraversalDirection.right => PhysicalKeyboardKey.arrowRight,
    };
    sendBurst(<(LogicalKeyboardKey, PhysicalKeyboardKey)>[
      for (var i = 0; i < count; i++) (logical, physical),
    ]);
    await settle(tester);
  }

  /// Envoie [keys] (appui puis relâchement de chacune) dans la même tâche :
  /// voir [burst].
  static void sendBurst(List<(LogicalKeyboardKey, PhysicalKeyboardKey)> keys) {
    // Le chemin d'une touche venue du moteur, comme [sendKey].
    // ignore: deprecated_member_use
    final handler = ServicesBinding.instance.keyEventManager.keyMessageHandler!;
    void send(KeyEvent event) {
      HardwareKeyboard.instance.handleKeyEvent(event);
      // ignore: deprecated_member_use
      handler(KeyMessage(<KeyEvent>[event], null));
    }

    for (final (logical, physical) in keys) {
      send(KeyDownEvent(
        physicalKey: physical,
        logicalKey: logical,
        timeStamp: Duration.zero,
      ));
      send(KeyUpEvent(
        physicalKey: physical,
        logicalKey: logical,
        timeStamp: Duration.zero,
      ));
    }
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

/// L'app du banc, montée comme `main.dart` monte la sienne : voir
/// [TvNavHarness].
class TvNavHarnessApp extends StatelessWidget {
  const TvNavHarnessApp({
    super.key,
    this.engine = TvNavEngine.dpad,
    required this.navigatorKey,
    required this.home,
    this.profileKey,
    this.navigatorObservers = const <NavigatorObserver>[],
    this.browser = false,
    this.around,
  });

  /// Voir [TvNavHarness.pump].
  final bool browser;
  final Widget Function(Widget app)? around;

  /// Les raccourcis de `WidgetsApp.defaultShortcuts` sous `kIsWeb`, pour les
  /// touches en cause.
  static const Map<ShortcutActivator, Intent> browserShortcuts =
      <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.arrowLeft):
        ScrollIntent(direction: AxisDirection.left),
    SingleActivator(LogicalKeyboardKey.arrowRight):
        ScrollIntent(direction: AxisDirection.right),
    SingleActivator(LogicalKeyboardKey.arrowUp):
        ScrollIntent(direction: AxisDirection.up),
    SingleActivator(LogicalKeyboardKey.arrowDown):
        ScrollIntent(direction: AxisDirection.down),
    SingleActivator(LogicalKeyboardKey.enter): ButtonActivateIntent(),
  };

  final TvNavEngine engine;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget home;
  final String? profileKey;
  final List<NavigatorObserver> navigatorObservers;

  @override
  Widget build(BuildContext context) {
    final app = ValueListenableBuilder<bool>(
      valueListenable: TvMode.enabled,
      builder: (context, isTv, _) => TvScope(
        isTv: isTv,
        child: switch (engine) {
          TvNavEngine.dpad => _dpad(),
          TvNavEngine.legacy => _legacy(),
        },
      ),
    );
    return around?.call(app) ?? app;
  }

  /// Sans animation : dpad saute au lieu de défiler, et un test ne dépend pas
  /// du nombre d'images pompées.
  static Widget _still(BuildContext context, Widget child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child,
      );

  Widget _dpad() => TvNavRoot.aboveApp(
        navigatorKey: navigatorKey,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: navigatorObservers,
          shortcuts: <ShortcutActivator, Intent>{
            if (browser) ...browserShortcuts,
            ...TvNavRoot.shortcuts,
          },
          actions: TvNavRoot.actions,
          builder: (context, child) => _still(
            context,
            TvNavRoot.belowApp(
              profileKey: profileKey,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: home,
        ),
      );

  Widget _legacy() => TvFocusGuard(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: navigatorObservers,
          shortcuts: <ShortcutActivator, Intent>{
            ...WidgetsApp.defaultShortcuts,
            if (browser) ...browserShortcuts,
            ...(browser ? tvRemoteShortcuts(webTv: true) : tvSelectShortcuts),
          },
          actions: <Type, Action<Intent>>{
            ...WidgetsApp.defaultActions,
            DirectionalFocusIntent: TvDirectionalFocusAction(),
            TvBackIntent: TvBackAction(),
          },
          builder: (context, child) => _still(
            context,
            FocusTraversalGroup(
              policy: TvTraversalPolicy(),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: home,
        ),
      );
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
