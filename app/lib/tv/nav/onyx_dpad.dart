import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/lite_mode.dart';
import '../../utils/app_platform.dart';
import '../tv_mode.dart';
import 'tv_back.dart';
import 'tv_dpad_focusable.dart';
import 'tv_foreground_route.dart';
import 'tv_nav_theme.dart';

/// Le seul `Dpad` de l'app (ADR-0110).
///
/// Il se pose dans `MaterialApp.builder`, au-dessus du navigateur : chaque
/// route, chaque dialogue et chaque feuille passe par lui. Il est **toujours
/// monté**, sur téléviseur comme ailleurs, et ne change que de configuration
/// quand [TvMode.enabled] bascule : retirer ou insérer un widget à cette
/// hauteur reparenterait l'app entière et lui ferait perdre son état.
///
/// Ce qu'il ajoute à dpad, et pourquoi :
///
/// - **hors téléviseur, un jeu de touches vide et `restoreFocus: false`**,
///   jamais `enabled: false`. Un dpad désactivé garde ses raccourcis et avale
///   les flèches (constat C3) : le bureau perdrait ses flèches et le téléphone
///   afficherait un focus que personne n'a demandé ;
/// - **pas de `goBack` sur Android** : Android envoie le Retour de la
///   télécommande en touche *et* en `popRoute`, même quand la touche a été
///   traitée. Avec le jeu par défaut, un appui défaisait deux couches
///   (constat C2). Le Retour passe par [TvBack] ;
/// - **le focus revient dans la route affichée à chaque reprise** (constat
///   C14, N1 du rapport de phase 0). dpad rend le focus au dernier élément
///   encore monté sans vérifier que sa route est au premier plan ; une route
///   poussée pendant la pause gardait le focus sous elle. Parade à retirer
///   quand la correction amont sera dans la version épinglée ;
/// - **une mémoire de zone par profil** : la mémoire persistante de dpad est
///   une table statique pour toute l'app (constat C7). [profileKey] préfixe
///   les clés des `TvRegion`, et la table se vide quand il change (changement
///   de profil, déconnexion).
class OnyxDpad extends StatefulWidget {
  const OnyxDpad({
    super.key,
    required this.child,
    this.profileKey,
    this.onBlockedMove,
  });

  final Widget child;

  /// Qui navigue : le serveur et le profil ouverts, sous une forme stable
  /// (`"<serveur>:<profil>"`). Nul avant la connexion.
  final String? profileKey;

  /// Une flèche qui n'a mené nulle part : bord d'une zone, rien dans cette
  /// direction. Le retour sonore ou haptique éventuel se branche ici.
  final ValueChanged<TraversalDirection>? onBlockedMove;

  /// Remplace [AppPlatform.isAndroid] dans les tests, qui tournent sur l'hôte.
  @visibleForTesting
  static bool? debugIsAndroidOverride;

  static bool get _isAndroid => debugIsAndroidOverride ?? AppPlatform.isAndroid;

  /// Un jeu où aucune touche n'a de sens pour dpad : hors téléviseur, les
  /// flèches, Tab et Entrée gardent le sens que leur donne Flutter.
  static const DpadKeySet inertKeySet = DpadKeySet(
    up: <LogicalKeyboardKey>[],
    down: <LogicalKeyboardKey>[],
    left: <LogicalKeyboardKey>[],
    right: <LogicalKeyboardKey>[],
    select: <LogicalKeyboardKey>[],
    back: <LogicalKeyboardKey>[],
    menu: <LogicalKeyboardKey>[],
  );

  /// Retour d'un téléviseur qui n'est pas Android : Échap d'un clavier, B
  /// d'une manette, la touche Retour d'un navigateur (téléviseur LG,
  /// ADR-0076).
  static const List<LogicalKeyboardKey> _back = <LogicalKeyboardKey>[
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.browserBack,
    LogicalKeyboardKey.gameButtonB,
  ];

  /// Le menu d'une carte : la touche menu, ou Y d'une manette, comme
  /// l'ancien `TvFocusable`.
  static const List<LogicalKeyboardKey> _menu = <LogicalKeyboardKey>[
    LogicalKeyboardKey.contextMenu,
    LogicalKeyboardKey.gameButtonY,
  ];

