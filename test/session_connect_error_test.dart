import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/state/session.dart';

import 'support/fakes.dart';

void main() {
  test(
    'a dead backend reads as plain language, never as an exception',
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
    },
  );

  test(
    'a rejected auth keeps the specific message, with no hint to follow',
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
    },
  );

  test(
    'a rejected credential expires the session so the token can be dropped',
    () async {
      var expiries = 0;
      final session = InstanceSession(
        StoredInstance(baseUrl: 'http://test', token: 'expired'),
        api: ArmonicHttpApi('http://test'),
        connectSocket: (_) async => FakeSocket(authError: 'unauthorized'),
        onSessionExpired: () => expiries++,
      );
      addTearDown(session.dispose);

      await session.connect();

      expect(session.sessionExpired, isTrue);
      expect(expiries, 1);

      // Reconnecting against the same dead credential must not re-fire it.
      await session.connect();
      expect(expiries, 1);
    },
  );

  test('a non-credential auth failure leaves the token alone', () async {
    var expiries = 0;
    final session = InstanceSession(
      StoredInstance(baseUrl: 'http://test', token: 'jwt'),
      api: ArmonicHttpApi('http://test'),
      connectSocket: (_) async => FakeSocket(authError: 'server busy'),
      onSessionExpired: () => expiries++,
    );
    addTearDown(session.dispose);

    await session.connect();

    expect(session.sessionExpired, isFalse);
    expect(expiries, 0);
    expect(session.errorMessage, 'server busy');
  });

  test('clearToken keeps the instance but drops the credential', () {
    final instance = StoredInstance(
      baseUrl: 'http://test',
      name: 'Casa',
      description: 'la de siempre',
      token: 'expired',
      displayName: 'Leo',
    );

    final cleared = instance.clearToken();

    expect(cleared.token, isNull);
    expect(cleared.baseUrl, 'http://test');
    expect(cleared.name, 'Casa');
    expect(cleared.description, 'la de siempre');
    expect(cleared.displayName, 'Leo');
    // copyWith can't do this — null means "unchanged" there.
    expect(instance.copyWith(token: null).token, 'expired');
  });
}
