import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/server_account.dart';
import '../../theme/app_colors.dart';
import '../../tv/tv_mode.dart';
import 'server_account_subtitle.dart';

/// Un compte de la liste « Mes serveurs » : son serveur, son état (actif,
/// principal, lié) et le menu de ses options.
class ServerAccountTile extends StatelessWidget {
  const ServerAccountTile({
    super.key,
    required this.account,
    required this.isActive,
    required this.isPrimary,
    required this.busy,
    required this.onSelect,
    required this.onTogglePrimary,
    required this.onRename,
    required this.links,
    required this.onLink,
    required this.onUnlink,
    required this.onForget,
  });

  final ServerAccount account;
  final bool isActive;

  /// Celui sur lequel l'app redémarre, marqué d'une étoile.
  final bool isPrimary;

  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onTogglePrimary;
  final VoidCallback onRename;
  final List<AccountLink> links;
  final VoidCallback? onLink;
  final VoidCallback onUnlink;
  final VoidCallback? onForget;

  @override
  Widget build(BuildContext context) {
    // Le fond est porté par un Material et non par un DecoratedBox : sinon il
    // se peint par-dessus l'onde de la tuile, et toucher un serveur ne donne
    // aucun retour visible — précisément sur le geste dont tout dépend ici.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.10)
            : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          // Sur un téléviseur, le filet bleu du serveur actif se lisait comme
          // l'anneau du focus : deux éléments semblaient focalisés à la fois.
          // La coche et le fond teinté suffisent à le désigner.
          side: BorderSide(
            color: isActive && !TvMode.isTv
                ? AppColors.primary.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: isActive || busy ? null : onSelect,
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.16),
            child: Icon(
              isActive ? Icons.check_rounded : Icons.dns_rounded,
              size: 20,
              color: AppColors.textPrimary,
            ),
          ),
          title: Row(
            children: [
              Flexible(child: Text(account.displayName)),
              if (isPrimary) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
              ],
            ],
          ),
          subtitle: Text(
            serverAccountSubtitle(account,
                isActive: isActive, isPrimary: isPrimary, links: links),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: PopupMenuButton<String>(
            tooltip: tr('Options du compte {0}', [account.username]),
            enabled: !busy,
            onSelected: (value) {
              switch (value) {
                case 'primary':
                  onTogglePrimary();
                case 'link':
                  onLink?.call();
                case 'unlink':
                  onUnlink();
                case 'rename':
                  onRename();
                case 'forget':
                  onForget?.call();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'primary',
                child: Text(isPrimary
                    ? tr('Ne plus démarrer ici')
                    : tr('Démarrer sur ce serveur')),
              ),
              if (onLink != null)
                PopupMenuItem(
                    value: 'link', child: Text(tr('Lier un compte'))),
              if (links.isNotEmpty)
                PopupMenuItem(
                    value: 'unlink', child: Text(tr('Dissocier ce compte'))),
              PopupMenuItem(value: 'rename', child: Text(tr('Renommer'))),
              if (onForget != null)
                PopupMenuItem(
                  value: 'forget',
                  child: Text(tr('Retirer de cet appareil')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
