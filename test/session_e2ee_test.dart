import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:armonic_client/mls/client.dart';
import 'package:armonic_client/mls/store.dart';
import 'package:armonic_client/state/session.dart';

import 'support/fake_mls.dart';
import 'support/fakes.dart';

/// Two members of "s1" on one shared delivery service. The owner ("me") is
/// online first and starts the group; bob publishes key packages and gets
/// added; the fake server's mls-commit broadcasts are relayed by hand.
class Pair {
  final ds = FakeDeliveryService()
    ..memberships['s1'] = {'me', 'bob'}
    ..online = {'me', 'bob'};
  late final FakeBackend meBackend = defaultBackend()..mls = ds;
  late final FakeBackend bobBackend = defaultBackend()..mls = ds;
  final meSocket = FakeSocket();
  final bobSocket = FakeSocket(userId: 'bob');
  late InstanceSession me;
  late InstanceSession bob;
  final meStore = MemoryMlsStore();
  final bobStore = MemoryMlsStore();

  Future<void> connect() async {
    me = await connectedSession(meBackend, meSocket, mlsStore: meStore);
    bob = await connectedSession(
      bobBackend,
      bobSocket,
      token: 'jwt-bob',
      mlsStore: bobStore,
    );
    await settle();
  }

  /// Lets the two sessions drive themselves to a steady state. It only
  /// waits: calling sync() by hand here would hide exactly the class of bug
  /// where the app needs a nudge nobody sends it.
  Future<void> settle() async {
    for (var round = 0; round < 6; round++) {
      await drainEvents(40);
    }
  }

  /// Hands a frame one session sent to the other, as the server would.
  void relay(FakeSocket from, FakeSocket to) {
    final frame = from.lastOfType('text-message')!;
    to.emit({
      ...frame,
      'id': 'srv-${DateTime.now().microsecondsSinceEpoch}',
      'userId': from.userId,
      'createdAt': '2026-01-01T10:00:00Z',
    });
  }

  void dispose() {
    me.dispose();
    bob.dispose();
  }
}

