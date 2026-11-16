import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_mode.dart';
import '../../widgets/global/onyx_menu.dart';

/// Ce que dit le libellé d'une [MediaVersion], rangé en trois morceaux.
///
/// Le serveur n'envoie qu'une chaîne : « 1920 × 1080 · HEVC · film.mkv »,
/// « 2160p · film.mkv » ou « Qualité inconnue · film.mkv ». Ni le son ni la
/// taille n'arrivent au client : on n'affiche que ce que la chaîne porte, et
/// un morceau absent reste absent.
@immutable
class VersionLabel {
  const VersionLabel({required this.resolution, this.codec, this.fileName});

  factory VersionLabel.parse(String label) {
    final parts = label.split(' · ');
    final resolution = _shortResolution(parts.first.trim());
    if (parts.length == 1) return VersionLabel(resolution: resolution);
    if (parts.length == 2) {
      return VersionLabel(resolution: resolution, fileName: parts[1].trim());
    }
    return VersionLabel(
      resolution: resolution,
      codec: parts[1].trim(),
      fileName: parts.skip(2).join(' · ').trim(),
    );
  }

  /// « 1920 × 1080 » devient « 1080p » et la hauteur UHD « 4K » ; tout le reste
  /// (« 1080p », « Qualité inconnue ») passe tel quel.
  static String _shortResolution(String raw) {
    final match = RegExp(r'^\d+\s*[×x]\s*(\d+)$').firstMatch(raw);
    if (match == null) return raw;
    final height = int.parse(match.group(1)!);
    return height >= 2000 ? '4K' : '${height}p';
  }

  final String resolution;
  final String? codec;
  final String? fileName;

  /// Le texte de la capsule : « 4K · HEVC ».
  String get short => codec == null || codec!.isEmpty
      ? resolution
      : '$resolution · $codec';

  /// Le sous-titre d'une ligne du menu : codec et fichier, quand on les a.
  String? get detail {
    final parts = [
      if (codec != null && codec!.isNotEmpty) codec!,
      if (fileName != null && fileName!.isNotEmpty) fileName!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Le choix d'une version : un libellé « Version » et une capsule qui ouvre
/// un [OnyxMenuButton] (ADR-0130). Sur un téléviseur, l'ancienne liste
/// déroulante de Material reste en place.
class VersionPicker extends StatelessWidget {
  const VersionPicker({
    super.key,
    required this.versions,
    required this.selectedId,
    required this.onSelected,
    this.helperText,
  });

  final List<MediaVersion> versions;
  final int? selectedId;
  final ValueChanged<MediaVersion> onSelected;
  final String? helperText;

  MediaVersion? get _selected {
    for (final v in versions) {
      if (v.item.media.id == selectedId) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (TvScope.of(context)) return _tvDropdown();
    final selected = _selected ?? versions.first;
    final helper = helperText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              tr('Version'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppType.subhead,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: OnyxMenuButton<int>(
                tooltip: tr('Version'),
                items: [
                  for (final v in versions)
                    OnyxMenuItem<int>(
                      value: v.item.media.id,
                      label: VersionLabel.parse(v.label).resolution,
                      subtitle: VersionLabel.parse(v.label).detail,
                      checked: v.item.media.id == selected.item.media.id,
                    ),
                ],
                onSelected: (id) =>
                    onSelected(versions.firstWhere((v) => v.item.media.id == id)),
                child: _Capsule(text: VersionLabel.parse(selected.label).short),
              ),
            ),
          ],
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              helper,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: AppType.footnote,
              ),
            ),
          ),
      ],
    );
  }

  Widget _tvDropdown() {
    return DropdownButtonFormField<int>(
      key: ValueKey(selectedId),
      initialValue: selectedId,
      isExpanded: true,
      decoration: InputDecoration(labelText: tr('Version'), helperText: helperText),
      items: [
        for (final v in versions)
          DropdownMenuItem(
            value: v.item.media.id,
            child: Text(v.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (id) {
        if (id != null) {
          onSelected(versions.firstWhere((v) => v.item.media.id == id));
        }
      },
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppType.body,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(AppIcons.expand, size: 16, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
