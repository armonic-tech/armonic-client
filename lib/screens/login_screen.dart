import 'package:flutter/material.dart';

import '../api/http_api.dart';
import '../api/pow_gate.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import 'onboarding_common.dart';

/// Login into an already-claimed instance
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
    final api = ArmonicHttpApi(widget.baseUrl);
    try {
      final token = await withProofOfWork(
        api,
        (altcha) => api.login(username, password, altcha: altcha),
      );
      if (mounted) Navigator.of(context).pop(token);
    } on PowFailure catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = switch (e.statusCode) {
          401 => strings.wrongCredentials,
          409 => strings.powExpired,
          429 => strings.tooManyAttempts(e.retryAfter),
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
    return OnboardingScaffold(
      title: strings.loginTitle,
      info: widget.info,
      error: _error,
      child: CredentialsForm(
        intro: strings.loginIntro,
        submitLabel: strings.login,
        busy: _busy,
        onSubmit: _login,
      ),
    );
  }
}
