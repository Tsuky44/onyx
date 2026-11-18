part of '../api_client.dart';

/// Inviter à une séance « Regarder ensemble » les personnes qui ont Onyx
/// ouvert (ADR-0148). Voir `server/handlers/watch_party_invites.go`.
mixin _WatchPartyInviteEndpoints {
  Dio get _dio;

  /// Le serveur sait inviter et tenir la boîte d'invitations. Un serveur
  /// d'avant n'a pas les routes : on ne lui pose pas la question.
  Future<bool> supportsWatchPartyInvites() async {
    final ping = await _dio.get('/api/ping');
    final info = ServerCapabilities.tryParse(ping.data);
    return info != null && info.supports(ServerCapabilities.watchPartyInvites);
  }

  /// Attend le prochain changement de la boîte après [since], une vingtaine
  /// de secondes au plus. Tant que l'app attend ici, le serveur la tient pour
  /// ouverte : c'est ce qui la rend invitable.
  Future<WatchPartyInvites> pollWatchPartyInvites({
    required int since,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get(
      '/api/me/watch-party-invites',
      queryParameters: {'since': since},
      cancelToken: cancelToken,
    );
    return WatchPartyInvites.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> declineWatchPartyInvite(String id) async {
    await _dio
        .post('/api/me/watch-party-invites/${Uri.encodeComponent(id)}/decline');
  }

  /// Les personnes qui ont Onyx ouvert et ne sont pas déjà dans la séance.
  Future<List<WatchPartyInvitee>> listWatchPartyInvitees(
    String code, {
    required String memberId,
  }) async {
    final response = await _dio.get(
      '/api/watch-parties/${Uri.encodeComponent(code)}/invitees',
      queryParameters: {'member': memberId},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return [
      for (final item in (data['invitees'] as List? ?? const []))
        if (item is Map<String, dynamic>) WatchPartyInvitee.fromJson(item),
    ];
  }

  Future<void> inviteToWatchParty(
    String code, {
    required String memberId,
    required int userId,
  }) async {
    await _dio.post(
      '/api/watch-parties/${Uri.encodeComponent(code)}/invite',
      data: {'member_id': memberId, 'user_id': userId},
    );
  }
}
