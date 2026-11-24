import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../providers/library_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_deferred_keyboard.dart';
import 'settings_ui.dart';
import '../../../widgets/global/onyx_dialog.dart';
import '../../../theme/app_icons.dart';
import 'folder_picker.dart';

/// Ce qu'un administrateur a saisi pour une bibliothèque.
typedef LibraryDraft = ({String name, LibraryKind kind, String path});

/// Ouvre le formulaire d'une bibliothèque : création quand [library] est null,
/// modification sinon. [onSubmit] envoie la saisie au serveur ; tant qu'il
/// échoue le formulaire reste ouvert avec la raison que le serveur donne (un
/// dossier introuvable, déjà pris…), au lieu de se fermer sur une saisie
/// perdue. Rend vrai quand la bibliothèque est enregistrée.
///
/// À la création, [loadFolders] donne les dossiers que le serveur voit sous
/// son point de montage : le premier préremplit le formulaire, les autres se
/// proposent d'un geste (ADR-0155). Quand [browse] est donné et que le serveur
/// sait explorer ses dossiers, le chemin se choisit dans l'explorateur
/// ([FolderPicker], ADR-0165) et la saisie à la main passe sous « Avancé » ; un
/// serveur plus ancien garde le formulaire d'avant.
Future<bool> showLibraryEditor(
  BuildContext context, {
  MediaLibrary? library,
  required Future<void> Function(LibraryDraft draft) onSubmit,
  Future<LibraryFolders> Function()? loadFolders,
  FolderLoader? browse,
}) async {
  final saved = await showOnyxDialog<bool>(
    context: context,
    builder: (_) => LibraryEditorDialog(
      library: library,
      onSubmit: onSubmit,
      loadFolders: loadFolders,
      browse: browse,
    ),
  );
  return saved == true;
}

/// Le formulaire d'une nouvelle bibliothèque, branché sur le serveur : celui des
/// Paramètres et de l'assistant de première installation (ADR-0165). Rend vrai
/// quand la bibliothèque est créée (le serveur lance alors son analyse).
Future<bool> showNewLibraryEditor(
  BuildContext context,
  LibraryProvider provider,
) {
  return showLibraryEditor(
    context,
    onSubmit: (draft) => provider.createLibrary(
        name: draft.name, kind: draft.kind, path: draft.path),
    loadFolders: provider.apiClient.getLibraryFolders,
    browse: (path) => provider.apiClient.browseFolders(path: path),
  );
}

@visibleForTesting
class LibraryEditorDialog extends StatefulWidget {
  const LibraryEditorDialog({
    super.key,
    required this.library,
    required this.onSubmit,
    this.loadFolders,
    this.browse,
  });

  final MediaLibrary? library;
  final Future<void> Function(LibraryDraft draft) onSubmit;
  final Future<LibraryFolders> Function()? loadFolders;
  final FolderLoader? browse;

  @override
  State<LibraryEditorDialog> createState() => _LibraryEditorDialogState();
}

class _LibraryEditorDialogState extends State<LibraryEditorDialog> {
  late final _name = TextEditingController(text: widget.library?.name ?? '');
  late final _path = TextEditingController(text: widget.library?.path ?? '');
  late LibraryKind _kind = widget.library?.kind ?? LibraryKind.movies;
  bool _saving = false;
  String? _error;

  /// Les dossiers libres du serveur, et ce que le formulaire en a repris : un
  /// nom ou un dossier tapé à la main n'est jamais remplacé.
  List<LibraryFolder> _folders = const [];
  String? _suggestedName;
  String? _suggestedPath;

  /// Faux quand le serveur a dit qu'il ne sait pas explorer : le formulaire
  /// d'avant, chemin tapé et pastilles de dossiers libres.
  late bool _browsable = widget.browse != null;

  /// L'explorateur est ouvert : à la création tant qu'aucun dossier n'est
  /// choisi, à la modification quand on demande à changer de dossier.
  late bool _pickerOpen = !_editing;

  bool get _editing => widget.library != null;

  @override
  void initState() {
    super.initState();
    final load = widget.loadFolders;
    // Avec l'explorateur, les pastilles ne servent plus : il montre tout.
    if (!_editing && load != null && !_browsable) _loadFolders(load);
  }

