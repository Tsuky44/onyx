import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/watch_list.dart';
import '../../providers/watch_lists_provider.dart';
import '../../screens/settings/widgets/settings_ui.dart'
    show UserAvatar, settingsErrorText;
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import 'empty_state.dart';

/// Ouvre la feuille « Partager » d'une liste du compte (ADR-0127, ADR-0129).
Future<void> showWatchListMembersSheet(BuildContext context, WatchList list) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (_) => WatchListMembersSheet(list: list),
  );
}

/// Ce qu'un compte peut faire de la liste, tel que la feuille le propose :
/// rien, la voir, ou la remplir.
enum _Access { none, viewer, editor }

_Access _accessOf(WatchListMember? member) => switch (member?.role) {
      null => _Access.none,
      WatchListRole.viewer => _Access.viewer,
      WatchListRole.editor => _Access.editor,
    };

String _accessLabel(_Access access) => switch (access) {
      _Access.none => tr('Aucun accès'),
      _Access.viewer => tr('Peut voir'),
      _Access.editor => tr('Peut ajouter des titres'),
    };

/// Avec qui la liste est partagée : tout le serveur en lecture, et des
/// personnes choisies, qui la remplissent ou la voient seulement, même quand
/// elle est privée. Chaque geste part tout de suite au serveur, et l'écran
/// suit ce qu'il renvoie ; un échec se dit et laisse l'état d'avant.
///
/// Un serveur d'avant les rôles (ADR-0127) ne sait qu'inviter à remplir :
/// une personne s'y coche et se décoche, sans choix de rôle.
class WatchListMembersSheet extends StatefulWidget {
  const WatchListMembersSheet({super.key, required this.list});

  final WatchList list;

  @override
  State<WatchListMembersSheet> createState() => _WatchListMembersSheetState();
}

class _WatchListMembersSheetState extends State<WatchListMembersSheet> {
  List<WatchListMember>? _people;
  String? _error;
  final Set<int> _pending = {};
  bool _savingShared = false;

  /// La personne dont les choix sont dépliés.
  int? _expanded;

