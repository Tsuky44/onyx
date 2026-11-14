import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/otp.dart';
import '../../models/server_account.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/server_registry.dart';
import '../../services/server_discovery.dart';
import '../../theme/app_colors.dart';
import '../../tv/tv_deferred_keyboard.dart';
import '../../widgets/global/otp_code_dialog.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../widgets/global/onyx_dialog.dart';
import '../../l10n/tr.dart';
import 'servers_support.dart';

/// Ajoute un serveur : soit on y a déjà un compte, soit on demande à y entrer.
///
/// Les deux chemins sont sur le même écran parce que la personne, elle, ne sait
/// pas toujours lequel la concerne avant d'avoir tapé l'adresse.
class AddServerScreen extends StatefulWidget {
  const AddServerScreen({
    super.key,
    this.initialUrl,
    this.initialUsername,
    this.signIn = false,
  });

  /// Pré-remplis quand on vient d'un serveur lié à son compte : il ne reste
  /// que le mot de passe à taper.
  final String? initialUrl;
  final String? initialUsername;
  final bool signIn;

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

enum _AddMode { signIn, request }

class _AddServerScreenState extends State<AddServerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _messageController = TextEditingController();

  late _AddMode _mode = widget.signIn ? _AddMode.signIn : _AddMode.request;
  bool _busy = false;
  bool _discovering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverController.text = widget.initialUrl ?? '';
    _usernameController.text = widget.initialUsername ?? '';
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    if (_discovering) return;
    setState(() => _discovering = true);
    String? found;
    try {
      found = await ServerDiscovery.find();
    } catch (_) {
      found = null;
    }
    if (!mounted) return;
    final address = found;
    setState(() {
      _discovering = false;
      if (address != null) _serverController.text = address;
    });
    if (found == null) _snack(tr('Aucun serveur Onyx trouvé sur ce réseau.'));
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final url = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _busy = true;
      _error = null;
    });

    final previous = auth.activeServer;
    try {
      if (_mode == _AddMode.signIn) {
        final account = await _signIn(auth, url, username, password);
        if (account == null || !mounted) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        _snack(tr('{0} ajouté.', [account.displayName]));
        if (previous != null && !ServerRegistry.sameServer(previous, account)) {
          await _offerLink(previous, account);
        }
      } else {
        await auth.requestAccess(
          serverUrl: url,
          username: username,
          password: password,
          message: _messageController.text.trim(),
        );
        if (!mounted) return;
        _snack(
            tr('Demande envoyée. Vous serez connecté dès qu’elle sera acceptée.'));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = serverErrorText(e);
      });
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Ouvre la session, code compris quand ce serveur en demande un
  /// (ADR-0041). null : le code a été abandonné.
  Future<ServerAccount?> _signIn(
    AuthProvider auth,
    String url,
    String username,
    String password,
  ) async {
    try {
      return await auth.addServerWithPassword(
        serverUrl: url,
        username: username,
        password: password,
      );
    } on OtpRequired catch (e) {
      if (!mounted) return null;
      final api = context.read<ApiClient>();
      final result = await showOtpLoginDialog(
        context,
        challenge: e.challenge,
        verify: (code) => api.verifyLoginOtp(e.challenge, code),
      );
      if (result == null) return null;
      return auth.adoptOtpSession(result);
    }
  }

  /// Juste après l'ajout, le bon moment pour demander si c'est la même
  /// personne : sur un appareil partagé, ce n'est pas toujours le cas, donc
  /// rien n'est lié sans le demander.
  Future<void> _offerLink(ServerAccount previous, ServerAccount added) async {
    final api = context.read<ApiClient>();
    await api.refreshAccountLinks();
    if (!mounted ||
        api.servers.linkedAccounts(previous.id).any((a) => a.id == added.id)) {
      return;
    }
    final link = await showOnyxDialog<bool>(
      context: context,
      builder: (ctx) => OnyxDialog(
        title: tr('Lier à {0} sur {1} ?',
            [previous.username, previous.displayName]),
        icon: AppIcons.link,
        message: tr('Si ces deux comptes sont à vous, vos serveurs se '
            'transmettront votre progression et chacun apparaîtra sur vos '
            'autres appareils. Les administrateurs des deux serveurs '
            'doivent accepter le lien une première fois.'),
        actions: [
          OnyxDialogAction(
            label: tr('Plus tard'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          OnyxDialogAction(
            label: tr('Lier'),
            primary: true,
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (link == true && mounted) {
      await linkAndReport(context, previous.id, added.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requesting = _mode == _AddMode.request;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(tr('Ajouter un serveur'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            SegmentedButton<_AddMode>(
              segments: [
                ButtonSegment(
                  value: _AddMode.request,
                  label: Text(tr('Demander l’accès')),
                  icon: Icon(Icons.doorbell_outlined, size: 18),
                ),
                ButtonSegment(
                  value: _AddMode.signIn,
                  label: Text(tr('J’ai un compte')),
                  icon: Icon(Icons.login_rounded, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (selection) => setState(() => _mode = selection.first),
            ),
            const SizedBox(height: 14),
            Text(
              requesting
                  ? tr('Choisissez l’identifiant et le mot de passe que vous '
                      'aurez sur ce serveur. Le compte n’est créé qu’une '
                      'fois la demande acceptée.')
                  : tr('Entrez les identifiants de votre compte sur ce '
                      'serveur. Votre serveur actuel n’est pas touché.'),
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: AppType.subhead),
            ),
            const SizedBox(height: 20),
            TvDeferredKeyboard(
              builder: (context, focusNode, canRequestFocus) => TextFormField(
                focusNode: focusNode,
                canRequestFocus: canRequestFocus,
                controller: _serverController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: tr('Adresse du serveur'),
                  hintText: 'http://192.168.1.50:8080',
                  prefixIcon: Icon(Icons.dns_rounded),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? tr('Requis') : null,
              ),
            ),
            if (ServerDiscovery.isSupported)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _discovering ? null : _discover,
                  icon: _discovering
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore_rounded, size: 18),
                  label: Text(_discovering
                      ? tr('Recherche…')
                      : tr('Détecter le serveur sur le réseau')),
                ),
              ),
            const SizedBox(height: 12),
            TvDeferredKeyboard(
              builder: (context, focusNode, canRequestFocus) => TextFormField(
                focusNode: focusNode,
                canRequestFocus: canRequestFocus,
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: tr('Nom d’utilisateur'),
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? tr('Requis') : null,
              ),
            ),
            const SizedBox(height: 12),
            TvDeferredKeyboard(
              builder: (context, focusNode, canRequestFocus) => TextFormField(
                focusNode: focusNode,
                canRequestFocus: canRequestFocus,
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: tr('Mot de passe'),
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return tr('Requis');
                  if (v.length < 4) return tr('Minimum 4 caractères');
                  return null;
                },
              ),
            ),
            if (requesting) ...[
              const SizedBox(height: 12),
              TvDeferredKeyboard(
                builder: (context, focusNode, canRequestFocus) => TextFormField(
                  focusNode: focusNode,
                  canRequestFocus: canRequestFocus,
                  controller: _messageController,
                  maxLength: 280,
                  decoration: InputDecoration(
                    labelText: tr('Message (facultatif)'),
                    hintText: tr('Dites qui vous êtes'),
                    prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.35)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error, fontSize: AppType.subhead),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(requesting ? tr('Envoyer la demande') : tr('Ajouter')),
            ),
          ],
        ),
      ),
    );
  }
}
