import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/media_requests_provider.dart';

/// Le compte peut demander un titre : il en a le droit, et le serveur a un
/// compagnon de demandes réglé. Sans l'un ou l'autre, ni onglet Demandes ni
/// fiche de demande — seulement le titre absent.
///
/// Le droit se lit d'abord : un compte sans lui n'interroge pas le compagnon.
bool canRequestMedia(BuildContext context, {bool listen = false}) {
  final auth = Provider.of<AuthProvider>(context, listen: listen);
  if (!auth.permissions.requestMedia) return false;
  return Provider.of<MediaRequestsProvider>(context, listen: listen)
      .companionConfigured;
}
