// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_theme.dart';
import '../liquid_glass.dart';

/// Le bouton de lecture du bandeau d'accueil : le verbe, puis l'épisode qu'il
/// lance, plus pâle (« Reprendre S2 E4 »).
///
/// Hors téléviseur, une pilule, comme les pièces de verre du reste de l'écran
/// (ADR-0154) ; sur un téléviseur, le bouton d'avant, que la télécommande
/// connaît (ADR-0112).
class HeroPlayButton extends StatelessWidget {
  const HeroPlayButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.episodeCode,
    this.autofocus = false,
    this.isTv = false,
  });

  final String label;
  final String? episodeCode;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool isTv;

  @override
  Widget build(BuildContext context) {
    final code = episodeCode;
    final text = code == null
        ? Text(label)
        : Text.rich(
            TextSpan(children: [
              TextSpan(text: label),
              const TextSpan(text: ' '),
              TextSpan(
                text: code,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.background.withValues(alpha: 0.55),
                ),
              ),
            ]),
            // Lu d'un seul tenant : « Reprendre S2 E4 ».
            semanticsLabel: '$label $code',
          );
    return ElevatedButton.icon(
      onPressed: onPressed,
      autofocus: autofocus,
      icon: Icon(AppIcons.play, size: isTv ? 28 : 22),
      label: text,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.symmetric(horizontal: isTv ? 28 : 24, vertical: 14),
        shape: isTv ? null : const StadiumBorder(),
      ),
    );
  }
}

/// « Plus d'infos » : la fiche du titre. Hors téléviseur, en verre liquide,
/// et réduit à son icône sur téléphone.
class HeroInfoButton extends StatelessWidget {
  const HeroInfoButton({
    super.key,
    required this.onPressed,
    this.compact = false,
    this.isTv = false,
  });

  final VoidCallback onPressed;
  final bool compact;
  final bool isTv;

  @override
  Widget build(BuildContext context) {
    final label = tr('Plus d’infos');
    if (isTv) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(AppIcons.info, size: 22),
        label: Text(label),
        // Sans bordure au repos, mais avec l'anneau au focus : `side` posé ici
        // remplaçait celui du thème, et « Plus d'infos » n'avait aucun focus
        // visible à la télécommande.
        style: AppTheme.focusRinged(
          OutlinedButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          resting: BorderSide.none,
        ),
      );
    }
    // Le verre porte le fond ; le bouton, transparent, garde le survol, le
    // toucher et l'anneau du clavier.
    final style = AppTheme.focusRinged(
      OutlinedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        shape: const StadiumBorder(),
        minimumSize: const Size(48, 48),
        padding: compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
      resting: BorderSide.none,
    );
    final button = compact
        ? SizedBox.square(
            dimension: 48,
            child: OutlinedButton(
              onPressed: onPressed,
              style: style,
              child: const Icon(AppIcons.info, size: 22),
            ),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(AppIcons.info, size: 22),
            label: Text(label),
            style: style,
          );
    return LiquidGlass(
      child: compact ? Tooltip(message: label, child: button) : button,
    );
  }
}
