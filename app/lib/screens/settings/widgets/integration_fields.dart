import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../tv/tv_deferred_keyboard.dart';

/// Un champ de clé d'API : masqué par défaut, avec un œil pour la révéler. Sorti
/// de la page Services pour que l'assistant de première installation emploie
/// les mêmes champs (ADR-0165).
class IntegrationKeyField extends StatefulWidget {
  const IntegrationKeyField({
    super.key,
    required this.controller,
    required this.label,
    required this.configured,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final bool configured;
  final String? hint;

  @override
  State<IntegrationKeyField> createState() => _IntegrationKeyFieldState();
}

class _IntegrationKeyFieldState extends State<IntegrationKeyField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TvDeferredKeyboard(
      builder: (context, focusNode, canRequestFocus) => TextField(
        focusNode: focusNode,
        canRequestFocus: canRequestFocus,
        controller: widget.controller,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.configured
              ? tr('Clé active {0} — laisser vide pour la garder',
                  [widget.hint ?? '••••'])
              : tr('Coller la clé'),
          prefixIcon: const Icon(Icons.key_rounded),
          suffixIcon: IconButton(
            tooltip: _obscure ? tr('Afficher') : tr('Masquer'),
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(_obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
          ),
        ),
      ),
    );
  }
}

/// La rangée de boutons d'un formulaire de service : effacer la clé, tester
/// (quand le serveur sait le faire), enregistrer.
class IntegrationActions extends StatelessWidget {
  const IntegrationActions({
    super.key,
    required this.saving,
    required this.onSave,
    required this.onClear,
    this.onTest,
    this.testing = false,
    this.saveLabel,
  });

  final bool saving;
  final VoidCallback onSave;
  final VoidCallback? onClear;

  /// C'est le serveur qui joint le service : lui seul sait dire si ça passe.
  final VoidCallback? onTest;
  final bool testing;

  /// Le texte du bouton principal ; « Enregistrer » par défaut.
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (onClear != null)
          TextButton(
            onPressed: saving ? null : onClear,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(tr('Effacer la clé')),
          ),
        if (onTest != null)
          OutlinedButton(
            onPressed: saving ? null : onTest,
            child: Text(testing ? tr('Test…') : tr('Tester')),
          ),
        FilledButton(
          onPressed: saving ? null : onSave,
          child: Text(saving && !testing
              ? tr('Enregistrement…')
              : saveLabel ?? tr('Enregistrer')),
        ),
      ],
    );
  }
}
