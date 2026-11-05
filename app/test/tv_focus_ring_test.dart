import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/theme/app_theme.dart';
import 'package:onyx/theme/app_type.dart';
import 'package:onyx/tv/tv_ui_scale.dart';
import 'package:onyx/widgets/global/detail_actions.dart';
import 'package:onyx/widgets/global/detail_hero.dart';

const _focused = <WidgetState>{WidgetState.focused};

void main() {
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
