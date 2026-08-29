import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/models.dart';

/// Brute-forces the number whose SHA-256 matches the challenge.
///
/// Work is done in chunks with a yield between them rather than in one tight
/// loop: on web there are no isolates, so an uninterrupted loop would freeze
/// the frame. Dart's native SHA-256 is fast enough that the default difficulty
/// costs a few tens of milliseconds, so the chunking is about staying
/// responsive, not about throughput.
///
/// Any matching number is accepted, not the smallest one, so the search does
/// not have to run in order.
class PowSolver {
  static const chunkSize = 4096;

  /// Returns the base64 payload for the request's `altcha` field.
  /// Throws [PowUnsolvable] if no number in range matches, which means the
  /// challenge was not one this instance issued.
  static Future<String> solve(PowChallenge challenge) async {
    final saltBytes = utf8.encode(challenge.salt);

    for (var base = 0; base <= challenge.maxNumber; base += chunkSize) {
      final end = (base + chunkSize).clamp(0, challenge.maxNumber + 1);
      for (var n = base; n < end; n++) {
        final digest = sha256.convert([...saltBytes, ...utf8.encode('$n')]);
        if (digest.toString() == challenge.challenge) {
          return base64.encode(
            utf8.encode(jsonEncode(challenge.solutionJson(n))),
          );
        }
      }
      // Hand the frame back so the UI keeps painting mid-solve.
      await Future<void>.delayed(Duration.zero);
    }
    throw const PowUnsolvable();
  }
}

class PowUnsolvable implements Exception {
  const PowUnsolvable();

  @override
  String toString() => 'proof of work challenge had no solution in range';
}
