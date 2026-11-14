import 'dart:async';

import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/models/my_request.dart';
import 'package:onyx/models/request_catalog_filters.dart';
import 'package:onyx/models/request_progress.dart';
import 'package:onyx/providers/auth_provider.dart';

import 'tv_detail_bench.dart';

/// Un serveur réduit à ce qu'une recherche lui demande : sa bibliothèque et
/// son catalogue de demandes (ADR-0129). Il sait aussi ouvrir les fiches que
/// la recherche ouvre : celle d'un titre de la bibliothèque (`TvDetailApi`)
/// et celle d'une demande.
class SearchCatalogApi extends TvDetailApi {
  SearchCatalogApi({
    this.movies = const [],
    this.shows = const [],
    Map<String, List<RequestMediaItem>>? catalog,
  }) : catalog = catalog ?? {};

  final List<HomeMediaItem> movies;
  final List<Media> shows;

  /// Ce que le catalogue répond à chaque recherche ; rien pour les autres.
  final Map<String, List<RequestMediaItem>> catalog;

  /// Les recherches reçues, dans l'ordre.
  final List<String> asked = <String>[];

  /// Tant qu'il n'est pas complété, le catalogue ne répond pas.
  Completer<void>? gate;

  /// Vrai pour un catalogue en panne.
  bool broken = false;

  @override
  String get baseUrl => 'http://localhost:8080';

  @override
  Future<List<HomeMediaItem>> getMovies() async => movies;

  @override
  Future<List<Media>> getShows() async => shows;

  @override
  Future<RequestCatalogPage> getRequestCatalog({
    required int page,
    required String type,
    String? query,
    RequestCatalogFilters filters = RequestCatalogFilters.defaults,
  }) async {
    asked.add(query ?? '');
    await gate?.future;
    if (broken) throw StateError('catalogue en panne');
    return RequestCatalogPage(
      page: 1,
      totalPages: 1,
      results: catalog[query] ?? const [],
    );
  }

  @override
  Future<RequestAccess> getRequestAccess() async => RequestAccess.basic;

  @override
  Future<RequestMediaDetails> getRequestMediaDetails(
    int id,
    RequestMediaType type,
  ) async =>
      RequestMediaDetails(
        id: id,
        mediaType: type,
        title: 'Titre à demander',
        overview: 'Synopsis',
        posterPath: null,
        backdropPath: null,
        releaseDate: '2024-02-28',
        rating: 7,
        status: RequestMediaStatus.unknown,
        runtime: 120,
        genres: const ['Drame'],
        trailerKey: null,
        seasons: const [],
        recommendations: const [],
      );

  @override
  Future<RequestProgress?> getRequestProgress(
    int tmdbId,
    RequestMediaType type,
  ) async =>
      null;
}

/// Un compte qui a les droits donnés, sans passer par la connexion.
class FakeAuth extends AuthProvider {
  FakeAuth(super.api, this._permissions);

  final Permissions _permissions;

  @override
  User? get currentUser =>
      User(id: 1, username: 'mathis', permissions: _permissions);

  @override
  Permissions get permissions => _permissions;
}

Media libraryMedia(
  int id,
  String title, {
  MediaType type = MediaType.movie,
  int? tmdbId,
  int day = 1,
  String? posterUrl,
}) =>
    Media(
      id: id,
      type: type,
      title: title,
      duration: 6000,
      tmdbId: tmdbId,
      posterUrl: posterUrl,
      releaseDate: '2021-09-15',
      createdAt: DateTime(2026, 3, day),
    );

HomeMediaItem libraryMovie(
  int id,
  String title, {
  int? tmdbId,
  int day = 1,
  String? posterUrl,
  int watchedSeconds = 0,
  bool finished = false,
}) =>
    HomeMediaItem(
      media: libraryMedia(id, title,
          tmdbId: tmdbId, day: day, posterUrl: posterUrl),
      currentPositionSeconds: watchedSeconds,
      isFinished: finished,
      duration: 6000,
    );

/// Un titre du catalogue de demandes, tel que le serveur le rend.
RequestMediaItem catalogTitle(
  int id,
  String title, {
  RequestMediaType type = RequestMediaType.movie,
  RequestMediaStatus status = RequestMediaStatus.unknown,
}) =>
    RequestMediaItem(
      id: id,
      mediaType: type,
      title: title,
      overview: '',
      posterPath: null,
      backdropPath: null,
      releaseDate: '2024-02-28',
      rating: 0,
      status: status,
    );
