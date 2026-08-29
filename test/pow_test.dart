import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/api/pow_gate.dart';
import 'package:armonic_client/api/pow_solver.dart';
import 'package:armonic_client/models/models.dart';

/// Builds a challenge whose answer is [number], the way the server does:
/// challenge = sha256(salt + number).
PowChallenge challengeFor(int number, {int maxNumber = 5000}) {
  const salt = 'abc123?expires=9999999999';
  final digest = sha256.convert(utf8.encode('$salt$number'));
  return PowChallenge(
    algorithm: 'SHA-256',
    challenge: digest.toString(),
    maxNumber: maxNumber,
    salt: salt,
    signature: 'server-hmac',
  );
}

void main() {
  group('PowSolver', () {
    test('finds the number and echoes the challenge back verbatim', () async {
      final challenge = challengeFor(1234);

      final payload = await PowSolver.solve(challenge);
      final solution = jsonDecode(utf8.decode(base64.decode(payload)))
          as Map<String, dynamic>;

      expect(solution['number'], 1234);
      // The server re-derives its HMAC from these, so altering any one of
      // them would invalidate the proof.
      expect(solution['challenge'], challenge.challenge);
      expect(solution['salt'], challenge.salt);
      expect(solution['signature'], 'server-hmac');
      expect(solution['algorithm'], 'SHA-256');
    });

    test('solves a number on a chunk boundary', () async {
      final payload = await PowSolver.solve(challengeFor(PowSolver.chunkSize));
      final solution = jsonDecode(utf8.decode(base64.decode(payload)))
          as Map<String, dynamic>;
      expect(solution['number'], PowSolver.chunkSize);
    });

    test('solves the last number in range', () async {
      final payload =
          await PowSolver.solve(challengeFor(300, maxNumber: 300));
      final solution = jsonDecode(utf8.decode(base64.decode(payload)))
          as Map<String, dynamic>;
      expect(solution['number'], 300);
    });

    test('throws when no number in range matches', () async {
      final unsolvable = PowChallenge(
        algorithm: 'SHA-256',
        challenge: 'f' * 64,
        maxNumber: 500,
        salt: 'x?expires=9999999999',
        signature: 's',
      );
      expect(() => PowSolver.solve(unsolvable), throwsA(isA<PowUnsolvable>()));
    });
  });

  group('withProofOfWork', () {
    /// A backend whose /pow/challenge answers [status] with [body], and whose
    /// submit responses are taken from [responses] in order.
    ArmonicHttpApi apiWith({
      required int challengeStatus,
      String challengeBody = '',
      required List<http.Response> submitResponses,
      List<String>? seenAltcha,
      int? challengeHits,
    }) {
      var submitIndex = 0;
      return ArmonicHttpApi(
        'http://test',
        client: MockClient((request) async {
          if (request.url.path == '/pow/challenge') {
            return http.Response(challengeBody, challengeStatus);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          seenAltcha?.add(body['altcha'] as String? ?? '<none>');
          return submitResponses[submitIndex++];
        }),
      );
    }

    test('sends no solution when the instance has PoW off (404)', () async {
      final seen = <String>[];
      final api = apiWith(
        challengeStatus: 404,
        submitResponses: [http.Response('{"token":"jwt"}', 200)],
        seenAltcha: seen,
      );

      final token = await withProofOfWork(
          api, (altcha) => api.login('ada', 'pw', altcha: altcha));

      expect(token, 'jwt');
      expect(seen, ['<none>']);
    });

    test('solves and attaches the proof when PoW is on', () async {
      final seen = <String>[];
      final api = apiWith(
        challengeStatus: 200,
        challengeBody: jsonEncode({
          'algorithm': 'SHA-256',
          'challenge': challengeFor(42).challenge,
          'maxnumber': 5000,
          'salt': challengeFor(42).salt,
          'signature': 'sig',
        }),
        submitResponses: [http.Response('{"token":"jwt"}', 200)],
        seenAltcha: seen,
      );

      final token = await withProofOfWork(
          api, (altcha) => api.login('ada', 'pw', altcha: altcha));

      expect(token, 'jwt');
      expect(seen, hasLength(1));
      final solution =
          jsonDecode(utf8.decode(base64.decode(seen.single))) as Map;
      expect(solution['number'], 42);
    });

    test('a 409 buys one fresh challenge and a retry', () async {
      final seen = <String>[];
      final api = apiWith(
        challengeStatus: 200,
        challengeBody: jsonEncode({
          'algorithm': 'SHA-256',
          'challenge': challengeFor(7).challenge,
          'maxnumber': 5000,
          'salt': challengeFor(7).salt,
          'signature': 'sig',
        }),
        submitResponses: [
          http.Response('proof of work already used', 409),
          http.Response('{"token":"jwt"}', 200),
        ],
        seenAltcha: seen,
      );

      final token = await withProofOfWork(
          api, (altcha) => api.login('ada', 'pw', altcha: altcha));

      expect(token, 'jwt');
      expect(seen, hasLength(2));
    });

    test('a second 409 is re-raised, so a real conflict still surfaces',
        () async {
      final api = apiWith(
        challengeStatus: 200,
        challengeBody: jsonEncode({
          'algorithm': 'SHA-256',
          'challenge': challengeFor(9).challenge,
          'maxnumber': 5000,
          'salt': challengeFor(9).salt,
          'signature': 'sig',
        }),
        submitResponses: [
          http.Response('server already claimed', 409),
          http.Response('server already claimed', 409),
        ],
      );

      await expectLater(
        withProofOfWork(api, (altcha) => api.login('ada', 'pw', altcha: altcha)),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)),
      );
    });

    test('a 400 becomes PowFailure, not a credentials error', () async {
      final api = apiWith(
        challengeStatus: 200,
        challengeBody: jsonEncode({
          'algorithm': 'SHA-256',
          'challenge': challengeFor(3).challenge,
          'maxnumber': 5000,
          'salt': challengeFor(3).salt,
          'signature': 'sig',
        }),
        submitResponses: [http.Response('malformed proof of work', 400)],
      );

      await expectLater(
        withProofOfWork(api, (altcha) => api.login('ada', 'pw', altcha: altcha)),
        throwsA(isA<PowFailure>()),
      );
    });

    test('a 401 passes through untouched', () async {
      final api = apiWith(
        challengeStatus: 404,
        submitResponses: [http.Response('invalid credentials', 401)],
      );

      await expectLater(
        withProofOfWork(api, (altcha) => api.login('ada', 'pw', altcha: altcha)),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });

  test('ApiException carries Retry-After off a 429', () async {
    final api = ArmonicHttpApi(
      'http://test',
      client: MockClient((_) async => http.Response(
            'rate limit exceeded',
            429,
            headers: {'retry-after': '3'},
          )),
    );

    await expectLater(
      api.login('ada', 'pw'),
      throwsA(isA<ApiException>()
          .having((e) => e.retryAfter, 'retryAfter', 3)
          .having((e) => e.isRateLimited, 'isRateLimited', isTrue)),
    );
  });
}