  /// Le serveur ne sait pas explorer : on revient au formulaire d'avant, et on
  /// va chercher les pastilles qu'il pouvait proposer.
  void _browseUnsupported() {
    if (!_browsable) return;
    setState(() => _browsable = false);
    final load = widget.loadFolders;
    if (!_editing && load != null) _loadFolders(load);
  }

  /// Reprend le dossier choisi dans l'explorateur : son chemin, son type deviné
  /// (à la création seulement : le type d'une bibliothèque ne change pas), et
  /// son nom tant que le nom est vide ou vient d'une proposition (ADR-0155).
  void _usePick(FolderPick pick) {
    setState(() {
      final name = _name.text.trim();
      if (name.isEmpty || name == _suggestedName) {
        _name.text = pick.name;
        _suggestedName = pick.name;
      }
      _path.text = pick.path;
      _suggestedPath = pick.path;
      final kind = pick.kind;
      if (kind != null && !_editing) _kind = kind;
      _pickerOpen = false;
      _error = null;
    });
  }

  Future<void> _loadFolders(Future<LibraryFolders> Function() load) async {
    try {
      final found = await load();
      if (!mounted || found.folders.isEmpty) return;
      setState(() {
        _folders = found.folders;
        if (_path.text.trim().isEmpty) _useFolder(found.folders.first);
      });
    } catch (e) {
      // Sans la liste, le formulaire se remplit à la main, comme avant : une
      // erreur ici n'empêche pas de créer la bibliothèque.
      debugPrint('LibraryEditorDialog: dossiers du serveur indisponibles: $e');
    }
  }

  /// Reprend [folder] : son chemin, son type, et son nom tant que le nom est
  /// vide ou vient d'une proposition.
  void _useFolder(LibraryFolder folder) {
    final name = _name.text.trim();
    if (name.isEmpty || name == _suggestedName) {
      _name.text = folder.name;
      _suggestedName = folder.name;
    }
    _path.text = folder.path;
    _suggestedPath = folder.path;
    _kind = folder.kind;
  }

  /// Un autre type choisi : tant que le dossier vient d'une proposition, il
  /// suit, vers le premier dossier libre de ce type.
  void _chooseKind(LibraryKind kind) {
    setState(() {
      _kind = kind;
      if (_path.text.trim() != _suggestedPath) return;
      for (final folder in _folders) {
        if (folder.kind == kind) {
          _useFolder(folder);
          return;
        }
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final path = _path.text.trim();
    if (name.isEmpty || path.isEmpty) {
      setState(
        () => _error = tr('Donnez un nom et un dossier à la bibliothèque.'),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit((name: name, kind: _kind, path: path));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = settingsErrorText(e, tr('Échec de l’enregistrement.'));
      });
    }
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    required String hint,
    bool autofocus = false,
    int? maxLength,
  }) {
    return TvDeferredKeyboard(
      builder: (context, focusNode, canRequestFocus) => TextField(
        focusNode: focusNode,
        canRequestFocus: canRequestFocus,
        controller: controller,
        autofocus: autofocus,
        maxLength: maxLength,
        enabled: !_saving,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
        ),
      ),
    );
  }

