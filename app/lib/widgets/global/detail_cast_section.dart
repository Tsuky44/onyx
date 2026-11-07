import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_focus.dart';
import '../../tv/nav/tv_region.dart';
import '../../utils/poster_url.dart';
import '../../utils/responsive.dart';
import 'app_network_image.dart';
import 'detail_metadata.dart';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

(String first, String rest) _splitName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return ('', '');
  if (parts.length == 1) return (parts[0], '');
  return (parts[0], parts.sublist(1).join(' '));
}

/// La distribution en éventail : cartes superposées inclinées selon la largeur.
/// La carte choisie se redresse et écarte ses voisines ; un second appui ouvre
/// la fiche de la personne. La dernière carte ouvre tout le casting.
class CastSection extends StatefulWidget {
  final List<CastMember> cast;
  final void Function(CastMember member)? onTapMember;

  /// Marge gauche/droite du titre. Par défaut la marge de page.
  final double? horizontalPadding;

  const CastSection({
    super.key,
    required this.cast,
    this.onTapMember,
    this.horizontalPadding,
  });

  /// Le diamètre d'un portrait pour le préchargement d'images.
  static const double avatarSize = 70;

  @override
  State<CastSection> createState() => _CastSectionState();
}

class _CastSectionState extends State<CastSection> {
  int _selectedIndex = 0;

  void _move(int step, int total) {
    if (total <= 0) return;
    setState(() {
      _selectedIndex = (_selectedIndex + step + total) % total;
    });
  }

  void _showFullCast(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FullCastSheet(
        cast: widget.cast,
        onTapMember: widget.onTapMember,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cast.isEmpty) return const SizedBox.shrink();

    final pad = widget.horizontalPadding ?? AppLayout.pagePadding(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final bool isNarrow = width < 600;
        final double cardWidth =
            isNarrow ? 88.0 : (width < 760 ? 140.0 : 150.0);
        final double cardHeight = cardWidth * 1.5;
        final double fanHeight =
            isNarrow ? 196.0 : (width < 760 ? 286.0 : 300.0);
        final double fanMargin = isNarrow ? 40.0 : 104.0;
        final int maxVisible = isNarrow ? 4 : 7;

        final int actorsCount = math.min(widget.cast.length, maxVisible);
        final bool hasMore = widget.cast.length > actorsCount;
        final int totalCards = actorsCount + (hasMore ? 1 : 0);
        final int current =
            _selectedIndex.clamp(0, math.max(0, totalCards - 1));

        final double step = totalCards <= 1
            ? 0.0
            : math.min(
                (width - fanMargin - 2 * cardWidth) /
                    math.max(totalCards - 2, 1),
                cardWidth * 0.78,
              );
        final double gap = math.max(0.0, cardWidth - step + 8.0);
        final double start = totalCards <= 1
            ? (width - cardWidth) / 2.0
            : (width - (step * (totalCards - 1) + cardWidth + gap)) / 2.0;

        final cardIndices = List.generate(totalCards, (i) => i);
        cardIndices.sort((a, b) {
          if (a == current) return 1;
          if (b == current) return -1;
          return a.compareTo(b);
        });

        final selectedActor =
            current < actorsCount ? widget.cast[current] : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête : Titre « Distribution », flèches et lien « Tout le casting »
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr('Distribution'),
                    style: detailSectionTitleStyle(context),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (actorsCount > 1) ...[
                        _ArrowButton(
                          icon: AppIcons.back,
                          tooltip: tr('Acteur précédent'),
                          onPressed: () => _move(-1, actorsCount),
                        ),
                        const SizedBox(width: 8),
                        _ArrowButton(
                          icon: AppIcons.chevronRight,
                          tooltip: tr('Acteur suivant'),
                          onPressed: () => _move(1, actorsCount),
                        ),
                        const SizedBox(width: 12),
                      ],
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _showFullCast(context),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${tr('Tout le casting')} (${widget.cast.length})',
                                style: const TextStyle(
                                  fontSize: AppType.footnote,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                AppIcons.chevronRight,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Éventail des cartes
            TvRegion.rail(
              child: SizedBox(
                height: fanHeight,
                width: width,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final i in cardIndices)
                      _buildAnimatedCard(
                        context: context,
                        index: i,
                        totalCards: totalCards,
                        actorsCount: actorsCount,
                        current: current,
                        start: start,
                        step: step,
                        gap: gap,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        fanHeight: fanHeight,
                        isNarrow: isNarrow,
                      ),
                  ],
                ),
              ),
            ),

