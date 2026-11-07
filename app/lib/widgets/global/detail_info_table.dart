import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../utils/format.dart';
import '../../utils/long_date.dart';

/// Une ligne de métadonnées de [DetailInfoTable].
typedef DetailInfoRow = ({String label, String value});

/// Un fait clé affiché en grille dans le cartel (date, durée, saisons, note...).
class CartelFact {
  final IconData icon;
  final String label;
  final String value;

  const CartelFact({
    required this.icon,
    required this.label,
    required this.value,
  });
}

/// Libellé du statut TMDB dans la langue de l'interface.
String detailStatusLabel(String status) {
  const map = {
    'Released': 'Sorti',
    'Post Production': 'Post-production',
    'In Production': 'En production',
    'Planned': 'Planifié',
    'Rumored': 'Rumeur',
    'Canceled': 'Annulé',
    'Ended': 'Terminé',
    'Returning Series': 'En cours',
    'Pilot': 'Pilote',
  };
  final label = map[status];
  return label == null ? status : tr(label);
}

/// Une date écrite en toutes lettres.
String detailDateLabel(String date) {
  final parsed = DateTime.tryParse(date);
  return parsed == null ? date : formatLongDate(parsed);
}

/// Nom de langue en français pour le cartel.
String formatLanguage(String? code) {
  if (code == null || code.isEmpty) return '';
  const languages = {
    'fr': 'Français',
    'en': 'Anglais',
    'es': 'Espagnol',
    'it': 'Italien',
    'de': 'Allemand',
    'ja': 'Japonais',
    'ko': 'Coréen',
    'zh': 'Chinois',
    'pt': 'Portugais',
    'ru': 'Russe',
    'nl': 'Néerlandais',
    'sv': 'Suédois',
    'no': 'Norvégien',
    'da': 'Danois',
    'fi': 'Finnois',
    'pl': 'Polonais',
    'hi': 'Hindi',
    'ar': 'Arabe',
    'tr': 'Turc',
  };
  final lower = code.toLowerCase();
  return languages[lower] ?? code.toUpperCase();
}

/// Nom de pays en français pour le cartel.
String formatCountry(String? code) {
  if (code == null || code.isEmpty) return '';
  const countries = {
    'FR': 'France',
    'US': 'États-Unis',
    'GB': 'Royaume-Uni',
    'CA': 'Canada',
    'DE': 'Allemagne',
    'IT': 'Italie',
    'ES': 'Espagne',
    'JP': 'Japon',
    'KR': 'Corée du Sud',
    'CN': 'Chine',
    'AU': 'Australie',
    'BE': 'Belgique',
    'CH': 'Suisse',
    'SE': 'Suède',
    'NO': 'Norvège',
    'DK': 'Danemark',
    'NL': 'Pays-Bas',
    'IN': 'Inde',
    'BR': 'Brésil',
    'MX': 'Mexique',
  };
  final upper = code.toUpperCase();
  return countries[upper] ?? code;
}

/// Formate un montant en dollars (ex. « 190 M $US »).
String formatMoney(int? amount) {
  if (amount == null || amount <= 0) return '';
  if (amount >= 1000000000) {
    final val = (amount / 1000000000.0).toStringAsFixed(1);
    return '$val Md \$US';
  }
  if (amount >= 1000000) {
    final val = (amount / 1000000.0).round();
    return '$val M \$US';
  }
  return '$amount \$US';
}

/// Cartel de la fiche (verre discret) : nature, langue et pays, créateurs,
/// faits clés en grille, lignes de l'équipe et thèmes en bulles.
class DetailInfoTable extends StatelessWidget {
  final double rating;
  final List<DetailInfoRow> rows;
  final List<String> studios;

  // Champs optionnels du cartel
  final String? kind;
  final String? title;
  final String? byline;
  final List<CartelFact> facts;
  final List<String> keywords;
  final String? collectionName;
  final VoidCallback? onCollectionTap;

  const DetailInfoTable({
    super.key,
    required this.rating,
    required this.rows,
    required this.studios,
    this.kind,
    this.title,
    this.byline,
    this.facts = const [],
    this.keywords = const [],
    this.collectionName,
    this.onCollectionTap,
  });

