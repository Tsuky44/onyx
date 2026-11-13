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

/// Ouvre la feuille « Inviter » d'une liste du compte (ADR-0127).
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

/// Les autres comptes du serveur, cochés quand le propriétaire les a invités
/// à remplir la liste. Cocher invite, décocher retire : chaque geste part
/// tout de suite au serveur, et se défait à l'écran s'il échoue.
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

  Future<void> _toggle(WatchListMember person, bool invited) async {
    if (_pending.contains(person.id)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending.add(person.id));
    try {
      if (invited) {
        await _provider.removeMember(widget.list.id, person.id);
      } else {
        await _provider.addMember(widget.list.id, person.id);
      }
    } catch (e) {
      debugPrint('WatchListMembersSheet: toggle ${person.id} failed: $e');
      messenger.showSnackBar(SnackBar(
        content: Text(settingsErrorText(
            e, tr('L’invitation n’a pas pu être modifiée. Réessayez.'))),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _pending.remove(person.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final invited = context.select<WatchListsProvider, Set<int>>((p) => {
          for (final m in p.detail(widget.list.id)?.members ?? const []) m.id,
        });
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Inviter à la liste'),
                      style: const TextStyle(
                          fontSize: AppType.title3,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                        'Les comptes cochés peuvent ajouter et retirer des '
                        'titres dans « {0} ». Vous seul la modifiez.',
                        [widget.list.displayName]),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
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
                    for (final (index, person) in people.indexed)
                      _PersonRow(
                        person: person,
                        invited: invited.contains(person.id),
                        busy: _pending.contains(person.id),
                        autofocus: index == 0,
                        onTap: () =>
                            _toggle(person, invited.contains(person.id)),
                      ),
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
    required this.invited,
    required this.busy,
    required this.onTap,
    this.autofocus = false,
  });

  final WatchListMember person;
  final bool invited;
  final bool busy;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: invited,
      child: ListTile(
        autofocus: autofocus,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: UserAvatar(person.username),
        title:
            Text(person.username, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Icon(
          invited ? AppIcons.check : null,
          color: busy ? AppColors.textMuted : AppColors.accent,
        ),
        onTap: onTap,
      ),
    );
  }
}
