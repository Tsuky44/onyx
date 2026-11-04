import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../services/new_episodes/new_episode_alerts.dart';
import '../../tv/tv_mode.dart';
import '../../utils/app_platform.dart';
import '../../utils/store_build.dart';
import '../../widgets/global/resume_preview/hover_preview_preference.dart';
import '../player/playback/native_tv_preference.dart';
import 'settings_categories.dart';
import 'settings_sections.dart';

/// Un réglage qu'on peut chercher : son nom, la page où il se trouve et des
/// mots que l'on tape sans connaître son libellé exact.
class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.section,
    required this.title,
    required this.category,
    required this.icon,
    this.group,
    this.keywords = '',
  });

  /// La page à ouvrir (voir [SettingsCategory.opens]).
  final String section;
  final String title;
  final String category;
  final IconData icon;

  /// Le groupe de la page qui porte le réglage, quand il en a un.
  final String? group;

  /// Synonymes français et anglais, séparés par des espaces. Volontairement
  /// hors de `tr` : ils ne s'affichent jamais, ils servent à retrouver.
  final String keywords;

  /// Où le réglage se trouve, sous son titre dans les résultats.
  String get path => group == null ? category : '$category · $group';

  String get _haystack => _fold('$title $group $category $keywords');
  String get _titleFold => _fold(title);
}

/// Les entrées de [index] qui correspondent à [query], les titres qui la
/// contiennent d'abord. Tous les mots tapés doivent se retrouver, dans
/// n'importe quel ordre, sans tenir compte des accents ni de la casse.
List<SettingsSearchEntry> searchSettings(
  List<SettingsSearchEntry> index,
  String query,
) {
  final words = _fold(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];

  final inTitle = <SettingsSearchEntry>[];
  final elsewhere = <SettingsSearchEntry>[];
  for (final entry in index) {
    final haystack = entry._haystack;
    if (!words.every(haystack.contains)) continue;
    final title = entry._titleFold;
    (words.every(title.contains) ? inTitle : elsewhere).add(entry);
  }
  return [...inTitle, ...elsewhere];
}

const _accents = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ç': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'ô': 'o',
  'ö': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ÿ': 'y',
  'œ': 'oe',
  '’': "'",
};

String _fold(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_accents[char] ?? char);
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Tout ce que la recherche sait trouver pour ce compte, sur cet appareil.
///
/// Les catégories et leurs pages y sont d'office. Les réglages sont listés à
/// la main, parce qu'une page est un widget et non une donnée : ce qu'une page
/// ne dessine pas (un droit, une plateforme) n'est pas proposé non plus, avec
/// les mêmes conditions que la page. `settings_search_test.dart` garde chaque
/// entrée rattachée à une page qui existe.
List<SettingsSearchEntry> buildSettingsSearchIndex(
  List<SettingsCategory> categories,
  Permissions p,
) {
  final entries = <SettingsSearchEntry>[];

  for (final category in categories) {
    entries.add(SettingsSearchEntry(
      section: category.id,
      title: category.label,
      category: category.label,
      icon: category.icon,
      keywords: category.hint,
    ));
    for (final section in category.sections) {
      if (section.label == category.label) continue;
      entries.add(SettingsSearchEntry(
        section: section.id,
        title: section.label,
        category: category.label,
        icon: category.icon,
      ));
    }
  }

  for (final setting in _settings(p)) {
    final category = categories.where((c) => c.opens(setting.section));
    if (category.isEmpty) continue;
    final owner = category.first;
    entries.add(SettingsSearchEntry(
      section: setting.section,
      title: setting.title,
      category: owner.label,
      icon: owner.icon,
      group: setting.group,
      keywords: setting.keywords,
    ));
  }
  return entries;
}

typedef _Setting = ({
  String section,
  String group,
  String title,
  String keywords,
});

_Setting _s(String section, String group, String title,
        [String keywords = '']) =>
    (section: section, group: group, title: title, keywords: keywords);

