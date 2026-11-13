import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/server_account.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../tv/nav/tv_focusable.dart';
import '../../tv/nav/tv_region.dart';
import 'profile_disc.dart';

/// Ce que l'on choisit dans le menu du compte.
sealed class AccountMenuChoice {
  const AccountMenuChoice();
}

/// Une personne de la rangée de profils.
final class AccountMenuProfile extends AccountMenuChoice {
  const AccountMenuProfile(this.account);
  final ServerAccount account;
}

/// Un autre serveur de cet appareil.
final class AccountMenuServer extends AccountMenuChoice {
  const AccountMenuServer(this.account);
  final ServerAccount account;
}

/// Les lignes du menu qui ne portent pas de compte.
enum AccountMenuAction implements AccountMenuChoice {
  addProfile,
  manageProfiles,
  watchParty,
  settings,
  linkDevice,
  signOut,
}

/// Le contenu du menu du compte : les personnes du serveur en tête, puis les
/// actions.
///
/// Changer de personne était le geste le plus fréquent du menu et demandait
/// deux écrans (« Changer d'utilisateur », puis « Qui regarde ? ») : les
/// pastilles sont maintenant dans le menu, celles de « Qui regarde ? » en
/// petit. Le focus y remplit une ligne de blanc à l'encre noire, comme les
/// boutons du lecteur et le dos des affiches.
class AccountMenuPanel extends StatelessWidget {
  const AccountMenuPanel({
    super.key,
    required this.profiles,
    required this.current,
    required this.serverLabel,
    required this.otherServers,
    required this.canAddProfile,
    required this.canLinkDevice,
    required this.onChoice,
    this.scale = 1,
  });

  /// Les personnes de cet appareil sur le serveur actif, l'actif compris.
  final List<ServerAccount> profiles;
  final ServerAccount? current;

  /// Le serveur actif et le rôle qu'on y a, sous la rangée.
  final String? serverLabel;
  final List<ServerAccount> otherServers;
  final bool canAddProfile;
  final bool canLinkDevice;
  final ValueChanged<AccountMenuChoice> onChoice;

  /// Ce que le menu prend en plus sur un téléviseur, lu de plus loin.
  final double scale;

  /// La largeur du menu, avant [scale].
  static const double width = 296;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    // Au moins une ligne a le focus à l'ouverture : la personne en cours, et
    // à défaut la première ligne.
    final profileFocused = profiles.any((p) => p.id == current?.id);
    return Container(
      width: width * s,
      padding: EdgeInsets.all(10 * s),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18 * s),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 32 * s,
            offset: Offset(0, 12 * s),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profiles.isNotEmpty || canAddProfile) ...[
            SizedBox(height: 6 * s),
            TvRegion.rail(
              entersAtStart: false,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8 * s,
                runSpacing: 10 * s,
                children: [
                  for (final account in profiles)
                    _ProfileChip(
                      account: account,
                      current: account.id == current?.id,
                      scale: s,
                      onSelect: () => onChoice(AccountMenuProfile(account)),
                    ),
                  if (canAddProfile)
                    _AddChip(
                      scale: s,
                      onSelect: () => onChoice(AccountMenuAction.addProfile),
                    ),
                ],
              ),
            ),
          ],
          if (serverLabel != null) ...[
            SizedBox(height: 8 * s),
            Text(
              serverLabel!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: AppType.caption * s,
              ),
            ),
          ],
          _Hairline(scale: s),
          TvRegion.list(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MenuRow(
                  icon: AppIcons.switchUser,
                  label: tr('Gérer les profils'),
                  scale: s,
                  first: !profileFocused,
                  onSelect: () => onChoice(AccountMenuAction.manageProfiles),
                ),
                _MenuRow(
                  icon: AppIcons.watchParty,
                  label: tr('Rejoindre une séance'),
                  scale: s,
                  onSelect: () => onChoice(AccountMenuAction.watchParty),
                ),
                // Un seul serveur n'a pas besoin d'un sélecteur ; à partir
                // de deux, chacun a sa ligne. Voir ADR-0013.
                for (final server in otherServers)
                  _MenuRow(
                    icon: AppIcons.switchServer,
                    label: tr('Passer sur {0}', [server.displayName]),
                    scale: s,
                    onSelect: () => onChoice(AccountMenuServer(server)),
                  ),
                _MenuRow(
                  icon: AppIcons.settings,
                  label: tr('Paramètres'),
                  scale: s,
                  onSelect: () => onChoice(AccountMenuAction.settings),
                ),
                if (canLinkDevice)
                  _MenuRow(
                    icon: AppIcons.scan,
                    label: tr('Connecter un appareil'),
                    scale: s,
                    onSelect: () => onChoice(AccountMenuAction.linkDevice),
                  ),
                _Hairline(scale: s),
                _MenuRow(
                  icon: AppIcons.signOut,
                  label: tr('Se déconnecter'),
                  scale: s,
                  destructive: true,
                  onSelect: () => onChoice(AccountMenuAction.signOut),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: 8 * scale),
        child: Container(height: 1, color: AppColors.glassBorder),
      );
}

