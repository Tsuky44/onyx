import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../playback/playback_session.dart';
import '../../playback/sleep_timer.dart';

import '../../../../models/models.dart';
import '../../../../tv/nav/tv_back.dart';
import '../../../../tv/tv_focus.dart';
import '../../../../tv/tv_mode.dart';
import '../../../../utils/app_platform.dart';
import '../../hooks/use_episode_navigation.dart';
import '../../hooks/use_player_controller.dart';
import '../../hooks/use_player_popup.dart';
import '../../player_menu_choices.dart';
import '../../video_display_mode.dart';
import '../direct_source_label.dart';
import '../track_label.dart';
import 'onyx_chrome_theme.dart';
import 'onyx_glass_panel.dart';
import 'onyx_menu_section.dart';
import 'onyx_menu_style.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_type.dart';
import '../../../../theme/focus_fill.dart';
import '../../../../l10n/tr.dart';

export 'onyx_menu_section.dart';
export 'onyx_menu_style.dart';

part 'onyx_settings_menu_rows.dart';
part 'onyx_settings_menu_sections.dart';

/// Chrome Onyx settings menu: a narrow list of sections, each drilling into a
/// list of choices, instead of a tall tabbed panel.
///
/// A tabbed panel shows every category's chrome at once —
/// header, subtitle, five segmented tabs — before showing a single option. On
/// Chrome Onyx that reads as a dialog dropped on the video. This menu instead
/// puts one column of rows over the picture: what each setting is *currently*
/// on is visible without opening anything, and a category costs one tap.
///
/// Sur un téléviseur, chaque réglage a son bouton rond et son propre menu
/// ([standalone]) : pas d'index à traverser, Retour le ferme. Le dessin est
/// celui des menus de l'Apple TV — un panneau de verre, de grandes lignes, la
/// ligne sous la télécommande en blanc ([OnyxMenuStyle], ADR-0130).
///
/// Like the rest of this chrome, the look is locked — see [OnyxChromeTheme].
class OnyxSettingsMenu extends StatefulWidget {
  final PlaybackSession session;
  final PlayerController? playerController;
  final EpisodeNavigationController? episodeNav;

  final VideoDisplayMode currentMode;
  final ValueChanged<VideoDisplayMode> onModeChanged;

  final double playbackRate;
  final List<double> playbackRates;
  final ValueChanged<double> onRateChanged;

  final Future<void> Function(int absoluteSeconds)? onSeekToAbsolute;

  /// Opening straight on a category — the CC and audio buttons of the chrome
  /// point at their own list rather than at the index.
  final OnyxMenuSection initialSection;

  /// Le menu d'un seul réglage : [initialSection] et rien d'autre. Son en-tête
  /// nomme le réglage au lieu de ramener à l'index, et Retour ferme le menu.
  final bool standalone;

  final VoidCallback onClose;

  const OnyxSettingsMenu({
    super.key,
    required this.session,
    required this.currentMode,
    required this.onModeChanged,
    required this.playbackRate,
    required this.playbackRates,
    required this.onRateChanged,
    required this.onClose,
    this.playerController,
    this.episodeNav,
    this.onSeekToAbsolute,
    this.initialSection = OnyxMenuSection.root,
    this.standalone = false,
  }) : assert(
          !standalone || initialSection != OnyxMenuSection.root,
          'un menu seul montre un réglage, pas l’index',
        );

  @override
  State<OnyxSettingsMenu> createState() => _OnyxSettingsMenuState();
}

/// Retour depuis une section : remonter à l'index au lieu de tout fermer. Sur
/// l'index, désactivée — le menu se ferme.
class _UpOneLevelAction extends Action<PlayerPopupBackIntent> {
  _UpOneLevelAction(this._menu);

  final _OnyxSettingsMenuState _menu;

  @override
  bool isEnabled(PlayerPopupBackIntent intent) =>
      _menu.mounted && _menu._canGoUp;

