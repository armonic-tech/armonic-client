import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/http_api.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/instance_store.dart';
import '../util/invite_link.dart';
import '../util/web_env.dart';
import 'claim_screen.dart';
import 'invite_signup_screen.dart';
import 'login_screen.dart';
import 'scan_invite_screen.dart';

class AddInstanceScreen extends StatefulWidget {
  final String? initialUrl;

  /// Go straight to onboarding with [initialUrl]: the page was opened from an
  /// invite QR, so there is nothing for the user to type.
  final bool autoConnect;

  const AddInstanceScreen({
    super.key,
    this.initialUrl,
    this.autoConnect = false,
  });

  @override
  State<AddInstanceScreen> createState() => _AddInstanceScreenState();
}

class _AddInstanceScreenState extends State<AddInstanceScreen> {
  late final TextEditingController _urlController = TextEditingController(
    text: widget.initialUrl ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connect();
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final link = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanInviteScreen()));
    if (link == null || !mounted) return;
    _urlController.text = link;
    await _connect();
  }

  Future<void> _connect() async {
    final input = backendInviteLink(_urlController.text);
    final baseUrl = normalizeBaseUrl(input);
    if (baseUrl.isEmpty || Uri.parse(baseUrl).host.isEmpty) {
      setState(() => _error = strings.invalidUrl);
      return;
    }
    final inviteToken = inviteTokenFromUrl(input);

    setState(() {
      _busy = true;
      _error = null;
    });

    final InstanceInfo info;
    try {
      info = await ArmonicHttpApi(baseUrl).info();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e is ApiTimeoutException
            ? strings.requestTimedOut
            : strings.couldNotContactInstance(e);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final Widget next;
    if (inviteToken != null && inviteToken.isNotEmpty) {
      next = InviteSignupScreen(
        baseUrl: baseUrl,
        info: info,
        inviteToken: inviteToken,
      );
    } else if (!info.claimed) {
      next = ClaimScreen(baseUrl: baseUrl, info: info);
    } else {
      next = LoginScreen(baseUrl: baseUrl, info: info);
    }

    final token = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => next));
    if (token == null || !mounted) return;

    final instance = StoredInstance(
      baseUrl: baseUrl,
      name: info.name,
      description: info.description,
      token: token,
    );
    await context.read<InstanceStore>().upsert(instance);
    if (mounted) Navigator.of(context).pop(instance);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(strings.addInstanceTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          // Scrolls so a phone's keyboard cannot overflow the form.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isSecureContext) ...[
                  _InsecurePageBanner(),
                  const SizedBox(height: 16),
                ],
                Text(strings.addInstanceIntro),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: strings.urlLabel,
                    hintText: strings.urlHint,
                    border: const OutlineInputBorder(),
                  ),
                  // A phone would raise its keyboard over the scan button.
                  autofocus: !canScanQr,
                  onSubmitted: (_) => _connect(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings.connect),
                ),
                if (canScanQr) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(strings.scanInviteQr),
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

/// Over plain HTTP (anything but localhost) the browser hides
/// `getUserMedia` and WebCrypto: no microphone, and no session storage
/// either. Said up front, because otherwise it fails much later and vaguely.
class _InsecurePageBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_open, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              strings.insecurePageWarning,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