  /// Construit le cartel pour un titre de la bibliothèque.
  factory DetailInfoTable.forDetails(
    MediaDetails details, {
    List<String>? keywords,
    VoidCallback? onCollectionTap,
  }) {
    final isTv = details.type == MediaType.show;
    final title = details.title;
    final original = details.originalTitle;
    final date = details.releaseDate;
    final language = details.originalLanguage;
    final country =
        details.countries.isNotEmpty ? details.countries.first : null;
    final director = details.director;
    final writers = details.writers;
    final seasons = details.numberOfSeasons;
    final episodes = details.numberOfEpisodes;
    final studios = details.studios;
    final rating = details.voteAverage;
    final collection = details.collection;

    final kindParts = [
      isTv ? tr('SÉRIE TÉLÉVISÉE') : tr('FILM'),
      if (language != null && language.isNotEmpty)
        formatLanguage(language).toUpperCase(),
      if (country != null && country.isNotEmpty)
        formatCountry(country).toUpperCase(),
    ];
    final kind = kindParts.join(' · ');

    String? byline;
    if (director != null && director.isNotEmpty) {
      byline = isTv
          ? '${tr('Créée par')} $director'
          : '${tr('Réalisé par')} $director';
    }

    final facts = <CartelFact>[
      if (date != null && date.isNotEmpty)
        CartelFact(
          icon: AppIcons.calendar,
          label: isTv ? tr('Première diffusion') : tr('Sortie'),
          value: detailDateLabel(date),
        ),
      if (!isTv && details.runtime > 0)
        CartelFact(
          icon: AppIcons.schedule,
          label: tr('Durée'),
          value: formatDuration(details.runtime * 60),
        ),
      if (isTv && seasons > 0)
        CartelFact(
          icon: AppIcons.collection,
          label: tr('Saisons'),
          value:
              '$seasons saison${seasons > 1 ? 's' : ''}${episodes > 0 ? ', $episodes épisodes' : ''}',
        ),
      if (rating > 0)
        CartelFact(
          icon: AppIcons.rating,
          label: tr('Note TMDB'),
          value: '${(rating * 10).round()}%',
        ),
    ];

    final rows = <DetailInfoRow>[
      if (original != null && original.isNotEmpty && original != title)
        (label: tr('Titre original'), value: original),
      if (isTv && director != null && director.isNotEmpty)
        (label: tr('Réalisation'), value: director),
      if (writers.isNotEmpty)
        (label: tr('Scénario'), value: writers.join(', ')),
      if (details.status != null &&
          details.status!.isNotEmpty &&
          details.status != 'unknown')
        (label: tr('Statut'), value: detailStatusLabel(details.status!)),
    ];

    return DetailInfoTable(
      rating: rating,
      rows: rows,
      studios: studios,
      kind: kind,
      title: title,
      byline: byline,
      facts: facts,
      keywords: keywords ?? const [],
      collectionName: collection?.name,
      onCollectionTap: onCollectionTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (title != null && title!.isNotEmpty) {
      return _buildCartel(context);
    }
    return _buildLegacyTable(context);
  }

  /// Le cartel moderne inspiré de MediaHub.
  Widget _buildCartel(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2ECE2).withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kind != null && kind!.isNotEmpty) ...[
            Text(
              kind!,
              style: const TextStyle(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: Color(0xFF7F7C78),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            title!,
            style: const TextStyle(
              fontSize: AppType.display,
              fontWeight: FontWeight.w800,
              color: Color(0xFFD3D0CB),
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          if (byline != null && byline!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              byline!,
              style: const TextStyle(
                fontSize: AppType.body,
                color: Color(0xFFA8A5A0),
              ),
            ),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              child: _CartelFactsGrid(facts: facts),
            ),
          ],
          if (rows.isNotEmpty ||
              studios.isNotEmpty ||
              collectionName != null) ...[
            const SizedBox(height: 6),
            for (final row in rows)
              _CartelDetailRow(
                label: row.label,
                value: row.value,
              ),
            if (studios.isNotEmpty)
              _CartelDetailRow(
                label: tr('Studios'),
                value: studios.take(3).join(', '),
              ),
            if (collectionName != null && collectionName!.isNotEmpty)
              _CartelDetailRow(
                label: tr('Saga'),
                value: collectionName!,
                onTap: onCollectionTap,
              ),
          ],
          if (keywords.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in keywords)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: AppType.footnote,
                        color: Color(0xFFA8A5A1),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Le rendu classique pour compatibilité ascendante.
  Widget _buildLegacyTable(BuildContext context) {
    if (rating <= 0 && rows.isEmpty && studios.isEmpty) {
      return const SizedBox.shrink();
    }
    final divider =
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.06));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rating > 0) _ratingHeader(rating),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0 || rating > 0) divider,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      rows[i].label,
                      style: TextStyle(
                        fontSize: AppType.footnote,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rows[i].value,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: AppType.footnote,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (studios.isNotEmpty) ...[
            if (rows.isNotEmpty || rating > 0) divider,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      tr('Studios'),
                      style: TextStyle(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final studio in studios.take(3))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        studio,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: AppType.caption,
                          color: AppColors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ratingHeader(double rating) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.tmdb,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              tr('TMDB'),
              style: const TextStyle(
                fontSize: AppType.micro,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(rating * 10).round()}%',
            style: const TextStyle(
              fontSize: AppType.body,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartelFactsGrid extends StatelessWidget {
  final List<CartelFact> facts;

  const _CartelFactsGrid({required this.facts});

  @override
  Widget build(BuildContext context) {
    final rowsCount = (facts.length + 1) ~/ 2;
    return Column(
      children: [
        for (var r = 0; r < rowsCount; r++) ...[
          if (r > 0) const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildItem(facts[r * 2])),
              const SizedBox(width: 14),
              Expanded(
                child: (r * 2 + 1 < facts.length)
                    ? _buildItem(facts[r * 2 + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildItem(CartelFact fact) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(fact.icon, size: 16, color: const Color(0xFF7F7C78)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fact.label,
                style: const TextStyle(
                  fontSize: AppType.caption,
                  color: Color(0xFF7F7C78),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                fact.value,
                style: const TextStyle(
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD3D0CB),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CartelDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _CartelDetailRow({
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.045),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: AppType.subhead,
                color: Color(0xFF7F7C78),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: onTap != null
                ? MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onTap,
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: AppType.subhead,
                          color: Color(0xFFD3D0CB),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  )
                : Text(
                    value,
                    style: const TextStyle(
                      fontSize: AppType.subhead,
                      color: Color(0xFFB9B6B1),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
