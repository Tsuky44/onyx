part of '../api_client.dart';

/// Le calendrier « À venir » (ADR 2026-11-27-tsuky-calendrier-sorties-serveur).
mixin _CalendarEndpoints {
  Dio get _dio;

  /// Les sorties de [from] à [to], ou null quand le serveur ne connaît pas le
  /// calendrier : un serveur qui n'annonce pas `calendar` n'a pas la route.
  /// [today] est le jour de cet appareil, qui décide du « prochain épisode ».
  Future<CalendarFeed?> getCalendar({
    required DateTime from,
    required DateTime to,
    required DateTime today,
  }) async {
    final ping = await _dio.get('/api/ping');
    final info = ServerCapabilities.tryParse(ping.data);
    if (info == null || !info.supports(ServerCapabilities.calendar)) {
      return null;
    }
    final response = await _dio.get('/api/calendar', queryParameters: {
      'from': _calendarDay(from),
      'to': _calendarDay(to),
      'today': _calendarDay(today),
    });
    return CalendarFeed.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  /// Suit une série, ou la remet dans le calendrier après un retrait.
  Future<void> followCalendarShow(int tmdbId) async {
    await _dio.put('/api/calendar/follows/$tmdbId');
  }

  /// Retire une série du calendrier, même regardée ou demandée.
  Future<void> unfollowCalendarShow(int tmdbId) async {
    await _dio.delete('/api/calendar/follows/$tmdbId');
  }
}

String _calendarDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
