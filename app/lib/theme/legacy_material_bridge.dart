// Le seul import de l'ancien Material dans `lib/` : c'est le rôle de ce
// fichier (ADR-0168, liste du test material_ui_migration_guard_test.dart).
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:flutter_localizations/flutter_localizations.dart'
    as legacy_l10n;
import 'package:material_ui/material_ui.dart';

/// Le thème et les textes de l'app, vus par l'**ancien** Material.
///
/// Depuis la migration vers `material_ui` (ADR-0168), l'app et ses dépendances
/// ne partagent plus le même Material : `material_ui` en est une copie
/// distincte, avec ses propres `Theme` et `MaterialLocalizations`. Une
/// dépendance qui importe encore `flutter/material.dart` (dpad, mobile_scanner,
/// octo_image, window_manager…) ne voit donc pas le thème de l'app : son
/// `Theme.of` retombe sur le thème clair par défaut (primaire violet, police
/// du système), et `MaterialLocalizations.of` échoue faute de textes.
///
/// Ce pont, posé une fois dans `MaterialApp.builder`, donne à ces widgets un
/// ancien `Theme` tiré de celui de l'app, et les textes de l'ancien Material
/// dans la langue de l'app, comme ceux de `material_ui`
/// (`AppMaterialLocalizations`).
///
/// Pourquoi pas `MaterialUiCompatibilityBridge`, le pont de `material_ui` :
/// il est lui-même déprécié (il faudrait un `ignore` de plus à chaque
/// usage) et il recalcule l'ancien thème à chaque construction. Celui-ci
/// fait la même correspondance (couleurs, textes, densité, plateforme) et
/// garde le résultat par thème. Les textes sont les mêmes : ceux de
/// `flutter_localizations`, dépréciés avec l'ancien Material.
///
/// À retirer quand plus aucune dépendance n'importe l'ancien Material : le
/// test de garde en tient la liste.
class LegacyMaterialBridge extends StatelessWidget {
  const LegacyMaterialBridge({super.key, required this.child});

  final Widget child;

  /// Un ancien thème par thème de l'app : le thème du téléviseur est recopié
  /// à chaque reconstruction de `MaterialApp`, celui du reste ne change pas.
  static final Expando<legacy.ThemeData> _legacyThemes =
      Expando<legacy.ThemeData>('LegacyMaterialBridge');

  /// Les traductions de l'ancien Material et de l'ancien Cupertino : ce sont
  /// d'autres types que ceux de `material_ui` et `cupertino_ui`, que
  /// l'app fournit déjà. La langue est celle de l'app, héritée.
  static const List<LocalizationsDelegate<dynamic>> _legacyDelegates =
      <LocalizationsDelegate<dynamic>>[
    // ignore: deprecated_member_use
    legacy_l10n.GlobalMaterialLocalizations.delegate,
    // ignore: deprecated_member_use
    legacy_l10n.GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return legacy.Theme(
      data: _legacyThemes[theme] ??= legacyThemeOf(theme),
      child: Localizations.override(
        context: context,
        delegates: _legacyDelegates,
        child: child,
      ),
    );
  }

  /// La même correspondance que `MaterialUiCompatibilityBridge` : couleurs,
  /// styles de texte (police comprise), densité et plateforme. Les thèmes de
  /// composants ne passent pas : aucun widget d'une dépendance affichée par
  /// l'app ne les lit.
  static legacy.ThemeData legacyThemeOf(ThemeData theme) {
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    return legacy.ThemeData(
      platform: theme.platform,
      visualDensity: legacy.VisualDensity(
        horizontal: theme.visualDensity.horizontal,
        vertical: theme.visualDensity.vertical,
      ),
      colorScheme: legacy.ColorScheme(
        brightness: scheme.brightness,
        primary: scheme.primary,
        onPrimary: scheme.onPrimary,
        primaryContainer: scheme.primaryContainer,
        onPrimaryContainer: scheme.onPrimaryContainer,
        secondary: scheme.secondary,
        onSecondary: scheme.onSecondary,
        secondaryContainer: scheme.secondaryContainer,
        onSecondaryContainer: scheme.onSecondaryContainer,
        tertiary: scheme.tertiary,
        onTertiary: scheme.onTertiary,
        tertiaryContainer: scheme.tertiaryContainer,
        onTertiaryContainer: scheme.onTertiaryContainer,
        error: scheme.error,
        onError: scheme.onError,
        errorContainer: scheme.errorContainer,
        onErrorContainer: scheme.onErrorContainer,
        surface: scheme.surface,
        onSurface: scheme.onSurface,
        surfaceDim: scheme.surfaceDim,
        surfaceBright: scheme.surfaceBright,
        surfaceContainerLowest: scheme.surfaceContainerLowest,
        surfaceContainerLow: scheme.surfaceContainerLow,
        surfaceContainer: scheme.surfaceContainer,
        surfaceContainerHigh: scheme.surfaceContainerHigh,
        surfaceContainerHighest: scheme.surfaceContainerHighest,
        onSurfaceVariant: scheme.onSurfaceVariant,
        outline: scheme.outline,
        outlineVariant: scheme.outlineVariant,
        shadow: scheme.shadow,
        scrim: scheme.scrim,
        inverseSurface: scheme.inverseSurface,
        onInverseSurface: scheme.onInverseSurface,
        inversePrimary: scheme.inversePrimary,
        surfaceTint: scheme.surfaceTint,
      ),
      textTheme: legacy.TextTheme(
        displayLarge: text.displayLarge,
        displayMedium: text.displayMedium,
        displaySmall: text.displaySmall,
        headlineLarge: text.headlineLarge,
        headlineMedium: text.headlineMedium,
        headlineSmall: text.headlineSmall,
        titleLarge: text.titleLarge,
        titleMedium: text.titleMedium,
        titleSmall: text.titleSmall,
        bodyLarge: text.bodyLarge,
        bodyMedium: text.bodyMedium,
        bodySmall: text.bodySmall,
        labelLarge: text.labelLarge,
        labelMedium: text.labelMedium,
        labelSmall: text.labelSmall,
      ),
    );
  }
}
