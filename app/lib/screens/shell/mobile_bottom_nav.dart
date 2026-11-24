import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../widgets/global/liquid_glass.dart';
import '../../widgets/global/interface_tour/tour_anchor.dart';
import '../../theme/app_type.dart';
import '../../l10n/tr.dart';
import '../library/library_screen.dart';
import 'phone_more_menu.dart';
import 'phone_search.dart';
import 'shell_tabs.dart';

/// La barre d'onglets du téléphone (ADR-0142) : une capsule de verre qui
/// flotte en bas de l'écran, le verre de la pilule de l'Apple TV posé où le
/// pouce l'attend, et à côté d'elle un rond de verre pour la recherche.
///
/// - **au repos**, l'icône et le nom de chaque onglet, une lentille de verre
///   clair sous celui qui est affiché ;
/// - **la page défile vers le bas** ([minimized]), la capsule se réduit à
///   l'onglet affiché et la recherche reste ; elle revient en entier au
///   premier geste vers le haut ;
/// - **un onglet est touché**, la lentille glisse jusqu'à lui ;
/// - **Listes et Hors ligne** se rangent derrière un onglet « Plus » quand
///   les deux existent (ADR-0146) : il ouvre un petit menu de verre, et sur
///   l'une des deux pages il passe directement à l'autre ;
/// - **la recherche s'ouvre** ([search]), le rond s'étire sur toute la
///   largeur et devient le champ, pendant que les onglets s'effacent dessous ;
///   le clavier monte ensuite et le champ monte avec lui. Elle se referme à
///   l'envers : le clavier descend, puis la bulle redevient un rond. Une fiche
///   ouverte depuis les résultats rend la capsule de la même façon ;
/// - **un autre champ ouvre le clavier**, la barre lui laisse la place
///   (ADR-0141).
///
/// Elle remplace la barre pleine largeur, en verre sombre et dense, qui
/// prenait 90 points au bas de chaque écran.
class MobileBottomNav extends StatefulWidget {
  /// L'identifiant de l'onglet affiché (voir [ShellTabs]).
  final String selected;
  final ValueChanged<String> onTabSelected;

  /// Les bibliothèques du serveur (ADR-0058).
  final List<MediaLibrary> libraries;

  final bool canRequestMedia;
  final bool canDownload;

  /// Le serveur tient des listes (ADR-0070).
  final bool canUseLists;

  /// La recherche du téléphone. Null : pas de rond de recherche.
  final PhoneSearchSession? search;

  /// La page défile vers le bas : la capsule se réduit à l'onglet affiché.
  final bool minimized;

  /// La capsule réduite est touchée : elle demande à revenir en entier.
  final VoidCallback? onExpand;

  /// Au-delà, les bibliothèques ne tiennent plus côte à côte entre l'accueil
  /// et les deux derniers onglets : un seul onglet les réunit et ouvre leur
  /// liste.
  static const int maxInlineLibraries = 2;

  /// La hauteur de la capsule et du rond : « B bis », la version compacte
  /// que l'utilisateur a choisie (62 sur la première maquette).
  static const double height = 52;

  /// La marge des côtés de l'écran, et l'écart entre la capsule et le rond.
  static const double side = 16;
  static const double gap = 8;

  /// Ce qui sépare la barre du bas de l'écran : un peu moins que la zone de
  /// l'indicateur d'accueil d'iOS ou de la poignée des gestes d'Android,
  /// qu'elle chevauche comme la barre d'iOS, et jamais moins de 12. Au-dessus
  /// des trois boutons de navigation d'Android, plus hauts, elle se pose
  /// au-dessus d'eux : le bas de la capsule serait sous leurs touches.
  static double bottomFor(EdgeInsets padding) {
    final inset = padding.bottom;
    if (inset > _gestureInset) return inset + 8;
    return math.max(inset - 14, 12);
  }

  /// La plus haute zone de gestes : l'indicateur d'accueil d'un iPhone.
  static const double _gestureInset = 34;

  /// La place que les pages laissent libre sous leur contenu pour que la
  /// barre ne le cache pas : sa hauteur, son écart au bas de l'écran, et un
  /// peu d'air. Rien quand un autre champ a le clavier : la barre s'efface.
  static double reserveFor(
    EdgeInsets padding, {
    required bool keyboardOpen,
    required bool searching,
  }) {
    if (keyboardOpen && !searching) return 0;
    return bottomFor(padding) + height + 12;
  }

