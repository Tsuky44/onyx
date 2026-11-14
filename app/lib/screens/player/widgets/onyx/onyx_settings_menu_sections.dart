part of 'onyx_settings_menu.dart';

/// Les listes du menu, une par réglage, et ce que chaque réglage vaut en ce
/// moment (la ligne de l'index).
///
/// Sorties de `onyx_settings_menu.dart` quand les menus ont pris leur dessin
/// d'Apple TV (ADR-0130) : le fichier touchait le plafond de l'ADR-0052.
extension _OnyxMenuSections on _OnyxSettingsMenuState {
  // --- Current-value summaries shown on the root rows ----------------------

  String get _qualityValue {
    final playing = _playingQualityLabel(short: true);
    // En Auto, la ligne dit les deux : qui choisit, et ce qui est joué.
    return (_controller?.isAutoQuality ?? false)
        ? tr('Auto · {0}', [playing])
        : playing;
  }

  /// Ce qui est joué en ce moment : le fichier, ou un barreau de l'échelle.
  ///
  /// [short] pour la ligne de résumé, étroite : la résolution seule, sans le
  /// débit qui l'accompagne dans le menu déroulé.
  String _playingQualityLabel({required bool short}) {
    final quality = _controller?.currentQuality;
    if (quality == null) {
      return directSourceLabel(local: _controller?.isLocalPlayback ?? false)
          .label;
    }
    for (final tier in _qualityTiers) {
      if (tier.key == quality) return short ? tier.resolutionLabel : tier.label;
    }
    return quality == '2160p' ? '4K' : quality;
  }

  String get _audioValue {
    final controller = _controller;
    final tracks = controller?.mediaTracks?.audio;
    if (controller != null && tracks != null && tracks.isNotEmpty) {
      final index = controller.selectedAudioIndex;
      if (index >= 0 && index < tracks.length) {
        return splitTrackLabel(tracks[index].displayName).$1;
      }
      return '—';
    }
    final current = widget.session.currentAudioTrack;
    if (current == null || current.id == 'no') return tr('Désactivé');
    return current.title ?? current.language ?? tr('Piste 1');
  }

  String get _subtitlesValue {
    final controller = _controller;
    if (controller == null) return '—';

    if (controller.listsEmbeddedSubtitles) {
      final current = widget.session.currentSubtitleTrack;
      if (current == null || current.id == 'no') return tr('Désactivés');
      return current.title ?? current.language ?? tr('Piste 1');
    }

    final lang = controller.selectedSubtitleLang;
    if (lang == null) return tr('Désactivés');
    final track = controller.mediaTracks?.subtitles
        .where((s) => s.lang == lang)
        .firstOrNull;
    return track == null ? lang : splitTrackLabel(track.displayName).$1;
  }

  String get _speedValue => PlayerMenuChoices.rateLabel(widget.playbackRate);

  String get _displayValue => _mode.label;

  String get _sleepValue {
    final episodes = SleepTimer.instance.episodesLeft;
    if (episodes != null) return _sleepEpisodes(episodes);
    final remaining = SleepTimer.instance.remaining;
    return remaining == null ? tr('Désactivée') : _sleepRemaining(remaining);
  }

  /// Arrondi à la minute supérieure : « 1 min » tant qu'il reste du temps,
  /// jamais un « 0 min » qui annoncerait une coupure déjà faite.
  static String _sleepRemaining(Duration remaining) {
    final minutes = (remaining.inSeconds / 60).ceil();
    if (minutes < 60) return '$minutes min';
    final rest = (minutes % 60).toString().padLeft(2, '0');
    return '${minutes ~/ 60} h $rest';
  }

  static String _sleepEpisodes(int count) =>
      tr('{0} épisode{1}', [count, count > 1 ? 's' : '']);

  static String _sleepChoiceLabel(Duration choice) {
    if (choice.inMinutes < 60) return '${choice.inMinutes} minutes';
    final hours = choice.inHours;
    return hours == 1 ? '1 heure' : '$hours heures';
  }

  static String _timecode(double seconds) {
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Lays out a section and decides which of its rows the remote arrives on.
  ///
  /// The option already in force, so opening "Audio" outlines the language
  /// being played and the next press moves from there. A list with nothing
  /// selected — the chapters — hands it to the first row.
  ///
  /// Un `null` dans [options] est un filet entre deux groupes (la minuterie
  /// sépare ses épisodes de ses durées) : il ne prend jamais le focus.
  Widget _sectionList(List<_OnyxMenuOption?> options) {
    final style = OnyxMenuStyle.current;
    final selected = options.indexWhere((option) => option?.selected ?? false);
    final entry =
        selected < 0 ? options.indexWhere((option) => option != null) : selected;

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.symmetric(
        horizontal: style.padding - style.overhang,
      ),
      children: [
        for (var i = 0; i < options.length; i++)
          options[i]?.withFocusNode(i == entry ? _entryNode : null) ??
              const _OnyxMenuDivider(),
      ],
    );
  }

