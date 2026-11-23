// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import 'settings_tile.dart';

/// Lit un dossier du serveur ([path] null : la racine). Rend null quand le
/// serveur ne sait pas explorer ses dossiers (un serveur plus ancien).
typedef FolderLoader = Future<FsListing?> Function(String? path);

/// Le dossier que l'on vient de choisir, avec ce que le serveur en a deviné.
/// [kind] est null quand le dossier n'est pas passé sous les yeux du serveur
/// (la racine) : l'appelant garde alors le type qu'il avait.
typedef FolderPick = ({String path, String name, LibraryKind? kind});

/// L'explorateur de dossiers du serveur (ADR-0165) : un fil d'Ariane, les
/// sous-dossiers du dossier ouvert avec le type deviné et le nombre de vidéos,
/// et un bouton pour choisir le dossier ouvert.
///
/// Un seul widget pour l'éditeur de bibliothèque des Paramètres et l'assistant
/// de première installation. Il ne parle pas à `ApiClient` : l'appelant lui
/// passe [loadFolder], ce qui le rend testable avec un faux serveur.
///
/// Sur téléviseur, chaque ligne et chaque miette est une cible de focus du
/// parcours habituel (comme les réglages) : Haut et Bas descendent la liste,
/// OK ouvre un dossier ou choisit celui d'en haut.
class FolderPicker extends StatefulWidget {
  const FolderPicker({
    super.key,
    required this.loadFolder,
    required this.onChoose,
    this.onUnsupported,
    this.initialPath,
    this.enabled = true,
    this.listHeight = 260,
  });

  final FolderLoader loadFolder;
  final ValueChanged<FolderPick> onChoose;

  /// Appelé quand le serveur ne sait pas explorer : l'appelant retombe sur la
  /// saisie à la main.
  final VoidCallback? onUnsupported;

  /// Où l'explorateur s'ouvre ; la racine sinon (ou si ce dossier a disparu).
  final String? initialPath;
  final bool enabled;

  /// La hauteur de la liste : elle défile au-delà, la page autour reste fixe.
  final double listHeight;

  @override
  State<FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<FolderPicker> {
  FsListing? _listing;
  bool _loading = true;
  bool _unsupported = false;
  String? _error;

  /// Un compteur par chargement : la réponse d'un dossier quitté ne remplace
  /// pas celui qu'on regarde (voir `LibraryProvider`).
  int _request = 0;

  /// Tout ce que le serveur a montré, par chemin : choisir le dossier ouvert
  /// retrouve ainsi son type deviné, même après un saut par le fil d'Ariane.
  final Map<String, FsFolder> _seen = {};

  @override
  void initState() {
    super.initState();
    _open(widget.initialPath);
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _open(String? path, {bool fallbackToRoot = true}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await widget.loadFolder(path);
      if (!mounted || request != _request) return;
      if (listing == null) {
        setState(() {
          _loading = false;
          _unsupported = true;
        });
        widget.onUnsupported?.call();
        return;
      }
      for (final folder in listing.folders) {
        _seen[folder.path] = folder;
      }
      setState(() {
        _listing = listing;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      // Un dossier qui a disparu ou qui sort de la racine : on repart de la
      // racine plutôt que de rester sur une erreur.
      if (path != null && fallbackToRoot) {
        await _open(null, fallbackToRoot: false);
        return;
      }
      debugPrint('FolderPicker: dossiers du serveur indisponibles: $e');
      setState(() {
        _loading = false;
        _error = tr('Impossible de lire les dossiers du serveur.');
      });
    }
  }

  void _choose(FsListing listing) {
    final known = _seen[listing.path];
    final crumbs = listing.breadcrumb;
    final name = known?.name ??
        (crumbs.isNotEmpty ? crumbs.last.name : _lastSegment(listing.path));
    widget.onChoose((path: listing.path, name: name, kind: known?.kind));
  }

  static String _lastSegment(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    if (_unsupported) return const SizedBox.shrink();
    final listing = _listing;
    if (listing == null) {
      if (_error != null) {
        return _Message(
          icon: Icons.error_outline_rounded,
          text: _error!,
          action: TextButton(
            onPressed: () => _open(widget.initialPath),
            child: Text(tr('Réessayer')),
          ),
        );
      }
      return SizedBox(
        height: 96,
        child: Center(
          child: Semantics(
            label: tr('Chargement des dossiers'),
            child: const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    final enabled = widget.enabled && !_loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Breadcrumb(
          crumbs: listing.breadcrumb,
          onOpen: enabled ? (path) => _open(path) : null,
        ),
        const SizedBox(height: 8),
        if (listing.emptyRoot)
          _EmptyRootDiagnostic(root: listing.root)
        else if (!listing.readable)
          _Message(
            icon: Icons.lock_outline_rounded,
            text: tr('Le serveur n’a pas le droit de lire ce dossier. '
                'Vérifiez ses droits, ou choisissez-en un autre.'),
          )
        else
          _FolderList(
            listing: listing,
            height: widget.listHeight,
            onOpen: enabled ? (folder) => _open(folder.path) : null,
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
        ],
        const SizedBox(height: 12),
        // Le dossier ouvert est celui qu'on choisit : son chemin est dit sur le
        // bouton, pour ne pas avoir à le deviner du fil d'Ariane.
        FilledButton.icon(
          onPressed: enabled && !listing.emptyRoot && listing.readable
              ? () => _choose(listing)
              : null,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(tr('Choisir ce dossier')),
        ),
        const SizedBox(height: 4),
        Text(
          listing.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppType.footnote,
          ),
        ),
      ],
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.crumbs, required this.onOpen});

  final List<FsCrumb> crumbs;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < crumbs.length; i++) ...[
          if (i > 0)
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textMuted),
          if (i == crumbs.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                crumbs[i].name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            TextButton(
              onPressed: onOpen == null ? null : () => onOpen!(crumbs[i].path),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(crumbs[i].name),
            ),
        ],
      ],
    );
  }
}

