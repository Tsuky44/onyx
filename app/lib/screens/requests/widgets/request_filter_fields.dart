import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_icons.dart';
import '../../../tv/tv_deferred_keyboard.dart';

/// Les champs de la période et de la durée, partagés par la feuille des
/// filtres (TV) et les panneaux des capsules (bureau, téléphone).

/// Une date `AAAA-MM-JJ`, saisie à la main ou choisie au calendrier.
class RequestDateField extends StatelessWidget {
  const RequestDateField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  Future<void> _pick(BuildContext context) async {
    final value = controller.text;
    final initial =
        value.isNotEmpty ? DateTime.tryParse(value) : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final formatted = '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    controller.text = formatted;
    onChanged(formatted);
  }

  @override
  Widget build(BuildContext context) {
    return TvDeferredKeyboard(
      builder: (context, focusNode, canRequestFocus) => TextField(
        focusNode: focusNode,
        canRequestFocus: canRequestFocus,
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: tr('YYYY-MM-DD'),
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: tr('Choisir une date'),
            icon: const Icon(AppIcons.calendar, size: 18),
            onPressed: () => _pick(context),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// Une durée en minutes (borne basse ou haute).
class RequestDurationField extends StatelessWidget {
  const RequestDurationField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TvDeferredKeyboard(
      builder: (context, focusNode, canRequestFocus) => TextField(
        focusNode: focusNode,
        canRequestFocus: canRequestFocus,
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => onChanged(v.trim()),
      ),
    );
  }
}
