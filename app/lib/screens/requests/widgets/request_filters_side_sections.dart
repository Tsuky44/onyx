import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../models/request_catalog_filters.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../widgets/global/filter_panel/onyx_filter_panel.dart';
import 'request_provider_logo.dart';

/// Ce qui n'appartient qu'au panneau des Demandes : la grille des logos de
/// streaming et la note d'une liste qui charge. Le reste du panneau vient
/// de `widgets/global/filter_panel/`.

/// Les services de streaming en tuiles de logos, cinq par rangée. Les
/// [preview] premiers (les mieux classés dans la région) et les cochés se
/// montrent d'abord ; le reste attend « Voir les autres ».
class RequestProviderTiles extends StatefulWidget {
  const RequestProviderTiles({
    super.key,
    required this.providers,
    required this.selected,
    required this.onToggle,
    this.preview = requestProviderPreviewLimit,
  });

  final List<RequestWatchProvider> providers;
  final List<int> selected;
  final ValueChanged<int> onToggle;
  final int preview;

  @override
  State<RequestProviderTiles> createState() => _RequestProviderTilesState();
}

class _RequestProviderTilesState extends State<RequestProviderTiles> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.providers;
    final shown = _all
        ? all
        : [
            for (var i = 0; i < all.length; i++)
              if (i < widget.preview ||
                  widget.selected.contains(all[i].providerId))
                all[i],
          ];
    final hidden = all.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 5,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final p in shown)
              _ProviderTile(
                provider: p,
                selected: widget.selected.contains(p.providerId),
                onTap: () => widget.onToggle(p.providerId),
              ),
          ],
        ),
        if (hidden > 0 || _all) ...[
          const SizedBox(height: 6),
          OnyxFilterLink(
            label: _all
                ? tr('Voir moins')
                : trPlural(hidden, 'Voir 1 autre service',
                    'Voir les {0} autres services'),
            expanded: _all,
            onPressed: () => setState(() => _all = !_all),
          ),
        ],
      ],
    );
  }
}

/// Un logo de service : un anneau blanc et une coche quand il est coché, le
/// nom en bulle au survol.
class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final RequestWatchProvider provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: provider.providerName,
      child: Semantics(
        button: true,
        selected: selected,
        label: provider.providerName,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: LayoutBuilder(builder: (context, constraints) {
            final side = constraints.biggest.shortestSide;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: AppMotion.fade(context, AppMotion.micro),
                  curve: AppMotion.curve,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    // Au repos, le filet des capsules : un logo qui charge
                    // ou qui manque a la couleur du panneau, et sans lui la
                    // tuile disparaîtrait.
                    border: Border.all(
                      width: 2,
                      color:
                          selected ? AppColors.textPrimary : AppColors.border,
                    ),
                  ),
                  child: RequestProviderLogo(
                      url: provider.logoUrl, size: side - 10),
                ),
                if (selected)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.surfaceElevated, width: 2),
                      ),
                      child: const Icon(AppIcons.check,
                          size: 10, color: AppColors.background),
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// Une liste qui charge, qui a échoué (avec « Réessayer ») ou qui est vide,
/// à la place des capsules ou des logos.
class RequestPanelNote extends StatelessWidget {
  const RequestPanelNote.loading({super.key})
      : message = null,
        onRetry = null;

  const RequestPanelNote({super.key, required this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    final onRetry = this.onRetry;
    if (message == null) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: AppType.subhead,
            ),
          ),
        ),
        if (onRetry != null)
          OnyxFilterLink(label: tr('Réessayer'), onPressed: onRetry),
      ],
    );
  }
}
