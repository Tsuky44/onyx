import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../../utils/responsive.dart';
import 'detail_info_table.dart';
import 'detail_metadata.dart';

/// Un crédit de la fiche : « Réalisateur », « Denis Villeneuve ».
typedef DetailCredit = ({String label, String value});

/// Le corps d'une fiche sous son en-tête, partagé par toutes les fiches :
/// la distribution en éventail à gauche ([extra]), le cartel à droite sur un
/// grand écran ([infoTable]) et dessous ailleurs.
class DetailSummarySection extends StatelessWidget {
  final List<DetailCredit> credits;
  final List<String> keywords;
  final Widget infoTable;

  /// La distribution en éventail à gauche du cartel.
  final Widget? extra;

  /// Le titre des crédits, affiché au-dessus d'eux si présents.
  final String? mainTitle;

  const DetailSummarySection({
    super.key,
    required this.credits,
    required this.infoTable,
    this.keywords = const [],
    this.extra,
    this.mainTitle,
  });

  /// Construit la section pour un titre de la bibliothèque.
  factory DetailSummarySection.forDetails({
    Key? key,
    required MediaDetails? details,
    Widget? extra,
    String? mainTitle,
  }) {
    return DetailSummarySection(
      key: key,
      credits: const [],
      infoTable: details == null
          ? const SizedBox.shrink()
          : DetailInfoTable.forDetails(details),
      extra: extra,
      mainTitle: mainTitle,
    );
  }

  /// Largeur à partir de laquelle [infoTable] passe à droite de la distribution.
  static const double wideBreakpoint = 1100;

  /// La colonne d'informations à droite : calibrée à la largeur du cartel
  /// MediaHub (27rem ~ 432 px), sans écraser la distribution.
  static double _sidebarWidth(double width) =>
      (width * 0.28).clamp(360.0, 432.0);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final hasMain = credits.isNotEmpty || keywords.isNotEmpty;
    final hasMainContent = hasMain || extra != null;
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (extra != null) extra!,
        if (hasMain) ...[
          if (extra != null) const SizedBox(height: 28),
          _CreditsBlock(credits: credits, keywords: keywords, title: mainTitle),
        ],
      ],
    );
    return Padding(
      padding: AppLayout.pageInsets(context, top: 28, bottom: 8),
      child: width >= wideBreakpoint
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: main),
                const SizedBox(width: 48),
                SizedBox(width: _sidebarWidth(width), child: infoTable),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasMainContent) ...[main, const SizedBox(height: 32)],
                infoTable,
              ],
            ),
    );
  }
}

/// Les crédits puis les mots-clés, sous un [title] facultatif.
class _CreditsBlock extends StatelessWidget {
  final List<DetailCredit> credits;
  final List<String> keywords;
  final String? title;

  const _CreditsBlock({
    required this.credits,
    this.keywords = const [],
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(title!, style: detailSectionTitleStyle(context)),
          const SizedBox(height: 16),
        ],
        if (credits.isNotEmpty) _CreditsGrid(credits: credits),
        if (credits.isNotEmpty && keywords.isNotEmpty)
          const SizedBox(height: 24),
        if (keywords.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final word in keywords) _KeywordTag(word)],
          ),
      ],
    );
  }
}

class _CreditsGrid extends StatelessWidget {
  final List<DetailCredit> credits;

  const _CreditsGrid({required this.credits});

  @override
  Widget build(BuildContext context) {
    const colWidth = 200.0;
    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        for (final c in credits)
          SizedBox(
            width: colWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.value,
                  style: const TextStyle(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  c.label,
                  style: const TextStyle(
                    fontSize: AppType.footnote,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeywordTag extends StatelessWidget {
  final String text;

  const _KeywordTag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: AppType.footnote,
          color: Color(0xFFA8A5A1),
        ),
      ),
    );
  }
}