  /// Le dossier choisi, l'explorateur quand il est ouvert, et la saisie à la
  /// main repliée sous « Avancé ».
  List<Widget> _browserSection() {
    final chosen = _path.text.trim();
    return [
      Text(
        tr('Dossier'),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: AppType.subhead,
        ),
      ),
      const SizedBox(height: 8),
      if (chosen.isNotEmpty && !_pickerOpen)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_outlined),
          title: Text(chosen, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: TextButton(
            onPressed:
                _saving ? null : () => setState(() => _pickerOpen = true),
            child: Text(tr('Changer')),
          ),
        ),
      if (_pickerOpen)
        FolderPicker(
          loadFolder: widget.browse!,
          initialPath: chosen.isEmpty ? null : chosen,
          enabled: !_saving,
          onChoose: _usePick,
          onUnsupported: _browseUnsupported,
        ),
      Theme(
        // Pas de filet haut et bas autour du repli.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            tr('Avancé : saisir le chemin à la main'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppType.footnote,
            ),
          ),
          children: [
            _field(
              _path,
              label: tr('Dossier'),
              hint: tr('Chemin complet sur le serveur'),
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return OnyxDialog(
      title: _editing
          ? tr('Modifier la bibliothèque')
          : tr('Nouvelle bibliothèque'),
      icon: AppIcons.folder,
      width: 440,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            _name,
            label: tr('Nom'),
            hint: tr('Le nom affiché dans l’app'),
            autofocus: !_editing,
            // La limite du serveur : un nom s'affiche dans un onglet.
            maxLength: 40,
          ),
          const SizedBox(height: 14),
          if (_browsable) ..._browserSection() else ...[
            _field(
              _path,
              label: tr('Dossier'),
              hint: tr('Chemin complet sur le serveur'),
            ),
            if (_folders.isNotEmpty) ...[
              const SizedBox(height: 10),
              _FolderChoices(
                folders: _folders,
                path: _path,
                enabled: !_saving,
                onChoose: (folder) => setState(() => _useFolder(folder)),
              ),
            ],
          ],
          const SizedBox(height: 6),
          Text(
            tr(
              'Le dossier tel que le serveur le voit (dans son conteneur). '
              'Un dossier ne sert qu’à une bibliothèque.',
            ),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppType.footnote,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            tr('Contenu du dossier'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppType.subhead,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<LibraryKind>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: LibraryKind.movies,
                label: Text(tr('Films')),
              ),
              ButtonSegment(
                value: LibraryKind.shows,
                label: Text(tr('Séries')),
              ),
              ButtonSegment(value: LibraryKind.other, label: Text(tr('Autre'))),
            ],
            selected: {_kind},
            // Des fiches lues comme des films ne deviennent pas des
            // épisodes : le type se choisit à la création.
            onSelectionChanged: _editing || _saving
                ? null
                : (choice) => _chooseKind(choice.first),
          ),
          const SizedBox(height: 8),
          // Ce que le choix change, dit là où il se fait : le serveur va
          // chercher des affiches pour les deux premiers, pas pour « Autre ».
          Text(
            switch (_kind) {
              LibraryKind.movies => tr(
                'Chaque fichier est un film : le '
                'serveur cherche son affiche et sa fiche.',
              ),
              LibraryKind.shows => tr(
                'Les fichiers sont des épisodes, '
                'regroupés par série et par saison.',
              ),
              LibraryKind.other => tr(
                'Vidéos personnelles, concerts, '
                'cours… Chaque vidéo garde le nom de son fichier, sans '
                'recherche d’affiche ni de fiche.',
              ),
            },
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppType.footnote,
              height: 1.4,
            ),
          ),
          if (_editing) ...[
            const SizedBox(height: 6),
            Text(
              tr(
                'Le contenu ne se change pas : supprimez la bibliothèque '
                'et recréez-la.',
              ),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppType.footnote,
                height: 1.4,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            SettingsBanner(_error!, tone: BannerTone.error),
          ],
        ],
      ),
      actions: [
        OnyxDialogAction(
          label: tr('Annuler'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        OnyxDialogAction(
          label: _saving ? tr('Enregistrement…') : tr('Enregistrer'),
          primary: true,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}

/// Les dossiers que le serveur a trouvés, en pastilles : celle du dossier
/// saisi est cochée, et en toucher une remplit le formulaire avec.
class _FolderChoices extends StatelessWidget {
  const _FolderChoices({
    required this.folders,
    required this.path,
    required this.enabled,
    required this.onChoose,
  });

  final List<LibraryFolder> folders;
  final TextEditingController path;
  final bool enabled;
  final ValueChanged<LibraryFolder> onChoose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Dossiers trouvés sur le serveur'),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppType.footnote,
          ),
        ),
        const SizedBox(height: 6),
        // Le dossier tapé à la main décoche la pastille sans reconstruire
        // tout le formulaire.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: path,
          builder: (context, value, _) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final folder in folders)
                Tooltip(
                  message: folder.path,
                  child: ChoiceChip(
                    label: Text(folder.name),
                    selected: value.text.trim() == folder.path,
                    showCheckmark: false,
                    onSelected: enabled ? (_) => onChoose(folder) : null,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
