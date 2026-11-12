import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_page_transitions.dart';
import '../tv/tv_mode.dart';
import 'focus_fill.dart';
import '../theme/app_type.dart';

abstract final class AppTheme {
  /// La police de l'application, embarquée dans le paquet — voir l'ADR-0025.
  ///
  /// Elle l'était auparavant par `google_fonts`, qui allait chercher les mêmes
  /// fichiers sur le réseau au premier lancement et les relisait depuis un
  /// cache disque aux suivants. Entre les deux, le texte s'affichait dans la
  /// police du système puis sautait : une application qui doit ouvrir un film
  /// sans serveur joignable ne peut pas dépendre de Google pour écrire un
  /// titre.
  static const String fontFamily = 'Manrope';

  /// The outline a focused control wears.
  ///
  /// Material's own focus treatment is a ten-percent wash of the primary
  /// colour — legible at arm's length on a phone, invisible from a sofa. A
  /// remote-driven UI lives or dies on the user being able to find the cursor,
  /// so focus gets a real ring, on every button, everywhere.
  static WidgetStateProperty<BorderSide?> _focusSide(BorderSide? resting,
      {Color color = AppColors.focus}) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: color, width: 2.5);
      }
      return resting;
    });
  }

  /// Le bord d'une puce ([ChoiceChip]) : [resting] au repos, l'anneau au
  /// focus.
  ///
  /// Le focus d'une puce n'était qu'un voile bleu — le même que celui d'une
  /// puce choisie. Dans une rangée « 2 3 4 5 », la télécommande ne savait pas
  /// distinguer le choix en cours de celui qu'elle survolait.
  static BorderSide chipSide(BorderSide resting) {
    return WidgetStateBorderSide.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return const BorderSide(color: AppColors.focus, width: 2.5);
      }
      return resting;
    });
  }

  /// Le thème, construit une fois.
  ///
  /// C'était un getter : chaque lecture reconstruisait `ThemeData` et toutes
  /// ses déclinaisons — et en rendait une *autre instance*, ce qui fait
  /// reconstruire tout ce qui lit `Theme.of(context)`. La racine le lit deux
  /// fois sur un téléviseur.
  static ThemeData? _dark;
  static ThemeData get dark => _dark ??= _buildDark();

  static ThemeData _buildDark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      // Posé sur le thème et non sur le seul `textTheme` : un `TextStyle`
      // construit à la main, sans partir d'un style du thème, hérite alors de
      // la police lui aussi au lieu de retomber sur celle du système.
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      // Une seule transition de page, quel que soit le système — voir
      // [OnyxPageTransitionsBuilder].
      pageTransitionsTheme: appPageTransitionsTheme,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accentMuted,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.onAccent,
        onSecondary: AppColors.onAccent,
        onSurface: AppColors.textPrimary,
        outline: AppColors.border,
      ),
    );

    final textTheme = base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: AppType.title3,
          letterSpacing: -0.02 * 20,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceElevated,
        selectedColor: AppColors.primary.withValues(alpha: 0.22),
        labelStyle:
            textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: chipSide(BorderSide(color: AppColors.glassBorder)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.glassBorder,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        labelStyle:
            textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      // Blanc au repos, sauf sur téléviseur : la commande blanche y est
      // celle qui a le focus (ADR-0112).
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: focusRinged(
            restOnTv: FocusFill.glass,
            ElevatedButton.styleFrom(
              backgroundColor: AppColors.textPrimary,
              foregroundColor: AppColors.background,
              disabledBackgroundColor: AppColors.surfaceHover,
              disabledForegroundColor: AppColors.textMuted,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            )),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: focusRinged(
          OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: BorderSide(color: AppColors.glassBorder),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          resting: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      // Les boutons-icônes aussi : sans anneau, leur focus n'était qu'un voile
      // de 10 % sur un disque déjà gris — les actions d'une fiche ou d'un
      // épisode devenaient introuvables à la télécommande.
      iconButtonTheme: IconButtonThemeData(
        style: focusRinged(const ButtonStyle()),
      ),
      // Un bouton plein se remplit de la couleur de l'anneau : le même bleu
      // sur le même bleu, « Nouvelle liste » ne montrait aucun focus. Son
      // anneau est blanc.
      filledButtonTheme: FilledButtonThemeData(
        style: FocusFill.wrap(const ButtonStyle().copyWith(
          side: _focusSide(null, color: AppColors.textPrimary),
        )),
      ),
      textButtonTheme: TextButtonThemeData(
        style: focusRinged(TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        )),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.textPrimary,
        foregroundColor: AppColors.background,
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      focusColor: AppColors.primary.withValues(alpha: 0.24),
      // Pas d'ondulation Material : l'onde qui se propage depuis le doigt est
      // l'idiome d'Android, et sur un fond charbon elle se lisait comme une
      // tache grise sous chaque ligne pressée. Les boutons gardent leur voile
      // d'appui (overlayColor), les cartes leur échelle (`Pressable`).
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.white.withValues(alpha: 0.04),
      hoverColor: Colors.white.withValues(alpha: 0.04),
      // Menus, listes déroulantes et infobulles : une seule matière, celle
      // des popovers de verre (`GlassSurface`) — un fond élevé, un filet clair
      // et une ombre ample, plutôt que la teinte de surface de Material 3.
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.6),
        shape: _menuShape,
        textStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        labelTextStyle: WidgetStatePropertyAll(textTheme.bodyMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        )),
      ),
      menuTheme: MenuThemeData(style: _menuStyle),
      dropdownMenuTheme: DropdownMenuThemeData(menuStyle: _menuStyle),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: AppColors.surfaceHover,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.glassBorder),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  static final ShapeBorder _menuShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: BorderSide(color: AppColors.glassBorder),
  );

  static final MenuStyle _menuStyle = MenuStyle(
    backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceElevated),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(12),
    shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.6)),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: AppColors.glassBorder),
    )),
  );

  /// Les menus contextuels d'un téléviseur, à l'échelle de ses pages.
  ///
  /// Un menu s'ouvre dans une route à part, que [TvUiScale] n'agrandit pas
  /// (elle ne s'applique qu'aux pages) : sur l'Apple TV, qui annonce 1920
  /// points de large, le menu du compte s'affichait aux deux tiers de la
  /// taille de la page, illisible du canapé. [scale] est le facteur de
  /// [TvUiScale] ; seuls les textes et les marges du menu le suivent, sa
  /// position reste celle que calcule Flutter.
  static PopupMenuThemeData popupMenuThemeScaled(double scale) {
    final base = dark.popupMenuTheme;
    final factor = scale * tvMenuBoost;
    TextStyle? grow(TextStyle? style) =>
        style?.copyWith(fontSize: (style.fontSize ?? AppType.body) * factor);
    return base.copyWith(
      textStyle: grow(base.textStyle),
      labelTextStyle: WidgetStatePropertyAll(
          grow(base.labelTextStyle?.resolve(const <WidgetState>{}))),
      menuPadding: EdgeInsets.symmetric(vertical: 8 * factor),
    );
  }

  /// Ce qu'un menu de téléviseur prend en plus de l'échelle de la page : à
  /// l'échelle seule, le menu du compte restait « trop petit » à l'essai sur
  /// Apple TV (2026-11-12). Un menu se lit de plus loin qu'une page, d'un
  /// coup d'œil, et ses lignes sont des cibles.
  static const double tvMenuBoost = 1.25;

  /// Le facteur par lequel les menus grandissent ici : celui de
  /// [popupMenuThemeScaled] sur un téléviseur, 1 ailleurs. Pour ce que le
  /// thème ne sait pas porter : la hauteur d'une ligne, la taille d'une
  /// icône, la largeur du menu.
  static double menuScaleOf(BuildContext context) {
    // Le style de base n'a pas de taille à lui : c'est celle du corps de
    // texte, la même que [popupMenuThemeScaled] agrandit.
    final size = Theme.of(context).popupMenuTheme.textStyle?.fontSize;
    final base = dark.popupMenuTheme.textStyle?.fontSize ?? AppType.body;
    if (size == null || base <= 0) return 1;
    return size / base;
  }

  /// Adds the focus ring to a button style without disturbing anything else it
  /// declares. [resting] is the border the button wears when it is not focused.
  ///
  /// Public for the local button themes, which replace the app's instead of
  /// merging into it ([DetailActions.secondaryStyle]).
  ///
  /// Sur téléviseur, le bouton focalisé se remplit aussi de blanc
  /// ([FocusFill], ADR-0112) : l'anneau seul ne se voyait pas sur un bouton
  /// déjà blanc. [restOnTv] : voir [FocusFill.wrap].
  static ButtonStyle focusRinged(ButtonStyle style,
      {BorderSide? resting, Color? restOnTv}) {
    return FocusFill.wrap(
        _capsuleOnTv(style).copyWith(side: _focusSide(resting)),
        restOnTv: restOnTv);
  }

  /// Sur téléviseur, un bouton est une capsule (ADR-0118) : la forme des
  /// commandes des interfaces de salon, qui se lit de loin comme « bouton »
  /// là où un rectangle arrondi se confond avec une carte. Ailleurs, la forme
  /// que le style déclare.
  static ButtonStyle _capsuleOnTv(ButtonStyle style) {
    final shape = style.shape;
    return style.copyWith(
      shape: WidgetStateProperty.resolveWith(
        (states) =>
            TvMode.isTv ? const StadiumBorder() : shape?.resolve(states),
      ),
    );
  }
}