List<_Setting> _settings(Permissions p) {
  final isTv = TvMode.isTv;
  final hasDownloads = !AppPlatform.isWeb && !AppPlatform.isTvOS;
  return [
    // — Mon compte
    _s(SettingsSections.account, tr('Sécurité'), tr('Changer mon mot de passe'),
        'password mdp secret'),
    _s(
        SettingsSections.account,
        tr('Validation en deux étapes'),
        tr('Validation en deux étapes'),
        'otp 2fa totp authentification code secours backup'),
    _s(SettingsSections.account, tr('Mes appareils connectés'),
        tr('Mes appareils connectés'), 'sessions devices deconnecter'),
    _s(SettingsSections.account, tr('Mon compte'), tr('Se déconnecter'),
        'logout sign out deconnexion'),
    _s(SettingsSections.account, tr('Mon compte'), tr('Supprimer mon compte'),
        'delete effacer'),

    // — Général
    if (!AppPlatform.isTvOS)
      _s(SettingsSections.device, tr('Affichage'), tr('Mode télécommande'),
          'tv television remote telecommande dpad'),
    _s(SettingsSections.device, tr('Affichage'), tr('Mode léger'),
        'lite performance animations lent fluide'),
    _s(SettingsSections.device, tr('Langue'), tr('Langue de l’interface'),
        'language francais english langue traduction'),
    if (NewEpisodeAlerts.supported) ...[
      _s(SettingsSections.device, tr('Notifications'), tr('Nouveaux épisodes'),
          'notifications alertes episodes series'),
      if (p.manageSettings)
        _s(SettingsSections.device, tr('Notifications'),
            tr('Nouvelles demandes'), 'notifications alertes requests'),
    ],
    _s(SettingsSections.device, tr('Interface'), tr('Revoir la présentation'),
        'tour tutoriel onboarding visite guide'),
    if (HoverPreviewPreference.supported && !isTv)
      _s(SettingsSections.device, tr('Interface'), tr('Aperçu au survol'),
          'hover souris preview reprendre'),
    if (AppPlatform.isMobile && !isTv)
      _s(SettingsSections.account, tr('Ajouter un appareil'),
          tr('Connecter un appareil'), 'qr code scanner lier link tv'),
    if (!AppPlatform.isTvOS && !StoreBuild.enabled)
      _s(
          SettingsSections.account,
          tr('Ajouter un appareil'),
          tr('Installer Onyx sur un autre appareil'),
          'installeur applications download windows android'),
    if (!AppPlatform.isWeb)
      _s(SettingsSections.downloads, tr('Images'), tr('Cache des images'),
          'cache vider clear affiches espace'),
    _s(SettingsSections.device, tr('Aide'), tr('Journal'),
        'logs erreur debug diagnostic'),
    _s(SettingsSections.device, tr('À propos'), tr('Licences open source'),
        'licenses version mpv ffmpeg'),

    // — Lecture
    _s(SettingsSections.playback, tr('Audio'), tr('Langue audio par défaut'),
        'audio language piste vo vf'),
    if (!AppPlatform.isApple)
      _s(SettingsSections.playback, tr('Vidéo'), tr('Décodage matériel'),
          'hardware decoding gpu image noire verte codec'),
    if (AppPlatform.isAndroid)
      _s(SettingsSections.playback, tr('Vidéo'), tr('Adapter l’écran au film'),
          'frame rate fps refresh saccades 24p'),
    if (NativeTvPlayerPreference.isAvailable(isTvOS: AppPlatform.isTvOS))
      _s(SettingsSections.playback, tr('Apple TV'), tr('Lecteur Apple TV'),
          'natif native onyx avplayer lecteur player tvos'),
    _s(SettingsSections.playback, tr('Connexion'), tr('Qualité automatique'),
        'bitrate debit transcodage quality reseau'),
    _s(SettingsSections.playback, tr('Séries'),
        tr('Passer le récap automatiquement'), 'skip recap resume'),
    _s(SettingsSections.playback, tr('Séries'),
        tr('Passer l’intro automatiquement'), 'skip intro generique'),
    _s(
        SettingsSections.playback,
        tr('Vous regardez encore ?'),
        tr('Demander si vous regardez encore'),
        'still watching enchainement veille endormi'),

    // — Téléchargements
    if (hasDownloads) ...[
      _s(SettingsSections.downloads, tr('Épisodes suivants'),
          tr('Téléchargement automatique'), 'auto download offline hors ligne'),
      _s(SettingsSections.downloads, tr('Épisodes suivants'),
          tr('Épisodes d’avance'), 'prefetch suivant'),
      _s(SettingsSections.downloads, tr('Réseau'), tr('Sur un réseau limité'),
          'wifi cellulaire mobile data forfait'),
      _s(SettingsSections.downloads, tr('Sur cet appareil'),
          tr('Médias gardés hors ligne'), 'offline stockage espace supprimer'),
    ],

    // — Serveurs et partage
    _s(SettingsSections.servers, tr('Serveur actif'), tr('Serveur actif'),
        'server adresse url changer'),
    _s(SettingsSections.servers, tr('Mes serveurs'), tr('Mes serveurs'),
        'ajouter server comptes'),
    _s(SettingsSections.emby, tr('Compte lié'), tr('Synchroniser maintenant'),
        'emby progression sync'),
    _s(SettingsSections.emby, tr('Compte lié'), tr('Délier le compte Emby'),
        'unlink'),
    _s(SettingsSections.shares, tr('Lien reçu'),
        tr('Ouvrir un lien de partage'), 'share coller paste'),

    // — Administration
    if (p.manageSettings) ...[
      _s(SettingsSections.library, tr('Bibliothèques'), tr('Bibliothèques'),
          'dossiers folders chemins ajouter supprimer'),
      _s(SettingsSections.integrations, tr('The Movie Database (TMDB)'),
          tr('Clé API TMDB'), 'tmdb api key cle metadata'),
      _s(SettingsSections.integrations, tr('Fanart.tv'),
          tr('Clé API Fanart.tv'), 'fanart api key cle logos fonds'),
      _s(SettingsSections.integrations, tr('Service de demandes'),
          tr('Clé d’intégration MediaHub'), 'mediahub requests api key'),
      _s(SettingsSections.security, tr('Validation en deux étapes'),
          tr('Validation en deux étapes'), 'otp 2fa obligatoire politique'),
      _s(
          SettingsSections.serverLogs,
          tr('Journaux des lectures'),
          tr('Conserver les journaux des lectures'),
          'logs playback lectures erreurs debug'),
      _s(SettingsSections.serverLogs, tr('Journaux des lectures'),
          tr('Mesurer la lecture'), 'metrics mesures debit cadence decodeur'),
      _s(SettingsSections.announcement, tr('Message'),
          tr('Message aux utilisateurs'), 'annonce banniere publier'),
    ],
    if (p.manageLibrary) ...[
      _s(SettingsSections.library, tr('Analyse'),
          tr('Synchroniser la bibliothèque'), 'scan indexer refresh'),
      _s(SettingsSections.library, tr('Analyse'), tr('Médias à vérifier'),
          'review identification erreurs'),
      _s(SettingsSections.library, tr('Maintenance'),
          tr('Compléter les affiches et résumés'), 'posters metadata images'),
      _s(SettingsSections.library, tr('Maintenance'),
          tr('Réidentifier tout le catalogue'), 'identify match tmdb'),
      _s(SettingsSections.library, tr('Maintenance'),
          tr('Extraire les sous-titres'), 'subtitles srt ass'),
    ],
    _s(SettingsSections.users, tr('Demandes d’accès'), tr('Demandes d’accès'),
        'access requests inscription'),
    _s(SettingsSections.users, tr('Invitations'), tr('Invitations'),
        'invite code lien compte'),
  ];
}