  // --- Sections ------------------------------------------------------------

  List<QualityTier> get _qualityTiers =>
      PlayerMenuChoices.qualityTiers(_controller?.mediaTracks);

  Widget _buildQuality() {
    final controller = _controller;
    if (controller == null) return const _OnyxMenuEmpty();
    final direct = directSourceLabel(
      local: controller.isLocalPlayback,
      streamSubtitle: tr('Le fichier tel quel'),
    );

    final auto = controller.isAutoQuality;

    return _sectionList([
      // L'Auto choisit entre toutes les lignes qui suivent, d'après ce que la
      // connexion porte (ADR-0056). Absente d'un fichier téléchargé et face à
      // un serveur qui n'annonce pas ses débits : elle n'aurait rien à choisir.
      if (controller.autoQualityAvailable)
        _OnyxMenuOption(
          label: tr('Auto'),
          subtitle: auto
              ? _playingQualityLabel(short: false)
              : tr('S’adapte à la connexion'),
          selected: auto,
          onTap: () {
            widget.onClose();
            controller.chooseAutoQuality();
          },
        ),
      // Direct Play is native-only: it hands the player the file itself, which
      // a browser cannot open. Un Dolby Vision profil 5 que ce moteur montre
      // rose et vert reste proposé, en le disant (ADR-0060).
      if (!AppPlatform.isWeb)
        _OnyxMenuOption(
          label: direct.label,
          subtitle: controller.directPlayHasWrongColours
              ? tr('Couleurs incorrectes sur cet appareil')
              : direct.subtitle,
          selected: !auto && controller.currentQuality == null,
          onTap: () {
            widget.onClose();
            controller.chooseQuality(null);
          },
        ),
      for (final tier in _qualityTiers)
        () {
          return _OnyxMenuOption(
            label: tier.resolutionLabel,
            subtitle: tier.bitrateLabel,
            selected: !auto && controller.currentQuality == tier.key,
            onTap: () {
              widget.onClose();
              controller.chooseQuality(tier.key);
            },
          );
        }(),
    ]);
  }

  Widget _buildAudio() {
    final controller = _controller;
    final tracks = controller?.mediaTracks?.audio;

    if (controller != null && tracks != null && tracks.isNotEmpty) {
      return _sectionList([
        for (var i = 0; i < tracks.length; i++)
          () {
            final (title, subtitle) = splitTrackLabel(tracks[i].displayName);
            final selected = i == controller.selectedAudioIndex;
            return _OnyxMenuOption(
              label: title,
              subtitle: subtitle,
              selected: selected,
              onTap: () {
                if (!selected) controller.switchAudioTrack(i);
                widget.onClose();
              },
            );
          }(),
      ]);
    }

    final internal = widget.session.audioTracks;
    if (internal.isEmpty) return const _OnyxMenuEmpty();
    final current = widget.session.currentAudioTrack;

    return _sectionList([
      for (var i = 0; i < internal.length; i++)
        _OnyxMenuOption(
          label: internal[i].id == 'no'
              ? tr('Désactivé')
              : internal[i].title ??
                  (internal[i].language != null
                      ? tr('Audio ({0})', [internal[i].language])
                      : tr('Audio {0}', [i + 1])),
          selected: internal[i] == current,
          onTap: () {
            widget.session.setAudioTrack(internal[i]);
            widget.onClose();
          },
        ),
    ]);
  }

