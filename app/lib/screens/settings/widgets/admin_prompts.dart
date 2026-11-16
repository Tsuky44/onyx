import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../tv/tv_deferred_keyboard.dart';
import '../../../utils/password_policy.dart';
import '../../../widgets/global/onyx_dialog.dart';

/// Password prompt shared by the admin reset and the self-service change.
/// [minLength] : [minNewPasswordLength] pour un mot de passe choisi, 4 pour
/// en confirmer un existant, qui a pu être créé avec l'ancienne limite.
Future<String?> promptPassword(
  BuildContext context, {
  required String title,
  String? hint,
  String label = 'Nouveau mot de passe',
  int minLength = 4,
}) =>
    _promptPassword(context,
        title: title, hint: hint, label: label, minLength: minLength);

/// Le prompt de la réinitialisation par un administrateur : un mot de passe
/// *choisi*, donc soumis à la longueur minimale.
Future<String?> promptNewPassword(BuildContext context,
        {required String title, String? hint}) =>
    _promptPassword(context, title: title, hint: hint);

Future<String?> _promptPassword(BuildContext context,
    {required String title,
    String? hint,
    String label = 'Nouveau mot de passe',
    int minLength = minNewPasswordLength}) {
  final controller = TextEditingController();
  return showOnyxDialog<String>(
    context: context,
    builder: (ctx) => OnyxDialog(
      title: title,
      message: hint,
      content: TvDeferredKeyboard(
        builder: (context, focusNode, canRequestFocus) => TextField(
          focusNode: focusNode,
          canRequestFocus: canRequestFocus,
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr(label),
            helperText: minLength > 4
                ? tr('Au moins {0} caractères', ['$minLength'])
                : null,
          ),
        ),
      ),
      actions: [
        OnyxDialogAction(
          label: tr('Annuler'),
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        OnyxDialogAction(
          label: tr('Valider'),
          primary: true,
          onPressed: () {
            final value = controller.text;
            if (value.length < minLength) return;
            Navigator.of(ctx).pop(value);
          },
        ),
      ],
    ),
  );
}

/// Surfaces the server's own message — notably "Droits insuffisants" — rather
/// than a generic failure.
///
/// When there is no such message, it still says what happened. A bare "Action
/// impossible." hid whether the server refused, answered something else (a
/// proxy's error page), or could not be reached — which is the whole diagnosis.
String adminErrorText(Object error) {
  debugPrint('Users admin: $error');
  if (error is DioException) {
    final response = error.response;
    var data = response?.data;
    // Part of the server's errors are JSON sent as text/plain (Go's
    // http.Error), which Dio leaves as a string.
    if (data is String) {
      try {
        data = jsonDecode(data);
      } on FormatException {
        // Not JSON: an error page, most likely from a proxy.
      }
    }
    if (data is Map && data['error'] != null) return data['error'].toString();
    if (response == null) {
      return tr('Serveur injoignable ({0}).', [error.type.name]);
    }
    return tr('Action impossible (HTTP {0}).', [response.statusCode]);
  }
  return tr('Action impossible : {0}', [error]);
}