void main() {
  test(
    'a lone member bootstraps the group with no nudging from the test',
    () async {
      // No settle loop and no manual sync: exactly what the app does on its
      // own after connecting. If this needs help, real instances send in the
      // clear.
      final ds = FakeDeliveryService()
        ..memberships['s1'] = {'me'}
        ..online = {'me'};
      final socket = FakeSocket();
      final session = await connectedSession(
        defaultBackend()..mls = ds,
        socket,
      );
      addTearDown(session.dispose);
      await drainEvents(60);

      expect(ds.epochs['s1'], greaterThan(0));
      expect(session.e2eeStatus, E2eeStatus.ready);

      session.sendText('esto tiene que salir cifrado');
      await drainEvents(20);
      final sent = socket.lastOfType('text-message')!;
      expect(sent['encrypted'], isTrue);
      expect(sent['content'], isNot(contains('cifrado')));
    },
  );

  test('the owner starts the group and adds the other member', () async {
    final p = Pair();
    await p.connect();
    addTearDown(p.dispose);

    expect(p.me.e2eeStatus, E2eeStatus.ready);
    expect(p.bob.e2eeStatus, E2eeStatus.ready);
    expect(p.ds.epochs['s1'], greaterThanOrEqualTo(1));
    expect(p.ds.members['s1']!.length, 2);
    expect(p.me.mls!.groupFor('s1')!.epoch, p.bob.mls!.groupFor('s1')!.epoch);
  });

  test('messages travel encrypted and are read on the other side', () async {
    final p = Pair();
    await p.connect();
    addTearDown(p.dispose);

    p.me.sendText('hola bob');
    await drainEvents(20);
    final sent = p.meSocket.lastOfType('text-message')!;
    expect(sent['encrypted'], isTrue);
    expect(sent['content'], isNot(contains('hola')));
    // The optimistic echo shows the plaintext to the sender.
    expect(p.me.messagesFor('c-text').last.content, 'hola bob');

    p.relay(p.meSocket, p.bobSocket);
    await drainEvents(20);
    final got = p.bob.messagesFor('c-text').last;
    expect(got.encrypted, isTrue);
    expect(got.locked, isFalse);
    expect(got.content, 'hola bob');

    // And back, so both directions of the tree are exercised.
    p.bob.sendText('hola me');
    await drainEvents(20);
    p.relay(p.bobSocket, p.meSocket);
    await drainEvents(20);
    expect(p.me.messagesFor('c-text').last.content, 'hola me');
  });

  test(
    'history is decrypted after a restart; unknown epochs stay locked',
    () async {
      final p = Pair();
      await p.connect();
      addTearDown(p.dispose);

      p.me.sendText('para el historial');
      await drainEvents(20);
      final sent = p.meSocket.lastOfType('text-message')!;
      final stored = {
        'id': 'm-hist',
        'serverId': 's1',
        'channelId': 'c-text',
        'userId': 'me',
        'content': sent['content'],
        'encrypted': true,
        'createdAt': '2026-01-01T09:00:00Z',
      };
      // An envelope from an epoch nobody has (a member removed long ago).
      final foreign = {
        ...stored,
        'id': 'm-foreign',
        'content': jsonEncode({
          'v': 1,
          'e': 99,
          's': 0,
          'n': base64Encode(List.filled(12, 1)),
          'c': base64Encode(List.filled(32, 2)),
        }),
      };

      // Bob reopens the app: a fresh session on the same device store must
      // read the history with the keys it persisted.
      final bobAgain = await connectedSession(
        p.bobBackend..messages.addAll([foreign, stored]),
        FakeSocket(userId: 'bob'),
        token: 'jwt-bob',
        mlsStore: p.bobStore,
      );
      addTearDown(bobAgain.dispose);
      await drainEvents(40);

      final history = bobAgain.messagesFor('c-text');
      final readable = history.singleWhere((m) => m.id == 'm-hist');
      expect(readable.locked, isFalse);
      expect(readable.content, 'para el historial');
      final locked = history.singleWhere((m) => m.id == 'm-foreign');
      expect(locked.locked, isTrue);
      expect(locked.content, isNot(contains('historial')));
    },
  );

  test('a member refuses to send while no coordinator can add it', () async {
    final ds = FakeDeliveryService()
      ..memberships['s1'] = {'me', 'bob'}
      ..online = {'bob'}
      ..owner = 'bob';
    final bob = await connectedSession(
      defaultBackend(ownerId: 'bob')..mls = ds,
      FakeSocket(userId: 'bob'),
      token: 'jwt-bob',
    );
    addTearDown(bob.dispose);
    await drainEvents(60);
    expect(ds.epochs['s1'], greaterThan(0));

    // Bob goes away: the group exists, but nobody left in it is online to
    // commit the add.
    ds.listeners.clear();
    ds.online = {'me'};

    final meSocket = FakeSocket();
    final me = await connectedSession(
      defaultBackend(ownerId: 'bob')..mls = ds,
      meSocket,
    );
    addTearDown(me.dispose);
    await drainEvents(60);
    expect(me.e2eeStatus, E2eeStatus.waitingForKeys);

    final errors = <String>[];
    me.errors.listen(errors.add);
    me.sendText('esto no puede salir en claro');
    await drainEvents(20);

    expect(meSocket.lastOfType('text-message'), isNull);
    expect(errors, isNotEmpty);
  });

  test('an instance without the MLS routes keeps sending plaintext', () async {
    // backend.mls stays null: every /mls path answers 500, as an older
    // backend's 404 would.
    final socket = FakeSocket();
    final session = await connectedSession(defaultBackend(), socket);
    addTearDown(session.dispose);
    await drainEvents(40);

    expect(session.e2eeStatus, E2eeStatus.starting);
    session.sendText('hola en claro');
    await drainEvents(20);
    final sent = socket.lastOfType('text-message')!;
    expect(sent['content'], 'hola en claro');
    expect(sent.containsKey('encrypted'), isFalse);
  });

  test('a kicked member is evicted and cannot read the next epoch', () async {
    final p = Pair();
    await p.connect();
    addTearDown(p.dispose);

    final bobGroupBefore = p.bob.mls!.groupFor('s1')!;
    p.ds.memberships['s1'] = {'me'};
    p.ds.online = {'me'};
    p.meSocket.emit({'type': 'mls-sync', 'serverId': 's1'});
    await p.settle();

    expect(p.ds.members['s1']!.keys, [p.me.mls!.deviceId]);
    expect(p.me.e2eeStatus, E2eeStatus.ready);

    p.me.sendText('despues de la expulsion');
    await drainEvents(20);
    final frame = p.meSocket.lastOfType('text-message')!;
    final envelope = frame['content'] as String;
    // Bob's last group state has no key for the new epoch.
    await expectLater(
      () => bobGroupBefore.decrypt(
        'c-text',
        (() {
              final j = jsonDecode(envelope) as Map;
              return j;
            })()
            as dynamic,
      ),
      throwsA(anything),
    );
  });

  test('an image goes up encrypted and is opened by the recipient', () async {
    final p = Pair();
    await p.connect();
    addTearDown(p.dispose);

    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 20, height: 10)),
    );
    final staged = await p.me.uploadImage(png, 'x.png');
    expect(p.meBackend.uploadedPaths, ['/server/s1/upload/encrypted']);
    expect(staged.ref, isNotNull);
    expect(staged.width, 20);
    // What the server received is not a PNG.
    expect(
      p.meBackend.lastEncryptedBlob!.sublist(0, 4),
      isNot([137, 80, 78, 71]),
    );

    p.me.sendText('', attachmentId: staged.id, attachmentRef: staged.ref);
    await drainEvents(20);
    // Bob's backend serves the same blob store.
    p.bobBackend.blobs.addAll(p.meBackend.blobs);
    p.relay(p.meSocket, p.bobSocket);
    await drainEvents(20);
    final got = p.bob.messagesFor('c-text').last;
    expect(got.attachmentRef, isNotNull);
    expect(got.attachmentRef!.width, 20);

    final thumb = await p.bob.attachments.load(
      '/attachment/${staged.id}/thumb',
      ref: got.attachmentRef,
    );
    expect(img.decodePng(thumb)!.width, 20);
  });
}
