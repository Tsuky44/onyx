import 'package:flutter/material.dart';

import '../player_chrome_fade.dart';

import '../../../../desktop_window.dart';
import '../../../../theme/app_motion.dart';
import '../../../../tv/nav/tv_region.dart';
import '../../../../utils/format.dart';
import '../../../../widgets/global/app_network_image.dart';
import '../avoid_cutouts.dart';
import '../../playback/skip_segments.dart';
import '../../playback/timeline_previews.dart';
import 'onyx_brightness_slider.dart';
import 'onyx_chrome_buttons.dart';
import 'onyx_chrome_theme.dart';
import 'onyx_menu_section.dart';
import 'onyx_progress_bar.dart';
import 'onyx_scrim.dart';
import 'onyx_skip_intro_button.dart';
import 'onyx_tabs.dart';
import 'onyx_tv_tabs.dart';
import '../../../../l10n/tr.dart';

part 'onyx_chrome_layout.dart';
part 'onyx_controls_rows.dart';
part 'onyx_handheld_chrome.dart';
part 'onyx_pointer_chrome.dart';

/// Chrome Onyx: the hand-written player chrome, the only one the app has.
///
/// Nothing here is placed by the user: the arrangement is code, not data,
/// which is what lets it be laid out in real pixels and stay faithful.
///
/// Un seul arrangement, celui du lecteur d'Apple, décliné selon ce qui
/// pilote l'écran (ADR-0139) : la télécommande ([_buildTvChrome], ADR-0124),
/// le doigt ([_buildHandheldChrome], ADR-0136), la souris
/// ([_buildPointerChrome]). Le logo en haut à gauche, ce qu'on regarde en une
/// ligne, l'essentiel en boutons ronds de verre, la barre fine à repère.
class OnyxControlsLayer extends StatelessWidget {
  final bool visible;

  /// Anchors subtitle positioning to the scrubber, as the other layers do.
  final GlobalKey? timelineAnchorKey;

  // --- Playback -----------------------------------------------------------
  final bool isPlaying;
  final Duration position;
  final Duration duration;

  /// Downloaded-ahead fraction, 0.0 -> 1.0.
  final double buffered;

  final VoidCallback onPlayPause;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final ValueChanged<double> onSeekFraction;
  final ValueChanged<bool>? onScrubbingChanged;

  /// What left and right do on the focused scrubber, on a television. Default
  /// to [onRewind] / [onForward]; the player passes steps that chain while
  /// the key is held instead of seeking on each one.
  final VoidCallback? onScrubStepBack;
  final VoidCallback? onScrubStepForward;

  /// Television only: the remote moved between the chrome's controls. The
  /// player uses it to hold the chrome on screen while someone is using it.
  final VoidCallback? onRemoteNavigate;

  // --- Identity -----------------------------------------------------------

  /// Bold line: movie title, or show name for an episode.
  final String? title;

  /// Muted line above it: release year for a movie, `S1:E3 - …` for an episode.
  final String? overline;

  final String? logoUrl;

  /// Un épisode : [title] est le nom de la série, [overline] celui de
  /// l'épisode. Sur un téléviseur et un écran tenu en main, le logo dit alors
  /// la série et la ligne du bas l'épisode seul ; pour un film, cette ligne
  /// est son titre. Voir [_buildIdentityLine].
  final bool isEpisode;

  // --- Volume -------------------------------------------------------------

  /// 0.0 -> 100.0, matching media_kit.
  final double volume;
  final ValueChanged<double> onVolumeChanged;

  // --- Brightness ---------------------------------------------------------

  /// Screen brightness, 0.0 -> 1.0, or null on a screen whose backlight this
  /// app does not drive — a desktop monitor, a television, a browser tab. The
  /// left-hand bar is left out entirely rather than shown doing nothing.
  final double? brightness;
  final ValueChanged<double>? onBrightnessChanged;

  /// True while the bar is being dragged, so the chrome can be held open.
  final ValueChanged<bool>? onBrightnessDraggingChanged;

  // --- Utilities ----------------------------------------------------------
  final VoidCallback onBack;
  final VoidCallback onToggleSubtitles;
  final VoidCallback onOpenAudio;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleFullscreen;

  /// Image dans l'image d'ordinateur ; null là où elle n'existe pas.
  final VoidCallback? onTogglePictureInPicture;

  /// Verrouille l'écran contre les touchers — voir [PlayerScreenLock]. Null
  /// hors d'un appareil tenu en main : une souris ou une télécommande ne
  /// touchent rien par accident.
  final VoidCallback? onLockScreen;

  // --- Conditional --------------------------------------------------------

  /// Series only — null on a movie or at the end of a season.
  final VoidCallback? onSkipNext;

  /// Series only — null on a movie or on the first episode of a season.
  final VoidCallback? onSkipPrevious;

  /// Ouvre la feuille des onglets sur « Épisodes ». Une série seulement.
  final VoidCallback? onOpenEpisodes;