class _FolderList extends StatelessWidget {
  const _FolderList({
    required this.listing,
    required this.height,
    required this.onOpen,
  });

  final FsListing listing;
  final double height;
  final ValueChanged<FsFolder>? onOpen;

  @override
  Widget build(BuildContext context) {
    final folders = listing.folders;
    if (folders.isEmpty) {
      return _Message(
        icon: Icons.folder_off_outlined,
        text: tr('Aucun sous-dossier ici. Vous pouvez choisir ce dossier.'),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          return _FolderTile(
            folder: folder,
            onOpen: onOpen == null || folder.covered
                ? null
                : () => onOpen!(folder),
          );
        },
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.onOpen});

  final FsFolder folder;
  final VoidCallback? onOpen;

  /// « Films · 124 vidéos » : le type deviné, puis le compte (« 50+ » quand le
  /// serveur a cessé de compter).
  String _subtitle() {
    if (folder.covered) {
      return tr('Déjà utilisé par une bibliothèque');
    }
    final kind = switch (folder.kind) {
      LibraryKind.movies => tr('Films'),
      LibraryKind.shows => tr('Séries'),
      LibraryKind.other => tr('Autre'),
    };
    if (folder.videoCount == 0) return tr('{0} · aucune vidéo', [kind]);
    final count = folder.videoCountCapped
        ? tr('{0}+ vidéos', [folder.videoCount])
        : trPlural(folder.videoCount, '{0} vidéo', '{0} vidéos');
    return '$kind · $count';
  }

  @override
  Widget build(BuildContext context) {
    final tile = SettingsTile(
      icon: switch (folder.kind) {
        LibraryKind.movies => Icons.movie_outlined,
        LibraryKind.shows => Icons.tv_rounded,
        LibraryKind.other => Icons.folder_outlined,
      },
      title: folder.name,
      subtitle: _subtitle(),
      onTap: onOpen,
      showChevron: !folder.covered,
    );
    // Un dossier déjà pris reste lisible mais n'invite à rien : grisé, sans
    // cible de focus.
    return folder.covered ? Opacity(opacity: 0.45, child: tile) : tile;
  }
}

/// La racine est vide : le serveur ne voit rien parce que rien n'est monté dans
/// son conteneur. Ce n'est pas un problème de bibliothèque, et la ligne à
/// ajouter au compose est dite en clair.
class _EmptyRootDiagnostic extends StatelessWidget {
  const _EmptyRootDiagnostic({required this.root});

  final String root;

  @override
  Widget build(BuildContext context) {
    final mount = root.isEmpty ? '/media' : root;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Aucun média trouvé'),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Aucun média trouvé : montez votre dossier dans le compose. '
                'Ajoutez une ligne comme celle-ci sous « volumes » du service '
                'onyx-server, puis relancez-le.'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppType.footnote,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              '- /chemin/vers/vos/films:$mount/Films:ro',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: AppType.footnote,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Le dossier de gauche est celui de votre machine, celui de '
                'droite est ce que le serveur verra.'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppType.footnote,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppType.footnote,
              height: 1.4,
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
