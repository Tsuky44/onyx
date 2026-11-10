import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/theme/app_theme.dart';
import 'package:onyx/theme/focus_fill.dart';
import 'package:onyx/tv/tv_mode.dart';

const _focused = <WidgetState>{WidgetState.focused};
const _rest = <WidgetState>{};

/// ADR-0112 : sur téléviseur, la seule commande blanche est celle qui a le
/// focus.
void main() {
  late bool previous;
  setUp(() => previous = TvMode.enabled.value);
  tearDown(() => TvMode.enabled.value = previous);

  ButtonStyle elevated() => AppTheme.dark.elevatedButtonTheme.style!;

  test('sur téléviseur, le bouton focalisé se remplit de blanc, texte noir',
      () {
    TvMode.enabled.value = true;
    for (final style in <ButtonStyle>[
      elevated(),
      AppTheme.dark.outlinedButtonTheme.style!,
      AppTheme.dark.textButtonTheme.style!,
      AppTheme.dark.iconButtonTheme.style!,
      AppTheme.dark.filledButtonTheme.style!,
    ]) {
      expect(style.backgroundColor?.resolve(_focused), FocusFill.fill);
      expect(style.foregroundColor?.resolve(_focused), FocusFill.ink);
    }
  });

  test('sur téléviseur, le bouton blanc au repos passe au verre', () {
    TvMode.enabled.value = true;
    expect(elevated().backgroundColor?.resolve(_rest), FocusFill.glass);
    expect(elevated().foregroundColor?.resolve(_rest), AppColors.textPrimary);
  });

  test(
      'hors téléviseur, le bouton principal reste blanc et le focus garde '
      'son anneau', () {
    TvMode.enabled.value = false;
    expect(elevated().backgroundColor?.resolve(_rest), AppColors.textPrimary);
    expect(
        elevated().backgroundColor?.resolve(_focused), AppColors.textPrimary);
    expect(elevated().side?.resolve(_focused)?.color, AppColors.focus);
  });

  test('un bouton désactivé ne prend pas le remplissage', () {
    TvMode.enabled.value = true;
    expect(
      elevated().backgroundColor?.resolve(
          const <WidgetState>{WidgetState.focused, WidgetState.disabled}),
      isNot(FocusFill.fill),
    );
  });
}
