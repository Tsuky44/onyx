// ignore: deprecated_member_use
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
import '../../tv/tv_deferred_keyboard.dart';
import '../../utils/responsive.dart';
import '../../utils/search_match.dart' show foldForSearch;
import 'adaptive_panel.dart';
import 'empty_state.dart';
import 'list_visibility_choice.dart';
import 'onyx_menu_panel.dart' show OnyxMenuHairline;
import 'onyx_toast.dart';
import 'watch_list_access_control.dart';

/// Ouvre « Partager » pour une liste du compte (ADR-0127, ADR-0129,
/// ADR-0161) : un panneau collé au bouton [anchor] sur grand écran, une
/// feuille du bas sur téléphone et téléviseur (ADR-0131).
Future<void> showWatchListMembersSheet(
  BuildContext context,
  WatchList list, {
  BuildContext? anchor,
}) {
  return showAdaptivePanel<void>(
    context,
    anchor: anchor,
    width: 460,
    estimatedHeight: 520,
    sheetColor: AppColors.surfaceElevated,
    dragHandle: true,
    builder: (_) => WatchListMembersSheet(list: list),
  );
}

/// Au-delà de ce nombre de comptes, un champ filtre la liste des personnes.
const int _searchThreshold = 6;

/// Avec qui la liste est partagée : tout le serveur en lecture, et des
/// personnes choisies, qui la remplissent ou la voient seulement, même quand
/// elle est privée. Chaque geste part tout de suite au serveur, et l'écran
/// suit ce qu'il renvoie ; un échec se dit et laisse l'état d'avant.
///
/// « À regarder plus tard » ne s'ouvre à personne en particulier : elle n'a
/// que le choix de qui la voit. Un serveur d'avant les rôles (ADR-0127) ne
/// sait qu'inviter à remplir : le choix n'a alors que deux issues.
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
  String _query = '';

  WatchListsProvider get _provider => context.read<WatchListsProvider>();

  // Qui ouvre « Partager » a déjà vérifié que le serveur sait inviter ;
  // « À regarder plus tard » n'invite personne.
  bool get _withPeople => !widget.list.isWatchLater;

  @override
  void initState() {
    super.initState();
    if (_withPeople) _load();
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
    showOnyxToast(context, settingsErrorText(e, fallback), error: true);
  }

  Future<void> _setAccess(WatchListMember person, WatchListAccess access) async {
    if (_pending.contains(person.id)) return;
    setState(() => _pending.add(person.id));
    try {
      switch (access) {
        case WatchListAccess.none:
          await _provider.removeMember(widget.list.id, person.id);
        case WatchListAccess.viewer:
          await _provider.addMember(widget.list.id, person.id,
              role: WatchListRole.viewer);
        case WatchListAccess.editor:
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
    if (_savingShared || list.isShared == shared) return;
    setState(() => _savingShared = true);
    try {
      await _provider.updateList(list,
          name: list.name, description: list.description, isShared: shared);
    } catch (e) {
      debugPrint('WatchListMembersSheet: share with everyone failed: $e');
      if (mounted) _showError(e, tr('La liste n’a pas pu être modifiée.'));
    } finally {
      if (mounted) setState(() => _savingShared = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = AdaptivePanelScope.isPanel(context);
    final list = context.select<WatchListsProvider, WatchList>(
        (p) => p.summary(widget.list.id) ?? widget.list);
    final members =
        context.select<WatchListsProvider, Map<int, WatchListMember>>((p) => {
              for (final m in p.detail(widget.list.id)?.members ?? const [])
                m.id: m,
            });
    const pad = EdgeInsets.symmetric(horizontal: 20);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, panel ? 18 : 0, 12, 0),
              child: _Title(
                title: list.isWatchLater
                    ? list.displayName
                    : tr('Partager « {0} »', [list.displayName]),
                closable: panel,
              ),
            ),
            const SizedBox(height: 16),
            Padding(padding: pad, child: _SectionLabel(tr('Qui peut la voir'))),
            const SizedBox(height: 8),
            Padding(
              padding: pad,
              child: ListVisibilityChoice(
                shared: list.isShared,
                busy: _savingShared,
                autofocus: !_withPeople,
                onChanged: (v) => _setShared(list, v),
              ),
            ),
            if (_withPeople) ...[
              const SizedBox(height: 14),
              const OnyxMenuHairline(),
              const SizedBox(height: 10),
              Padding(
                padding: pad,
                child: _SectionLabel(
                  members.isEmpty
                      ? tr('Personnes')
                      : trPlural(members.length, 'Personnes · {0} invitée',
                          'Personnes · {0} invitées'),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(child: _peopleBody(members)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: Text(
                  tr('Les personnes qui ajoutent peuvent aussi retirer des '
                      'titres. Vous seul renommez ou supprimez la liste.'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppType.footnote,
                    height: 1.45,
                  ),
                ),
              ),
            ] else
              const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _peopleBody(Map<int, WatchListMember> members) {
    final people = _people;
    if (_error != null) {
      return ErrorStateView(message: _error!, onRetry: _load);
    }
    if (people == null) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (people.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Text(tr('Il n’y a pas d’autre compte sur ce serveur.'),
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    final query = foldForSearch(_query.trim());
    final shown = query.isEmpty
        ? people
        : [
            for (final p in people)
              if (foldForSearch(p.username).contains(query)) p,
          ];
    final roles = context.select<WatchListsProvider, bool>(
        (p) => p.supportsMemberRoles);
    final choices = roles
        ? WatchListAccess.values
        : const [WatchListAccess.none, WatchListAccess.editor];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (people.length > _searchThreshold)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: _SearchField(onChanged: (v) => setState(() => _query = v)),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final (index, person) in shown.indexed)
                _PersonRow(
                  person: person,
                  access: WatchListAccess.of(members[person.id]),
                  choices: choices,
                  busy: _pending.contains(person.id),
                  autofocus: index == 0,
                  onChanged: (a) => _setAccess(person, a),
                ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(tr('Aucun compte ne correspond.'),
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.title, required this.closable});

  final String title;
  final bool closable;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: AppType.title3,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(tr('Chaque changement s’applique tout de suite.'),
                  style: const TextStyle(
                      fontSize: AppType.subhead,
                      color: AppColors.textSecondary)),
            ],
          ),
        ),
        if (closable)
          IconButton(
            tooltip: tr('Fermer'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(AppIcons.close,
                size: 18, color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

/// Le titre d'un groupe en petites capitales, comme ceux des menus.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: AppType.caption,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TvDeferredKeyboard(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      builder: (context, focusNode, canRequestFocus) => TextField(
        focusNode: focusNode,
        canRequestFocus: canRequestFocus,
        onChanged: onChanged,
        style: const TextStyle(fontSize: AppType.body),
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('Rechercher un compte'),
          prefixIcon: const Icon(AppIcons.search, size: 18),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.access,
    required this.choices,
    required this.busy,
    required this.onChanged,
    this.autofocus = false,
  });

  final WatchListMember person;
  final WatchListAccess access;
  final List<WatchListAccess> choices;
  final bool busy;
  final ValueChanged<WatchListAccess> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final invited = access != WatchListAccess.none;
    // Sur téléphone, la capsule dit déjà l'accès : la légende le répéterait.
    final compact = AppLayout.isCompact(context);
    final Widget control;
    if (busy) {
      control = const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox.square(
            dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (compact) {
      control = WatchListAccessChip(
        person: person.username,
        value: access,
        choices: choices,
        onChanged: onChanged,
      );
    } else {
      control = WatchListAccessSegments(
        person: person.username,
        value: access,
        choices: choices,
        autofocus: autofocus,
        onChanged: onChanged,
      );
    }
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            UserAvatar(person.username),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: AppType.callout,
                          fontWeight: FontWeight.w500)),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(access.label,
                        style: TextStyle(
                            fontSize: AppType.footnote,
                            color: invited
                                ? AppColors.accentMuted
                                : AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            control,
          ],
        ),
      ),
    );
  }
}