  @override
  Object? invoke(PlayerPopupBackIntent intent) {
    _menu._backToRoot();
    return true;
  }
}

class _OnyxSettingsMenuState extends State<OnyxSettingsMenu> {
  late OnyxMenuSection _section;
  late VideoDisplayMode _mode;
  StreamSubscription<void>? _tracksSubscription;

  /// Fait avancer le « reste 23 min » tant que la minuterie de veille court.
  Timer? _sleepRefresh;

  /// Where the remote lands on the list currently shown: the value already in
  /// force inside a section, the row it came back from on the index.
  ///
  /// One node moved from row to row on every section change, rather than an
  /// `autofocus` on each: two rows claiming the entry point is a ring that
  /// jumps.
  final FocusNode _entryNode = FocusNode(debugLabel: 'onyx-menu-entry');

  /// The section just left, so the index puts the ring back on its row instead
  /// of dropping the user at the top of the list.
  OnyxMenuSection? _returnedFrom;

  PlayerController? get _controller => widget.playerController;

  /// Une section ouverte depuis l'index peut y remonter. Le menu d'un seul
  /// réglage n'a pas d'index : Retour le ferme.
  bool get _canGoUp => !widget.standalone && _section != OnyxMenuSection.root;

  /// `setState`, pour les extensions de cet état (le membre est protégé).
  void _update(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _mode = widget.currentMode;
    _tracksSubscription = _controller?.tracksStream.listen((_) {
      if (mounted) setState(() {});
    });
    SleepTimer.instance.addListener(_handleSleepTimerChanged);
    _syncSleepRefresh();
    _focusEntryAfterBuild();
  }

  @override
  void dispose() {
    SleepTimer.instance.removeListener(_handleSleepTimerChanged);
    _sleepRefresh?.cancel();
    _tracksSubscription?.cancel();
    _entryNode.dispose();
    super.dispose();
  }

  void _handleSleepTimerChanged() {
    _syncSleepRefresh();
    if (mounted) setState(() {});
  }

  /// Un réveil par minute affichée, posé sur l'instant où le libellé change —
  /// pas une boucle : le menu ne se redessine que lorsqu'il a autre chose à
  /// dire.
  void _syncSleepRefresh() {
    _sleepRefresh?.cancel();
    _sleepRefresh = null;
    final remaining = SleepTimer.instance.remaining;
    if (remaining == null) return;
    final untilNextMinute = Duration(
      microseconds: remaining.inMicroseconds % Duration.microsecondsPerMinute,
    );
    _sleepRefresh = Timer(
      // Juste après le changement, pour ne pas relire la même minute.
      untilNextMinute + const Duration(milliseconds: 50),
      () {
        if (!mounted) return;
        setState(() {});
        _syncSleepRefresh();
      },
    );
  }

  // --- Remote navigation ---------------------------------------------------

