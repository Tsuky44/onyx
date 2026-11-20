part of '../api_client.dart';

/// Les appels de l'assistant de première installation et de l'explorateur de
/// dossiers du serveur (ADR-0165).
///
/// Un serveur plus ancien ne connaît aucune de ces routes et répond 404 : chaque
/// méthode le dit par un `null` au lieu de lever, et l'app se comporte alors
/// comme avant (pas d'assistant, chemin tapé à la main).
mixin _SetupEndpoints {
  Dio get _dio;

  static bool _isMissing(DioException e) => e.response?.statusCode == 404;

  /// Un dossier du serveur et ses sous-dossiers. [path] absent : la racine que
  /// le serveur expose. Null quand le serveur ne sait pas explorer (404 sur la
  /// racine) ; un chemin qui n'existe plus (404) ou hors de la racine (400) lève
  /// et l'explorateur retombe sur la racine.
  Future<FsListing?> browseFolders({String? path}) async {
    try {
      final response = await _dio.get(
        '/api/fs/browse',
        queryParameters: path == null ? null : {'path': path},
      );
      return FsListing.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (path == null && _isMissing(e)) return null;
      rethrow;
    }
  }

  /// Le serveur essaie la clé TMDB donnée, ou celle qu'il a enregistrée quand
  /// elle est vide. Null pour un serveur qui ne sait pas la tester.
  Future<TmdbTest?> testTmdbKey({String? apiKey}) async {
    try {
      final response = await _dio.post('/api/settings/tmdb/test', data: {
        'tmdb_api_key': apiKey ?? '',
      });
      return TmdbTest.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (_isMissing(e)) return null;
      rethrow;
    }
  }

  /// Où en est l'installation du serveur. Null pour un serveur d'avant
  /// l'assistant : l'app n'en ouvre pas.
  Future<SetupState?> getSetupGuide() async {
    try {
      final response = await _dio.get('/api/setup/state');
      return SetupState.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (_isMissing(e)) return null;
      rethrow;
    }
  }

  /// Marque l'installation comme finie ou ignorée : l'assistant ne se rouvre
  /// plus, sur aucun appareil.
  Future<void> completeSetup() async {
    try {
      await _dio.post('/api/setup/complete');
    } on DioException catch (e) {
      // Un serveur sans assistant n'a rien à marquer.
      if (!_isMissing(e)) rethrow;
    }
  }
}
