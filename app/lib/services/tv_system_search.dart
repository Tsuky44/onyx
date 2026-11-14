import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/app_platform.dart';

/// Une affiche de l'écran de recherche du système.
@immutable
class SystemSearchItem {
  const SystemSearchItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.posterUrl,
    this.badge,
    this.badgeTint,
    this.dimmed = false,
    this.progress,
    this.watched = false,
  });

  /// Ce que l'écran rend quand on choisit l'affiche ; unique dans l'écran.
  final String id;
  final String title;

  /// La ligne sous le titre : l'année, le type.
  final String subtitle;

  /// L'adresse complète de l'affiche, à la taille où elle se dessine.
  final String? posterUrl;

  /// Le texte de la pastille posée en haut à droite (« Indispo »), et sa
  /// couleur en ARGB quand ce n'est pas le blanc.
  final String? badge;
  final int? badgeTint;

  /// Vrai pour un titre que le serveur n'a pas : son affiche est voilée.
  final bool dimmed;

  /// La part déjà vue d'un film en cours, de 0 à 1.
  final double? progress;
  final bool watched;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'poster': posterUrl,
        'badge': badge,
        'badgeTint': badgeTint,
        'dimmed': dimmed,
        'progress': progress,
        'watched': watched,
      };
}

/// Un rayon de l'écran de recherche du système : un titre et ses affiches.
@immutable
class SystemSearchSection {
  const SystemSearchSection({
    required this.id,
    required this.title,
    required this.items,
  });

  /// Stable d'une recherche à l'autre : l'écran reconnaît le rayon et ne
  /// redessine que ce qui a changé.
  final String id;
  final String title;
  final List<SystemSearchItem> items;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'items': [for (final item in items) item.toMap()],
      };
}

/// Ce que l'écran de recherche du système montre sous son clavier.
@immutable
class SystemSearchContent {
  const SystemSearchContent({
    required this.sections,
    this.emptyTitle,
    this.emptyMessage,
  });

  final List<SystemSearchSection> sections;

  /// Le message à la place des affiches quand il n'y en a aucune.
  final String? emptyTitle;
  final String? emptyMessage;

  Map<String, Object?> toMap() => {
        'sections': [for (final section in sections) section.toMap()],
        'emptyTitle': emptyTitle,
        'emptyMessage': emptyMessage,
      };
}

/// Ce que l'écran de recherche du système fait savoir.
class TvSystemSearchEvents {
  const TvSystemSearchEvents({
    required this.onQuery,
    required this.onSelect,
    required this.onClosed,
  });

  /// Le texte du champ a changé : tapé, dicté ou saisi depuis un iPhone.
  final ValueChanged<String> onQuery;

  /// L'affiche d'identifiant donné a été choisie.
  final ValueChanged<String> onSelect;

  /// L'écran a été quitté par la touche Retour de la télécommande.
  final VoidCallback onClosed;
}

/// L'écran de recherche du système sur l'Apple TV (ADR-0129) : le clavier en
/// ligne de tvOS, avec la dictée et la saisie depuis un iPhone, et les
/// affiches sous lui. Seul UIKit sait le montrer ; l'hôte natif
/// (`tvos/Runner/SystemSearch*.swift`) le présente par-dessus Flutter.
///
/// Dart garde la main sur le contenu : il apprend ce qu'on tape
/// ([TvSystemSearchEvents.onQuery]), cherche, et dit quoi afficher
/// ([update]). L'écran natif ne connaît ni la bibliothèque ni le serveur.
abstract final class TvSystemSearch {
  static const MethodChannel _channel = MethodChannel('onyx/tv_search');

  /// Vrai sur l'Apple TV, seul hôte qui sert ce canal.
  static bool get isSupported => debugSupported ?? AppPlatform.isTvOS;

  /// Pour les tests, qui tournent sans hôte natif.
  @visibleForTesting
  static bool? debugSupported;

  static TvSystemSearchEvents? _events;

  /// Branche [events] sur l'écran, ou les débranche avec null.
  static void listen(TvSystemSearchEvents? events) {
    _events = events;
    _channel.setMethodCallHandler(events == null ? null : _onNativeCall);
  }

  static Future<Object?> _onNativeCall(MethodCall call) async {
    final events = _events;
    if (events == null) return null;
    switch (call.method) {
      case 'query':
        events.onQuery(call.arguments as String? ?? '');
      case 'select':
        events.onSelect(call.arguments as String? ?? '');
      case 'closed':
        events.onClosed();
    }
    return null;
  }

  /// Présente l'écran avec son premier contenu. Faux quand l'hôte ne l'a pas
  /// montré : l'appelant garde alors la recherche dessinée par Flutter.
  ///
  /// [colors] porte les couleurs de l'app en ARGB, sous leur nom
  /// d'`AppColors` : l'écran natif n'en invente aucune.
  static Future<bool> present({
    required String placeholder,
    required Map<String, int> colors,
    required SystemSearchContent content,
  }) async {
    if (!isSupported) return false;
    try {
      final shown = await _channel.invokeMethod<bool>('present', {
        'placeholder': placeholder,
        'colors': colors,
        'content': content.toMap(),
      });
      return shown ?? false;
    } on PlatformException catch (error) {
      debugPrint('Recherche du système : présentation refusée ($error)');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Remplace ce que l'écran montre sous son clavier.
  static Future<void> update(SystemSearchContent content) =>
      _send('update', content.toMap());

  /// Retire l'écran sans l'oublier : une fiche s'ouvre par-dessus la
  /// recherche. [show] le rend tel qu'il était, sur l'affiche qu'on a quittée.
  static Future<void> hide() => _send('hide');

  static Future<void> show() => _send('show');

  /// Ferme l'écran pour de bon.
  static Future<void> close() => _send('close');

  static Future<void> _send(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      debugPrint('Recherche du système : « $method » a échoué ($error)');
    } on MissingPluginException {
      // Un hôte sans ce canal : la recherche de Flutter est déjà à l'écran.
    }
  }
}
