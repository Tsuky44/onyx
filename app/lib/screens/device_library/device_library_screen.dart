import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/device_video.dart';
import '../../navigation/search_route_observer.dart';
import '../../services/device_library/device_library.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../utils/responsive.dart';
import '../../widgets/global/empty_state.dart';
import '../player/player_screen.dart';
import 'device_video_row.dart';

/// Ouvre la bibliothèque de l'appareil, depuis n'importe quel écran.
void openDeviceLibrary(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => const DeviceLibraryScreen(),
  ));
}

/// Les vidéos personnelles de l'appareil : les dossiers suivis et ce qu'ils
/// contiennent, lisibles sans compte ni serveur (ADR-0104).
class DeviceLibraryScreen extends StatefulWidget {
  const DeviceLibraryScreen({super.key, this.library});

  /// Pour les tests ; l'instance de l'app sinon.
  final DeviceLibrary? library;

  @override
  State<DeviceLibraryScreen> createState() => _DeviceLibraryScreenState();
}

class _DeviceLibraryScreenState extends State<DeviceLibraryScreen>
    with WidgetsBindingObserver {
  DeviceLibrary get _library => widget.library ?? DeviceLibrary.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _library.addListener(_rebuild);
    // Le scan d'ouverture tient lieu de suivi sur mobile, où le système ne
    // prévient pas d'un fichier arrivé dans le stockage partagé.
    unawaited(_library.initialize().then((_) => _library.rescan()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _library.removeListener(_rebuild);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Revenir de l'app Fichiers ou de l'appareil photo avec une vidéo de plus.
    if (state == AppLifecycleState.resumed) unawaited(_library.rescan());
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.error : null,
    ));
  }

  Future<void> _addFolder() async {
    final String? path;
    try {
      path = await FilePicker.getDirectoryPath(
        dialogTitle: tr('Choisir un dossier de vidéos'),
      );
    } catch (e) {
      _toast(tr('Le sélecteur de dossier n’a pas pu s’ouvrir.'), error: true);
      return;
    }
    if (path == null) return;
    if (!await _library.addFolder(path)) {
      _toast(tr('Ce dossier n’est pas lisible : autorisez l’accès aux vidéos.'),
          error: true);
    }
  }

  Future<void> _importFiles() async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          for (final ext in kDeviceVideoExtensions) ext.substring(1),
        ],
      );
    } catch (e) {
      _toast(tr('Le sélecteur de fichiers n’a pas pu s’ouvrir.'), error: true);
      return;
    }
    final paths = [
      for (final file in picked)
        if (file.path != null) file.path!,
    ];
    if (paths.isEmpty) return;
    final count = await _library.importFiles(paths);
    if (count == 0) _toast(tr('Aucune vidéo n’a pu être importée.'), error: true);
  }

  Future<void> _confirmRemoveFolder(String folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Ne plus suivre ce dossier ?')),
        content: Text(tr('Les fichiers restent où ils sont ; seules leurs '
            'vidéos disparaissent de cette liste.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Ne plus suivre')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _library.removeFolder(folder);
  }

  Future<void> _confirmDelete(DeviceVideo video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Supprimer cette vidéo ?')),
        content: Text(tr('« {0} » sera effacée de l’appareil.', [video.title])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Annuler')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(tr('Supprimer')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _library.deleteVideo(video);
  }

  void _play(DeviceVideo video) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      settings: const RouteSettings(name: SearchRouteObserver.playerRouteName),
      builder: (_) => PlayerScreen(media: video.toHomeMediaItem()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final library = _library;
    final pad = AppLayout.pagePadding(context);
    final videos = library.videos;
    final app = library.appFolder;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(tr('Vidéos de cet appareil')),
        actions: [
          if (library.isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: tr('Actualiser'),
              icon: const Icon(AppIcons.refresh),
              onPressed: library.rescan,
            ),
          if (library.canImportFiles)
            IconButton(
              tooltip: tr('Importer des vidéos'),
              icon: const Icon(AppIcons.add),
              onPressed: _importFiles,
            ),
          if (library.canPickFolders)
            IconButton(
              tooltip: tr('Ajouter un dossier'),
              icon: const Icon(AppIcons.add),
              onPressed: _addFolder,
            ),
        ],
      ),
      body: !library.isSupported
          ? EmptyStateView(
              icon: AppIcons.folder,
              title: tr('Indisponible ici'),
              message: tr('Cet appareil n’a pas de dossier de vidéos à '
                  'parcourir.'),
            )
          : CustomScrollView(
              scrollCacheExtent: AppLayout.imageCacheExtent(context),
              slivers: [
                if (library.folders.isNotEmpty || app != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 8, pad, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (app != null)
                            Chip(
                              avatar: const Icon(AppIcons.folder, size: 16),
                              label: Text(tr('Dossier Onyx (app Fichiers)')),
                            ),
                          for (final folder in library.folders)
                            InputChip(
                              avatar: const Icon(AppIcons.folder, size: 16),
                              label: Text(folder, overflow: TextOverflow.ellipsis),
                              onDeleted: () => _confirmRemoveFolder(folder),
                              deleteButtonTooltipMessage: tr('Ne plus suivre'),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (videos.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: library.isScanning
                        ? const Center(child: CircularProgressIndicator())
                        : EmptyStateView(
                            icon: AppIcons.movie,
                            title: tr('Aucune vidéo'),
                            message: library.canImportFiles
                                ? tr('Importez des vidéos depuis l’app Fichiers, '
                                    'ou déposez-les dans le dossier Onyx depuis '
                                    'le Finder ou l’app Fichiers.')
                                : tr('Ajoutez un dossier de l’appareil : ses '
                                    'vidéos apparaîtront ici et se liront sans '
                                    'serveur.'),
                            actionLabel: library.canImportFiles
                                ? tr('Importer des vidéos')
                                : tr('Ajouter un dossier'),
                            actionIcon: AppIcons.add,
                            onAction: library.canImportFiles
                                ? _importFiles
                                : _addFolder,
                          ),
                  )
                else
                  SliverList.builder(
                    itemCount: videos.length,
                    itemBuilder: (context, index) {
                      final video = videos[index];
                      final previous = index > 0 ? videos[index - 1] : null;
                      final startsGroup = previous == null ||
                          previous.folder != video.folder ||
                          previous.subfolder != video.subfolder;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (startsGroup)
                            Padding(
                              padding: EdgeInsets.fromLTRB(pad, 20, pad, 4),
                              child: Text(
                                _groupLabel(video, app),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppType.subhead,
                                ),
                              ),
                            ),
                          DeviceVideoRow(
                            video: video,
                            onPlay: () => _play(video),
                            onDelete: app != null && video.folder == app
                                ? () => _confirmDelete(video)
                                : null,
                          ),
                        ],
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 48)),
              ],
            ),
    );
  }

  String _groupLabel(DeviceVideo video, String? app) {
    final root = video.folder == app ? tr('Dossier Onyx') : video.folder;
    return video.subfolder.isEmpty ? root : '$root / ${video.subfolder}';
  }
}