  /// Puts the remote on the entry point of the list now showing.
  ///
  /// After the frame: the list has just been replaced, and [_entryNode] is
  /// attached to a row only once that row is built. Waiting is also what makes
  /// this choice win over the popup's generic "focus the first thing you find"
  /// — on a track list the ring belongs on the language being played, not on
  /// whatever happens to be at the top.
  void _focusEntryAfterBuild() {
    // Off a television nobody asked for the focus, and taking it would paint a
    // ring neither the pointer nor a finger called for.
    if (!TvMode.isTv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entryNode.requestFocus();
    });
  }

  void _openSection(OnyxMenuSection section) {
    setState(() => _section = section);
    _focusEntryAfterBuild();
  }

  void _backToRoot() {
    setState(() {
      _returnedFrom = _section;
      _section = OnyxMenuSection.root;
    });
    _focusEntryAfterBuild();
  }

  /// The index row the remote lands on.
  OnyxMenuSection get _rootEntry =>
      _returnedFrom ??
      (_hasQuality ? OnyxMenuSection.quality : OnyxMenuSection.audio);

  /// Back and left go up one level instead of closing everything.
  ///
  /// The menu shows a hierarchy — an index, a section — and the remote has to
  /// be able to climb it the same way it came down. On the index the key is
  /// left alone: it reaches the popup, which closes the menu, and that is the
  /// right next step up.
  KeyEventResult _handleMenuKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_canGoUp) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _backToRoot();
      return KeyEventResult.handled;
    }
    if (isSelfHandledBackKey(key)) {
      // Voir [TvBack.claimKey] : pas deux couches pour un appui.
      if (TvBack.claimKey(context)) _backToRoot();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- Section availability ------------------------------------------------

  bool get _hasChapters =>
      widget.episodeNav != null &&
      widget.episodeNav!.chapters.isNotEmpty &&
      widget.onSeekToAbsolute != null;

  bool get _hasQuality => _controller != null;

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final style = OnyxMenuStyle.current;
    return Focus(
      // Never a destination itself: this node is here only to see the keys
      // travelling up from the focused row.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleMenuKey,
      child: Actions(
        actions: <Type, Action<Intent>>{
          PlayerPopupBackIntent: _UpOneLevelAction(this),
        },
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: style.width,
            child: OnyxGlassPanel(
              radius: BorderRadius.circular(style.radius),
              // Height follows the visible section, so leaving a 12-chapter
              // list for "Format d'image" shrinks the menu instead of leaving
              // a hole.
              child: AnimatedSize(
                duration: AppMotion.focus,
                curve: AppMotion.curve,
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: style.maxHeight),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: style.padding),
                    child: _section == OnyxMenuSection.root
                        ? _buildRoot()
                        : _buildSection(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoot() {
    Widget row(OnyxMenuSection section, String label, String value) {
      return _OnyxMenuRow(
        label: label,
        value: value,
        focusNode: _rootEntry == section ? _entryNode : null,
        onTap: () => _openSection(section),
      );
    }

    final style = OnyxMenuStyle.current;
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.symmetric(
        horizontal: style.padding - style.overhang,
      ),
      children: [
        if (_hasQuality)
          row(OnyxMenuSection.quality, tr('Qualité'), _qualityValue),
        row(OnyxMenuSection.audio, tr('Audio'), _audioValue),
        row(OnyxMenuSection.subtitles, tr('Sous-titres'), _subtitlesValue),
        row(OnyxMenuSection.speed, tr('Vitesse de lecture'), _speedValue),
        row(OnyxMenuSection.display, tr('Format d’image'), _displayValue),
        row(OnyxMenuSection.sleep, tr('Minuterie de veille'), _sleepValue),
        if (_hasChapters)
          row(
            OnyxMenuSection.chapters,
            tr('Chapitres'),
            '${widget.episodeNav!.chapters.length}',
          ),
      ],
    );
  }

  Widget _buildSection() {
    final (title, body) = switch (_section) {
      OnyxMenuSection.quality => (tr('Qualité'), _buildQuality()),
      OnyxMenuSection.audio => (tr('Audio'), _buildAudio()),
      OnyxMenuSection.subtitles => (tr('Sous-titres'), _buildSubtitles()),
      OnyxMenuSection.speed => (tr('Vitesse de lecture'), _buildSpeed()),
      OnyxMenuSection.display => (tr('Format d’image'), _buildDisplay()),
      OnyxMenuSection.sleep => (tr('Minuterie de veille'), _buildSleep()),
      OnyxMenuSection.chapters => (tr('Chapitres'), _buildChapters()),
      OnyxMenuSection.root => ('', const SizedBox.shrink()),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.standalone)
          _OnyxMenuHeader(title: title)
        else
          _OnyxMenuBackHeader(title: title, onBack: _backToRoot),
        Flexible(child: body),
      ],
    );
  }
}
