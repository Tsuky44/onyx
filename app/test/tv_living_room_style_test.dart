import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/settings/widgets/settings_ui.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/theme/app_theme.dart';
import 'package:onyx/theme/focus_fill.dart';
import 'package:onyx/tv/tv_mode.dart';

/// Le style de salon d'un téléviseur (ADR-0118) : des boutons en capsule, et
/// une ligne de réglage qui se remplit de blanc quand la télécommande la vise.

void _tv(bool enabled) {
  final previous = TvMode.enabled.value;
  TvMode.enabled.value = enabled;
  addTearDown(() => TvMode.enabled.value = previous);
}

Future<void> _pumpTile(
  WidgetTester tester, {
  required bool isTv,
  required FocusNode node,
  Widget? trailing,
}) async {
  _tv(isTv);
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.automatic);
  await tester.pumpWidget(TvScope(
    isTv: isTv,
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Focus(
          focusNode: node,
          canRequestFocus: false,
          child: SettingsTile(
            title: 'Lecteur Apple TV',
            subtitle: 'Natif ou Onyx',
            trailing: trailing,
            onTap: () {},
          ),
        ),
      ),
    ),
  ));
}

Color _titleColor(WidgetTester tester) =>
    tester.widget<Text>(find.text('Lecteur Apple TV')).style!.color!;

void main() {
  group('boutons', () {
    for (final (name, style) in [
      ('plein', (ThemeData t) => t.elevatedButtonTheme.style!),
      ('à bordure', (ThemeData t) => t.outlinedButtonTheme.style!),
    ]) {
      test('sur téléviseur, un bouton $name est une capsule', () {
        _tv(true);
        expect(style(AppTheme.dark).shape!.resolve({}), isA<StadiumBorder>());
      });

      test('ailleurs, un bouton $name garde son rectangle arrondi', () {
        _tv(false);
        expect(style(AppTheme.dark).shape!.resolve({}),
            isA<RoundedRectangleBorder>());
      });
    }
  });

  group('menus', () {
    testWidgets('ce que le thème ne porte pas lit le même facteur',
        (tester) async {
      late double onTv;
      late double elsewhere;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark.copyWith(
          popupMenuTheme: AppTheme.popupMenuThemeScaled(1.5),
        ),
        home: Builder(builder: (context) {
          onTv = AppTheme.menuScaleOf(context);
          return Theme(
            data: AppTheme.dark,
            child: Builder(builder: (context) {
              elsewhere = AppTheme.menuScaleOf(context);
              return const SizedBox();
            }),
          );
        }),
      ));

      expect(onTv, closeTo(1.5 * AppTheme.tvMenuBoost, 1e-9));
      expect(elsewhere, 1);
    });
  });

  group('ligne de réglage', () {
    testWidgets('visée sur téléviseur, son texte passe au noir sur blanc',
        (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await _pumpTile(tester, isTv: true, node: node);
      expect(_titleColor(tester), AppColors.textPrimary);

      node.descendants.first.requestFocus();
      await tester.pump();

      expect(_titleColor(tester), FocusFill.ink);
      expect(tester.widget<InkWell>(find.byType(InkWell)).focusColor,
          FocusFill.fill);
    });

    testWidgets(
        'le focus sur sa commande ne la remplit pas, et la commande le garde',
        (tester) async {
      // Enveloppée au moment où elle prend le focus, la commande renaissait
      // et le perdait : droite depuis une catégorie revenait à la catégorie.
      final node = FocusNode();
      final control = FocusNode();
      addTearDown(node.dispose);
      addTearDown(control.dispose);
      await _pumpTile(
        tester,
        isTv: true,
        node: node,
        trailing: TextButton(
          focusNode: control,
          onPressed: () {},
          child: const Text('Changer'),
        ),
      );

      control.requestFocus();
      await tester.pump();
      await tester.pump();

      expect(control.hasPrimaryFocus, isTrue);
      expect(_titleColor(tester), AppColors.textPrimary);
    });

    testWidgets('sa valeur est repeinte en encre, pas un interrupteur',
        (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await _pumpTile(tester,
          isTv: true, node: node, trailing: const Text('Natif'));
      node.descendants.first.requestFocus();
      await tester.pump();
      expect(
        find.ancestor(
            of: find.text('Natif'), matching: find.byType(ColorFiltered)),
        findsOneWidget,
      );

      await _pumpTile(
        tester,
        isTv: true,
        node: node,
        trailing: Switch(value: true, onChanged: (_) {}),
      );
      await tester.pump();
      expect(
        find.ancestor(
            of: find.byType(Switch), matching: find.byType(ColorFiltered)),
        findsNothing,
      );
    });

    testWidgets('hors téléviseur, le focus ne change pas son texte',
        (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await _pumpTile(tester, isTv: false, node: node);

      node.descendants.first.requestFocus();
      await tester.pump();

      expect(_titleColor(tester), AppColors.textPrimary);
    });
  });
}
