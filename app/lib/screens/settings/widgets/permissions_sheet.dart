import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import 'admin_prompts.dart';
import 'settings_ui.dart';
import 'user_rights.dart';

/// Une liste d'interrupteurs, un par droit, dans un groupe de réglages.
///
/// [locked] : les droits qu'on montre sans les laisser changer (affichés
/// éteints). Une invitation qui accorderait `manage_users` ferait du droit
/// d'inviter le droit de tout faire.
class PermissionSwitches extends StatelessWidget {
  const PermissionSwitches({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.footer,
    this.locked = const {},
  });

  final Permissions value;
  final void Function(String key, bool granted) onChanged;
  final String? title;
  final String? footer;
  final Set<String> locked;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: title,
      footer: footer,
      dividerIndent: 16,
      children: [
        for (final entry in permissionLabels)
          SettingsSwitchTile(
            title: tr(entry.$2),
            value: !locked.contains(entry.$1) && readPermission(value, entry.$1),
            onChanged: locked.contains(entry.$1)
                ? null
                : (granted) => onChanged(entry.$1, granted),
          ),
      ],
    );
  }
}

/// Le gabarit d'une feuille de réglages : un titre, une phrase, le contenu qui
/// défile, et le bouton qui valide en bas.
class SettingsSheetFrame extends StatelessWidget {
  const SettingsSheetFrame({
    super.key,
    required this.title,
    this.hint,
    required this.children,
  });

  final String title;
  final String? hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 8 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: AppType.title3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(
                  hint!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppType.footnote,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Editor for one account's rights, plus the invitation template that goes with
/// `invite_users`.
class PermissionsSheet extends StatefulWidget {
  const PermissionsSheet({super.key, required this.user});

  final User user;

  @override
  State<PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<PermissionsSheet> {
  late Permissions _permissions = widget.user.permissions;
  late Permissions _inviteGrants = widget.user.inviteGrants;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().updateUserPermissions(
            widget.user.id,
            _permissions,
            inviteGrants: _inviteGrants,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = adminErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSheetFrame(
      title: tr('Droits de {0}', [widget.user.username]),
      hint: tr('Le raccourci « Administrateur » coche tout.'),
      children: [
        SettingsGroup(
          dividerIndent: 16,
          children: [
            SettingsSwitchTile(
              title: tr('Administrateur'),
              value: _permissions.isAdmin,
              onChanged: (value) => setState(() {
                _permissions = value
                    ? Permissions.all
                    : const Permissions(requestMedia: true);
                if (!value) _inviteGrants = const Permissions();
              }),
            ),
          ],
        ),
        PermissionSwitches(
          value: _permissions,
          onChanged: (key, granted) => setState(() {
            _permissions = writePermission(_permissions, key, granted);
            if (key == 'invite_users' && !granted) {
              _inviteGrants = const Permissions();
            }
          }),
        ),
        if (_permissions.inviteUsers)
          PermissionSwitches(
            title: tr('Droits accordés par ses invitations'),
            footer: tr('C’est vous qui décidez ce que ses liens accordent : '
                'la personne qui invite ne choisit rien, elle ne peut '
                'donc pas se fabriquer un compte administrateur.'),
            value: _inviteGrants,
            locked: const {'manage_users'},
            onChanged: (key, granted) => setState(() {
              _inviteGrants = writePermission(_inviteGrants, key, granted);
            }),
          ),
        if (_error != null) ...[
          SettingsBanner(_error!, tone: BannerTone.error),
        ],
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? tr('Enregistrement…') : tr('Enregistrer')),
        ),
      ],
    );
  }
}
