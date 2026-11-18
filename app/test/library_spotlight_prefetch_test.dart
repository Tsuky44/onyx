import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/library/widgets/library_spotlight_prefetch.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/media_details_cache.dart';

/// Le volet d'une bibliothèque ou de la recherche du bureau posait le titre
/// en toutes lettres, puis le logo une demi-seconde après le survol.
/// Demande de l'utilisateur : que le logo s'affiche tout de suite. Les
/// affiches à l'écran préparent donc la fiche du volet avant le survol
/// (ADR-0142).

class _Api extends ApiClient {
  final List<int> asked = [];
  final Map<int, Completer<MediaDetails>> pending = {};

  @override
  Future<MediaDetails> getMediaDetails(int mediaId) {
    asked.add(mediaId);
    return (pending[mediaId] = Completer<MediaDetails>()).future;
  }

  void answer(int id) => pending.remove(id)!.complete(MediaDetails(
        id: id,
        type: MediaType.movie,
        title: 'Film $id',
      ));
}

Media _movie(int id) => Media(
      id: id,
      type: MediaType.movie,
      title: 'Film $id',
      duration: 6000,
      createdAt: DateTime(2026),
    );

void main() {
  setUp(() {
    MediaDetailsCache.clear();
    LibrarySpotlightPrefetch.resetForTest();
  });

  test('les affiches préparent leur fiche, quelques-unes à la fois', () async {
    final api = _Api();
    for (var id = 1; id <= 10; id++) {
      LibrarySpotlightPrefetch.warm(api, _movie(id), devicePixelRatio: 1);
    }
    // Pas une rafale de dix requêtes devant les affiches elles-mêmes.
    expect(api.asked, [1, 2, 3, 4]);

    while (api.pending.isNotEmpty) {
      api.answer(api.pending.keys.first);
      await pumpEventQueue();
    }

    expect(api.asked, [for (var id = 1; id <= 10; id++) id]);
    for (var id = 1; id <= 10; id++) {
      expect(MediaDetailsCache.isFresh(id), isTrue, reason: 'Film $id');
    }
  });

  test('une affiche déjà préparée ne redemande pas sa fiche', () async {
    final api = _Api();
    LibrarySpotlightPrefetch.warm(api, _movie(1), devicePixelRatio: 1);
    api.answer(1);
    await pumpEventQueue();

    LibrarySpotlightPrefetch.warm(api, _movie(1), devicePixelRatio: 1);

    expect(api.asked, [1]);
  });

  test('une affiche sortie de l\'écran avant son tour ne demande rien',
      () async {
    final api = _Api();
    for (var id = 1; id <= 6; id++) {
      LibrarySpotlightPrefetch.warm(api, _movie(id), devicePixelRatio: 1);
    }
    LibrarySpotlightPrefetch.forget(6);

    while (api.pending.isNotEmpty) {
      api.answer(api.pending.keys.first);
      await pumpEventQueue();
    }

    expect(api.asked, [1, 2, 3, 4, 5]);
    expect(LibrarySpotlightPrefetch.waitingForTest, 0);
  });

  test('une fiche en route est rejointe sans attendre le focus', () async {
    final api = _Api();
    LibrarySpotlightPrefetch.warm(api, _movie(1), devicePixelRatio: 1);

    expect(MediaDetailsCache.isLoading(1), isTrue);
    api.answer(1);
    await pumpEventQueue();
    expect(MediaDetailsCache.isLoading(1), isFalse);
  });
}