  WatchListsProvider get _provider => context.read<WatchListsProvider>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      // Les invités viennent du détail de la liste : il se relit pour que la
      // feuille ne coche pas d'après un cache périmé.
      final people = await _provider.people();
      await _provider.loadDetail(widget.list.id, silent: true);
      if (mounted) setState(() => _people = people);
    } catch (e) {
      debugPrint('WatchListMembersSheet: people unavailable: $e');
      if (mounted) {
        setState(() => _error = tr('Impossible de charger les comptes.'));
      }
    }
  }

  void _showError(Object e, String fallback) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(settingsErrorText(e, fallback)),
      backgroundColor: AppColors.error,
    ));
  }

  Future<void> _setAccess(WatchListMember person, _Access access) async {
    if (_pending.contains(person.id)) return;
    setState(() {
      _pending.add(person.id);
      _expanded = null;
    });
    try {
      switch (access) {
        case _Access.none:
          await _provider.removeMember(widget.list.id, person.id);
        case _Access.viewer:
          await _provider.addMember(widget.list.id, person.id,
              role: WatchListRole.viewer);
        case _Access.editor:
          await _provider.addMember(widget.list.id, person.id,
              role: WatchListRole.editor);
      }
    } catch (e) {
      debugPrint('WatchListMembersSheet: access ${person.id} failed: $e');
      if (mounted) {
        _showError(e, tr('L’invitation n’a pas pu être modifiée. Réessayez.'));
      }
    } finally {
      if (mounted) setState(() => _pending.remove(person.id));
    }
  }

  Future<void> _setShared(WatchList list, bool shared) async {
    if (_savingShared) return;
    setState(() => _savingShared = true);
    try {
      await _provider.updateList(list,
          name: list.name, description: list.description, isShared: shared);
    } catch (e) {
      debugPrint('WatchListMembersSheet: share with everyone failed: $e');
      if (mounted) {
        _showError(e, tr('La liste n’a pas pu être modifiée.'));
      }
    } finally {
      if (mounted) setState(() => _savingShared = false);
    }
  }

  void _onPersonTap(WatchListMember person, _Access access, bool roles) {
    if (!roles) {
      // Serveur d'avant les rôles : cocher invite à remplir, décocher retire.
      _setAccess(
          person, access == _Access.none ? _Access.editor : _Access.none);
      return;
    }
    setState(() => _expanded = _expanded == person.id ? null : person.id);
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final roles =
        context.select<WatchListsProvider, bool>((p) => p.supportsMemberRoles);
    final list = context.select<WatchListsProvider, WatchList>(
        (p) => p.summary(widget.list.id) ?? widget.list);
    final members =
        context.select<WatchListsProvider, Map<int, WatchListMember>>((p) => {
              for (final m in p.detail(widget.list.id)?.members ?? const [])
                m.id: m,
            });
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(tr('Partager « {0} »', [list.displayName]),
                  style: const TextStyle(
                      fontSize: AppType.title3,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              value: list.isShared,
              onChanged: _savingShared ? null : (v) => _setShared(list, v),
              title: Text(tr('Tout le serveur peut la voir')),
              subtitle: Text(
                tr('Les autres comptes la voient sans pouvoir la modifier.'),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: AppType.subhead),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Text(
                roles
                    ? tr('Choisissez qui peut ajouter des titres, ou '
                        'seulement voir la liste quand elle est privée.')
                    : tr(
                        'Les comptes cochés peuvent ajouter et retirer des '
                        'titres dans « {0} ». Vous seul la modifiez.',
                        [list.displayName]),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            if (_error != null)
              Flexible(child: ErrorStateView(message: _error!, onRetry: _load))
            else if (people == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
              )
            else if (people.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Text(tr('Il n’y a pas d’autre compte sur ce serveur.'),
                    style: const TextStyle(color: AppColors.textMuted)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (index, person) in people.indexed) ...[
                      _PersonRow(
                        person: person,
                        access: _accessOf(members[person.id]),
                        roles: roles,
                        expanded: _expanded == person.id,
                        busy: _pending.contains(person.id),
                        autofocus: index == 0,
                        onTap: () => _onPersonTap(
                            person, _accessOf(members[person.id]), roles),
                      ),
                      if (roles && _expanded == person.id)
                        for (final access in _Access.values.reversed)
                          _AccessChoice(
                            access: access,
                            selected: _accessOf(members[person.id]) == access,
                            autofocus: _accessOf(members[person.id]) == access,
                            onTap: () => _setAccess(person, access),
                          ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.access,
    required this.roles,
    required this.expanded,
    required this.busy,
    required this.onTap,
    this.autofocus = false,
  });

  final WatchListMember person;
  final _Access access;

  /// Le serveur connaît les rôles : la ligne déplie ses choix au lieu de
  /// cocher.
  final bool roles;
  final bool expanded;
  final bool busy;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final invited = access != _Access.none;
    final Widget? trailing;
    if (busy) {
      trailing = const SizedBox.square(
          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (roles) {
      trailing = RotatedBox(
        quarterTurns: expanded ? 2 : 0,
        child: const Icon(AppIcons.expand, color: AppColors.textMuted),
      );
    } else {
      trailing =
          invited ? const Icon(AppIcons.check, color: AppColors.accent) : null;
    }
    return Semantics(
      checked: roles ? null : invited,
      expanded: roles ? expanded : null,
      child: ListTile(
        autofocus: autofocus,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: UserAvatar(person.username),
        title:
            Text(person.username, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: roles
            ? Text(_accessLabel(access),
                style: TextStyle(
                    color: invited ? AppColors.accent : AppColors.textMuted))
            : null,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

/// Un des trois choix d'une personne, sous sa ligne dépliée.
class _AccessChoice extends StatelessWidget {
  const _AccessChoice({
    required this.access,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final _Access access;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: ListTile(
        autofocus: autofocus,
        dense: true,
        contentPadding: const EdgeInsets.only(left: 80, right: 24),
        title: Text(_accessLabel(access)),
        trailing: selected
            ? const Icon(AppIcons.check, color: AppColors.accent)
            : null,
        onTap: onTap,
      ),
    );
  }
}
