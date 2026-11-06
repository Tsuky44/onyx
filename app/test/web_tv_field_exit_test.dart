import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/tv_deferred_keyboard.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/tv/web_tv_field_exit.dart';

import 'support/tv_nav_harness.dart';

/// Sur un téléviseur, le clavier virtuel se referme sans que le champ perde le
/// focus, et les flèches restent au curseur : sans sortie, la télécommande
/// restait dans le premier champ ouvert.
///
/// - **Ancien système** : [WebTvFieldExit] relâche le champ (Haut et Bas sur
///   webOS, les quatre flèches sur Android TV et Apple TV).
/// - **dpad** : Haut et Bas sortent d'un champ d'une ligne par la règle de
///   dpad, Gauche et Droite à ses bords. Sur webOS, `WebTvFieldExit` n'est
///   donc plus installé ; sur Android TV et Apple TV il l'est encore, pour
///   Gauche et Droite seulement (ADR-0110, phase 4).
void main() {
  tearDown(() {
    WebTvFieldExit.debugKeyboardOwnsRemote = null;
    WebTvFieldExit.debugUninstall();
  });

  /// Les écrans montent les champs sous le garde-fou de l'ancien système, qui
  /// donnait le focus lâché à l'élément suivant ; sous dpad, ce rôle est à
  /// dpad. Le banc monte l'un ou l'autre.
  Future<GlobalKey<TvDeferredKeyboardState>> pumpColumn(
    WidgetTester tester,
    TvNavEngine engine, {
    int maxLines = 1,
    String text = '',
    int caret = 0,
  }) async {
    final key = GlobalKey<TvDeferredKeyboardState>();
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    Widget field({Key? key}) => TvDeferredKeyboard(
          key: key,
          builder: (context, focusNode, canRequestFocus) => TextField(
            controller: key == null ? null : controller,
            focusNode: focusNode,
            canRequestFocus: canRequestFocus,
            maxLines: maxLines,
          ),
        );
    await TvNavHarness.pump(
      tester,
      Scaffold(
        body: Column(children: [field(), field(key: key), field()]),
      ),
      engine: engine,
    );
    key.currentState!.requestKeyboard();
    await tester.pumpAndSettle();
    controller.selection = TextSelection.collapsed(offset: caret);
    await tester.pump();
    return key;
  }

  /// Une rangée : une cible, un champ, une cible. [text] est écrit dans le
  /// champ, le curseur à [caret] (la fin du texte sans autre précision).
  Future<void> pumpRow(
    WidgetTester tester,
    TvNavEngine engine, {
    required String text,
    int? caret,
  }) async {
    final key = GlobalKey<TvDeferredKeyboardState>();
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await TvNavHarness.pump(
      tester,
      Scaffold(
        body: Row(children: [
          TvFocusable(onSelect: () {}, child: const TvTestTile('Gauche')),
          SizedBox(
            width: 400,
            child: TvDeferredKeyboard(
              key: key,
              builder: (context, focusNode, canRequestFocus) => TextField(
                controller: controller,
                focusNode: focusNode,
                canRequestFocus: canRequestFocus,
              ),
            ),
          ),
          TvFocusable(onSelect: () {}, child: const TvTestTile('Droite')),
        ]),
      ),
      engine: engine,
    );
    key.currentState!.requestKeyboard();
    await tester.pumpAndSettle();
    controller.selection = TextSelection.collapsed(offset: caret ?? text.length);
    await tester.pump();
  }

  bool editing() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  /// Le focus est sur le cadre de ce champ-là, pas sur un voisin.
  bool onFrameOf(GlobalKey<TvDeferredKeyboardState> key) {
    final focus = FocusManager.instance.primaryFocus;
    return focus?.debugLabel == 'tv-deferred-keyboard' &&
        focus?.context?.findAncestorStateOfType<TvDeferredKeyboardState>() ==
            key.currentState;
  }

  String? focusedTile() => focusedLabelOf(FocusManager.instance.primaryFocus);

  TvNavHarness.forEachEngine((engine) {
    // Le filet de l'ancien système tourne sur webOS sans dpad ; sous dpad, il
    // n'est pas installé sur webOS.
    group('webOS', () {
      setUp(() {
        if (engine == TvNavEngine.legacy) WebTvFieldExit.install();
      });

      for (final arrow in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
      ]) {
        testWidgets('${arrow.keyLabel} sort du champ', (tester) async {
          final key = await pumpColumn(tester, engine);
          expect(editing(), isTrue);

          await tester.sendKeyEvent(arrow);
          await tester.pumpAndSettle();

          expect(editing(), isFalse);
          // Rien ne reprend le focus au voisin où il vient d'arriver : le
          // champ-bouton quitté ne le récupère pas (sous dpad, c'était
          // `TvDeferredKeyboard` qui le rendait à son cadre).
          if (engine == TvNavEngine.dpad) {
            expect(onFrameOf(key), isFalse);
            expect(FocusManager.instance.primaryFocus?.debugLabel,
                'tv-deferred-keyboard');
          } else {
            expect(onFrameOf(key), isTrue);
          }
        });
      }

      // Sous dpad, un texte sur plusieurs lignes ne laisse sortir que de son
      // tout début ou de sa toute fin : les flèches verticales du milieu
      // gardent le curseur.
      testWidgets('un texte sur plusieurs lignes garde ses flèches',
          (tester) async {
        await pumpColumn(tester, engine,
            maxLines: 3, text: 'a\nb\nc', caret: 0);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();

        expect(editing(), isTrue);
      });

      testWidgets('hors téléviseur, le champ garde ses flèches',
          (tester) async {
        await pumpColumn(tester, engine);
        TvMode.enabled.value = false;
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();

        expect(editing(), isTrue);
      });
    });

    // Leur clavier ouvert garde la télécommande : une flèche qui arrive au
    // champ veut dire qu'il est fermé, et le champ ne la retient plus.
    group('Android TV et Apple TV', () {
      setUp(() {
        WebTvFieldExit.debugKeyboardOwnsRemote = true;
        WebTvFieldExit.install();
      });

      testWidgets('Gauche sort du champ, curseur au milieu du texte',
          (tester) async {
        await pumpRow(tester, engine, text: 'http://192.168.1.50', caret: 8);
        expect(editing(), isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();

        // Sans ce filet, dpad laisserait Gauche au curseur jusqu'au début du
        // texte : la télécommande restait prisonnière du champ.
        expect(editing(), isFalse);
        expect(focusedTile(), 'Gauche');
      });

      testWidgets('Droite sort du champ, curseur au milieu du texte',
          (tester) async {
        await pumpRow(tester, engine, text: 'http://192.168.1.50', caret: 8);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();

        expect(editing(), isFalse);
        expect(focusedTile(), 'Droite');
      });

      testWidgets('Bas sort du champ et fait le pas demandé, d’un seul appui',
          (tester) async {
        final key = await pumpColumn(tester, engine);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();

        // Le cadre du champ suivant, pas celui du champ quitté : le premier
        // appui ne se perd plus à poser l'anneau.
        expect(editing(), isFalse);
        expect(onFrameOf(key), isFalse);
        expect(FocusManager.instance.primaryFocus?.debugLabel,
            'tv-deferred-keyboard');
      });
    });
  });

  // La règle de dpad pour Gauche et Droite, sans le filet : webOS sous dpad.
  group('dpad sans filet', () {
    testWidgets('Gauche déplace le curseur tant qu\'il reste du texte',
        (tester) async {
      await pumpRow(tester, TvNavEngine.dpad,
          text: 'http://192.168.1.50', caret: 8);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(editing(), isTrue);
    });

    testWidgets('Gauche sort du champ au début du texte', (tester) async {
      await pumpRow(tester, TvNavEngine.dpad, text: 'abc', caret: 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(editing(), isFalse);
      expect(focusedTile(), 'Gauche');
    });

    testWidgets('Droite sort du champ à la fin du texte', (tester) async {
      await pumpRow(tester, TvNavEngine.dpad, text: 'abc');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(editing(), isFalse);
      expect(focusedTile(), 'Droite');
    });
  });
}
