import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/state/session.dart';

import 'support/fakes.dart';

void main() {
  test('a dead backend reads as plain language, never as an exception',
      () async {
    final session = InstanceSession(
      StoredInstance(baseUrl: 'http://test', token: 'jwt'),
      api: ArmonicHttpApi('http://test'),
      connectSocket: (_) async =>
          throw Exception('WebSocketException: Failed to connect WebSocket'),
    );
    addTearDown(session.dispose);

    await session.connect();

    expect(session.status, SessionStatus.error);
    expect(session.errorMessage, strings.instanceUnreachable);
    expect(session.errorHint, strings.instanceUnreachableHint);
  });

  test('a rejected auth keeps the specific message, with no hint to follow',
      () async {
    // The server answers the auth frame with an error instead of auth-ok.
    final socket = FakeSocket(authError: 'unauthorized');
    final session = InstanceSession(
      StoredInstance(baseUrl: 'http://test', token: 'expired'),
      api: ArmonicHttpApi('http://test'),
      connectSocket: (_) async => socket,
    );
    addTearDown(session.dispose);

    await session.connect();

    expect(session.errorMessage, strings.sessionInvalid);
    expect(session.errorHint, isNull);
  });
}
