import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/theme/app_theme.dart';
import 'package:onyx/theme/app_type.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/tv/tv_ui_scale.dart';
import 'package:onyx/widgets/global/detail_actions.dart';
import 'package:onyx/widgets/global/detail_hero.dart';

import 'support/tv_nav_harness.dart';

const _focused = <WidgetState>{WidgetState.focused};

/// L'anneau d'Onyx : la bordure d'accent posée sur la carte focalisée.
Finder _ring() => find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.border is Border &&
          (decoration.border! as Border).top.color == AppColors.accent;
    });

void main() {
  // Les styles et l'échelle ci-dessous ne dépendent d'aucun système de
  // navigation ; l'anneau d'une carte, lui, est dessiné par l'un ou l'autre.
  TvNavHarness.forEachEngine((engine) {
    testWidgets('l’anneau est dessiné sur la carte focalisée et la suit',
        (tester) async {
      final nav = await TvNavHarness.pump(
        tester,
        Scaffold(
          body: Row(
            children: [
              TvFocusable(
                autofocus: true,
                onSelect: () {},
                child: const TvTestTile('a'),
              ),
              TvFocusable(onSelect: () {}, child: const TvTestTile('b')),
            ],
          ),
        ),
        engine: engine,
      );
      expect(nav.focusedLabel, 'a');
      expect(_ring(), findsOneWidget);

      await nav.press(TraversalDirection.right);

      expect(nav.focusedLabel, 'b');
      expect(_ring(), findsOneWidget,
          reason: 'un seul anneau : celui de la carte qui a le focus');
    });

    testWidgets('hors téléviseur, aucun anneau n’est dessiné', (tester) async {
      await TvNavHarness.pump(
        tester,
        Scaffold(
          body: TvFocusable(
            autofocus: true,
            onSelect: () {},
            child: const TvTestTile('a'),
          ),
        ),
        engine: engine,
        isTv: false,
      );

      expect(_ring(), findsNothing);
    });
  });

  testWidgets(
      'les boutons ronds d’une fiche gardent l’anneau de focus sous leur filet',
      (tester) async {
    late ButtonStyle style;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        style = heroRoundButtonStyle(context, DetailActions.secondaryStyle);
        return const SizedBox();
      }),
    ));

    expect(style.side?.resolve(_focused)?.color, AppColors.accent);
    expect(style.side?.resolve(const <WidgetState>{})?.color,
        isNot(AppColors.accent));
  });

  test('un bouton plein porte un anneau blanc, visible sur son fond bleu', () {
    final side = AppTheme.dark.filledButtonTheme.style?.side?.resolve(_focused);

    expect(side?.color, AppColors.textPrimary);
    expect(side?.width, greaterThan(2));
  });

  test('les menus d’un téléviseur suivent l’échelle de ses pages', () {
    // Le thème ne fixe pas toujours la taille : c'est alors celle du corps.
    final base =
        AppTheme.dark.popupMenuTheme.textStyle!.fontSize ?? AppType.body;
    final scaled = AppTheme.popupMenuThemeScaled(1.5);

    expect(scaled.textStyle!.fontSize, base * 1.5);
    expect(
      scaled.labelTextStyle!.resolve(const <WidgetState>{})!.fontSize,
      base * 1.5,
    );
  });

  test('l’échelle d’un téléviseur se lit sur sa largeur', () {
    expect(TvUiScale.factorFor(1920), 1.5);
    expect(TvUiScale.factorFor(960), 0.75);
    // Rien à mesurer : pas d'agrandissement plutôt qu'une division par zéro.
    expect(TvUiScale.factorFor(0), 1);
  });
}
