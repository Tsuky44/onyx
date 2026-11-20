import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../providers/home_provider.dart';
import '../../providers/setup_provider.dart';
import '../../theme/app_icons.dart';
import '../../widgets/global/empty_state.dart';
import '../settings/settings_screen.dart';
import '../setup/widgets/setup_home_card.dart';

/// L'accueil d'un serveur qui n'a encore rien à montrer.
///
/// Deux raisons, deux messages. Sans aucune bibliothèque — un serveur neuf
/// n'en a pas (ADR-0058) — il n'y a rien à analyser : on mène l'administrateur
/// là où il déclare ses dossiers. Avec des bibliothèques encore vides, c'est
/// une analyse qu'il reste à lancer.
///
/// Chaque action n'est tendue qu'à qui le serveur la permet (ADR-0001) : aux
/// autres comptes on dit qui peut agir, au lieu d'un bouton qui échoue.
class HomeEmptyView extends StatelessWidget {
  const HomeEmptyView({
    super.key,
    required this.libraries,
    required this.permissions,
    required this.homeProvider,
  });

  /// Les bibliothèques du serveur ; null tant qu'on ne les connaît pas.
  final List<MediaLibrary>? libraries;
  final Permissions permissions;
  final HomeProvider homeProvider;

  @override
  Widget build(BuildContext context) {
    final libraries = this.libraries;
    final setup = Provider.of<SetupProvider?>(context);
    final child = _empty(context, libraries);
    // Des bibliothèques déclarées mais une installation pas finie : la
    // checklist se pose au-dessus du message (ADR-0165). Sans bibliothèque,
    // elle prend la place du message lui-même.
    if (libraries != null &&
        libraries.isNotEmpty &&
        permissions.manageSettings &&
        setup != null &&
        setup.needsSetup) {
      return Column(
        children: [
          const SetupHomeCard(canManage: true),
          Expanded(child: child),
        ],
      );
    }
    return child;
  }

  Widget _empty(BuildContext context, List<MediaLibrary>? libraries) {
    if (libraries != null && libraries.isEmpty) {
      if (!permissions.manageSettings) {
        return EmptyStateView(
          icon: AppIcons.collection,
          title: tr('Aucune bibliothèque'),
          message: tr('L’administrateur de ce serveur n’a pas encore déclaré '
              'de bibliothèque.'),
        );
      }
      // Un serveur dont l'installation n'est pas finie montre sa checklist à la
      // place du simple « Aucune bibliothèque » (ADR-0165).
      final setup = Provider.of<SetupProvider?>(context);
      if (setup != null && setup.needsSetup) {
        return const SetupHomeCard(canManage: true);
      }
      return EmptyStateView(
        icon: AppIcons.collection,
        title: tr('Aucune bibliothèque'),
        message: tr('Choisissez un dossier du serveur et donnez-lui le nom que '
            'vous voulez. Vous pouvez en créer autant que nécessaire.'),
        actionLabel: tr('Ajouter une bibliothèque'),
        actionIcon: AppIcons.add,
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SettingsScreen(
                initialSection: SettingsSections.library),
          ),
        ),
      );
    }

    if (!permissions.manageLibrary) {
      return EmptyStateView(
        icon: AppIcons.collection,
        title: tr('Bibliothèque vide'),
        message: tr('Rien sur ce serveur pour l’instant. Son administrateur '
            'peut en ajouter.'),
      );
    }
    return EmptyStateView(
      icon: AppIcons.collection,
      title: tr('Bibliothèque vide'),
      message: tr('Ajoutez des fichiers dans les dossiers de vos '
          'bibliothèques, puis lancez une synchronisation.'),
      actionLabel: tr('Synchroniser'),
      onAction: homeProvider.triggerLibraryScan,
      secondaryActionLabel: tr('Extraire les sous-titres'),
      onSecondaryAction: homeProvider.triggerSubtitleExtract,
    );
  }
}