  /// Sur un film : ouvre la même feuille sur « Infos ». Les deux servent le
  /// bouton des onglets ([_buildEssentialActions]), là où le chrome ne porte
  /// pas les onglets lui-même : un écran tenu en main, une fenêtre étroite.
  final VoidCallback? onOpenInfo;

  /// Only while an intro chapter is playing.
  final VoidCallback? onSkipIntro;

  /// Set while the intro counts down to skipping itself: the pill fills over
  /// that time.
  final Duration? skipIntroCountdown;

  /// Le passage que [onSkipIntro] saute : le récap ou l'intro.
  final SkipSegment skipSegment;

  /// Chapter starts as fractions, for the scrubber ticks.
  final List<double> chapterMarks;

  final GlobalKey? settingsButtonKey;
  final GlobalKey? subtitlesButtonKey;

  // --- Television ---------------------------------------------------------

  /// Sur un téléviseur, chaque réglage a son bouton rond : il ouvre le menu de
  /// [section], posé au-dessus de [anchor], le bouton lui-même (ADR-0130). Sur
  /// un écran tenu en main, les sous-titres et l'audio font de même (ADR-0136).
  final void Function(OnyxMenuSection section, BuildContext anchor)? onOpenMenu;

  /// Le menu ouvert par l'un de ces boutons, qui reste allumé tant qu'il l'est.
  /// [OnyxMenuSection.root] pour l'index de la roue crantée.
  final OnyxMenuSection? openMenu;

  /// Les onglets sous la barre d'un téléviseur ou d'un écran tenu en main, et
  /// celui dont le volet est ouvert. Voir [OnyxTvTabs].
  final List<OnyxTabEntry> tabs;
  final OnyxTab? openTab;
  final ValueChanged<OnyxTab?>? onTabChanged;

  /// How big the chrome is drawn, as a factor.
  ///
  /// 1 everywhere except on an iPhone, where the same widget reads slightly
  /// larger than it does on Android at the same width. Only what is drawn
  /// shrinks — the touch targets do not, see
  /// [OnyxChromeMetrics.scaledBy]. Passed in rather than read from the
  /// platform, for the same reason [showVolume] is: a test renders this
  /// chrome away from any device.
  final double scale;

  /// Whether the top bar carries a volume control (le chrome d'une souris).
  ///
  /// False on a phone: the handset has volume keys under the fingers already
  /// holding it, and a second control for the same thing costs a slot in a row
  /// that is short of them. Kept on a computer, where the only volume within
  /// reach is the one on screen.
  final bool showVolume;

  /// Driven by a remote rather than a mouse or a finger.
  ///
  /// The chrome takes its television arrangement ([_buildTvChrome]), without
  /// what a remote has no use for: the volume control (a set has its own on
  /// its own remote), the brightness bar (a television's backlight is not this
  /// app's to drive), the fullscreen toggle (there is no window) and the speed
  /// button (the rate is in the settings menu). The scrubber becomes a focus
  /// stop that seeks with left and right.
  final bool isTv;

  /// Un écran tenu en main, téléphone ou tablette : le chrome prend
  /// l'arrangement d'un téléviseur adapté au doigt ([_buildHandheldChrome],
  /// ADR-0136). Passé plutôt que lu de la plateforme, comme [showVolume] : un
  /// test dessine ce chrome loin de tout appareil.
  final bool handheld;

  /// Un écran tenu en main dans un navigateur : le bouton « Plein écran »
  /// rejoint le verrou, parce que la page a sa barre d'adresse à faire sortir.
  /// Une app installée occupe déjà tout l'écran.
  final bool handheldFullscreen;

  /// Where the remote lands when it enters the control bar. Play/pause is the
  /// button a hand reaches for first, and every other control is one or two
  /// presses from it.
  final FocusNode? playPauseFocusNode;

  /// The scrubber's node. On a television the remote lands here when it
  /// brought the HUD up with a seek, so left and right go on meaning "seek" —
  /// only now with an outline saying which control is answering.
  final FocusNode? progressFocusNode;

  /// Where the screen's own hardware sits — a camera bubble, a notch — as
  /// rectangles in the window's coordinates, from [DisplayCutouts].
  ///
  /// Rectangles rather than margins, and applied row by row rather than to the
  /// chrome as a whole: a bubble halfway down the left edge has to move the
  /// brightness bar and nothing else. Padding the layer would have moved the
  /// title, the scrubber and every button with it, which is the interface
  /// stepping aside for something that was in the way of one control.
  ///
  /// The scrims are never moved: a gradient that stops short of the camera
  /// reads as a rendering bug, while a button that stops short of it reads as
  /// intent.
  ///
  /// Empty for anything rendering this chrome away from a screen edge — a
  /// windowed desktop — which is why it is passed in rather than read from
  /// the ambient [MediaQuery].
  final List<Rect> cutouts;

  /// Stills of the timeline for the scrubber; null until the player has them.
  final TimelinePreviews? previews;

