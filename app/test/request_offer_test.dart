import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';

/// La fiche d'une demande propose « Demander » quand rien n'est demandé, et
/// « Compléter » (à côté de « Lire ») quand une série n'est demandée qu'en
/// partie.
RequestMediaDetails _details({
  required RequestMediaType type,
  RequestMediaStatus status = RequestMediaStatus.unknown,
  List<RequestMediaStatus> seasons = const [],
}) {
  return RequestMediaDetails(
    id: 1,
    mediaType: type,
    title: 'Titre',
    overview: '',
    posterPath: null,
    backdropPath: null,
    releaseDate: null,
    rating: 0,
    status: status,
    runtime: null,
    genres: const [],
    seasons: [
      for (var i = 0; i < seasons.length; i++)
        RequestSeason(
          number: i + 1,
          name: 'Saison ${i + 1}',
          episodeCount: 8,
          posterPath: null,
          status: seasons[i],
        ),
    ],
  );
}

void main() {
  const unknown = RequestMediaStatus.unknown;
  const available = RequestMediaStatus.available;
  const pending = RequestMediaStatus.pending;

  test('une série pas du tout demandée propose Demander', () {
    final show = _details(
        type: RequestMediaType.tv, seasons: [unknown, unknown, unknown]);
    expect(show.offer, RequestOffer.request);
    expect(show.requestableSeasons.map((s) => s.number), [1, 2, 3]);
  });

  test(
      'Compléter vise tout ce qui n\'est pas demandé, saison à moitié là '
      'comprise', () {
    final show = _details(
      type: RequestMediaType.tv,
      status: RequestMediaStatus.partial,
      seasons: [
        available,
        pending,
        unknown,
        RequestMediaStatus.partial,
      ],
    );
    expect(show.offer, RequestOffer.complete);
    expect(show.requestableSeasons.map((s) => s.number), [3, 4]);
  });

  test('une série dont toutes les saisons sont prises ne propose rien', () {
    final show = _details(
      type: RequestMediaType.tv,
      status: available,
      seasons: [available, pending],
    );
    expect(show.offer, RequestOffer.none);
  });

  test('les épisodes spéciaux ne suffisent pas à compléter', () {
    final show = _details(
      type: RequestMediaType.tv,
      status: available,
      seasons: [available],
    );
    final withSpecials = RequestMediaDetails(
      id: show.id,
      mediaType: show.mediaType,
      title: show.title,
      overview: '',
      posterPath: null,
      backdropPath: null,
      releaseDate: null,
      rating: 0,
      status: available,
      runtime: null,
      genres: const [],
      seasons: [
        ...show.seasons,
        const RequestSeason(
          number: 0,
          name: 'Spéciaux',
          episodeCount: 2,
          posterPath: null,
          status: unknown,
        ),
      ],
    );
    expect(withSpecials.offer, RequestOffer.none);
  });

  test('une saison qui sort et que MediaHub suit déjà n\'est pas à compléter',
      () {
    RequestSeason season(int n, RequestMediaStatus status, bool requested) =>
        RequestSeason(
          number: n,
          name: '',
          episodeCount: 10,
          availableEpisodes: 7,
          posterPath: null,
          status: status,
          requested: requested,
        );
    RequestMediaDetails show(List<RequestSeason> seasons) =>
        RequestMediaDetails(
          id: 1,
          mediaType: RequestMediaType.tv,
          title: 'Série',
          overview: '',
          posterPath: null,
          backdropPath: null,
          releaseDate: null,
          rating: 0,
          status: RequestMediaStatus.partial,
          runtime: null,
          genres: const [],
          seasons: seasons,
        );

    final airing = show([
      season(1, available, false),
      season(2, RequestMediaStatus.partial, true)
    ]);
    expect(airing.requestableSeasons, isEmpty);
    expect(airing.offer, RequestOffer.none);

    final held = show([
      season(1, available, false),
      season(2, RequestMediaStatus.partial, false)
    ]);
    expect(held.requestableSeasons.map((s) => s.number), [2]);
    expect(held.offer, RequestOffer.complete);
  });

  test('un film se demande, ne se complète jamais', () {
    expect(_details(type: RequestMediaType.movie).offer, RequestOffer.request);
    expect(_details(type: RequestMediaType.movie, status: pending).offer,
        RequestOffer.none);
  });
}
