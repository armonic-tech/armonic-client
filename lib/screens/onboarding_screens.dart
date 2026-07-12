import 'package:flutter/material.dart';

import '../api/http_api.dart';
import '../models/models.dart';

class ClaimScreen extends StatefulWidget {
  final String baseUrl;
  final InstanceInfo info;
  const ClaimScreen({super.key, required this.baseUrl, required this.info});

  @override
  State<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends State<ClaimScreen> {
  final _passwordController = TextEditingController();
  ClaimTicket? _ticket;
  bool _busy = false;
  String? _error;

  late final _api = ArmonicHttpApi(widget.baseUrl);

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitPassword() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ticket = await _api.claimPassword(_passwordController.text);
      setState(() {
        _ticket = ticket;
        _busy = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = switch (e.statusCode) {
          401 => 'Contraseña incorrecta',
          409 => 'Esta instancia ya fue reclamada por otra persona',
          _ => e.toString(),
        };
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _register(String username, String password) async {
    final ticket = _ticket;
    if (ticket == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await _api.claimRegister(ticket.ticket, username, password);
      if (mounted) Navigator.of(context).pop(token);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        if (e.statusCode == 401) {
          // Ticket expired (~10 min TTL): back to the password step.
          _ticket = null;
          _error = 'El ticket venció — ingresá la contraseña de nuevo';
        } else if (e.statusCode == 409 && e.message.contains('taken')) {
          _error = 'Ese nombre de usuario ya existe';
        } else if (e.statusCode == 409) {
          _error = 'Esta instancia ya fue reclamada por otra persona';
        } else {
          _error = e.toString();
        }
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingScaffold(
      title: 'Reclamar instancia',
      info: widget.info,
      error: _error,
      child: _ticket == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Esta instancia todavía no tiene dueño. Ingresá la '
                  'contraseña de la instancia (definida en el config.json '
                  'del servidor) para reclamarla y volverte admin.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña de la instancia',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submitPassword(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submitPassword,
                  child: const Text('Verificar'),
                ),
              ],
            )
          : _CredentialsForm(
              intro: 'Contraseña correcta. Creá tu cuenta de administrador '
                  '(el ticket vence en ~10 minutos).',
              submitLabel: 'Crear cuenta de admin',
              busy: _busy,
              onSubmit: _register,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Login (claimed instance, existing account).
// ---------------------------------------------------------------------------

class LoginScreen extends StatefulWidget {
  final String baseUrl;
  final InstanceInfo info;
  const LoginScreen({super.key, required this.baseUrl, required this.info});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _login(String username, String password) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token =
          await ArmonicHttpApi(widget.baseUrl).login(username, password);
      if (mounted) Navigator.of(context).pop(token);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.statusCode == 401
            ? 'Usuario o contraseña incorrectos'
            : e.toString();
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingScaffold(
      title: 'Iniciar sesión',
      info: widget.info,
      error: _error,
      child: _CredentialsForm(
        intro: '¿No tenés cuenta? Pedile un link de invitación al admin de '
            'la instancia — no hay registro público.',
        submitLabel: 'Entrar',
        busy: _busy,
        onSubmit: _login,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Invite redemption: new account from a single-use invite link.
// ---------------------------------------------------------------------------

class InviteSignupScreen extends StatefulWidget {
  final String baseUrl;
  final InstanceInfo info;
  final String inviteToken;
  const InviteSignupScreen({
    super.key,
    required this.baseUrl,
    required this.info,
    required this.inviteToken,
  });

  @override
  State<InviteSignupScreen> createState() => _InviteSignupScreenState();
}

class _InviteSignupScreenState extends State<InviteSignupScreen> {
  late final _api = ArmonicHttpApi(widget.baseUrl);
  late Future<InviteStatus> _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = _api.inviteStatus(widget.inviteToken);
  }

  Future<void> _signup(String username, String password) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token =
          await _api.inviteSignup(widget.inviteToken, username, password);
      if (mounted) Navigator.of(context).pop(token);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = switch (e.statusCode) {
          410 => 'Esta invitación ya no es válida',
          409 => 'Ese nombre de usuario ya existe',
          403 => 'La instancia todavía no fue reclamada por un admin',
          _ => e.toString(),
        };
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingScaffold(
      title: 'Unirse con invitación',
      info: widget.info,
      error: _error,
      child: FutureBuilder<InviteStatus>(
        future: _status,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final e = snap.error;
            final gone = e is ApiException && e.statusCode == 410;
            return Column(
              children: [
                Icon(Icons.link_off,
                    size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  gone
                      ? 'Esta invitación ya no es válida (vencida o ya usada).'
                      : 'No se pudo validar la invitación: $e',
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }
          final status = snap.data!;
          final expires = status.expiresAt?.toLocal();
          return _CredentialsForm(
            intro: 'Invitación válida para "${widget.info.name}"'
                '${expires != null ? ' — vence el $expires' : ''}. '
                'Creá tu cuenta para unirte.',
            submitLabel: 'Crear cuenta y unirme',
            busy: _busy,
            onSubmit: _signup,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _OnboardingScaffold extends StatelessWidget {
  final String title;
  final InstanceInfo info;
  final String? error;
  final Widget child;

  const _OnboardingScaffold({
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
              Text('${info.memberCount} miembros',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
              child,
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CredentialsForm extends StatefulWidget {
  final String intro;
  final String submitLabel;
  final bool busy;
  final void Function(String username, String password) onSubmit;

  const _CredentialsForm({
    required this.intro,
    required this.submitLabel,
    required this.busy,
    required this.onSubmit,
  });

  @override
  State<_CredentialsForm> createState() => _CredentialsFormState();
}

class _CredentialsFormState extends State<_CredentialsForm> {
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
      setState(() => _localError = 'Ingresá un nombre de usuario');
      return;
    }
    if (password.length < 8) {
      // Mirrors the backend's minimum (internal/auth).
      setState(() => _localError =
          'La contraseña debe tener al menos 8 caracteres');
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
          decoration: const InputDecoration(
            labelText: 'Usuario',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_localError != null) ...[
          const SizedBox(height: 8),
          Text(_localError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: widget.busy ? null : _submit,
          child: widget.busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.submitLabel),
        ),
      ],
    );
  }
}