/// La taille d'une pastille de la rangée, avant l'échelle du menu.
const double _chipSize = 48;

/// Une personne de la rangée : sa pastille et son nom. Celle en cours porte
/// un liseré blanc et reçoit le focus à l'ouverture.
class _ProfileChip extends StatefulWidget {
  const _ProfileChip({
    required this.account,
    required this.current,
    required this.scale,
    required this.onSelect,
  });

  final ServerAccount account;
  final bool current;
  final double scale;
  final VoidCallback onSelect;

  @override
  State<_ProfileChip> createState() => _ProfileChipState();
}

class _ProfileChipState extends State<_ProfileChip> {
  bool _lit = false;

  @override
  Widget build(BuildContext context) {
    final size = _chipSize * widget.scale;
    final radius = ProfileDisc.radiusFor(size);
    final name = widget.account.username;
    return _ChipFrame(
      caption: name,
      bright: widget.current || _lit,
      scale: widget.scale,
      child: Semantics(
        button: true,
        selected: widget.current,
        label: widget.current
            ? tr('{0}, en cours', [name])
            : tr('Regarder en tant que {0}', [name]),
        excludeSemantics: true,
        child: TvFocusable(
          autofocus: widget.current,
          entry: widget.current,
          borderRadius: radius,
          focusScale: 1.08,
          onSelect: widget.onSelect,
          onFocusChange: (focused) => setState(() => _lit = focused),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _lit = true),
            onExit: (_) => setState(() => _lit = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onSelect,
              child: Container(
                foregroundDecoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: widget.current
                        ? AppColors.textPrimary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ProfileDisc(account: widget.account, size: size),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// « Ajouter » : la pastille vide au bout de la rangée.
class _AddChip extends StatefulWidget {
  const _AddChip({required this.scale, required this.onSelect});

  final double scale;
  final VoidCallback onSelect;

  @override
  State<_AddChip> createState() => _AddChipState();
}

class _AddChipState extends State<_AddChip> {
  bool _lit = false;

  @override
  Widget build(BuildContext context) {
    final size = _chipSize * widget.scale;
    final radius = ProfileDisc.radiusFor(size);
    final label = tr('Ajouter');
    return _ChipFrame(
      caption: label,
      bright: _lit,
      scale: widget.scale,
      child: Semantics(
        button: true,
        label: tr('Ajouter un profil'),
        excludeSemantics: true,
        child: TvFocusable(
          borderRadius: radius,
          focusScale: 1.08,
          onSelect: widget.onSelect,
          onFocusChange: (focused) => setState(() => _lit = focused),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _lit = true),
            onExit: (_) => setState(() => _lit = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onSelect,
              child: AnimatedContainer(
                duration: AppMotion.fade(context, AppMotion.micro),
                curve: AppMotion.curve,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: Colors.white.withValues(alpha: _lit ? 0.12 : 0.04),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(
                  AppIcons.add,
                  size: 22 * widget.scale,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Une pastille et son nom dessous, sur une largeur fixe pour que les noms
/// longs ne décalent pas la rangée.
class _ChipFrame extends StatelessWidget {
  const _ChipFrame({
    required this.child,
    required this.caption,
    required this.bright,
    required this.scale,
  });

  final Widget child;
  final String caption;
  final bool bright;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (_chipSize + 8) * scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          SizedBox(height: 6 * scale),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: bright ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: AppType.caption * scale,
              fontWeight: bright ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Une ligne d'action. Le focus et le survol la remplissent de blanc à
/// l'encre noire ; « Se déconnecter » reste rouge, sur fond rouge pâle.
class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.scale,
    required this.onSelect,
    this.first = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final double scale;
  final VoidCallback onSelect;

  /// Reçoit le focus à l'ouverture quand la rangée de profils ne le prend
  /// pas.
  final bool first;
  final bool destructive;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final lit = _focused || _hovered;
    final destructive = widget.destructive;
    final Color background;
    final Color foreground;
    if (destructive) {
      background =
          lit ? AppColors.error.withValues(alpha: 0.16) : Colors.transparent;
      foreground = AppColors.error;
    } else {
      background = lit ? AppColors.textPrimary : Colors.transparent;
      foreground = lit ? AppColors.background : AppColors.textPrimary;
    }
    final fade = AppMotion.fade(context, AppMotion.micro);

    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: TvFocusable(
        autofocus: widget.first,
        entry: widget.first,
        focusScale: 1.0,
        showRing: false,
        borderRadius: BorderRadius.circular(10 * s),
        onSelect: widget.onSelect,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelect,
            child: AnimatedContainer(
              duration: fade,
              curve: AppMotion.curve,
              height: 40 * s,
              padding: EdgeInsets.symmetric(horizontal: 10 * s),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(10 * s),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 18 * s,
                    color: lit || destructive
                        ? foreground
                        : AppColors.textSecondary,
                  ),
                  SizedBox(width: 12 * s),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: AppType.body * s,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
