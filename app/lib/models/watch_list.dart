import '../l10n/tr.dart';
import 'media.dart';
import 'media_request.dart';

/// Les listes d'un compte : « À regarder plus tard » et les siennes, partagées
/// ou non avec les autres comptes du serveur (ADR-0070).
enum WatchListKind {
  /// La liste que chaque compte a d'office : elle ne se renomme ni ne se
  /// supprime.
  watchLater,
  custom;

  static WatchListKind parse(String? wire) =>
      wire == 'watch_later' ? WatchListKind.watchLater : WatchListKind.custom;
}

/// Ce qu'une liste range : un film ou une série.
enum WatchListMediaType {
  movie,
  show;

  static WatchListMediaType parse(String? wire) =>
      wire == 'show' ? WatchListMediaType.show : WatchListMediaType.movie;

  String get wire => name;
}

/// Ce qu'un invité peut faire d'une liste (ADR-0129).
enum WatchListRole {
  /// Il y ajoute et en retire des titres.
  editor,

  /// Il la voit, même privée, sans la modifier.
  viewer;

  /// Un serveur d'avant les rôles (ADR-0127) n'en envoie pas : ses invités
  /// remplissent tous la liste.
  static WatchListRole parse(String? value) =>
      value == 'viewer' ? WatchListRole.viewer : WatchListRole.editor;

  String get wire => name;
}

/// Un compte du serveur tel qu'une liste le montre : un invité, à la remplir
/// ou à la voir (ADR-0127, ADR-0129), ou quelqu'un qu'on peut inviter.
class WatchListMember {
  const WatchListMember({
    required this.id,
    required this.username,
    this.avatar = '',
    this.role = WatchListRole.editor,
  });

  final int id;
  final String username;

  /// L'image de profil, au format de l'ADR-0078 (vide : l'initiale).
  final String avatar;

  /// Le rôle de l'invité ; sans objet pour un compte qu'on peut inviter.
  final WatchListRole role;

  factory WatchListMember.fromJson(Map<String, dynamic> json) =>
      WatchListMember(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        avatar: json['avatar'] as String? ?? '',
        role: WatchListRole.parse(json['role'] as String?),
      );
}

class WatchListOwner {
  const WatchListOwner({required this.id, required this.username});

  final int id;
  final String username;

  factory WatchListOwner.fromJson(Map<String, dynamic> json) => WatchListOwner(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
      );
}

/// Le résumé d'une liste : ce que montrent la page des listes et la feuille
/// « Ajouter à une liste ».
class WatchList {
  const WatchList({
    required this.id,
    required this.kind,
    required this.name,
    required this.description,
    required this.isShared,
    required this.isMine,
    required this.owner,
    required this.itemCount,
    required this.posters,
    this.canEdit = false,
    this.isMember = false,
    this.memberCount = 0,
    this.updatedAt,
    this.containsItemId,
    this.watchedCount,
    this.onServerCount,
    this.nextItem,
  });

  final int id;
  final WatchListKind kind;
  final String name;
  final String description;
  final bool isShared;
  final bool isMine;

  /// Le compte peut y ajouter et en retirer des titres : la liste est à lui,
  /// ou son propriétaire l'a invité à la remplir.
  final bool canEdit;

  /// Le compte y est invité, à la remplir ou à la voir : il peut la quitter.
  final bool isMember;

  /// Combien de comptes le propriétaire a invités, à la remplir ou à la voir.
  final int memberCount;
  final WatchListOwner owner;
  final int itemCount;

  /// Les affiches des derniers ajouts, quatre au plus.
  final List<String> posters;
  final DateTime? updatedAt;

  /// L'élément de cette liste qui porte le titre demandé, 0 s'il n'y est pas ;
  /// null quand rien n'a été demandé.
  final int? containsItemId;

  /// Combien de titres le compte qui lit a vus ; null quand le serveur ne le
  /// dit pas (serveur d'avant l'ADR-0159). Le serveur tranche ce qu'est « vu » :
  /// un film terminé, une série dont chaque épisode présent l'est.
  final int? watchedCount;

  /// Combien de titres le serveur a ; null comme [watchedCount].
  final int? onServerCount;

  /// Le premier titre du serveur que le compte n'a pas vu, dans l'ordre
  /// d'ajout ; null quand il a tout vu ou que le serveur ne le dit pas.
  final WatchListNext? nextItem;

