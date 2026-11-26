part of '../api_client.dart';

/// Découverte côté utilisateur des serveurs pairs mutuellement acceptés par
/// les administrateurs (`GET /api/peers/suggested`).
mixin _PeersEndpoints {
  Dio get _dio;

  /// Serveurs pairs mutuellement acceptés par le serveur actif. Rend une liste
  /// vide sur un serveur plus ancien ou hors ligne, afin de ne jamais bloquer
  /// la saisie manuelle d'une adresse.
  Future<List<SuggestedPeerServer>> getSuggestedPeerServers() async {
    try {
      final ping = await _dio.get('/api/ping');
      final info = ServerCapabilities.tryParse(ping.data);
      if (info == null || !info.supports(ServerCapabilities.suggestedPeers)) {
        return const [];
      }
      final response = await _dio.get('/api/peers/suggested');
      if (response.data is! List) return const [];
      return (response.data as List)
          .whereType<Map>()
          .map((e) => SuggestedPeerServer.fromJson(Map<String, dynamic>.from(e)))
          .where((p) => p.url.trim().isNotEmpty)
          .toList();
    } catch (_) {
      // Un serveur plus ancien ou momentanément injoignable ne bloque pas
      // l'ajout manuel d'un serveur.
      return const [];
    }
  }
}
