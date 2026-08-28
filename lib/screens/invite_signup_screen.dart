import 'package:flutter/material.dart';

import '../api/http_api.dart';
import '../api/pow_gate.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import 'onboarding_common.dart';

/// create account from a single-use invite link.
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
      final token = await withProofOfWork(
        _api,
        (altcha) => _api.inviteSignup(widget.inviteToken, username, password,
            altcha: altcha),
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
          410 => strings.inviteInvalid,
          409 => strings.usernameTaken,
          403 => strings.instanceNotClaimedYet,
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
      title: strings.inviteJoinTitle,
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
                      ? strings.inviteNoLongerValid
                      : strings.couldNotValidateInvite(e),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          }
          final status = snap.data!;
          final expires = status.expiresAt?.toLocal();
          return CredentialsForm(
            intro: strings.inviteValidIntro(widget.info.name, expires),
            submitLabel: strings.createAccountAndJoin,
            busy: _busy,
            onSubmit: _signup,
          );
        },
      ),
    );
  }
}