  Widget _buildSubtitles() {
    final controller = _controller;
    if (controller == null) return const _OnyxMenuEmpty();

    // Direct Play reads the tracks off the file; a transcode carries the
    // canonical list from the server. Same split as [PlayerSubtitlesPicker].
    if (controller.listsEmbeddedSubtitles) {
      final subs =
          widget.session.subtitleTracks.where((t) => t.id != 'auto').toList();
      if (subs.isEmpty) return const _OnyxMenuEmpty();
      final current = widget.session.currentSubtitleTrack;

      return _sectionList([
        for (var i = 0; i < subs.length; i++)
          _OnyxMenuOption(
            label: subs[i].id == 'no'
                ? tr('Désactivés')
                : subs[i].title ??
                    (subs[i].language != null
                        ? tr('Sous-titre ({0})', [subs[i].language])
                        : tr('Sous-titre {0}', [i + 1])),
            selected: subs[i] == current,
            onTap: () {
              controller.selectInternalSubtitle(subs[i]);
              widget.onClose();
            },
          ),
      ]);
    }

    final subtitles =
        controller.mediaTracks?.subtitles ?? const <MediaSubtitleTrack>[];
    return _sectionList([
      _OnyxMenuOption(
        label: tr('Désactivés'),
        selected: controller.selectedSubtitleLang == null,
        onTap: () {
          controller.setSubtitle(null);
          widget.onClose();
        },
      ),
      for (final track in subtitles)
        () {
          final (title, subtitle) = splitTrackLabel(track.displayName);
          return _OnyxMenuOption(
            label: title,
            subtitle: subtitle,
            // A bitmap track has to be burned into the video while
            // transcoding, so picking it costs a short reload.
            badge: !track.ready ? '…' : (track.image ? 'image' : null),
            selected: controller.selectedSubtitleLang == track.lang,
            onTap: () {
              controller.setSubtitle(track.lang);
              widget.onClose();
            },
          );
        }(),
    ]);
  }

  Widget _buildSpeed() {
    return _sectionList([
      for (final rate in widget.playbackRates)
        _OnyxMenuOption(
          label: PlayerMenuChoices.rateLabel(rate),
          selected: rate == widget.playbackRate,
          onTap: () {
            widget.onRateChanged(rate);
            widget.onClose();
          },
        ),
    ]);
  }

  Widget _buildDisplay() {
    return _sectionList([
      for (final mode in VideoDisplayMode.values)
        _OnyxMenuOption(
          label: mode.label,
          subtitle: mode.description,
          selected: mode == _mode,
          onTap: () => _setMode(mode),
        ),
    ]);
  }

  /// The one section that stays open after a choice, so the ring has to follow
  /// it: the entry node has just moved to the other row, and without this the
  /// focus would be left on a row that no longer holds it.
  void _setMode(VideoDisplayMode mode) {
    _update(() => _mode = mode);
    widget.onModeChanged(mode);
    _focusEntryAfterBuild();
  }

  /// La lecture se met en pause à l'échéance, où qu'elle en soit : la
  /// minuterie suit d'un épisode au suivant. Voir [SleepTimer].
  ///
  /// Le compte en épisodes n'est proposé que devant un épisode : un film n'a
  /// pas de suivant à ne pas lancer.
  Widget _buildSleep() {
    final timer = SleepTimer.instance;
    final remaining = timer.remaining;
    final episodesLeft = timer.episodesLeft;

    return _sectionList([
      _OnyxMenuOption(
        label: tr('Désactivée'),
        selected: !timer.isActive,
        onTap: () {
          timer.cancel();
          widget.onClose();
        },
      ),
      if (widget.episodeNav != null) ...[
        null,
        for (final count in SleepTimer.episodeChoices)
          () {
            final selected = timer.episodesChosen == count;
            return _OnyxMenuOption(
              label: count == 1
                  ? tr('À la fin de l’épisode')
                  : tr('Après {0} épisodes', [count]),
              value: selected && episodesLeft != null && episodesLeft < count
                  ? tr('reste {0}', [_sleepEpisodes(episodesLeft)])
                  : null,
              selected: selected,
              onTap: () {
                timer.startEpisodes(count);
                widget.onClose();
              },
            );
          }(),
      ],
      null,
      for (final choice in SleepTimer.choices)
        () {
          final selected = timer.chosen == choice;
          return _OnyxMenuOption(
            label: _sleepChoiceLabel(choice),
            value: selected && remaining != null
                ? 'reste ${_sleepRemaining(remaining)}'
                : null,
            selected: selected,
            onTap: () {
              timer.start(choice);
              widget.onClose();
            },
          );
        }(),
    ]);
  }

  Widget _buildChapters() {
    final chapters = widget.episodeNav!.chapters;
    final seek = widget.onSeekToAbsolute!;

    return _sectionList([
      for (final chapter in chapters)
        _OnyxMenuOption(
          label: chapter.title.isEmpty
              ? tr('Chapitre {0}', [chapter.id])
              : chapter.title,
          value: _timecode(chapter.startTime),
          selected: false,
          onTap: () {
            widget.onClose();
            seek(chapter.startTime.round());
          },
        ),
    ]);
  }
}
