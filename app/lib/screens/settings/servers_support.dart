import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
