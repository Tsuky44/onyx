import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../utils/poster_url.dart';
import '../../utils/responsive.dart';
import 'adaptive_panel.dart';
import 'app_network_image.dart';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// Les initiales d'une personne sans photo, sur un dégradé sombre.
class CastInitialsPlaceholder extends StatelessWidget {
  final String name;
  final double fontSize;

  const CastInitialsPlaceholder({
    super.key,
    required this.name,
    this.fontSize = AppType.title2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A2C2C), Color(0xFF161717)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

/// Toute la distribution en grille, ouverte par la dernière carte de
/// [CastSection] ; dans un panneau sur grand écran (ADR-0131).
class FullCastSheet extends StatelessWidget {
  final List<CastMember> cast;
  final void Function(CastMember member)? onTapMember;

  const FullCastSheet({super.key, required this.cast, this.onTapMember});

  @override
  Widget build(BuildContext context) {
    // Dans un panneau, le cadre vient du seam (ADR-0131).
    final panel = AdaptivePanelScope.isPanel(context);
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return Container(
      height: panel ? null : height,
      decoration: panel
          ? null
          : const BoxDecoration(
              color: Color(0xFF141515),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
      child: Column(
        children: [
          if (!panel)
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${tr('Distribution')} (${cast.length})',
                  style: const TextStyle(
                    fontSize: AppType.title2,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(AppIcons.close,
                      color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: GridView.builder(
              scrollCacheExtent: AppLayout.imageCacheExtent(context),
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                childAspectRatio: 0.62,
                crossAxisSpacing: 14,
                mainAxisSpacing: 18,
              ),
              itemCount: cast.length,
              itemBuilder: (context, index) {
                final member = cast[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    onTapMember?.call(member);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            color: const Color(0xFF1F2121),
                            width: double.infinity,
                            child: member.profileUrl != null &&
                                    member.profileUrl!.isNotEmpty
                                ? AppNetworkImage(
                                    url: castProfileUrl(member.profileUrl),
                                    fit: BoxFit.cover,
                                    errorWidget: CastInitialsPlaceholder(
                                        name: member.name),
                                  )
                                : CastInitialsPlaceholder(name: member.name),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppType.footnote,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (member.character != null &&
                          member.character!.isNotEmpty)
                        Text(
                          member.character!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppType.caption,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
