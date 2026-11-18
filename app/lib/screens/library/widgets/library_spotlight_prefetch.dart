import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../models/models.dart';
import '../../../services/api_client.dart';
import '../../../services/media_details_cache.dart';
import '../../../utils/poster_url.dart';
import '../../../widgets/global/app_network_image.dart';

/// Prépare la fiche du volet (`LibrarySpotlight`) des affiches à l'écran,
/// avant que le pointeur ne s'y pose : la fiche du catalogue et le logo
/// décodé. Voir ADR-0142.
///
/// Sans elle, survoler une affiche posait le titre en toutes lettres, puis le
/// logo une demi-seconde plus tard : le volet attendait que le pointeur se
/// pose (220 ms), demandait la fiche, puis téléchargeait et décodait le logo.
/// Préparé ici, le survol trouve tout en mémoire et le logo se pose sur la
/// même image que le titre change.
///
/// Seules les cartes construites sont préparées : la grille est paresseuse,
/// ce sont celles à l'écran et juste autour. Une carte qui sort de la grille
/// avant son tour retire sa demande ([forget]) : un défilement rapide ne
/// laisse pas derrière lui une file de fiches que personne ne regardera.
class LibrarySpotlightPrefetch {
  LibrarySpotlightPrefetch._();

  /// Les demandes en vol à la fois : assez pour remplir un écran d'affiches
  /// en quelques allers-retours, sans passer devant les affiches elles-mêmes.
  static const int parallel = 4;

  /// Un titre préparé ne l'est pas de nouveau avant ce délai, celui où la
  /// fiche en mémoire reste fraîche.
  static Duration get cooldown => MediaDetailsCache.ttl;

  static final Map<int, DateTime> _warmedAt = {};
  static final LinkedHashMap<int, _Job> _waiting = LinkedHashMap();
  static int _running = 0;

  /// Prépare la fiche et le logo de [media], si ce n'est pas déjà fait.
  static void warm(
    ApiClient api,
    Media media, {
    required double devicePixelRatio,
  }) {
    final id = media.id;
    if (id <= 0) return;
    if (media.type != MediaType.movie && media.type != MediaType.show) return;
    final last = _warmedAt[id];
    // Une fiche effacée (changement de serveur, nouvelle association) se
    // prépare de nouveau, même dans le délai.
    if (last != null &&
        DateTime.now().difference(last) < cooldown &&
        MediaDetailsCache.peek(id) != null) {
      return;
    }
    if (_waiting.containsKey(id)) return;
    _warmedAt[id] = DateTime.now();
    _waiting[id] = _Job(api, id, devicePixelRatio);
    _pump();
  }

  /// La carte de [mediaId] a quitté l'écran : sa demande, si elle attend
  /// encore son tour, ne part pas. Une demande déjà partie va à son terme.
  static void forget(int mediaId) {
    if (_waiting.remove(mediaId) != null) _warmedAt.remove(mediaId);
  }

  @visibleForTesting
  static void resetForTest() {
    _warmedAt.clear();
    _waiting.clear();
    _running = 0;
  }

  @visibleForTesting
  static int get waitingForTest => _waiting.length;

  static void _pump() {
    while (_running < parallel && _waiting.isNotEmpty) {
      final id = _waiting.keys.first;
      final job = _waiting.remove(id)!;
      _running++;
      unawaited(job.run().whenComplete(() {
        _running--;
        _pump();
      }));
    }
  }
}

class _Job {
  _Job(this.api, this.id, this.devicePixelRatio);

  final ApiClient api;
  final int id;
  final double devicePixelRatio;

  Future<void> run() async {
    try {
      final details = await MediaDetailsCache.load(api, id);
      // Décodé à sa taille d'origine, comme `MediaLogoDisplay` le dessine :
      // la même entrée du cache d'images.
      await AppNetworkImage.precache(
        logoImageUrl(details.logoUrl, serverBaseUrl: api.baseUrl),
        devicePixelRatio: devicePixelRatio,
      );
    } catch (_) {
      // Une préparation ratée ne coûte que l'avance : le volet redemandera
      // la fiche au survol, et la carte pourra la reprendre plus tard.
      LibrarySpotlightPrefetch._warmedAt.remove(id);
    }
  }
}

/// Une affiche dont la fiche du volet se prépare tant qu'elle est construite.
class LibrarySpotlightWarmup extends StatefulWidget {
  const LibrarySpotlightWarmup({
    super.key,
    required this.media,
    required this.child,
  });

  final Media media;
  final Widget child;

  @override
  State<LibrarySpotlightWarmup> createState() => _LibrarySpotlightWarmupState();
}

class _LibrarySpotlightWarmupState extends State<LibrarySpotlightWarmup> {
  int? _warmed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warm();
  }

  @override
  void didUpdateWidget(LibrarySpotlightWarmup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id) {
      LibrarySpotlightPrefetch.forget(oldWidget.media.id);
      _warm();
    }
  }

  @override
  void dispose() {
    LibrarySpotlightPrefetch.forget(widget.media.id);
    super.dispose();
  }

  void _warm() {
    final id = widget.media.id;
    if (_warmed == id) return;
    _warmed = id;
    LibrarySpotlightPrefetch.warm(
      Provider.of<ApiClient>(context, listen: false),
      widget.media,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
