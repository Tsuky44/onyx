part of '../api_client.dart';

/// Le Rétro de fin d'année (ADR 2026-11-26-tsuky-retro-annuel).
mixin _RetroEndpoints {
  Dio get _dio;

  /// Où en est le Rétro de ce compte, ou null quand le serveur ne le connaît
  /// pas : un serveur qui n'annonce pas `retro` n'a pas la route, et on ne lui
  /// pose pas la question.
  Future<RetroStatus?> getRetroStatus() async {
    final ping = await _dio.get('/api/ping');
    final info = ServerCapabilities.tryParse(ping.data);
    if (info == null || !info.supports(ServerCapabilities.retro)) return null;
    final response = await _dio.get('/api/me/retro', queryParameters: {
      'tz_offset': DateTime.now().timeZoneOffset.inMinutes,
    });
    return RetroStatus.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  /// Le Rétro complet. Les jours et les heures sont découpés dans le fuseau
  /// de cet appareil.
  Future<RetroReport> getRetro(int year) async {
    final response = await _dio.get('/api/me/retro/$year', queryParameters: {
      'tz_offset': DateTime.now().timeZoneOffset.inMinutes,
    });
    return RetroReport.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  /// Le Rétro a été ouvert : l'accueil retire sa diapo et l'anneau, sur tous
  /// les appareils du compte.
  Future<void> markRetroSeen(int year) async {
    await _dio.post('/api/me/retro/$year/seen');
  }
}
