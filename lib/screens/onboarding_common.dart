import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';

/// flow claim / login / invite:
class OnboardingScaffold extends StatelessWidget {
  final String title;
  final InstanceInfo info;
  final String? error;
  final Widget child;

  const OnboardingScaffold({
    super.key,
    required this.title,
    required this.info,
    required this.error,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(info.name, style: Theme.of(context).textTheme.titleLarge),
              if (info.description.isNotEmpty) Text(info.description),
              Text(
                strings.membersCount(info.memberCount),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              child,
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// credentials form
class CredentialsForm extends StatefulWidget {
  final String intro;
  final String submitLabel;
  final bool busy;
  final void Function(String username, String password) onSubmit;

  const CredentialsForm({
    super.key,
    required this.intro,
    required this.submitLabel,
    required this.busy,
    required this.onSubmit,
  });

  @override
  State<CredentialsForm> createState() => _CredentialsFormState();
}

class _CredentialsFormState extends State<CredentialsForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty) {
      setState(() => _localError = strings.enterUsername);
      return;
    }
    if (password.length < 8) {
      // Mirrors the backend's minimum (internal/auth).
      setState(() => _localError = strings.passwordTooShort);
      return;
    }
    setState(() => _localError = null);
    widget.onSubmit(username, password);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.intro),
        const SizedBox(height: 16),
        TextField(
          controller: _username,
          autofocus: true,
          decoration: InputDecoration(
            labelText: strings.usernameLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(
            labelText: strings.passwordLabel,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_localError != null) ...[
          const SizedBox(height: 8),
          Text(
            _localError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: widget.busy ? null : _submit,
          child: widget.busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.submitLabel),
        ),
      ],
    );
  }
}
