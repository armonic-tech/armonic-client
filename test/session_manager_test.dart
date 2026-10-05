import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/state/session.dart';
import 'package:armonic_client/state/session_manager.dart';

import 'support/fakes.dart';

void main() {
  // One socket per session the manager builds, in creation order, so a test
  // can assert which ones were torn down.
  late List<FakeSocket> sockets;

  SessionManager managerWith() {
    sockets = [];
    final manager = SessionManager(
      onSessionExpired: (_) {},
      createSession: (instance) {
        final socket = FakeSocket();
        sockets.add(socket);
        return InstanceSession(
          instance,
          api: ArmonicHttpApi(
            instance.baseUrl,
            client: defaultBackend().client(),
          ),
          connectSocket: (_) async => socket,
        );
      },
    );
    addTearDown(manager.dispose);
    return manager;
  }

  final home = StoredInstance(baseUrl: 'http://home', token: 'jwt');
  final work = StoredInstance(baseUrl: 'http://work', token: 'jwt');

  // The rail reads the logo off the manager, so a logo that arrives mid
  // session has to notify: reading it off the session directly looked right
  // and then only repainted when something else rebuilt the shell - clicking
  // another instance, in the report.
  test('a logo arriving mid-session notifies the shell', () async {
    final manager = managerWith();
    var notifications = 0;
    manager.addListener(() => notifications++);

    manager.sessionFor(home);
    await drainEvents();
    expect(manager.logoPathOf(home.baseUrl), isNull);

    notifications = 0;
    sockets.first.emit({
      'type': 'server-updated',
      'serverId': 's1',
      'logoId': 'att-1',
      'logoThumbUrl': '/server/s1/logo/thumb?v=att-1',
    });
    await drainEvents();

    expect(manager.logoPathOf(home.baseUrl), '/server/s1/logo/thumb?v=att-1');
    expect(notifications, greaterThan(0));

    // And removing it is just as much a change.
    notifications = 0;
    sockets.first.emit({'type': 'server-updated', 'serverId': 's1'});
    await drainEvents();
    expect(manager.logoPathOf(home.baseUrl), isNull);
    expect(notifications, greaterThan(0));
  });

  // The counterpart: the manager still ignores the frames the shell has no
  // business rebuilding for.
  test('an ordinary frame does not notify the shell', () async {
    final manager = managerWith();
    manager.sessionFor(home);
    await drainEvents();

    var notifications = 0;
    manager.addListener(() => notifications++);
    sockets.first.emit({
      'type': 'text-message',
      'id': 'm1',
      'serverId': 's1',
      'channelId': 'c-text',
      'userId': 'someone',
      'content': 'hola',
      'createdAt': '2026-01-01T10:00:00Z',
    });
    await drainEvents();

    expect(notifications, 0);
  });

  test(
    'looking at another instance leaves the first session connected',
    () async {
      final manager = managerWith();

      final first = manager.sessionFor(home);
      manager.sessionFor(work);
      await drainEvents();

      // What used to break: the screen owned the session, so switching the rail
      // disposed it — socket closed, call dropped.
      expect(identical(manager.sessionFor(home), first), isTrue);
      expect(first.status, SessionStatus.connected);
      expect(sockets.first.isClosed, isFalse);
    },
  );

  test(
    'a fresh token for the same instance replaces the dead session',
    () async {
      final manager = managerWith();

      final expired = manager.sessionFor(
        StoredInstance(baseUrl: 'http://home', token: 'expired'),
      );
      await drainEvents();
      final reborn = manager.sessionFor(
        StoredInstance(baseUrl: 'http://home', token: 'new'),
      );
      await drainEvents();

      expect(identical(expired, reborn), isFalse);
      expect(sockets.first.isClosed, isTrue);
      expect(reborn.status, SessionStatus.connected);
    },
  );

  test('releasing an instance closes its socket and forgets it', () async {
    final manager = managerWith();

    final first = manager.sessionFor(home);
    await drainEvents();
    manager.release(home.baseUrl);

    expect(sockets.first.isClosed, isTrue);
    expect(identical(manager.sessionFor(home), first), isFalse);
  });

  test('no call means no bar: voiceSession stays null', () async {
    final manager = managerWith();

    manager.sessionFor(home);
    await drainEvents();

    expect(manager.voiceSession, isNull);
  });
}
