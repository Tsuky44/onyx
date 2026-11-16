import '../../l10n/tr.dart';
import '../../models/models.dart';

/// Ce que les menus du lecteur proposent, nommé une seule fois : chaque menu
/// du chrome Onyx doit dire la même vitesse et offrir les mêmes barreaux de
/// qualité.
abstract final class PlayerMenuChoices {
  const PlayerMenuChoices._();

  /// « Normale », « 1.25× », « 2× ».
  static String rateLabel(double rate) =>
      rate == 1.0 ? tr('Normale') : '${trimRate(rate)}×';

  /// Une vitesse sans ses zéros inutiles : « 1.25 », « 2 ».
  static String trimRate(double rate) {
    final text = rate.toStringAsFixed(2);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// Les barreaux figés d'avant l'échelle annoncée par le serveur.
  ///
  /// Un serveur plus ancien ne renvoie pas de `qualities`, et la médiathèque
  /// peut en réunir plusieurs (ADR-0013) : le menu doit rester utilisable en
  /// face de celui qui ne sait pas encore répondre. Ces cinq clés existent
  /// toujours côté serveur et gardent leurs débits d'origine.
  static const legacyQualities = <QualityTier>[
    QualityTier(key: '2160p', label: '4K', height: 2160, bitrateBps: 0),
    QualityTier(key: '1080p', label: '1080p', height: 1080, bitrateBps: 0),
    QualityTier(key: '720p', label: '720p', height: 720, bitrateBps: 0),
    QualityTier(key: '480p', label: '480p', height: 480, bitrateBps: 0),
    QualityTier(key: '360p', label: '360p', height: 360, bitrateBps: 0),
  ];

  /// L'échelle que le serveur annonce pour ce média, sinon [legacyQualities].
  static List<QualityTier> qualityTiers(MediaTracks? tracks) {
    final offered = tracks?.qualities ?? const <QualityTier>[];
    return offered.isEmpty ? legacyQualities : offered;
  }
}
