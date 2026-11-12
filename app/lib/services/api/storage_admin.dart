part of '../api_client.dart';

/// Le gestionnaire de stockage de l'administration (ADR-0115), réservé au
/// droit delete_media : lister, détailler, supprimer du disque.
mixin _StorageAdminEndpoints {
  Dio get _dio;

  Future<StorageList> getAdminStorage() async {
    final response = await _dio.get('/api/admin/storage');
    return StorageList.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  Future<StorageDetails> getAdminStorageDetails(int mediaId) async {
    final response = await _dio.get('/api/admin/storage/$mediaId');
    return StorageDetails.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  /// Supprime partout le film, la série ou la saison [mediaId] : MediaHub le
  /// retire de sorraa ou de Radarr/Sonarr avec ses demandes, puis le serveur
  /// efface les fichiers. Irréversible : l'écran confirme avant d'appeler.
  ///
  /// Le serveur attend MediaHub jusqu'à 60 s (Sonarr relit toutes ses
  /// séries) : l'échéance de 30 s par défaut couperait avant lui.
  Future<StorageDeleteReport> deleteAdminStorage(int mediaId) async {
    final response = await _dio.delete(
      '/api/admin/storage/$mediaId',
      options: Options(receiveTimeout: const Duration(seconds: 90)),
    );
    return StorageDeleteReport.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }
}
