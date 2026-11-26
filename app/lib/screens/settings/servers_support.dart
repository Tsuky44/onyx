import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/server_account.dart';
import '../../services/api_client.dart';
import '../../services/server_registry.dart';
import '../../theme/app_colors.dart';

/// Les autres comptes de cet appareil qu'on peut lier à [account] : sur un
/// autre serveur, et pas déjà liés.
List<ServerAccount> linkCandidates(ApiClient api, ServerAccount account) {
  final linked =
      api.servers.linkedAccounts(account.id).map((a) => a.id).toSet();
  return api.servers.accounts
      .where((a) =>
          !linked.contains(a.id) && !ServerRegistry.sameServer(a, account))
      .toList();
}

/// Les serveurs liés à un compte de cet appareil sur lesquels il n'a pas
/// encore de session, une fois chacun.
List<AccountLink> serversNotOnThisDevice(ApiClient api) {
  final seen = <String>{};
  final result = <AccountLink>[];
  for (final account in api.servers.accounts) {
    for (final link in api.servers.serverLinksFor(account.id)) {
      if (api.servers.accountForLink(link) != null) continue;
      final key = link.serverId.isEmpty ? link.url : link.serverId;
      if (seen.add(key)) result.add(link);
    }
  }
  return result;
}

/// Un serveur proposé à l'ajout : soit déjà lié au compte depuis un autre
/// appareil ([username] non nul), soit mutuellement accepté par les
/// administrateurs des deux serveurs.
class SuggestedServerOption {
  const SuggestedServerOption({
    required this.serverId,
    required this.name,
    required this.url,
    this.username,
  });

  final String serverId;
  final String name;
  final String url;
  final String? username;

  bool get isLinkedAccount => username != null && username!.isNotEmpty;

  String get prettyHost {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  String get displayName => name.trim().isNotEmpty ? name.trim() : prettyHost;
}

/// Rassemble les serveurs proposés à l'ajout : d'abord ceux déjà liés au
/// compte sur un autre appareil, puis les serveurs pairs mutuellement acceptés
/// par les administrateurs qui ne sont pas encore dans le carnet.
Future<List<SuggestedServerOption>> loadSuggestedServers(ApiClient api) async {
  final seenIds = <String>{};
  final seenUrls = <String>{};
  void markSeen(String serverId, String url) {
    if (serverId.isNotEmpty) seenIds.add(serverId);
    final normalized = ServerAccount.normalizeUrl(url);
    if (normalized.isNotEmpty) seenUrls.add(normalized);
  }

  bool isSeen(String serverId, String url) {
    if (serverId.isNotEmpty && seenIds.contains(serverId)) return true;
    final normalized = ServerAccount.normalizeUrl(url);
    return normalized.isNotEmpty && seenUrls.contains(normalized);
  }

  for (final existing in api.servers.accounts) {
    markSeen(existing.serverId ?? '', existing.url);
  }

  final result = <SuggestedServerOption>[];
  for (final link in serversNotOnThisDevice(api)) {
    if (isSeen(link.serverId, link.url)) continue;
    markSeen(link.serverId, link.url);
    result.add(SuggestedServerOption(
      serverId: link.serverId,
      name: link.displayName,
      url: link.url,
      username: link.remoteUsername,
    ));
  }

  final peers = await api.getSuggestedPeerServers();
  for (final peer in peers) {
    if (isSeen(peer.serverId, peer.url)) continue;
    markSeen(peer.serverId, peer.url);
    result.add(SuggestedServerOption(
      serverId: peer.serverId,
      name: peer.displayName,
      url: peer.url,
    ));
  }
  return result;
}

/// Lie deux comptes et dit où en est le lien.
Future<void> linkAndReport(
    BuildContext context, String fromId, String toId) async {
  final messenger = ScaffoldMessenger.of(context);
  final api = context.read<ApiClient>();
  try {
    final link = await api.linkAccounts(fromId, toId);
    messenger.showSnackBar(SnackBar(
      content: Text(link.isActive
          ? tr('Comptes liés. Les serveurs se transmettent désormais votre '
              'progression.')
          : tr('Lien demandé. Il sera actif dès que les administrateurs des '
              'deux serveurs l’auront accepté.')),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(serverErrorText(e)),
      backgroundColor: AppColors.error,
    ));
  }
}

/// Message d'erreur lisible : le serveur en écrit un français, sinon on parle
/// de réseau.
String serverErrorText(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return tr('Le serveur ne répond pas (délai dépassé).');
      case DioExceptionType.connectionError:
        return tr('Serveur injoignable. Vérifiez l’adresse et le réseau.');
      default:
        break;
    }
  }
  if (error is StateError) return error.message;
  return tr('Une erreur est survenue : {0}', [error]);
}
