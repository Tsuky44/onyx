import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../models/media_request.dart';
import '../../../models/watch_list.dart';
import '../../../theme/app_icons.dart';
import '../../../tv/nav/tv_entry_focus.dart';
import '../../../tv/tv_focus_caption.dart';
import '../../../tv/tv_mode.dart';
import '../../../utils/long_date.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/add_to_list_button.dart';
import '../../../widgets/global/detail_actions.dart';
import '../../../widgets/global/detail_hero.dart';

/// La rangée d'actions de la fiche d'une demande : le statut ou « Demander »,
/// la bande-annonce et les listes — le pendant de [DetailActions] pour un
/// titre que la bibliothèque n'a pas encore.
///
/// Sur un téléviseur, la télécommande arrive sur la première action, comme
/// sur « Lecture » d'une fiche de la bibliothèque. Sans ça, le focus tombait
/// sur le bouton retour, et Bas depuis lui sautait toute la rangée : les
/// saisons, pleine largeur, sont dans son faisceau, « Demander » non.
///
/// La rangée rend ce focus elle-même, une fois montée ([TvEntryFocus]). Un
/// `autofocus` ne suffit pas ici : la fiche attend le réseau, et la route a
/// déjà son focus, sur le bouton retour, quand les actions arrivent.
class RequestDetailActions extends StatefulWidget {
  const RequestDetailActions({
    super.key,
    required this.details,
    required this.listTitle,
    required this.onRequest,
    required this.onComplete,
    required this.onPlay,
    required this.onTrailer,
    this.submitting = false,
    this.launching = false,
  });

  final RequestMediaDetails details;

  /// Le titre tel que les listes le rangent (ADR-0070).
  final ListableTitle listTitle;

  /// « Demander » : le titre entier.
  final VoidCallback onRequest;

  /// « Compléter » : les saisons pas encore demandées.
  final VoidCallback onComplete;

  /// « Lire » : le titre est déjà, au moins en partie, dans la bibliothèque.
  final VoidCallback onPlay;

  final VoidCallback onTrailer;

  /// Une demande part : la pastille le dit. Elle garde son action, que
  /// l'écran ignore le temps de l'envoi — une pastille sans action perd le
  /// focus, et la télécommande se retrouvait ailleurs sur la page.
  final bool submitting;

  /// La fiche de lecture se cherche dans la bibliothèque.
  final bool launching;

  @override
  State<RequestDetailActions> createState() => _RequestDetailActionsState();
}

class _RequestDetailActionsState extends State<RequestDetailActions> {
  final FocusNode _entry = FocusNode(debugLabel: 'request-entry');

  RequestMediaDetails get details => widget.details;

  @override
  void initState() {
    super.initState();
    TvEntryFocus.claim(_entry);
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final trailer = details.trailerKey;
    final hasTrailer = trailer != null && trailer.isNotEmpty;
    final primary = _primary();
    // Une seule entrée : la première action de la rangée. Un statut seul
    // (« En cours de traitement ») n'en est pas une, la bande-annonce prend
    // alors le relais.
    final entersOnTrailer = primary.every((p) => !p.isAction);
    return TvFocusCaption(
      child: Wrap(
        spacing: compact ? 8 : 14,
        runSpacing: compact ? 8 : 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final pill in primary) pill.widget,
          if (hasTrailer)
            HeroPill(
              label: tr('Bande-annonce'),
              icon: AppIcons.playCircle,
              style: HeroPillStyle.trailer,
              iconOnlyWhenCompact: true,
              focusNode: entersOnTrailer ? _entry : null,
              autofocus: entersOnTrailer && TvMode.isTv,
              onPressed: widget.onTrailer,
            ),
          // Un titre que le serveur n'a pas peut déjà aller dans « À
          // regarder plus tard » (ADR-0070).
          IconButtonTheme(
            data: IconButtonThemeData(
                style: heroRoundButtonStyle(
                    context, DetailActions.secondaryStyle)),
            child: AddToListButton(title: widget.listTitle),
          ),
        ],
      ),
    );
  }

  /// Les pastilles de statut d'OnyxHub (`RequestStatusButton`).
  List<({Widget widget, bool isAction})> _primary() {
    final status = details.status;
    final offer = details.offer;
    var entered = false;

    // La première pastille qui agit reçoit la télécommande.
    FocusNode? entry() {
      if (entered) return null;
      entered = true;
      return _entry;
    }

    // `autofocus` en plus du focus rendu par [initState] : il marque l'entrée
    // de la rangée (`TvSections`), et sous dpad c'est lui que la restauration
    // de focus respecte.
    bool isEntry(FocusNode? node) => node != null && TvMode.isTv;

    // Disponible, même en partie : le bouton lance le média. Le statut se
    // lit dans le surtitre au-dessus du titre (RequestAvailabilityBadge).
    ({Widget widget, bool isAction}) play() {
      final node = entry();
      return (
        widget: HeroPill(
          label: tr('Lire'),
          icon: AppIcons.play,
          style: HeroPillStyle.glass,
          loading: widget.launching,
          focusNode: node,
          autofocus: isEntry(node),
          onPressed: widget.onPlay,
        ),
        isAction: true,
      );
    }

    ({Widget widget, bool isAction}) request(
        String label, VoidCallback onPressed) {
      final node = entry();
      return (
        widget: HeroPill(
          label: widget.submitting ? tr('Envoi de la demande') : label,
          icon: AppIcons.download,
          style: HeroPillStyle.glass,
          loading: widget.submitting,
          focusNode: node,
          autofocus: isEntry(node),
          onPressed: onPressed,
        ),
        isAction: true,
      );
    }

    ({Widget widget, bool isAction}) state(Widget pill) =>
        (widget: pill, isAction: false);

    final canComplete = offer == RequestOffer.complete;

    if (status == RequestMediaStatus.partial ||
        status == RequestMediaStatus.available) {
      return [
        play(),
        if (canComplete) request(tr('Compléter'), widget.onComplete),
      ];
    }

    if (status == RequestMediaStatus.pending ||
        status == RequestMediaStatus.processing) {
      final release = DateTime.tryParse(details.releaseDate ?? '');
      return [
        state(details.isAwaitingRelease()
            ? HeroPill(
                label: release == null
                    ? tr('En attente de sortie')
                    : tr('Sortie le {0}', [formatLongDate(release)]),
                icon: AppIcons.calendar,
                style: HeroPillStyle.status,
              )
            : HeroPill(
                label: tr('En cours de traitement'),
                style: HeroPillStyle.status,
                track: true,
              )),
        if (canComplete) request(tr('Compléter'), widget.onComplete),
      ];
    }

    // Une série à moitié demandée sans statut global : elle se complète.
    if (canComplete) return [request(tr('Compléter'), widget.onComplete)];
    if (offer != RequestOffer.request) return const [];
    return [request(tr('Demander'), widget.onRequest)];
  }
}