  bool get isWatchLater => kind == WatchListKind.watchLater;

  /// Le serveur a donné la progression : la vue large peut la montrer.
  bool get hasProgress => watchedCount != null && onServerCount != null;

  /// Les titres que le serveur n'a pas : ceux qu'on peut demander.
  int get toRequestCount => onServerCount == null
      ? 0
      : (itemCount - onServerCount!).clamp(0, itemCount);

  /// La part des titres de la liste déjà vus, de 0 à 1 : « N vus sur M », M
  /// comptant aussi ce qu'il reste à demander. 0 pour une liste vide.
  double get watchedFraction {
    final watched = watchedCount;
    if (watched == null || itemCount <= 0) return 0;
    return (watched / itemCount).clamp(0.0, 1.0);
  }

  /// Le nom à afficher : celui de « À regarder plus tard » suit la langue de
  /// l'interface, le serveur n'en range qu'une version.
  String get displayName => isWatchLater ? tr('À regarder plus tard') : name;

  /// Un élément en cours d'ajout porte un identifiant négatif : il compte
  /// déjà comme présent.
  bool get contains => (containsItemId ?? 0) != 0;

  factory WatchList.fromJson(Map<String, dynamic> json) => WatchList(
        id: (json['id'] as num).toInt(),
        kind: WatchListKind.parse(json['kind'] as String?),
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        isShared: json['is_shared'] as bool? ?? false,
        isMine: json['is_mine'] as bool? ?? false,
        canEdit: json['can_edit'] as bool? ?? false,
        // Un serveur d'avant les rôles (ADR-0127) ne dit pas `is_member` :
        // chez lui, un invité est celui qui remplit la liste d'un autre.
        isMember: json['is_member'] as bool? ??
            ((json['can_edit'] as bool? ?? false) &&
                !(json['is_mine'] as bool? ?? false)),
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        owner: WatchListOwner.fromJson(
            Map<String, dynamic>.from(json['owner'] as Map? ?? const {})),
        itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
        posters: (json['posters'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
        containsItemId: (json['contains_item_id'] as num?)?.toInt(),
        watchedCount: (json['watched_count'] as num?)?.toInt(),
        onServerCount: (json['on_server_count'] as num?)?.toInt(),
        nextItem: json['next_item'] is Map
            ? WatchListNext.fromJson(
                Map<String, dynamic>.from(json['next_item'] as Map))
            : null,
      );

  /// La même liste avec un titre de plus ou de moins, en attendant que le
  /// serveur confirme.
  WatchList withMembership(int itemId) => WatchList(
        id: id,
        kind: kind,
        name: name,
        description: description,
        isShared: isShared,
        isMine: isMine,
        canEdit: canEdit,
        isMember: isMember,
        memberCount: memberCount,
        owner: owner,
        itemCount: itemCount +
            (itemId != 0 && !contains
                ? 1
                : itemId == 0 && contains
                    ? -1
                    : 0),
        posters: posters,
        updatedAt: updatedAt,
        containsItemId: itemId,
        watchedCount: watchedCount,
        onServerCount: onServerCount,
        nextItem: nextItem,
      );
}

/// Le prochain titre à regarder d'une liste, du serveur : de quoi l'afficher
/// et le lancer (ADR-0159).
class WatchListNext {
  const WatchListNext({
    required this.id,
    required this.mediaId,
    required this.mediaType,
    required this.title,
    required this.posterUrl,
    required this.releaseDate,
  });

  final int id;

  /// La fiche du serveur, que « Lire » lance.
  final int mediaId;
  final WatchListMediaType mediaType;
  final String title;
  final String posterUrl;
  final String releaseDate;

  String? get year =>
      releaseDate.length >= 4 ? releaseDate.substring(0, 4) : null;

  factory WatchListNext.fromJson(Map<String, dynamic> json) => WatchListNext(
        id: (json['id'] as num?)?.toInt() ?? 0,
        mediaId: (json['media_id'] as num?)?.toInt() ?? 0,
        mediaType: WatchListMediaType.parse(json['media_type'] as String?),
        title: json['title'] as String? ?? '',
        posterUrl: json['poster_url'] as String? ?? '',
        releaseDate: json['release_date'] as String? ?? '',
      );
}

/// Un film ou une série d'une liste, sur le serveur ou pas encore.
class WatchListItem {
  const WatchListItem({
    required this.id,
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    required this.posterUrl,
    required this.releaseDate,
    required this.mediaId,
    this.addedAt,
    this.media,
    this.watched = false,
    this.episodesWatched = 0,
    this.episodesTotal = 0,
    this.nextEpisodeSeason = 0,
    this.nextEpisodeNumber = 0,
  });

  final int id;
  final WatchListMediaType mediaType;
  final int tmdbId;
  final String title;
  final String posterUrl;
  final String releaseDate;
  final DateTime? addedAt;

  /// La fiche du serveur, 0 quand il n'a pas (ou plus) ce titre.
  final int mediaId;

  /// Cette fiche, avec la progression du compte qui lit la liste.
  final HomeMediaItem? media;

  /// Le compte qui lit a vu ce titre. Le serveur tranche (un film terminé, une
  /// série dont chaque épisode présent l'est) ; faux pour un titre qu'il n'a
  /// pas, et pour un serveur d'avant l'ADR-0159.
  final bool watched;

  /// Où le compte en est d'une série : ses épisodes terminés, sur ceux que le
  /// serveur a, et le premier qui lui reste (0 quand il a tout vu). Le serveur
  /// les calcule (ADR-0162) ; tous à 0 pour un film, une série que le serveur
  /// n'a pas, et un serveur d'avant l'ADR-0162.
  final int episodesWatched;
  final int episodesTotal;
  final int nextEpisodeSeason;
  final int nextEpisodeNumber;

  /// Une série commencée et pas finie : la seule dont l'affiche dit où l'on en
  /// est. Une série jamais lancée ou entièrement vue n'a rien à ajouter à son
  /// affiche (la coche de « vu » suffit à la seconde).
  bool get isShowInProgress =>
      mediaType == WatchListMediaType.show &&
      !watched &&
      episodesTotal > 0 &&
      episodesWatched > 0 &&
      episodesWatched < episodesTotal;

  /// La part des épisodes terminés, de 0 à 1.
  double get episodesFraction =>
      episodesTotal <= 0 ? 0 : (episodesWatched / episodesTotal).clamp(0.0, 1.0);

  /// « S2 E5 » : l'épisode à regarder ensuite ; null quand le serveur ne le
  /// nomme pas (épisode sans numéro).
  String? get nextEpisodeCode => nextEpisodeSeason > 0 && nextEpisodeNumber > 0
      ? tr('S{0} E{1}', [nextEpisodeSeason, nextEpisodeNumber])
      : null;

  /// Le serveur a ce titre : il s'ouvre sur sa fiche.
  bool get isOnServer => media != null;

  /// Le chemin TMDB de l'affiche (`/abc.jpg`), ce que le serveur accepte pour
  /// ranger un titre qu'il n'a pas ; null pour une autre adresse.
  String? get tmdbPosterPath => _tmdbPath(posterUrl);

  String? get year =>
      releaseDate.length >= 4 ? releaseDate.substring(0, 4) : null;

  factory WatchListItem.fromJson(Map<String, dynamic> json) {
    final media = json['media'];
    return WatchListItem(
      id: (json['id'] as num).toInt(),
      mediaType: WatchListMediaType.parse(json['media_type'] as String?),
      tmdbId: (json['tmdb_id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      posterUrl: json['poster_url'] as String? ?? '',
      releaseDate: json['release_date'] as String? ?? '',
      addedAt: DateTime.tryParse(json['added_at'] as String? ?? ''),
      mediaId: (json['media_id'] as num?)?.toInt() ?? 0,
      watched: json['watched'] as bool? ?? false,
      episodesWatched: (json['episodes_watched'] as num?)?.toInt() ?? 0,
      episodesTotal: (json['episodes_total'] as num?)?.toInt() ?? 0,
      nextEpisodeSeason: (json['next_episode_season'] as num?)?.toInt() ?? 0,
      nextEpisodeNumber: (json['next_episode_number'] as num?)?.toInt() ?? 0,
      media: media is Map
          ? HomeMediaItem.fromJson(Map<String, dynamic>.from(media))
          : null,
    );
  }

  /// Le titre tel que le catalogue des demandes l'ouvre, pour ce que le
  /// serveur n'a pas.
  RequestMediaItem toRequestItem() => RequestMediaItem(
        id: tmdbId,
        mediaType: mediaType == WatchListMediaType.show
            ? RequestMediaType.tv
            : RequestMediaType.movie,
        title: title,
        overview: '',
        posterPath: _tmdbPath(posterUrl),
        backdropPath: null,
        releaseDate: releaseDate.isEmpty ? null : releaseDate,
        rating: 0,
        status: RequestMediaStatus.unknown,
      );

  /// Le chemin TMDB d'une affiche (`/abc.jpg`), que [RequestMediaItem]
  /// recompose ; null pour une autre adresse.
  static String? _tmdbPath(String url) {
    final marker = url.indexOf('/t/p/');
    if (marker < 0) return null;
    final slash = url.indexOf('/', marker + 5);
    return slash < 0 ? null : url.substring(slash);
  }
}

/// Une liste et son contenu, du plus récent ajout au plus ancien, avec les
/// comptes invités à la remplir.
class WatchListDetail {
  const WatchListDetail({
    required this.list,
    required this.items,
    this.members = const [],
  });

  final WatchList list;
  final List<WatchListItem> items;
  final List<WatchListMember> members;

  factory WatchListDetail.fromJson(Map<String, dynamic> json) =>
      WatchListDetail(
        list: WatchList.fromJson(json),
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((e) =>
                WatchListItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        members: (json['members'] as List<dynamic>? ?? const [])
            .map((e) =>
                WatchListMember.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Les listes du compte, « À regarder plus tard » en tête, et celles que les
/// autres comptes partagent.
class WatchListsOverview {
  const WatchListsOverview({required this.mine, required this.shared});

  static const empty = WatchListsOverview(mine: [], shared: []);

  final List<WatchList> mine;
  final List<WatchList> shared;

  factory WatchListsOverview.fromJson(Map<String, dynamic> json) {
    List<WatchList> read(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((e) => WatchList.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
    return WatchListsOverview(mine: read('mine'), shared: read('shared'));
  }
}

/// Un titre qu'on peut ranger dans une liste : une fiche du serveur, ou un
/// titre du catalogue que le serveur n'a peut-être pas.
class ListableTitle {
  const ListableTitle._({
    required this.title,
    this.mediaId = 0,
    this.tmdbId = 0,
    this.mediaType = WatchListMediaType.movie,
    this.posterPath,
    this.releaseDate,
  });

  /// Un film ou une série du serveur.
  factory ListableTitle.server(Media media) => ListableTitle._(
        title: media.title,
        mediaId: media.id,
        mediaType: media.type == MediaType.show
            ? WatchListMediaType.show
            : WatchListMediaType.movie,
      );

  /// Un titre du catalogue des demandes.
  factory ListableTitle.catalog(RequestMediaItem item) => ListableTitle._(
        title: item.title,
        tmdbId: item.id,
        mediaType: item.mediaType == RequestMediaType.tv
            ? WatchListMediaType.show
            : WatchListMediaType.movie,
        posterPath: item.posterPath,
        releaseDate: item.releaseDate,
      );

  /// Le titre d'un élément déjà rangé : pour le copier dans une autre liste,
  /// ou le remettre dans celle d'où on vient de le retirer.
  factory ListableTitle.fromItem(WatchListItem item) => ListableTitle._(
        title: item.title,
        mediaId: item.mediaId,
        tmdbId: item.tmdbId,
        mediaType: item.mediaType,
        posterPath: item.tmdbPosterPath,
        releaseDate: item.releaseDate,
      );

  final String title;
  final int mediaId;
  final int tmdbId;
  final WatchListMediaType mediaType;
  final String? posterPath;
  final String? releaseDate;

  bool get isOnServer => mediaId > 0;

  /// Le corps de `POST /api/lists/:id/items`.
  Map<String, dynamic> toJson() => isOnServer
      ? {'media_id': mediaId}
      : {
          'tmdb_id': tmdbId,
          'media_type': mediaType.wire,
          'title': title,
          if (posterPath != null && posterPath!.isNotEmpty)
            'poster_path': posterPath,
          if (releaseDate != null && releaseDate!.isNotEmpty)
            'release_date': releaseDate,
        };

  /// La question de `GET /api/lists` : dans quelles listes est ce titre.
  Map<String, dynamic> get probe => isOnServer
      ? {'media_id': mediaId}
      : {'tmdb_id': tmdbId, 'media_type': mediaType.wire};
}
