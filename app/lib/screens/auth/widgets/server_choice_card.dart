import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../models/server_account.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_focus.dart';
import '../../../widgets/global/profile_disc.dart';

/// Une carte de « Quel serveur ? » : un carré teinté, l'initiale du serveur,
/// son nom et une ligne d'état dessous.
///
/// La carte choisie porte un liseré blanc détaché de 2 px, comme la pastille
/// de la personne en cours dans le menu du compte (ADR-0126). L'emplacement du
/// liseré est toujours réservé : choisir une autre carte ne décale rien.
/// L'adresse technique n'est qu'en infobulle, au survol.
class ServerChoiceCard extends StatefulWidget {
  const ServerChoiceCard({
    super.key,
    required this.account,
    required this.size,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    this.status,
    this.autofocus = false,
  });

  final ServerAccount account;
  final double size;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;

  /// La ligne d'état ; rien quand l'information n'existe pas.
  final String? status;
  final bool autofocus;

  /// Écart entre la carte et son liseré, et épaisseur de celui-ci.
  static const double ringGap = 2;
  static const double ringWidth = 2;
  static const double radius = 22;

  /// Largeur d'une carte avec son liseré, pour caler le nom dessous.
  static double slotWidth(double size) => size + 2 * (ringGap + ringWidth);

  @override
  State<ServerChoiceCard> createState() => _ServerChoiceCardState();
}

class _ServerChoiceCardState extends State<ServerChoiceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final name = account.displayName;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final size = widget.size;
    final radius = BorderRadius.circular(ServerChoiceCard.radius * size / 120);

    return _CardFrame(
      width: ServerChoiceCard.slotWidth(size),
      name: name,
      nameBright: widget.selected,
      status: widget.status,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: tr('Serveur {0}', [name]),
        onTap: widget.enabled ? widget.onSelect : null,
        excludeSemantics: true,
        child: Tooltip(
          message: account.prettyHost,
          waitDuration: const Duration(milliseconds: 400),
          child: TvFocusable(
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            onSelect: widget.onSelect,
            borderRadius: radius,
            child: MouseRegion(
              cursor:
                  widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.enabled ? widget.onSelect : null,
                child: AnimatedContainer(
                  duration: AppMotion.fade(context, AppMotion.micro),
                  curve: AppMotion.curve,
                  padding: const EdgeInsets.all(ServerChoiceCard.ringGap),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      radius.topLeft.x + ServerChoiceCard.ringGap,
                    ),
                    border: Border.all(
                      color: widget.selected
                          ? AppColors.textPrimary
                          : Colors.transparent,
                      width: ServerChoiceCard.ringWidth,
                    ),
                  ),
                  child: AnimatedOpacity(
                    opacity: _hovered && !widget.selected ? 0.86 : 1,
                    duration: AppMotion.fade(context, AppMotion.micro),
                    curve: AppMotion.curve,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: ProfileDisc.tintFor(account),
                        borderRadius: radius,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: size / 3,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La carte « Ajouter » : mêmes mesures, bordure en pointillés et un « + ».
class AddServerCard extends StatefulWidget {
  const AddServerCard({
    super.key,
    required this.size,
    required this.enabled,
    required this.onSelect,
  });

  final double size;
  final bool enabled;
  final VoidCallback onSelect;

  @override
  State<AddServerCard> createState() => _AddServerCardState();
}

class _AddServerCardState extends State<AddServerCard> {
  bool _lit = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final radius = BorderRadius.circular(ServerChoiceCard.radius * size / 120);
    return _CardFrame(
      width: ServerChoiceCard.slotWidth(size),
      name: tr('Ajouter'),
      nameBright: false,
      child: Semantics(
        button: true,
        label: tr('Ajouter un serveur'),
        onTap: widget.enabled ? widget.onSelect : null,
        excludeSemantics: true,
        child: TvFocusable(
          enabled: widget.enabled,
          onSelect: widget.onSelect,
          borderRadius: radius,
          child: MouseRegion(
            cursor:
                widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
            onEnter: (_) => setState(() => _lit = true),
            onExit: (_) => setState(() => _lit = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.enabled ? widget.onSelect : null,
              child: Padding(
                padding: const EdgeInsets.all(
                  ServerChoiceCard.ringGap + ServerChoiceCard.ringWidth,
                ),
                child: CustomPaint(
                  foregroundPainter: _DashedBorder(
                    radius: radius,
                    color: Colors.white.withValues(alpha: _lit ? 0.5 : 0.28),
                  ),
                  child: AnimatedContainer(
                    duration: AppMotion.fade(context, AppMotion.micro),
                    curve: AppMotion.curve,
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      color: Colors.white.withValues(alpha: _lit ? 0.08 : 0.03),
                    ),
                    child: Icon(
                      AppIcons.add,
                      size: size * 0.3,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le nom et la ligne d'état sous une carte, sur une largeur fixe pour que la
/// rangée reste alignée quelle que soit la longueur des noms.
class _CardFrame extends StatelessWidget {
  const _CardFrame({
    required this.width,
    required this.name,
    required this.nameBright,
    required this.child,
    this.status,
  });

  final double width;
  final String name;
  final bool nameBright;
  final String? status;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  nameBright ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: AppType.callout,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (status != null) ...[
            const SizedBox(height: 2),
            Text(
              status!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppType.footnote,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.radius, required this.color});

  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(radius.toRRect(Offset.zero & size).deflate(0.5));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final PathMetric metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 11) {
        canvas.drawPath(metric.extractPath(at, at + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}
