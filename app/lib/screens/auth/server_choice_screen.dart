import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/server_account.dart';
import '../../services/server_registry.dart';
import '../../tv/nav/tv_region.dart';
import '../../tv/tv_mode.dart';
import '../../utils/responsive.dart';
import '../settings/servers_screen.dart';
import 'widgets/server_choice_card.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/server_reachability.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../../utils/on_screen.dart';
import '../../l10n/tr.dart';

/// Ce que l'app affiche quand le serveur principal ne répond pas au lancement.
///
/// Elle pourrait se rabattre toute seule sur un autre compte, ou ouvrir une
/// session hors ligne sans rien dire. Les deux sont des choix qu'elle n'a pas
/// à faire : désigner un serveur principal, c'est précisément dire « c'est
/// celui-là que je veux » — donc son absence se constate, elle ne se contourne
/// pas en silence. Voir ADR-0013 pour le carnet de comptes.
class ServerChoiceScreen extends StatefulWidget {
  const ServerChoiceScreen({super.key});

  @override
  State<ServerChoiceScreen> createState() => _ServerChoiceScreenState();
}

class _ServerChoiceScreenState extends State<ServerChoiceScreen>
    with OnScreenState<ServerChoiceScreen> {
  /// Y a-t-il un profil en cache pour le principal ? Sans lui, « continuer
  /// hors ligne » ne mènerait qu'à l'écran de connexion : autant ne pas le
  /// proposer.
  bool _canGoOffline = false;

  /// Guette le retour du principal tant que la question est à l'écran.
  ///
  /// [ServerReachability] ne prévient que sur une *transition* hors ligne →
  /// en ligne. Quand seule la requête de profil du lancement a échoué et que
  /// le ping, lui, est passé, il n'y a jamais eu de transition : sans ce
  /// guet, l'écran restait affiché devant un serveur qui répond.
  Timer? _watch;

  @override
  void initState() {
    super.initState();
    _lookForCachedProfile();
  }

  @override
  void didChangeOnScreen(bool onScreen) {
    _watch?.cancel();
    _watch = onScreen
        ? Timer.periodic(
            const Duration(seconds: 3),
            (_) => _retryIfPrimaryIsBack(),
          )
        : null;
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  /// Le ping d'abord : il est court et ne touche à rien, alors que la vraie
  /// tentative grise les boutons le temps d'un délai de connexion.
  Future<void> _retryIfPrimaryIsBack() async {
    final auth = context.read<AuthProvider>();
    final reachability = context.read<ServerReachability>();
    if (auth.isLoading) return;
    if (!await reachability.check() || auth.isLoading) return;
    await auth.retryPrimaryServer();
  }

  Future<void> _lookForCachedProfile() async {
    final cached = await context.read<ApiClient>().readCachedProfile();
    if (!mounted || cached == null) return;
    setState(() => _canGoOffline = true);
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  Future<void> _retry() async {
    final auth = context.read<AuthProvider>();
    final primary = auth.unreachablePrimary;
    if (await auth.retryPrimaryServer() || !mounted) return;
    _toast(
      tr('{0} ne répond toujours pas.', [
        primary?.displayName ?? tr('Le serveur principal'),
      ]),
      error: true,
    );
  }

  Future<void> _switchTo(ServerAccount account) async {
    final auth = context.read<AuthProvider>();
    if (await auth.switchServer(account.id) || !mounted) return;
    _toast(auth.errorMessage ?? tr('Bascule impossible.'), error: true);
  }

  Future<void> _stayOffline() async {
    final auth = context.read<AuthProvider>();
    if (await auth.continueOfflineOnPrimary() || !mounted) return;
    _toast(
      tr('Rien n’a été gardé de ce serveur : reconnectez-vous.'),
      error: true,
    );
  }

  /// Le serveur retenu, par son compte. Nul tant que rien n'a été touché : on
  /// retombe alors sur le premier, pour que « Continuer » ait toujours un nom.
  String? _selectedId;

  /// Un serveur par carte : deux personnes du même serveur n'en font qu'un, et
  /// le principal, qui ne répond pas, n'est pas à proposer.
  List<ServerAccount> _candidates(AuthProvider auth) {
    final primary = auth.unreachablePrimary;
    final result = <ServerAccount>[];
    for (final account in auth.servers) {
      if (account.id == primary?.id) continue;
      if (primary != null && ServerRegistry.sameServer(primary, account)) {
        continue;
      }
      if (result.any((kept) => ServerRegistry.sameServer(kept, account))) {
        continue;
      }
      result.add(account);
    }
    return result;
  }

  Future<void> _addServer() async {
    await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const AddServerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    // La télévision garde l'écran en liste : sa refonte est à part.
    if (TvScope.of(context)) return _buildTv(context);
    return _buildCards(context);
  }

  Widget _buildCards(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final primary = auth.unreachablePrimary;
    final servers = _candidates(auth);
    final compact = AppLayout.isCompact(context);
    final size = compact ? 92.0 : 120.0;
    final busy = auth.isLoading;
    ServerAccount? chosen;
    for (final account in servers) {
      if (account.id == _selectedId) chosen = account;
    }
    chosen ??= servers.isEmpty ? null : servers.first;
    final registry = auth.apiClient.servers;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('Quel serveur ?'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: AppType.choiceTitle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('{0} ne répond pas.', [
                      primary?.displayName ?? tr('Votre serveur'),
                    ]),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppType.body,
                    ),
                  ),
                  SizedBox(height: compact ? 28 : 40),
                  TvRegion.rail(
                    entersAtStart: false,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      spacing: compact ? 12 : 24,
                      runSpacing: compact ? 20 : 28,
                      children: [
                        for (final (index, account) in servers.indexed)
                          ServerChoiceCard(
                            account: account,
                            size: size,
                            selected: account.id == chosen?.id,
                            enabled: !busy,
                            autofocus: index == 0,
                            status: _statusOf(registry, account),
                            onSelect: () =>
                                setState(() => _selectedId = account.id),
                          ),
                        AddServerCard(
                          size: size,
                          enabled: !busy,
                          onSelect: _addServer,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 32 : 44),
                  if (chosen != null)
                    _ContinueButton(
                      label: tr('Continuer sur {0}', [chosen.displayName]),
                      onPressed: busy ? null : () => _switchTo(chosen!),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton(
                        onPressed: busy ? null : _retry,
                        child: Text(busy ? tr('Connexion…') : tr('Réessayer')),
                      ),
                      if (_canGoOffline)
                        TextButton(
                          onPressed: busy ? null : _stayOffline,
                          child: Text(tr('Continuer hors ligne')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Le nombre de profils sur ce serveur, seule information déjà connue ici.
  String? _statusOf(ServerRegistry registry, ServerAccount account) {
    final count = registry.usersOf(account.id).length;
    if (count < 1) return null;
    return count == 1 ? tr('1 profil') : tr('{0} profils', [count]);
  }

  Widget _buildTv(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final primary = auth.unreachablePrimary;
    final others = [
      for (final account in auth.servers)
        if (account.id != primary?.id) account,
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 52,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 20),
                Text(
                  tr('Serveur principal non disponible'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    '{0} ne répond pas. Voulez-vous basculer sur un autre '
                    'de vos serveurs ?',
                    [primary?.displayName ?? tr('Votre serveur')],
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppType.body,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                for (final account in others)
                  _ChoiceTile(
                    account: account,
                    busy: auth.isLoading,
                    onSelect: () => _switchTo(account),
                  ),
                if (others.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      tr('Aucun autre serveur n’est ouvert sur cet appareil.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: AppType.subhead,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: auth.isLoading ? null : _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    auth.isLoading ? tr('Connexion…') : tr('Réessayer'),
                  ),
                ),
                if (_canGoOffline) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: auth.isLoading ? null : _stayOffline,
                    child: Text(tr('Continuer hors ligne')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un serveur sur lequel basculer. Volontairement de la même famille que les
/// tuiles de l'écran des serveurs : c'est le même geste.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.account,
    required this.busy,
    required this.onSelect,
  });

  final ServerAccount account;
  final bool busy;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: busy ? null : onSelect,
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.16),
            child: const Icon(
              Icons.dns_rounded,
              size: 20,
              color: AppColors.textPrimary,
            ),
          ),
          title: Text(account.displayName),
          subtitle: Text(
            '${account.username} · ${account.prettyHost}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }
}

/// L'unique action pleine de l'écran : une capsule blanche.
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.textPrimary,
        foregroundColor: AppColors.background,
        disabledBackgroundColor: AppColors.textPrimary.withValues(alpha: 0.4),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        textStyle: const TextStyle(
            fontSize: AppType.callout, fontWeight: FontWeight.w600),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