  /// A remote seek is waiting to be committed — the scrubber then shows the
  /// still of where it will land.
  final bool remoteSeekPending;

  const OnyxControlsLayer({
    super.key,
    required this.visible,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onPlayPause,
    required this.onRewind,
    required this.onForward,
    required this.onSeekFraction,
    required this.volume,
    required this.onVolumeChanged,
    this.brightness,
    this.onBrightnessChanged,
    this.onBrightnessDraggingChanged,
    required this.onBack,
    required this.onToggleSubtitles,
    required this.onOpenAudio,
    required this.onOpenSettings,
    required this.onToggleFullscreen,
    this.onTogglePictureInPicture,
    this.onLockScreen,
    this.timelineAnchorKey,
    this.onScrubbingChanged,
    this.onScrubStepBack,
    this.onScrubStepForward,
    this.onRemoteNavigate,
    this.title,
    this.overline,
    this.logoUrl,
    this.isEpisode = false,
    this.onSkipNext,
    this.onSkipPrevious,
    this.onOpenEpisodes,
    this.onOpenInfo,
    this.onOpenMenu,
    this.openMenu,
    this.tabs = const <OnyxTabEntry>[],
    this.openTab,
    this.onTabChanged,
    this.onSkipIntro,
    this.skipIntroCountdown,
    this.skipSegment = SkipSegment.intro,
    this.chapterMarks = const [],
    this.settingsButtonKey,
    this.subtitlesButtonKey,
    this.isTv = false,
    this.handheld = false,
    this.handheldFullscreen = false,
    this.playPauseFocusNode,
    this.progressFocusNode,
    this.cutouts = const <Rect>[],
    this.previews,
    this.remoteSeekPending = false,
    this.showVolume = true,
    this.scale = 1,
  });

  /// The empty strip at the bottom of the top bar, and the one at the top of
  /// the bottom bar.
  ///
  /// Both are pure scrim: gradient, nothing drawn in them, nothing in them that
  /// can take a touch. They belong to the brightness bar as much as to the bars
  /// they pad — and on a phone held sideways they have to, because the bottom
  /// bar alone is more than half the height of the screen and what is left
  /// between the two is not enough to put a control in.
  static const double _topBarTail = 28;
  static const double _bottomBarLead = 60;

  /// Moves one row of the chrome clear of a camera bubble, if the bubble is
  /// actually on it. Everything else stays exactly where it was.
  Widget _dodgeCutouts(Widget child) =>
      cutouts.isEmpty ? child : AvoidCutouts(cutouts: cutouts, child: child);

  double get _progressFraction {
    final total = duration.inSeconds;
    if (total <= 0) return 0.0;
    return (position.inSeconds / total).clamp(0.0, 1.0);
  }

  int get _remainingSeconds {
    final left = duration.inSeconds - position.inSeconds;
    return left > 0 ? left : 0;
  }

  @override
  Widget build(BuildContext context) {
    // Sized from its own constraints rather than the window, so the chrome
    // gets the arrangement its own box deserves wherever it is rendered.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final m = OnyxChromeTheme.metricsFor(
          width,
          scale: scale,
          tv: isTv,
          handheld: handheld,
        );
        if (isTv) return _buildTvChrome(m);
        if (handheld) return _buildHandheldChrome(m, width);
        return _buildPointerChrome(m, constraints.biggest);
      },
    );
  }

  /// Wraps a part of the chrome in the show/hide fade — and takes it out of
  /// hit-testing while it is invisible, so a hidden control cannot be clicked.
  Widget _fadeWithChrome(Widget child) =>
      PlayerChromeFade(visible: visible, child: child);

  /// La barre de luminosité, dans la bande que les deux barres lui laissent.
  ///
  /// A full-width row holding one right-aligned control, rather than a box
  /// pinned to the right edge: that is the shape the cutout dodge reasons
  /// about, and it is what lets a camera on this edge push the bar in without
  /// moving anything else.
  ///
  /// [barWidth] : la largeur d'un bouton rond, sur un écran tenu en main. La
  /// rangée se cale alors comme celles des boutons — la marge dehors,
  /// l'évitement de la caméra dedans — et la barre tombe à leur verticale.
  Widget _buildBrightnessBand(OnyxChromeMetrics m, {double? barWidth}) {
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _fadeWithChrome(
          OnyxBrightnessSlider(
            value: brightness!,
            onChanged: onBrightnessChanged!,
            onDraggingChanged: onBrightnessDraggingChanged,
            metrics: m,
            barWidth: barWidth ?? OnyxBrightnessSlider.defaultBarWidth,
          ),
        ),
      ],
    );
    if (barWidth != null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: m.gutter),
        child: _dodgeCutouts(row),
      );
    }
    return _dodgeCutouts(
      Padding(
        padding: EdgeInsets.only(right: m.gutter - 8),
        child: row,
      ),
    );
  }

  Widget _brandText(OnyxChromeMetrics m) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: OnyxChromeTheme.title,
          fontSize: m.brandTextSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
