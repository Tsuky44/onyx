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

  /// Supprime du disque et du catalogue le film, la série ou la saison
  /// [mediaId]. Irréversible : l'écran confirme avant d'appeler.
  Future<StorageDeleteReport> deleteAdminStorage(int mediaId) async {
    final response = await _dio.delete('/api/admin/storage/$mediaId');
    return StorageDeleteReport.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }
}
