/// GET /pow/challenge: the proof-of-work an instance asks for before it will
/// look at a login, claim or invite-signup.
///
/// The instance may have it turned off, in which case the route 404s and the
/// client sends no solution at all — see [PowSolver].
class PowChallenge {
  final String algorithm;
  final String challenge;
  final int maxNumber;
  final String salt;
  final String signature;

  PowChallenge({
    required this.algorithm,
    required this.challenge,
    required this.maxNumber,
    required this.salt,
    required this.signature,
  });

  factory PowChallenge.fromJson(Map<String, dynamic> json) => PowChallenge(
    algorithm: json['algorithm'] as String? ?? '',
    challenge: json['challenge'] as String? ?? '',
    maxNumber: (json['maxnumber'] as num?)?.toInt() ?? 0,
    salt: json['salt'] as String? ?? '',
    signature: json['signature'] as String? ?? '',
  );

  /// The solved object, sent back base64-encoded in the request's `altcha`
  /// field. Every field of the challenge is echoed verbatim: the server
  /// re-derives its HMAC from them, so altering any one invalidates the proof.
  Map<String, dynamic> solutionJson(int number) => {
    'algorithm': algorithm,
    'challenge': challenge,
    'maxnumber': maxNumber,
    'salt': salt,
    'signature': signature,
    'number': number,
  };
}
