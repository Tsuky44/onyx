import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import 'pointer_click_zone.dart';

/// Ce qui reste du lecteur quand la fenêtre est réduite en image dans l'image
/// sur ordinateur : l'image seule, et au survol de quoi la piloter.
///
/// Au survol, trois boutons au centre : reculer de 10 s, pause ou lecture,
/// avancer de 10 s. Un clic ailleurs sur l'image fait aussi pause ou lecture,
/// un double-clic revient à la fenêtre normale, et glisser l'image déplace la
/// petite fenêtre (même [PointerClickZone] que le lecteur plein format). Le
/// bouton du coin dit la même chose à qui ne sait pas que le double-clic
/// existe.
class DesktopPipOverlay extends StatefulWidget {
  const DesktopPipOverlay({
    super.key,
    required this.playing,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onRestore,
    required this.onDrag,
  });

  final bool playing;
  final VoidCallback onTogglePlayback;

  /// Un saut relatif, en secondes : négatif pour reculer.
  final ValueChanged<int> onSeek;
  final VoidCallback onRestore;
  final PointerDragStart? onDrag;

  /// Le saut des deux boutons, celui de la barre du lecteur.
  static const int skipSeconds = 10;

  @override
  State<DesktopPipOverlay> createState() => _DesktopPipOverlayState();
}

class _DesktopPipOverlayState extends State<DesktopPipOverlay> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PointerClickZone(
            onClick: widget.onTogglePlayback,
            onDoubleClick: widget.onRestore,
            onDrag: widget.onDrag,
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _hovered ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: const ColoredBox(color: Colors.black38),
            ),
          ),
          // Invisibles, les boutons ne doivent pas non plus prendre un clic :
          // hors survol, toute l'image reste la zone de pause.
          IgnorePointer(
            ignoring: !_hovered,
            child: AnimatedOpacity(
              opacity: _hovered ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: IconButton(
                        key: const ValueKey('pip-restore'),
                        tooltip: tr('Revenir à la taille normale'),
                        color: Colors.white,
                        onPressed: widget.onRestore,
                        icon: const Icon(Icons.open_in_full_rounded, size: 20),
                      ),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _button(
                          key: 'pip-rewind',
                          icon: Icons.replay_10_rounded,
                          tooltip: tr('Reculer de 10 s'),
                          onPressed: () =>
                              widget.onSeek(-DesktopPipOverlay.skipSeconds),
                        ),
                        _button(
                          key: 'pip-play-pause',
                          icon: widget.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          tooltip: widget.playing ? tr('Pause') : tr('Lecture'),
                          size: 44,
                          onPressed: widget.onTogglePlayback,
                        ),
                        _button(
                          key: 'pip-forward',
                          icon: Icons.forward_10_rounded,
                          tooltip: tr('Avancer de 10 s'),
                          onPressed: () =>
                              widget.onSeek(DesktopPipOverlay.skipSeconds),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _button({
    required String key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 32,
  }) {
    return IconButton(
      key: ValueKey(key),
      tooltip: tooltip,
      color: Colors.white,
      onPressed: onPressed,
      icon: Icon(icon, size: size),
    );
  }
}
