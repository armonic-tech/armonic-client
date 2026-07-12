import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/http_api.dart';
import '../models/models.dart';
import '../state/instance_store.dart';
import 'onboarding_screens.dart';

class AddInstanceScreen extends StatefulWidget {
  final String? initialUrl;
  const AddInstanceScreen({super.key, this.initialUrl});

  @override
  State<AddInstanceScreen> createState() => _AddInstanceScreenState();
}

class _AddInstanceScreenState extends State<AddInstanceScreen> {
  late final TextEditingController _urlController =
      TextEditingController(text: widget.initialUrl ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final input = _urlController.text;
    final baseUrl = normalizeBaseUrl(input);
    if (baseUrl.isEmpty || Uri.parse(baseUrl).host.isEmpty) {
      setState(() => _error = 'Ingresá una URL válida (ej. http://host:4000)');
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
        _error = 'No se pudo contactar la instancia: $e';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final Widget next;
    if (inviteToken != null && inviteToken.isNotEmpty) {
      next = InviteSignupScreen(
          baseUrl: baseUrl, info: info, inviteToken: inviteToken);
    } else if (!info.claimed) {
      next = ClaimScreen(baseUrl: baseUrl, info: info);
    } else {
      next = LoginScreen(baseUrl: baseUrl, info: info);
    }

    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => next),
    );
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
      appBar: AppBar(title: const Text('Agregar instancia')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'URL de la instancia de Armonic, o un link de invitación '
                  'que te hayan compartido.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    hintText: 'http://mi-servidor:4000  ·  …?invite=abc123',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  onSubmitted: (_) => _connect(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Conectar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