  const MobileBottomNav({
    super.key,
    required this.selected,
    required this.onTabSelected,
    required this.libraries,
    required this.canRequestMedia,
    required this.canDownload,
    this.canUseLists = false,
    this.search,
    this.minimized = false,
    this.onExpand,
  });

  @override
  State<MobileBottomNav> createState() => _MobileBottomNavState();
}

class _MobileBottomNavState extends State<MobileBottomNav>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 0 : la capsule et le rond ; 1 : la bulle de recherche sur toute la
  /// largeur.
  late final AnimationController _searchOpening = AnimationController(
    vsync: this,
    duration: PhoneSearchSession.expand,
    value: widget.search?.isExpanded ?? false ? 1 : 0,
  )..addStatusListener(_onSearchStatus);

  bool _keyboardOpen = false;

  /// Le menu de l'onglet « Plus » est ouvert : la lentille est sur lui.
  bool _moreOpen = false;

  /// La capsule et le rond de la recherche, que le voile du menu épargne.
  final GlobalKey _capsuleKey = GlobalKey();
  final GlobalKey _roundKey = GlobalKey();

  /// Le rond vient d'être touché : le champ prend la main quand la bulle a
  /// pris toute la largeur. Pas au retour d'une fiche vers les résultats : le
  /// clavier les cacherait.
  bool _focusOnExpand = false;

  /// La bulle attend que le clavier soit descendu pour redevenir un rond.
  bool _collapsePending = false;
  Timer? _collapseFallback;

  /// Assez pour que le clavier d'iOS ou d'Android soit descendu. Un clavier
  /// qui ne dit pas qu'il est parti ne retient pas la bulle au-delà.
  static const Duration _keyboardWait = Duration(milliseconds: 450);

  /// La bulle est déployée : les résultats sont au premier plan.
  bool get _searching => widget.search?.isExpanded ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.search?.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(MobileBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search) {
      oldWidget.search?.removeListener(_onSearchChanged);
      widget.search?.addListener(_onSearchChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardOpen = _readKeyboard();
  }

  /// Le clavier se lit sur la vue et non dans le [MediaQuery] : le [Scaffold]
  /// de la coquille en retire l'encart pour tout ce qu'il contient.
  bool _readKeyboard() => View.of(context).viewInsets.bottom > 0;

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final open = _readKeyboard();
    if (open == _keyboardOpen) return;
    setState(() => _keyboardOpen = open);
    if (!open && _collapsePending) _collapse();
  }

  Duration? get _duration => AppMotion.reduced(context) ? Duration.zero : null;

  void _onSearchChanged() {
    if (!mounted) return;
    if (_searching) {
      _cancelCollapse();
      _searchOpening.animateTo(1,
          duration: _duration, curve: Curves.easeOutCubic);
    } else if (!_searchOpening.isDismissed && !_collapsePending) {
      // L'ouverture à l'envers : le clavier descend d'abord, la bulle posée
      // sur lui, puis elle redevient un rond et les onglets reviennent.
      if (_keyboardOpen) {
        _collapsePending = true;
        _collapseFallback = Timer(_keyboardWait, _collapse);
      } else {
        _collapse();
      }
    }
    setState(() {});
  }

  void _collapse() {
    _cancelCollapse();
    if (!mounted || _searching) return;
    _searchOpening.animateBack(0,
        duration: _duration, curve: Curves.easeOutCubic);
  }

  void _cancelCollapse() {
    _collapsePending = false;
    _collapseFallback?.cancel();
    _collapseFallback = null;
  }

  void _onSearchStatus(AnimationStatus status) {
    // Redevenue un rond : la barre peut de nouveau céder sa place au clavier
    // d'un autre champ.
    if (status == AnimationStatus.dismissed) {
      if (mounted) setState(() {});
      return;
    }
    // La bulle a pris toute la largeur : le champ prend la main, et le
    // clavier monte.
    if (status != AnimationStatus.completed || !_searching) return;
    if (!_focusOnExpand) return;
    _focusOnExpand = false;
    widget.search?.focusNode.requestFocus();
  }

  @override
  void dispose() {
    widget.search?.removeListener(_onSearchChanged);
    WidgetsBinding.instance.removeObserver(this);
    _cancelCollapse();
    _searchOpening.dispose();
    super.dispose();
  }

  Future<void> _pickLibrary(BuildContext context) async {
    final picked = await showModalBottomSheet<MediaLibrary>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final library in widget.libraries)
              ListTile(
                leading: Icon(
                  libraryIcon(library.kind,
                      selected: widget.selected == ShellTabs.library(library)),
                  color: AppColors.textPrimary,
                ),
                title: Text(ShellTabs.label(library)),
                trailing: widget.selected == ShellTabs.library(library)
                    ? const Icon(AppIcons.check, color: AppColors.textPrimary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(library),
              ),
          ],
        ),
      ),
    );
    if (picked != null) widget.onTabSelected(ShellTabs.library(picked));
  }

  @override
  Widget build(BuildContext context) {
    // Un autre champ a ouvert le clavier : la barre lui laisse la place, et
    // ne se posait plus sur lui (ADR-0141). Le champ de la recherche, lui, est
    // dans la barre : il monte avec le clavier, et elle le garde le temps de
    // redevenir un rond.
    final bubble =
        _searching || _collapsePending || !_searchOpening.isDismissed;
    if (_keyboardOpen && !bubble) return const SizedBox.shrink();
    final bottom = MobileBottomNav.bottomFor(MediaQuery.paddingOf(context));
    return Padding(
      padding: EdgeInsets.fromLTRB(
        MobileBottomNav.side,
        0,
        MobileBottomNav.side,
        bottom,
      ),
      child: SizedBox(
        height: MobileBottomNav.height,
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: _searchOpening,
            builder: (context, _) =>
                _buildBar(context, constraints.maxWidth, _searchOpening.value),
          ),
        ),
      ),
    );
  }

  Widget _buildBar(BuildContext context, double width, double opening) {
    final search = widget.search;
    const round = MobileBottomNav.height;
    final capsuleWidth = search == null
        ? width
        : width - round - MobileBottomNav.gap;
    final minimized = widget.minimized && !_searching;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Les onglets se resserrent et s'effacent sous la bulle qui s'étire.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: opening > 0,
            child: Opacity(
              opacity: (1 - opening * 1.6).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1 - 0.1 * opening,
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  key: _capsuleKey,
                  duration: AppMotion.move(context, AppMotion.emphasis),
                  curve: AppMotion.curve,
                  width: minimized ? round : capsuleWidth,
                  child: _GlassPill(
                    child: AnimatedSwitcher(
                      duration: AppMotion.fade(context),
                      child: minimized
                          ? _buildMinimized()
                          : _buildTabs(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (search != null)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: lerpDouble(round, width, opening),
            child: TourTarget(
              key: _roundKey,
              anchor: TourAnchor.search,
              child: _GlassPill(
                child: opening < 0.5
                    ? _buildSearchRound(search)
                    : Opacity(
                        opacity: ((opening - 0.5) * 2).clamp(0.0, 1.0),
                        child: PhoneSearchField(session: search),
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchRound(PhoneSearchSession search) {
    return Semantics(
      button: true,
      label: tr('Rechercher'),
      child: GestureDetector(
        key: const ValueKey('phone-search-round'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _focusOnExpand = true;
          search.open(reduced: AppMotion.reduced(context));
        },
        child: const Center(
          child: Icon(
            AppIcons.search,
            size: 21,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// La capsule réduite : l'onglet affiché seul, dans sa lentille. La toucher
  /// rend la barre entière.
  Widget _buildMinimized() {
    final tab = _tabs().firstWhere(
      (t) => t.selected,
      orElse: () => _tabs().first,
    );
    return Semantics(
      key: const ValueKey('phone-tab-bar-minimized'),
      button: true,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onExpand,
        child: Padding(
          padding: const EdgeInsets.all(_GlassPill.inset),
          child: _Lens(
            child: Center(
              child: Icon(
                tab.selectedIcon,
                size: 21,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    return Padding(
      key: const ValueKey('phone-tab-bar-tabs'),
      padding: const EdgeInsets.all(_GlassPill.inset),
      child: _TabRow(tabs: _tabs()),
    );
  }

  List<_Tab> _tabs() {
    final selected = widget.selected;
    final libraries = widget.libraries;
    final inline = libraries.length <= MobileBottomNav.maxInlineLibraries;
    return [
      _Tab(
        icon: AppIcons.home,
        selectedIcon: AppIcons.homeSelected,
        label: tr('Accueil'),
        selected: selected == ShellTabs.home,
        onTap: () => widget.onTabSelected(ShellTabs.home),
        // L'accueil porte l'ancre des bibliothèques quand elles sont réunies
        // ailleurs ; sinon c'est la première bibliothèque.
        anchor: libraries.isEmpty ? TourAnchor.library : null,
      ),
      if (inline)
        for (final (index, library) in libraries.indexed)
          _Tab(
            icon: libraryIcon(library.kind),
            selectedIcon: libraryIcon(library.kind, selected: true),
            label: ShellTabs.label(library),
            selected: selected == ShellTabs.library(library),
            onTap: () => widget.onTabSelected(ShellTabs.library(library)),
            anchor: index == 0 ? TourAnchor.library : null,
          )
      else
        _Tab(
          icon: AppIcons.collection,
          selectedIcon: AppIcons.collection,
          label: tr('Bibliothèques'),
          selected: ShellTabs.isLibrary(selected),
          onTap: () => _pickLibrary(context),
          anchor: TourAnchor.library,
        ),
      if (widget.canRequestMedia)
        _Tab(
          icon: AppIcons.request,
          selectedIcon: AppIcons.requestSelected,
          label: tr('Demandes'),
          selected: selected == ShellTabs.requests,
          onTap: () => widget.onTabSelected(ShellTabs.requests),
          anchor: TourAnchor.requests,
        ),
      ..._overflowTabs(),
    ];
  }

  /// Les pages qui se rangent derrière « Plus » quand il y en a au moins
  /// deux (ADR-0146).
  List<PhoneMoreItem> _overflow() => [
        if (widget.canUseLists)
          PhoneMoreItem(
            tab: ShellTabs.lists,
            icon: AppIcons.lists,
            selectedIcon: AppIcons.listsSelected,
            label: tr('Listes'),
          ),
        if (widget.canDownload)
          PhoneMoreItem(
            tab: ShellTabs.downloads,
            icon: AppIcons.offline,
            selectedIcon: AppIcons.offlineSelected,
            label: tr('Hors ligne'),
            anchor: TourAnchor.downloads,
          ),
      ];

  /// Une seule page : un onglet à elle, comme avant. Deux ou plus : l'onglet
  /// « Plus », qui prend l'icône et le nom de celle qui est affichée.
  List<_Tab> _overflowTabs() {
    final items = _overflow();
    if (items.length < 2) {
      return [
        for (final item in items)
          _Tab(
            icon: item.icon,
            selectedIcon: item.selectedIcon,
            label: item.label,
            selected: widget.selected == item.tab,
            onTap: () => widget.onTabSelected(item.tab),
            anchor: item.anchor,
          ),
      ];
    }
    PhoneMoreItem? current;
    for (final item in items) {
      if (item.tab == widget.selected) current = item;
    }
    TourAnchor? anchor;
    for (final item in items) {
      anchor ??= item.anchor;
    }
    return [
      _Tab(
        icon: current?.icon ?? AppIcons.more,
        selectedIcon: current?.selectedIcon ?? AppIcons.more,
        label: current?.label ?? tr('Plus'),
        selected: current != null || _moreOpen,
        onTap: () => _onMore(items, current),
        anchor: anchor,
      ),
    ];
  }

  /// L'onglet « Plus » est touché. Sur l'une de ses deux pages, il passe à
  /// l'autre : un menu pour un seul choix serait un geste de trop. Sinon, il
  /// ouvre son menu.
  Future<void> _onMore(List<PhoneMoreItem> items, PhoneMoreItem? current) async {
    if (current != null && items.length == 2) {
      widget.onTabSelected(items.firstWhere((i) => i.tab != current.tab).tab);
      return;
    }
    final capsule = _rectOf(_capsuleKey);
    if (capsule == null || _moreOpen) return;
    final round = _rectOf(_roundKey);
    setState(() => _moreOpen = true);
    final picked = await showPhoneMoreMenu(
      context,
      capsule: capsule,
      clear: [capsule, if (round != null) round],
      items: items,
      selected: widget.selected,
    );
    if (!mounted) return;
    setState(() => _moreOpen = false);
    if (picked != null) widget.onTabSelected(picked);
  }

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// Un onglet de la capsule.
class _Tab {
  const _Tab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.anchor,
  });

  final IconData icon;

  /// Plein quand l'onglet est affiché, creux sinon : la sélection se lit à la
  /// forme autant qu'à la lentille.
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// L'ancre de la visite guidée qu'il porte, s'il en porte une.
  final TourAnchor? anchor;
}

/// Les onglets de la capsule, et la lentille qui glisse de l'un à l'autre.
///
/// La lentille ne saute pas : ses deux bords partent ensemble, celui de devant
/// plus vif, si bien qu'elle s'étire en chemin et se resserre en se posant,
/// comme une goutte de verre. Touchée à nouveau en route, elle repart d'où
/// elle est. Sous « réduire les animations », elle se pose d'un coup.
class _TabRow extends StatefulWidget {
  const _TabRow({required this.tabs});

  final List<_Tab> tabs;

  @override
  State<_TabRow> createState() => _TabRowState();
}

class _TabRowState extends State<_TabRow> with SingleTickerProviderStateMixin {
  late final AnimationController _slide =
      AnimationController(vsync: this, value: 1);

  /// Les bords de la lentille, comptés en onglets : de [_from] vers [_to].
  (double, double) _from = (0, 1);
  (double, double) _to = (0, 1);

  int get _selected => widget.tabs.indexWhere((t) => t.selected);

  @override
  void initState() {
    super.initState();
    final i = _selected;
    if (i >= 0) _from = _to = (i.toDouble(), i + 1.0);
  }

  @override
  void didUpdateWidget(_TabRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final i = _selected;
    if (i < 0) return;
    final target = (i.toDouble(), i + 1.0);
    if (target == _to) return;
    _from = _edges(_slide.value);
    _to = target;
    _slide.duration = AppMotion.move(context, AppMotion.emphasis);
    _slide.forward(from: 0);
  }

  /// Les bords à l'instant [t] : celui qui mène suit une courbe plus vive,
  /// l'autre le rattrape.
  (double, double) _edges(double t) {
    final lead = Curves.easeOutCubic.transform(t);
    final follow = Curves.easeInOutCubic.transform(t);
    final rightward = _to.$1 >= _from.$1;
    return (
      lerpDouble(_from.$1, _to.$1, rightward ? follow : lead)!,
      lerpDouble(_from.$2, _to.$2, rightward ? lead : follow)!,
    );
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final hasLens = _selected >= 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final unit = constraints.maxWidth / tabs.length;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (hasLens)
              AnimatedBuilder(
                animation: _slide,
                builder: (context, _) {
                  final (left, right) = _edges(_slide.value);
                  return Positioned(
                    key: const ValueKey('phone-tab-lens'),
                    left: left * unit,
                    width: (right - left) * unit,
                    top: 0,
                    bottom: 0,
                    child: const _Lens(),
                  );
                },
              ),
            Row(
              children: [
                for (final tab in tabs)
                  Expanded(
                    child: tab.anchor == null
                        ? _BottomNavItem(tab: tab)
                        : TourTarget(
                            anchor: tab.anchor!,
                            child: _BottomNavItem(tab: tab),
                          ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Le verre de la capsule et du rond : le verre liquide du téléphone
/// ([LiquidGlass]), partagé avec la barre du haut.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child});

  final Widget child;

  /// Le retrait des onglets dans la capsule.
  static const double inset = 3;

  @override
  Widget build(BuildContext context) => LiquidGlass(child: child);
}

/// La lentille de verre clair sous l'onglet affiché.
class _Lens extends StatelessWidget {
  const _Lens({this.child = const SizedBox.expand()});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.17),
        borderRadius: const BorderRadius.all(Radius.circular(23)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: child,
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({required this.tab});

  final _Tab tab;

  @override
  Widget build(BuildContext context) {
    final selected = tab.selected;
    // Blanc et non bleu : l'accent est réservé au focus et à la progression,
    // et cinq onglets en bas d'écran ne sont ni l'un ni l'autre.
    final ink = selected
        ? AppColors.textPrimary
        : AppColors.textPrimary.withValues(alpha: 0.78);
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(selected ? tab.selectedIcon : tab.icon, color: ink, size: 19),
        const SizedBox(height: 1),
        // Le nom d'une bibliothèque est libre : au-delà de la largeur de
        // l'onglet il se coupe, il ne déborde pas sur le voisin.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Text(
            tab.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ink,
              fontSize: AppType.micro,
              // Resserré : « Demandes » et « Hors ligne » tiennent dans un
              // cinquième de capsule.
              letterSpacing: -0.2,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tab.onTap,
        child: content,
      ),
    );
  }
}
