import 'media.dart';

/// Une invitation à une séance « Regarder ensemble » envoyée à ce compte
/// (ADR-0148).
///
/// [media] est le média tel que ce compte le voit, celui que la séance lit au
/// moment de la réponse : une séance passée à l'épisode suivant invite à
/// celui-là.
class WatchPartyInvite {
  const WatchPartyInvite({
    required this.id,
    required this.code,
    required this.from,
    required this.mediaId,
    required this.media,
    required this.expiresIn,
  });

  final String id;
  final String code;

  /// Le nom de qui invite.
  final String from;
  final int mediaId;
  final HomeMediaItem? media;

  /// Le temps qu'il lui reste, compté par le serveur au moment de répondre :
  /// jamais comparé à l'horloge de l'appareil.
  final Duration expiresIn;

  factory WatchPartyInvite.fromJson(Map<String, dynamic> json) {
    final media = json['media'];
    return WatchPartyInvite(
      id: json['id'] as String? ?? '',
      code: json['code'] as String? ?? '',
      from: json['from'] as String? ?? '',
      mediaId: (json['media_id'] as num?)?.toInt() ?? 0,
      media:
          media is Map<String, dynamic> ? HomeMediaItem.fromJson(media) : null,
      expiresIn:
          Duration(seconds: (json['expires_in_seconds'] as num?)?.toInt() ?? 0),
    );
  }
}

/// La boîte d'invitations du compte, à une version donnée.
class WatchPartyInvites {
  const WatchPartyInvites({required this.version, required this.invites});

  final int version;
  final List<WatchPartyInvite> invites;

  factory WatchPartyInvites.fromJson(Map<String, dynamic> json) =>
      WatchPartyInvites(
        version: (json['version'] as num?)?.toInt() ?? 0,
        invites: [
          for (final item in (json['invites'] as List? ?? const []))
            if (item is Map<String, dynamic>) WatchPartyInvite.fromJson(item),
        ],
      );
}

/// Où en est l'invitation d'une personne à la séance.
enum WatchPartyInviteStatus {
  /// Pas encore invitée.
  none,

  /// Invitée, sans réponse.
  pending,

  /// Elle a refusé.
  declined;

  static WatchPartyInviteStatus parse(String? raw) => switch (raw) {
        'pending' => pending,
        'declined' => declined,
        _ => none,
      };
}

/// Une personne qui a Onyx ouvert en ce moment, et qu'on peut donc inviter.
class WatchPartyInvitee {
  const WatchPartyInvitee({
    required this.userId,
    required this.username,
    this.avatar = '',
    this.status = WatchPartyInviteStatus.none,
  });

  final int userId;
  final String username;

  /// L'image de profil telle que le serveur la décrit (ADR-0078).
  final String avatar;
  final WatchPartyInviteStatus status;

  WatchPartyInvitee copyWith({WatchPartyInviteStatus? status}) =>
      WatchPartyInvitee(
        userId: userId,
        username: username,
        avatar: avatar,
        status: status ?? this.status,
      );

  factory WatchPartyInvitee.fromJson(Map<String, dynamic> json) =>
      WatchPartyInvitee(
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        avatar: json['avatar'] as String? ?? '',
        status: WatchPartyInviteStatus.parse(json['invite_status'] as String?),
      );
}
