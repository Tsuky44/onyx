import 'package:dio/dio.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/media.dart' show MediaType;
import '../../models/watch_list.dart';
import '../../navigation/detail_flight.dart';
import '../../navigation/play_link.dart';
import '../../providers/auth_provider.dart';
import '../../providers/watch_lists_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../tv/nav/tv_back.dart';
import '../../tv/tv_mode.dart';
import '../../utils/responsive.dart';
import '../../widgets/global/empty_state.dart';
import '../../widgets/global/onyx_dialog.dart';
import '../../widgets/global/onyx_menu.dart';
import '../../widgets/global/onyx_toast.dart';
import '../../widgets/global/overlay_back_button.dart';
import '../../widgets/global/poster_grid_display_menu.dart';
import '../../widgets/global/poster_grid_zoom_region.dart';
import '../../widgets/global/watch_list_editor_dialog.dart';
import '../../widgets/global/watch_list_members_sheet.dart';
import '../requests/request_availability.dart';
import '../requests/request_detail_launch.dart';
import 'list_detail_view.dart';
import 'widgets/list_detail_actions.dart';
import 'widgets/list_detail_header.dart';
import 'widgets/list_detail_toolbar.dart';
import 'widgets/list_item_card.dart';
import 'widgets/list_progress.dart';
import 'widgets/list_selection_bar.dart';
import 'widgets/list_target_picker.dart';

/// Une liste et ses titres (ADR-0070). Son propriétaire la modifie et peut y
/// inviter d'autres comptes ; un invité y ajoute et en retire des titres
/// (ADR-0127) ; une liste partagée par un autre compte se lit seulement.
///
/// L'en-tête dit où la liste en est et lance le prochain titre ; les onglets
/// rangent les titres (À voir, Vus, À demander) et la sélection permet d'en
/// déplacer, d'en copier ou d'en retirer plusieurs (ADR-0160).
class ListDetailScreen extends StatefulWidget {
  const ListDetailScreen({super.key, required this.listId, this.initial});

  final int listId;

  /// Le résumé déjà connu, pour peindre l'en-tête avant la réponse.
  final WatchList? initial;

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  WatchListFilter _filter = WatchListFilter.all;
  WatchListSort _sort = WatchListSort.recent;

  /// En sélection : toucher une affiche la coche au lieu de l'ouvrir. Un mode
  /// plutôt qu'un appui long, que la télécommande n'a pas.
  bool _selecting = false;
  final Set<int> _selected = {};