            // Cartouche de l'acteur choisi sous l'éventail
            if (selectedActor != null) ...[
              const SizedBox(height: 16),
              Center(
                child: MouseRegion(
                  cursor: widget.onTapMember != null
                      ? SystemMouseCursors.click
                      : MouseCursor.defer,
                  child: GestureDetector(
                    onTap: widget.onTapMember == null
                        ? null
                        : () => widget.onTapMember!(selectedActor),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFF2F0ED)
                                  .withValues(alpha: 0.85),
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child: selectedActor.profileUrl != null &&
                                    selectedActor.profileUrl!.isNotEmpty
                                ? AppNetworkImage(
                                    url: castProfileUrl(
                                        selectedActor.profileUrl),
                                    fit: BoxFit.cover,
                                  )
                                : _InitialsPlaceholder(
                                    name: selectedActor.name,
                                    fontSize: AppType.footnote,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              selectedActor.name,
                              style: const TextStyle(
                                fontSize: AppType.headline,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (selectedActor.character != null &&
                                selectedActor.character!.isNotEmpty)
                              Text(
                                selectedActor.character!,
                                style: const TextStyle(
                                  fontSize: AppType.footnote,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAnimatedCard({
    required BuildContext context,
    required int index,
    required int totalCards,
    required int actorsCount,
    required int current,
    required double start,
    required double step,
    required double gap,
    required double cardWidth,
    required double cardHeight,
    required double fanHeight,
    required bool isNarrow,
  }) {
    final double k = index - (totalCards - 1) / 2.0;
    final bool isSelected = index == current;
    final bool isAfter = index > current;
    final double x = start + index * step + (isAfter ? gap : 0.0);
    final double lift = isSelected ? -18.0 : 0.0;
    final double y = k * k * 1.4 + lift;
    final double top = fanHeight - 18.0 - cardHeight + y;
    final double angle = isSelected ? 0.0 : (k * 2.2 * math.pi / 180.0);
    final double scale = isSelected ? 1.04 : 1.0;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      left: x,
      top: top,
      width: cardWidth,
      height: cardHeight,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        scale: scale,
        alignment: const FractionalOffset(0.5, 1.5),
        child: AnimatedRotation(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          turns: angle / (2 * math.pi),
          alignment: const FractionalOffset(0.5, 1.5),
          child: TvFocusable(
            borderRadius: BorderRadius.circular(14),
            onFocusChange: (focused) {
              if (focused && index != current) {
                setState(() => _selectedIndex = index);
              }
            },
            onSelect: () {
              if (index != current) {
                setState(() => _selectedIndex = index);
              } else {
                if (index < actorsCount) {
                  widget.onTapMember?.call(widget.cast[index]);
                } else {
                  _showFullCast(context);
                }
              }
            },
            child: GestureDetector(
              onTap: () {
                if (index != current) {
                  setState(() => _selectedIndex = index);
                } else {
                  if (index < actorsCount) {
                    widget.onTapMember?.call(widget.cast[index]);
                  } else {
                    _showFullCast(context);
                  }
                }
              },
              child: index < actorsCount
                  ? _buildActorCard(
                      member: widget.cast[index],
                      isSelected: isSelected,
                      isNarrow: isNarrow,
                    )
                  : _buildPlusCard(
                      remaining: widget.cast.length - actorsCount,
                      isSelected: isSelected,
                      isNarrow: isNarrow,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActorCard({
    required CastMember member,
    required bool isSelected,
    required bool isNarrow,
  }) {
    final (first, rest) = _splitName(member.name);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF1F2121),
        border: isSelected
            ? Border.all(
                color: const Color(0xFFF2F0ED).withValues(alpha: 0.85),
                width: 2,
              )
            : Border.all(
                color: Colors.white.withValues(alpha: 0.09),
                width: 1,
              ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.95),
                  blurRadius: 40,
                  offset: const Offset(0, 26),
                  spreadRadius: -16,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.9),
                  blurRadius: 22,
                  offset: const Offset(-10, 0),
                  spreadRadius: -12,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.9),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                  spreadRadius: -16,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (member.profileUrl != null && member.profileUrl!.isNotEmpty)
              AppNetworkImage(
                url: castProfileUrl(member.profileUrl),
                fit: BoxFit.cover,
                errorWidget: _InitialsPlaceholder(name: member.name),
              )
            else
              _InitialsPlaceholder(name: member.name),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  isNarrow ? 7 : 10,
                  isNarrow ? 24 : 34,
                  isNarrow ? 7 : 10,
                  isNarrow ? 8 : 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                    stops: const [0.0, 0.3, 1.0],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isNarrow ? AppType.caption : AppType.footnote,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (rest.isNotEmpty)
                      Text(
                        rest,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize:
                              isNarrow ? AppType.caption : AppType.footnote,
                          color: const Color(0xFFDFDCD9),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlusCard({
    required int remaining,
    required bool isSelected,
    required bool isNarrow,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF1E1F1F),
        border: isSelected
            ? Border.all(
                color: const Color(0xFFF2F0ED).withValues(alpha: 0.85),
                width: 2,
              )
            : Border.all(
                color: Colors.white.withValues(alpha: 0.09),
                width: 1,
              ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.9),
            blurRadius: 22,
            offset: const Offset(-10, 0),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '+$remaining',
                style: TextStyle(
                  fontSize: isNarrow ? AppType.title1 : AppType.display,
                  fontWeight: FontWeight.w300,
                  color: const Color(0xFFF2F0ED),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('Tout le casting'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isNarrow ? AppType.micro : AppType.caption,
                  color: const Color(0xFFA8A5A1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: IconButton(
        icon: Icon(icon, size: 16, color: Colors.white),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
      ),
    );
  }
}

class _InitialsPlaceholder extends StatelessWidget {
  final String name;
  final double fontSize;

  const _InitialsPlaceholder({
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

class _FullCastSheet extends StatelessWidget {
  final List<CastMember> cast;
  final void Function(CastMember member)? onTapMember;

  const _FullCastSheet({required this.cast, this.onTapMember});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFF141515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
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
                                    errorWidget: _InitialsPlaceholder(
                                        name: member.name),
                                  )
                                : _InitialsPlaceholder(name: member.name),
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
