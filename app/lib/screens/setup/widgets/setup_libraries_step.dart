import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/setup_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../settings/widgets/library_editor_dialog.dart';
import '../../settings/widgets/settings_ui.dart';

/// Étape 1 : les bibliothèques. Une bibliothèque, c'est un dossier de films ou
/// de séries du serveur ; on les ajoute avec l'explorateur de dossiers, ou tout
/// d'un coup avec « Ajouter tous les dossiers trouvés ». Le serveur analyse
/// chaque dossier dès qu'il est créé, pendant qu'on règle la suite (ADR-0165).
class SetupLibrariesStep extends StatefulWidget {
  const SetupLibrariesStep({super.key});

  @override
  State<SetupLibrariesStep> createState() => _SetupLibrariesStepState();
}

class _SetupLibrariesStepState extends State<SetupLibrariesStep> {
  /// Les dossiers que le serveur voit sous son point de montage et qu'aucune
  /// bibliothèque n'a encore.
  LibraryFolders _found = LibraryFolders.none;
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LibraryProvider>().loadLibraries();
      _loadFolders();
    });
  }

  Future<void> _loadFolders() async {
    try {
      final found =
          await context.read<LibraryProvider>().apiClient.getLibraryFolders();
      if (mounted) setState(() => _found = found);
    } catch (e) {
      // Sans la liste, le raccourci n'est simplement pas proposé : on ajoute
      // les dossiers un par un.
      debugPrint('SetupLibrariesStep: dossiers du serveur indisponibles: $e');
    }
  }

  Future<void> _addOne() async {
    final provider = context.read<LibraryProvider>();
    final saved = await showNewLibraryEditor(context, provider);
    if (!saved || !mounted) return;
    await _refresh();
  }

  /// Un geste pour tous les dossiers libres : chacun devient une bibliothèque
  /// du nom et du type que le serveur lui a devinés (ADR-0155).
  Future<void> _addAll() async {
    final provider = context.read<LibraryProvider>();
    final folders = List<LibraryFolder>.of(_found.folders);
    setState(() {
      _adding = true;
      _error = null;
    });
    var failed = 0;
    for (final folder in folders) {
      try {
        await provider.createLibrary(
            name: folder.name, kind: folder.kind, path: folder.path);
      } catch (e) {
        failed++;
        debugPrint('SetupLibrariesStep: ${folder.path} refusé: $e');
        _error = settingsErrorText(e, tr('Échec de l’enregistrement.'));
      }
    }
    if (!mounted) return;
    if (failed == 0) _error = null;
    await _refresh();
    if (mounted) setState(() => _adding = false);
  }

  Future<void> _refresh() async {
    await _loadFolders();
    if (mounted) await context.read<SetupProvider>().load();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LibraryProvider>();
    final libraries = [
      for (final library in provider.libraries)
        if (!library.isLegacy) library,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Vos bibliothèques'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          tr('Une bibliothèque, c’est un dossier de films ou de séries de '
              'votre serveur. Onyx l’analyse pour en faire un catalogue avec '
              'affiches et résumés. Vous pouvez en ajouter autant que vous '
              'voulez, et en changer plus tard dans les Paramètres.'),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppType.subhead,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        if (libraries.isNotEmpty) ...[
          SettingsGroup(
            dividerIndent: 64,
            children: [
              for (final library in libraries)
                SettingsTile(
                  icon: switch (library.kind) {
                    LibraryKind.movies => Icons.movie_outlined,
                    LibraryKind.shows => Icons.tv_rounded,
                    LibraryKind.other => Icons.folder_outlined,
                  },
                  title: library.name,
                  subtitle: library.path ?? '',
                  showChevron: false,
                ),
            ],
          ),
          SettingsBanner(
            tr('Le serveur analyse ces dossiers pendant que vous réglez la '
                'suite.'),
          ),
        ] else if (provider.librariesLoaded)
          SettingsBanner(
            tr('Aucune bibliothèque pour l’instant : sans elle, Onyx n’a rien '
                'à montrer.'),
          ),
        if (_error != null)
          SettingsBanner(_error!, tone: BannerTone.error),
        if (_found.folders.isNotEmpty) ...[
          FilledButton.icon(
            onPressed: _adding ? null : _addAll,
            icon: const Icon(Icons.library_add_rounded, size: 18),
            label: Text(_adding
                ? tr('Ajout en cours…')
                : trPlural(
                    _found.folders.length,
                    'Ajouter le dossier trouvé ({0})',
                    'Ajouter tous les dossiers trouvés ({0})',
                  )),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _adding ? null : _addOne,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(tr('Choisir un dossier')),
        ),
      ],
    );
  }
}
