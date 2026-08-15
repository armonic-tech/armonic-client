import 'package:flutter/material.dart';

import '../api/http_api.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import 'onboarding_common.dart';

/// claim an unclaimed instance 
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
          401 => strings.wrongPassword,
          409 => strings.instanceAlreadyClaimed,
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
          // Ticket expired
          _ticket = null;
          _error = strings.ticketExpired;
        } else if (e.statusCode == 409 && e.message.contains('taken')) {
          _error = strings.usernameTaken;
        } else if (e.statusCode == 409) {
          _error = strings.instanceAlreadyClaimed;
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
    return OnboardingScaffold(
      title: strings.claimInstanceTitle,
      info: widget.info,
      error: _error,
      child: _ticket == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(strings.claimIntro),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: strings.instancePasswordLabel,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submitPassword(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submitPassword,
                  child: Text(strings.verify),
                ),
              ],
            )
          : CredentialsForm(
              intro: strings.claimCredentialsIntro,
              submitLabel: strings.createAdminAccount,
              busy: _busy,
              onSubmit: _register,
            ),
    );
  }
}