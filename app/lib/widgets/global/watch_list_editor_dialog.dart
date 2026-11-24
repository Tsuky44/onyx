import 'package:material_ui/material_ui.dart';

import '../../l10n/tr.dart';
import '../../models/watch_list.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_deferred_keyboard.dart';
import 'list_visibility_choice.dart';
import 'onyx_dialog.dart';

/// Ce que la boîte de dialogue rend : le nom, la description et le partage.
typedef WatchListDraft = ({String name, String description, bool isShared});

/// Crée une liste, ou modifie [existing] (ADR-0070). Null quand on annule.
///
/// « À regarder plus tard » n'a que son partage à régler : son nom est celui
/// de l'app, et le serveur ignorerait un autre.
Future<WatchListDraft?> showWatchListEditor(
  BuildContext context, {
  WatchList? existing,
}) {
  return showOnyxDialog<WatchListDraft>(
    context: context,
    builder: (_) => _WatchListEditor(existing: existing),
  );
}

class _WatchListEditor extends StatefulWidget {
  const _WatchListEditor({this.existing});

  final WatchList? existing;

  @override
  State<_WatchListEditor> createState() => _WatchListEditorState();
}

class _WatchListEditorState extends State<_WatchListEditor> {
  // Les bornes du serveur (server/watchlists) : au-delà, il refuserait.
  static const _maxName = 80;
  static const _maxDescription = 500;

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late bool _isShared = widget.existing?.isShared ?? false;

  bool get _fixedName => widget.existing?.isWatchLater ?? false;
  bool get _canSave => _fixedName || _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop((
      name: _fixedName ? widget.existing!.name : _name.text.trim(),
      description:
          _fixedName ? widget.existing!.description : _description.text.trim(),
      isShared: _isShared,
    ));
  }

  /// Le compteur d'un champ, à droite dans le champ : on voit la borne avant
  /// de la buter.
  static Widget _counter(TextEditingController c, int max) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: c,
          builder: (_, value, __) => Text(
            '${value.text.characters.length} / $max',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: AppType.footnote),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    // Le partage d'une liste qui existe se règle dans « Partager » (ADR-0161) ;
    // seule la création, et « À regarder plus tard » qui n'a que lui, le
    // demandent ici.
    final askVisibility = existing == null || _fixedName;
    return OnyxDialog(
      icon: existing == null ? AppIcons.add : AppIcons.edit,
      title: existing == null
          ? tr('Nouvelle liste')
          : _fixedName
              ? existing.displayName
              : tr('Modifier la liste'),
      width: 460,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_fixedName) ...[
            // L'étiquette du champ monte sur son bord : de l'air sous le titre.
            const SizedBox(height: 10),
            TvDeferredKeyboard(
              builder: (context, focusNode, canRequestFocus) => TextField(
                controller: _name,
                focusNode: focusNode,
                canRequestFocus: canRequestFocus,
                autofocus: existing == null,
                maxLength: _maxName,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: tr('Nom'),
                  hintText: tr('Mes recommandations'),
                  counterText: '',
                  suffixIcon: _counter(_name, _maxName),
                  suffixIconConstraints:
                      const BoxConstraints(minWidth: 0, minHeight: 0),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TvDeferredKeyboard(
              builder: (context, focusNode, canRequestFocus) => TextField(
                controller: _description,
                focusNode: focusNode,
                canRequestFocus: canRequestFocus,
                maxLength: _maxDescription,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: tr('Description (facultative)'),
                  alignLabelWithHint: true,
                  counterText: '',
                ),
              ),
            ),
          ],
          if (askVisibility) ...[
            if (!_fixedName) const SizedBox(height: 18),
            Text(
              tr('Qui peut la voir').toUpperCase(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppType.caption,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            ListVisibilityChoice(
              shared: _isShared,
              autofocus: _fixedName,
              onChanged: (v) => setState(() => _isShared = v),
            ),
          ],
        ],
      ),
      actions: [
        OnyxDialogAction(
          label: tr('Annuler'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        OnyxDialogAction(
          label: existing == null ? tr('Créer') : tr('Enregistrer'),
          primary: true,
          onPressed: _canSave ? _save : null,
        ),
      ],
    );
  }
}
