import '../l10n/app_strings.dart';
import '../models/models.dart';
import 'http_api.dart';
import 'pow_solver.dart';

/// A proof of work that the server would not accept. Distinct from the
/// request's own failures (wrong password, taken username) so a screen can
/// tell the user to retry rather than to fix their input.
class PowFailure implements Exception {
  final String message;
  const PowFailure(this.message);

  @override
  String toString() => message;
}

/// Runs [submit] with a proof of work when the instance asks for one.
///
/// Instances ship with proof of work off, in which case `/pow/challenge`
/// answers 404 and [submit] is called with null — which is what lets one build
/// of the client talk to instances with it both on and off.
///
/// A `409` means the challenge expired or was already spent, so exactly one
/// fresh challenge is solved and the request retried. Note that a few routes
/// use 409 for their own conflicts too (a claim on an already-claimed
/// instance): those are re-raised untouched after that one retry, at the cost
/// of solving one challenge nobody needed.
Future<T> withProofOfWork<T>(
  ArmonicHttpApi api,
  Future<T> Function(String? altcha) submit,
) async {
  final challenge = await api.powChallenge();
  if (challenge == null) return submit(null);

  try {
    return await _solveAndSubmit(api, challenge, submit);
  } on ApiException catch (e) {
    if (e.statusCode != 409) rethrow;
    final fresh = await api.powChallenge();
    if (fresh == null) return submit(null);
    return _solveAndSubmit(api, fresh, submit);
  }
}

Future<T> _solveAndSubmit<T>(
  ArmonicHttpApi api,
  PowChallenge challenge,
  Future<T> Function(String? altcha) submit,
) async {
  final String payload;
  try {
    payload = await PowSolver.solve(challenge);
  } on PowUnsolvable {
    throw PowFailure(strings.powFailed);
  }

  try {
    return await submit(payload);
  } on ApiException catch (e) {
    // 400 on these routes only ever means the solution itself was rejected:
    // the client never sends a malformed body otherwise.
    if (e.statusCode == 400) throw PowFailure(strings.powFailed);
    rethrow;
  }
}
