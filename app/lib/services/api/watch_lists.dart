part of '../api_client.dart';

/// Les listes du compte : « À regarder plus tard » et les siennes, partagées
/// ou non (ADR-0070), et les comptes invités à les remplir ou à les voir
/// (ADR-0127, ADR-0129).
mixin _WatchListEndpoints {
  Dio get _dio;
  String get baseUrl;

  /// Les serveurs qui ont annoncé `watch_lists` sur `/api/ping`. Un « non »
  /// n'est pas retenu : le serveur peut être mis à jour pendant que l'app est
  /// ouverte.
  final Set<String> _serversWithWatchLists = {};

  /// Le serveur actif sait-il tenir des listes ?
  Future<bool> supportsWatchLists() async {
    final server = baseUrl;
    if (_serversWithWatchLists.contains(server)) return true;
    final ping = await _dio.get('/api/ping');
    final info = ServerCapabilities.tryParse(ping.data);
    if (info == null || !info.supports(ServerCapabilities.watchLists)) {
      return false;
    }
    _serversWithWatchLists.add(server);
    return true;
  }

  /// Le serveur actif laisse-t-il inviter des comptes à remplir une liste ?
  /// Même règle que [supportsWatchLists] : un « non » n'est pas retenu.
  Future<bool> supportsWatchListMembers() async {
    final ping = await _dio.get('/api/ping');
    final info = ServerCapabilities.tryParse(ping.data);
    return info != null && info.supports(ServerCapabilities.watchListMembers);
  }

  /// Le serveur actif sait-il inviter à voir seulement (ADR-0129) ? Un
  /// serveur plus ancien ignorerait le rôle et donnerait le droit d'écrire :
  /// l'app ne propose « Voir » qu'à cette condition.
  Future<bool> supportsWatchListMemberRoles() async {
    final ping = await _dio.get('/api/ping');
    final info = ServerCapabilities.tryParse(ping.data);
    return info != null &&
        info.supports(ServerCapabilities.watchListMemberRoles);
  }

  /// Les listes du compte et celles que les autres partagent. Avec
  /// [containing], chacune des listes du compte dit si elle a déjà ce titre.
  Future<WatchListsOverview> getWatchLists({ListableTitle? containing}) async {
    final response =
        await _dio.get('/api/lists', queryParameters: containing?.probe);
    return WatchListsOverview.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  Future<WatchListDetail> getWatchList(int id) async {
    final response = await _dio.get('/api/lists/$id');
    return WatchListDetail.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  Future<WatchList> createWatchList({
    required String name,
    String description = '',
    bool isShared = false,
  }) async {
    final response = await _dio.post('/api/lists', data: {
      'name': name,
      'description': description,
      'is_shared': isShared,
    });
    return WatchList.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  /// Renomme une liste, change sa description ou son partage. « À regarder
  /// plus tard » ne garde que le partage.
  Future<WatchList> updateWatchList(
    int id, {
    required String name,
    required String description,
    required bool isShared,
  }) async {
    final response = await _dio.put('/api/lists/$id', data: {
      'name': name,
      'description': description,
      'is_shared': isShared,
    });
    return WatchList.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> deleteWatchList(int id) async {
    await _dio.delete('/api/lists/$id');
  }

  /// Range un titre dans une liste. Un titre déjà présent revient tel quel.
  Future<WatchListItem> addToWatchList(int listId, ListableTitle title) async {
    final response =
        await _dio.post('/api/lists/$listId/items', data: title.toJson());
    return WatchListItem.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> removeFromWatchList(int listId, int itemId) async {
    await _dio.delete('/api/lists/$listId/items/$itemId');
  }

  /// Les autres comptes du serveur : ceux qu'on peut inviter.
  Future<List<WatchListMember>> getWatchListPeople() async {
    final response = await _dio.get('/api/list-people');
    return _readMembers(response.data);
  }

  /// Invite un compte à la liste, à la remplir ou à la voir, ou change son
  /// rôle ; renvoie tous les invités. Sans [role], le corps reste vide, comme
  /// le comprend un serveur d'avant les rôles.
  Future<List<WatchListMember>> addWatchListMember(int listId, int userId,
      {WatchListRole? role}) async {
    final response = await _dio.put('/api/lists/$listId/members/$userId',
        data: role == null ? null : {'role': role.wire});
    return _readMembers(response.data);
  }

  /// Retire un invité, ou quitte la liste quand [userId] est le compte
  /// lui-même.
  Future<void> removeWatchListMember(int listId, int userId) async {
    await _dio.delete('/api/lists/$listId/members/$userId');
  }

  static List<WatchListMember> _readMembers(Object? data) => (data
              as List<dynamic>? ??
          const [])
      .map((e) => WatchListMember.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
}
