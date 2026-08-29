import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/state/session.dart';

import 'support/fakes.dart';

/// What the UI keys the "you are no longer a member" pane on:
/// `serversLoaded && servers.isEmpty`. Both halves matter — the flag is what
/// keeps a failed read from looking like a kick.
void main() {
  test('a kicked account authenticates fine and loads zero servers', () async {
    final session = await connectedSession(
      FakeBackend(servers: [], channelsByServer: {}),
      FakeSocket(),
    );
    addTearDown(session.dispose);

    // The JWT is still valid — the kick removed the membership, not the user.
    expect(session.status, SessionStatus.connected);
    expect(session.userId, 'me');
    expect(session.serversLoaded, isTrue);
    expect(session.servers, isEmpty);
  });

  test('a failed server read stays un-loaded rather than reading as a kick',
      () async {
    final session = InstanceSession(
      StoredInstance(baseUrl: 'http://test', token: 'jwt'),
      api: ArmonicHttpApi('http://test',
          client: MockClient((_) async => http.Response('boom', 500))),
      connectSocket: (_) async => FakeSocket(),
    );
    addTearDown(session.dispose);

    await session.connect();
    await drainEvents();

    expect(session.status, SessionStatus.connected);
    expect(session.servers, isEmpty);
    // The pane must not appear: we never got an answer, so we don't know.
    expect(session.serversLoaded, isFalse);
  });
}