  WatchListsProvider get _provider => context.read<WatchListsProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _provider.loadDetail(widget.listId, silent: true);
    });
  }

  static String _errorText(Object error, String fallback) {
    final data = error is DioException ? error.response?.data : null;
    return data is Map && data['error'] != null
        ? data['error'].toString()
        : fallback;
  }

  void _showError(String message) =>
      showOnyxToast(context, message, error: true);

  void _setSelecting(bool on) => setState(() {
        _selecting = on;
        _selected.clear();
      });

  void _toggle(WatchListItem item) => setState(() {
        if (!_selected.remove(item.id)) _selected.add(item.id);
      });

  Future<void> _open(BuildContext cardContext, WatchListItem item) async {
    final media = item.media;
    if (media != null) {
      await openMediaDetail(cardContext, media.media, item: media);
    } else if (canRequestMedia(context) && item.tmdbId > 0) {
      // Ce que le serveur n'a pas s'ouvre là où on peut le demander.
      await openRequestDetail(cardContext, item.toRequestItem());
    } else {
      showOnyxToast(
          context, tr('« {0} » n’est pas encore sur le serveur', [item.title]),
          error: true);
      return;
    }
    // La fiche a pu retirer ce titre de la liste, ou l'avoir fait avancer.
    if (mounted) _provider.loadDetail(widget.listId, silent: true);
  }

  /// La fiche lance la lecture : le film à sa position, la série à l'épisode
  /// à reprendre (PlayLink, ADR-0091).
  Future<void> _play(int mediaId, WatchListMediaType type) async {
    final navigator = Navigator.of(context);
    final provider = _provider;
    await navigator.push(PlayLink.routeFor(
      type == WatchListMediaType.show ? MediaType.show : MediaType.movie,
      mediaId,
    ));
    provider.loadDetail(widget.listId, silent: true);
  }

  Future<void> _edit(WatchList list) async {
    final draft = await showWatchListEditor(context, existing: list);
    if (draft == null || !mounted) return;
    try {
      await _provider.updateList(list,
          name: draft.name,
          description: draft.description,
          isShared: draft.isShared);
    } catch (e) {
      debugPrint('ListDetailScreen: update failed: $e');
      if (mounted) {
        _showError(_errorText(e, tr('La liste n’a pas pu être modifiée.')));
      }
    }
  }

  Future<void> _leave(WatchList list) async {
    final myId = context.read<AuthProvider>().currentUser?.id;
    if (myId == null) return;
    final navigator = Navigator.of(context);
    try {
      await _provider.leaveList(list.id, myId);
      navigator.pop();
    } catch (e) {
      debugPrint('ListDetailScreen: leave failed: $e');
      if (mounted) {
        _showError(_errorText(e, tr('Vous n’avez pas pu quitter la liste.')));
      }
    }
  }

  Future<void> _delete(WatchList list, List<WatchListMember> members) async {
    final confirmed = await showOnyxDialog<bool>(
      context: context,
      builder: (dialogContext) => OnyxDialog(
        icon: AppIcons.delete,
        destructive: true,
        title: tr('Supprimer « {0} » ?', [list.displayName]),
        message: list.isShared || members.isNotEmpty
            ? tr('La liste disparaîtra aussi pour les comptes avec qui vous '
                'la partagez. Les films et séries restent sur le serveur.')
            : tr('Les films et séries restent sur le serveur.'),
        content: ListDeleteSummary(
          posters: watchListPosterUrls(context, list, max: 3),
          list: list,
          members: members,
        ),
        actions: [
          OnyxDialogAction(
            label: tr('Annuler'),
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          OnyxDialogAction(
            label: tr('Supprimer'),
            primary: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    try {
      await _provider.deleteList(list.id);
      navigator.pop();
    } catch (e) {
      debugPrint('ListDetailScreen: delete failed: $e');
      if (mounted) {
        _showError(_errorText(e, tr('La liste n’a pas pu être supprimée.')));
      }
    }
  }

  /// Retire des titres, puis laisse six secondes pour les remettre : plus de
  /// confirmation qui bloque, un retrait qu'on regrette se défait.
  Future<void> _remove(List<WatchListItem> items) async {
    if (items.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final provider = _provider;
    final listId = widget.listId;
    if (_selecting) _setSelecting(false);
    final result = await provider.removeItems(listId, items);
    if (!mounted) return;
    if (!result.isComplete) {
      _showError(tr('Certains titres n’ont pas pu être retirés.'));
    }
    if (result.done.isEmpty) return;
    showOnyxToastOn(
      messenger,
      result.done.length == 1
          ? tr('« {0} » retiré de la liste', [result.done.first.title])
          : trPlural(
              result.done.length, '{0} titre retiré', '{0} titres retirés'),
      duration: const Duration(seconds: 6),
      actionLabel: tr('Annuler'),
      onAction: () => provider.copyItems(listId, result.done),
    );
  }

  /// Déplace ou copie [items] dans une autre liste, au choix du compte, dans
  /// un menu collé à [anchor] ; « Nouvelle liste… » la crée d'abord.
  Future<void> _transfer(List<WatchListItem> items,
      {required bool move, required BuildContext anchor}) async {
    if (items.isEmpty) return;
    final provider = _provider;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final choice = await showListTargetPicker(
      context,
      anchor: anchor,
      targets: listTargets(provider.overview, except: widget.listId),
    );
    if (choice == null || !mounted) return;
    var target = choice.list;
    if (target == null) {
      final draft = await showWatchListEditor(context);
      if (draft == null || !mounted) return;
      try {
        target = await provider.createList(
            name: draft.name,
            description: draft.description,
            isShared: draft.isShared);
      } catch (e) {
        debugPrint('ListDetailScreen: create target failed: $e');
        if (mounted) {
          _showError(_errorText(
              e, tr('La liste n’a pas pu être créée. Réessayez.')));
        }
        return;
      }
    }
    if (!mounted) return;
    if (_selecting) _setSelecting(false);
    final result = move
        ? await provider.moveItems(widget.listId, target.id, items)
        : await provider.copyItems(target.id, items);
    if (!mounted) return;
    if (!result.isComplete) {
      _showError(move
          ? tr('Certains titres n’ont pas pu être déplacés.')
          : tr('Certains titres n’ont pas pu être copiés.'));
    }
    if (result.done.isEmpty) return;
    final message = move
        ? trPlural(result.done.length, '{0} titre déplacé vers « {1} »',
            '{0} titres déplacés vers « {1} »', [target.displayName])
        : trPlural(result.done.length, '{0} titre copié vers « {1} »',
            '{0} titres copiés vers « {1} »', [target.displayName]);
    final opened = target;
    showOnyxToastOn(
      messenger,
      message,
      actionLabel: tr('Ouvrir'),
      onAction: () => navigator.push(MaterialPageRoute(
        builder: (_) => ListDetailScreen(listId: opened.id, initial: opened),
      )),
    );
  }

  void _onListAction(ListAction action, WatchList list,
      List<WatchListItem> items, List<WatchListMember> members) {
    switch (action) {
      case ListAction.edit:
        _edit(list);
      case ListAction.share:
        // « À regarder plus tard » n'y a que le choix de qui la voit.
        showWatchListMembersSheet(context, list);
      case ListAction.select:
        _setSelecting(true);
      case ListAction.removeWatched:
        _remove([
          for (final i in items)
            if (i.watched) i
        ]);
      case ListAction.leave:
        _leave(list);
      case ListAction.delete:
        _delete(list, members);
    }
  }

  Future<void> _onItemMenu(
      GlobalKey anchor, WatchListItem item, WatchList list) async {
    final provider = _provider;
    final hasOthers =
        listTargets(provider.overview, except: widget.listId).isNotEmpty;
    final pick = await showOnyxMenu<ItemAction>(
      context: context,
      anchorKey: anchor,
      items:
          itemMenuItems(item, canEdit: list.canEdit, hasOtherLists: hasOthers),
    );
    if (pick == null || !mounted) return;
    switch (pick.value) {
      case ItemAction.play:
        await _play(item.mediaId, item.mediaType);
      case ItemAction.details:
        await _open(anchor.currentContext ?? context, item);
      case ItemAction.move:
        await _transfer([item],
            move: true, anchor: anchor.currentContext ?? context);
      case ItemAction.copy:
        await _transfer([item],
            move: false, anchor: anchor.currentContext ?? context);
      case ItemAction.remove:
        await _remove([item]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WatchListsProvider>();
    final detail = provider.detail(widget.listId);
    final list =
        detail?.list ?? provider.summary(widget.listId) ?? widget.initial;
    final items = detail?.items ?? const <WatchListItem>[];
    final shown = arrangeListItems(items, filter: _filter, sort: _sort);
    final padding = AppLayout.pagePadding(context);
    final error = provider.detailError(widget.listId);
    final canEdit = list?.canEdit ?? false;
    final selectedItems = [
      for (final i in items)
        if (_selected.contains(i.id)) i,
    ];
    final hasOthers =
        listTargets(provider.overview, except: widget.listId).isNotEmpty;

    Widget body;
    if (detail == null && error != null) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorStateView(
            message: error, onRetry: () => provider.loadDetail(widget.listId)),
      );
    } else if (detail == null) {
      body =
          const SliverFillRemaining(hasScrollBody: false, child: LoadingView());
    } else if (items.isEmpty) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyStateView(
          icon: AppIcons.addToList,
          title: tr('Cette liste est vide'),
          message: canEdit
              ? tr('Ajoutez un film ou une série depuis sa fiche, avec le '
                  'signet. Les titres du catalogue des demandes aussi.')
              : tr('Son propriétaire n’y a encore rien mis.'),
        ),
      );
    } else if (shown.isEmpty) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyStateView(
          icon: AppIcons.filter,
          title: tr('Aucun titre ici'),
          message: tr('Aucun titre de cette liste ne correspond à cet onglet.'),
        ),
      );
    } else {
      body = SliverMainAxisGroup(slivers: [
        const SliverPosterGridDisplayBar(),
        SliverPadding(
          // En sélection, la barre flotte au bas : la dernière rangée
          // d'affiches doit pouvoir remonter au-dessus d'elle.
          padding:
              EdgeInsets.fromLTRB(padding, 8, padding, _selecting ? 140 : 48),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) => SliverGrid(
              gridDelegate: AppLayout.posterGridDelegate(
                context,
                constraints.crossAxisExtent,
                compact: AppLayout.isCompact(context),
                withMeta: false,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = shown[index];
                  return ListItemCard(
                    key: ValueKey(item.id),
                    item: item,
                    selecting: _selecting,
                    selected: _selected.contains(item.id),
                    autofocus: TvMode.isTv && index == 0,
                    onTap: (cardContext) =>
                        _selecting ? _toggle(item) : _open(cardContext, item),
                    onMenu: (anchor) => _onItemMenu(anchor, item, list!),
                  );
                },
                childCount: shown.length,
              ),
            ),
          ),
        ),
      ]);
    }

    final members = detail?.members ?? const <WatchListMember>[];
    final posters = list == null
        ? const <String?>[]
        : watchListPosterUrls(context, list, max: 4);
    final header = SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(padding - 8, 4, padding, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OverlayBackButton(),
            if (list != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 8),
                child: ListDetailHeader(
                  list: list,
                  members: members,
                  posters: posters,
                  menuItems: listMenuItems(
                    list,
                    canInvite: provider.supportsMembers,
                    hasItems: items.isNotEmpty,
                    watchedCount: items.where((i) => i.watched).length,
                  ),
                  onMenu: (a) => _onListAction(a, list, items, members),
                  onPlayNext: list.nextItem == null
                      ? null
                      : () => _play(
                          list.nextItem!.mediaId, list.nextItem!.mediaType),
                  onShare: list.isMine &&
                          (list.isWatchLater || provider.supportsMembers)
                      ? (anchor) => showWatchListMembersSheet(context, list,
                          anchor: anchor)
                      : null,
                ),
              ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ListDetailToolbar(
                  filter: _filter,
                  counts: countListItems(items),
                  sort: _sort,
                  onFilter: (f) => setState(() => _filter = f),
                  onSort: (s) => setState(() => _sort = s),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return TvBackStep(
      // Retour pendant une sélection : on la quitte au lieu de fermer la liste
      // (ADR-0110 : TvBack est seul à décider du Retour).
      onBack: () {
        if (!_selecting) return false;
        _setSelecting(false);
        return true;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            PosterGridZoomRegion(
              child: CustomScrollView(
                scrollCacheExtent: AppLayout.imageCacheExtent(context),
                slivers: [
                  SliverToBoxAdapter(
                    // La lueur couvre l'en-tête et les onglets, pas plus : elle
                    // finit de se fondre au bas du bloc, sans laisser de bord
                    // au-dessus de la grille.
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ListHeaderGlow(
                              url: posters.isEmpty ? null : posters.first),
                        ),
                        header,
                      ],
                    ),
                  ),
                  body,
                ],
              ),
            ),
            if (_selecting)
              Positioned(
                left: padding,
                right: padding,
                bottom: 20 + MediaQuery.paddingOf(context).bottom,
                child: Center(
                  child: ListSelectionBar(
                    count: selectedItems.length,
                    total: shown.length,
                    canMoveOrCopy: hasOthers,
                    onClose: () => _setSelecting(false),
                    onSelectAll: () => setState(
                        () => _selected.addAll(shown.map((i) => i.id))),
                    onMove: (anchor) =>
                        _transfer(selectedItems, move: true, anchor: anchor),
                    onCopy: (anchor) =>
                        _transfer(selectedItems, move: false, anchor: anchor),
                    onRemove: () => _remove(selectedItems),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ce que la suppression emporte, sous la question : la liste par ses
/// affiches, son nombre de titres, et qui en perd l'accès (ADR-0161).
class ListDeleteSummary extends StatelessWidget {
  const ListDeleteSummary({
    super.key,
    required this.posters,
    required this.list,
    required this.members,
  });

  final List<String?> posters;
  final WatchList list;
  final List<WatchListMember> members;

  @override
  Widget build(BuildContext context) {
    final names = [for (final m in members) m.username];
    final count = list.itemCount == 1
        ? tr('1 titre')
        : tr('{0} titres', [list.itemCount]);
    final who = names.isEmpty
        ? null
        : names.length == 1
            ? tr('{0} perdra l’accès', [names.first])
            : tr('{0} personnes perdront l’accès', [names.length]);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          WatchListPosterFan(urls: posters, posterWidth: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(count,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
                if (who != null) ...[
                  const SizedBox(height: 4),
                  Text(who,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
