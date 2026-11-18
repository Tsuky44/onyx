import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/shell/mobile_bottom_nav.dart';
import 'package:onyx/screens/shell/shell_tabs.dart';
import 'package:onyx/tv/tv_deferred_keyboard.dart';
import 'package:onyx/widgets/global/glass_chrome.dart';

/// Le clavier d'un écran tactile se referme (ADR-0141) : au toucher hors du
/// champ, à la touche « Rechercher », et il ne se rouvre pas au retour sur une
/// page dont le champ avait le focus. Sur un iPhone, il ne partait jamais.
void main() {
  final touch = TargetPlatformVariant(
    const {TargetPlatform.iOS, TargetPlatform.android},
  );

  Widget field(FocusNode node, {Key? key}) => TvDeferredKeyboard(
        key: key,
        fieldFocusNode: node,
        builder: (context, focusNode, canRequestFocus) => TextField(
          focusNode: focusNode,
          canRequestFocus: canRequestFocus,
        ),
      );

  testWidgets('un toucher hors du champ referme le clavier', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          field(node),
          const SizedBox(key: ValueKey('page'), height: 400, width: 400),
        ]),
      ),
    ));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(node.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('page'))));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  }, variant: touch);

  testWidgets('un autre champ n’est pas « hors » : le clavier reste',
      (tester) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          field(first, key: const ValueKey('a')),
          field(second, key: const ValueKey('b')),
        ]),
      ),
    ));

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(second.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  }, variant: touch);

  testWidgets('au retour sur la page, le champ ne reprend pas le focus',
      (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(body: field(node)),
    ));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(node.hasFocus, isTrue);

    // La page des résultats, une fiche : ce qui recouvre le champ.
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: SizedBox.expand()),
    ));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse, reason: 'Flutter le lui rendait');
    expect(tester.testTextInput.isVisible, isFalse);

    // Le champ reste un champ : on y retape.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(node.hasFocus, isTrue);
  }, variant: touch);

  testWidgets('la touche « Rechercher » referme le clavier', (tester) async {
    final node = FocusNode();
    final controller = TextEditingController();
    addTearDown(node.dispose);
    addTearDown(controller.dispose);
    final submitted = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TvDeferredKeyboard(
          fieldFocusNode: node,
          builder: (context, focusNode, canRequestFocus) => GlassSearchInput(
            controller: controller,
            focusNode: focusNode,
            canRequestFocus: canRequestFocus,
            onSubmitted: submitted.add,
            hint: 'Rechercher',
          ),
        ),
      ),
    ));

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(submitted, contains('dune'));
    expect(node.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  }, variant: touch);

  testWidgets('sous une souris, Entrée garde le champ', (tester) async {
    final node = FocusNode();
    final controller = TextEditingController();
    addTearDown(node.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TvDeferredKeyboard(
          fieldFocusNode: node,
          builder: (context, focusNode, canRequestFocus) => GlassSearchInput(
            controller: controller,
            focusNode: focusNode,
            canRequestFocus: canRequestFocus,
            hint: 'Rechercher',
          ),
        ),
      ),
    ));

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'dune');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(node.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('la barre d’onglets du téléphone cède la place au clavier',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1170, 2532);
    addTearDown(tester.view.reset);
    // Sous un Scaffold, comme dans la coquille : il retire l'encart du
    // clavier du MediaQuery de son contenu.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const Expanded(child: SizedBox.expand()),
          MobileBottomNav(
            selected: ShellTabs.home,
            onTabSelected: (_) {},
            libraries: const [
              MediaLibrary(id: 1, name: 'Films', kind: LibraryKind.movies),
            ],
            canRequestMedia: true,
            canDownload: true,
          ),
        ]),
      ),
    ));
    expect(find.text('Accueil'), findsOneWidget);

    // Le clavier monte : la barre ne se pose plus sur lui.
    tester.view.viewInsets = const FakeViewPadding(bottom: 1008);
    await tester.pump();
    expect(find.text('Accueil'), findsNothing);

    tester.view.resetViewInsets();
    await tester.pump();
    expect(find.text('Accueil'), findsOneWidget);
  });
}