  /// Le jeu de touches de dpad selon l'appareil.
  static DpadKeySet keySetFor({required bool isTv, required bool isAndroid}) {
    if (!isTv) return inertKeySet;
    return DpadKeySet(
      back: isAndroid
          ? _back.where((key) => key != LogicalKeyboardKey.goBack).toList()
          : _back,
      menu: _menu,
    );
  }

  /// La clé de mémoire d'une zone, rangée sous le profil qui navigue.
  ///
  /// Avant la connexion, la zone est rangée sous `"-"` : elle se souvient
  /// encore, mais ce qu'elle retient part à la connexion.
  static String memoryKeyFor(BuildContext context, String id) {
    final profile =
        context.getInheritedWidgetOfExactType<TvNavScope>()?.profileKey;
    return '${profile ?? '-'}/$id';
  }

  @override
  State<OnyxDpad> createState() => _OnyxDpadState();
}

class _OnyxDpadState extends State<OnyxDpad> with WidgetsBindingObserver {
  bool _isTv = TvMode.isTv;

  @override
  void initState() {
    super.initState();
    // Inscrit avant celui de `Dpad`, monté plus bas : à la reprise, ce
    // gestionnaire passe donc avant la restauration de dpad, et doit attendre
    // qu'elle soit faite (voir [_afterResume]).
    WidgetsBinding.instance.addObserver(this);
    TvMode.enabled.addListener(_handleTvMode);
  }

  @override
  void didUpdateWidget(OnyxDpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileKey != widget.profileKey) {
      // La mémoire de dpad est une table statique pour toute l'app : sans
      // ce vidage, l'affiche où le profil A s'était arrêté resterait là où B
      // arrive. Les clés sont aussi préfixées par profil ; le vidage libère
      // en plus ce que l'autre profil ne retrouvera pas (constat C7).
      DpadRegionState.clearPersistentMemory();
    }
  }

  @override
  void dispose() {
    TvMode.enabled.removeListener(_handleTvMode);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleTvMode() {
    if (_isTv == TvMode.isTv) return;
    setState(() => _isTv = TvMode.isTv);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_isTv) return;
    // dpad restaure son focus de reprise dans un rappel de fin d'image puis
    // une microtâche, et le focus demandé ne se pose qu'à la microtâche
    // d'après. Tout cela est fait à l'image suivante : c'est là qu'on
    // regarde où il a atterri.
    _afterFrame(() => _afterFrame(_afterResume));
  }

  void _afterFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _afterResume() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary.context == null) return;
    final covered = TvForegroundRoute.coveredRouteOf(primary);
    if (covered == null) return;
    TvForegroundRoute.refocus(covered);
  }

  bool _handleBack() => TvBack.maybeOf(context)?.handleKey() ?? false;

  void _handleMenu() {
    TvDpadFocusable.contextMenuFor(FocusManager.instance.primaryFocus)?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = _isTv;
    return TvNavScope(
      profileKey: widget.profileKey,
      child: Dpad(
        keySet: OnyxDpad.keySetFor(
          isTv: isTv,
          isAndroid: OnyxDpad._isAndroid,
        ),
        restoreFocus: isTv,
        theme: TvNavTheme.data(lite: LiteScope.of(context)),
        onBack: isTv ? _handleBack : null,
        onMenu: isTv ? _handleMenu : null,
        onBlockedMove: widget.onBlockedMove,
        child: widget.child,
      ),
    );
  }
}

/// Ce qu'[OnyxDpad] publie dans l'arbre : sa présence (les `TvRegion` se
/// posent alors sur dpad plutôt que sur l'ancien système) et le profil qui
/// navigue.
class TvNavScope extends InheritedWidget {
  const TvNavScope({super.key, required this.profileKey, required super.child});

  final String? profileKey;

  /// Vrai sous un [OnyxDpad].
  static bool isActive(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TvNavScope>() != null;

  @override
  bool updateShouldNotify(TvNavScope oldWidget) =>
      oldWidget.profileKey != profileKey;
}
