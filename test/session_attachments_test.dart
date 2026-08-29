import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/state/session.dart';

import 'support/fakes.dart';

const _attachmentJson = {
  'id': 'att-1',
  'serverId': 's1',
  'userId': 'me',
  'mime': 'image/png',
  'size': 1234,
  'width': 640,
  'height': 480,
  'url': '/attachment/att-1',
  'thumbUrl': '/attachment/att-1/thumb',
  'createdAt': '2026-01-01T10:00:00Z',
};

void main() {
  test('uploading an image returns the attachment and hits the server route',
      () async {
    final backend = defaultBackend()..uploadResponse = _attachmentJson;
    final socket = FakeSocket();
    final session = await connectedSession(backend, socket);
    addTearDown(session.dispose);

    final uploaded =
        await session.uploadImage(Uint8List.fromList([1, 2, 3]), 'pic.png');

    expect(uploaded.id, 'att-1');
    expect(uploaded.width, 640);
    expect(uploaded.thumbUrl, '/attachment/att-1/thumb');
    expect(backend.uploadedPaths, ['/server/s1/upload']);
  });

  test('sending an image-only message is allowed and carries attachmentId',
      () async {
    final backend = defaultBackend();
    final socket = FakeSocket();
    final session = await connectedSession(backend, socket);
    addTearDown(session.dispose);

    session.sendText('', attachmentId: 'att-1');

    final sent = socket.lastOfType('text-message')!;
    expect(sent['content'], '');
    expect(sent['attachmentId'], 'att-1');
    // The optimistic echo must show the image too, or the sender sees a blank
    // bubble until a reload.
    final echo = session.messagesFor('c-text').last;
    expect(echo.attachmentId, 'att-1');
    expect(echo.hasAttachment, isTrue);
  });

  test('a message with neither text nor image is not sent', () async {
    final backend = defaultBackend();
    final socket = FakeSocket();
    final session = await connectedSession(backend, socket);
    addTearDown(session.dispose);

    session.sendText('');

    expect(socket.lastOfType('text-message'), isNull);
  });

  test('a text-only message sends no attachmentId key at all', () async {
    final backend = defaultBackend();
    final socket = FakeSocket();
    final session = await connectedSession(backend, socket);
    addTearDown(session.dispose);

    session.sendText('hola');

    expect(socket.lastOfType('text-message')!.containsKey('attachmentId'),
        isFalse);
  });

  test('an incoming text-message keeps its attachmentId', () async {
    final backend = defaultBackend();
    final socket = FakeSocket();
    final session = await connectedSession(backend, socket);
    addTearDown(session.dispose);

    socket.emit({
      'type': 'text-message',
      'id': 'm9',
      'serverId': 's1',
      'channelId': 'c-text',
      'userId': 'u2',
      'content': '',
      'attachmentId': 'att-7',
      'createdAt': '2026-01-01T10:00:00Z',
    });
    await drainEvents();

    expect(session.messagesFor('c-text').single.attachmentId, 'att-7');
  });

  group('upload failures are typed by what the user should do', () {
    Future<InstanceSession> sessionRejecting(int status) async {
      final backend = defaultBackend()..uploadStatus = status;
      return connectedSession(backend, FakeSocket());
    }

    for (final entry in {
      413: 'tamaño máximo',
      415: 'Formato no soportado',
      422: 'dimensiones',
      400: 'dañada',
    }.entries) {
      test('${entry.key} explains the specific problem', () async {
        final session = await sessionRejecting(entry.key);
        addTearDown(session.dispose);

        await expectLater(
          session.uploadImage(Uint8List.fromList([1]), 'x.png'),
          throwsA(isA<UploadFailure>()
              .having((e) => e.message, 'message', contains(entry.value))),
        );
      });
    }

    test('429 tells the user how long to wait', () async {
      final session = await sessionRejecting(429);
      addTearDown(session.dispose);

      await expectLater(
        session.uploadImage(Uint8List.fromList([1]), 'x.png'),
        throwsA(isA<UploadFailure>()
            .having((e) => e.message, 'message', contains('7s'))),
      );
    });
  });

  test('setAvatar posts to /me/avatar and updates the local avatar', () async {
    final backend = defaultBackend()
      ..uploadResponse = {..._attachmentJson, 'id': 'att-av'};
    final socket = FakeSocket();
    final session = await connectedSession(backend, socket);
    addTearDown(session.dispose);

    expect(session.myAvatarPath, isNull);

    await session.setAvatar(Uint8List.fromList([1, 2]), 'me.png');
    await drainEvents();

    expect(backend.uploadedPaths, contains('/me/avatar'));
    expect(session.avatarId, 'att-av');
    expect(session.myAvatarPath, '/attachment/att-av');
  });

  test('auth-ok seeds the caller avatar, and an empty one stays null',
      () async {
    final backend = defaultBackend();
    final withAvatar = FakeSocket();
    final session = await connectedSession(backend, withAvatar);
    addTearDown(session.dispose);
    // The default fake sends no avatarId at all.
    expect(session.avatarId, isNull);

    withAvatar.emit({
      'type': 'auth-ok',
      'userId': 'me',
      'displayName': 'Yo',
      'avatarId': 'att-x',
    });
    await drainEvents();
    expect(session.myAvatarPath, '/attachment/att-x');
  });

  test('the attachment cache fetches once and reuses the bytes', () async {
    var hits = 0;
    final api = ArmonicHttpApi(
      'http://test',
      client: MockClient((request) async {
        hits++;
        expect(request.headers['Authorization'], 'Bearer jwt');
        return http.Response.bytes(utf8.encode('png-bytes'), 200);
      }),
    );
    final session = InstanceSession(
      StoredInstance(baseUrl: 'http://test', token: 'jwt'),
      api: api,
      connectSocket: (_) async => FakeSocket(),
    );
    addTearDown(session.dispose);

    final first = await session.attachments.load('/attachment/a');
    final second = await session.attachments.load('/attachment/a');

    expect(utf8.decode(first), 'png-bytes');
    expect(second, first);
    expect(hits, 1, reason: 'the second load came from the cache');
    expect(session.attachments.peek('/attachment/a'), isNotNull);
  });

  test('concurrent loads of the same path share one request', () async {
    var hits = 0;
    final api = ArmonicHttpApi(
      'http://test',
      client: MockClient((_) async {
        hits++;
        return http.Response.bytes(utf8.encode('bytes'), 200);
      }),
    );
    final session = InstanceSession(
      StoredInstance(baseUrl: 'http://test', token: 'jwt'),
      api: api,
      connectSocket: (_) async => FakeSocket(),
    );
    addTearDown(session.dispose);

    await Future.wait([
      session.attachments.load('/attachment/a'),
      session.attachments.load('/attachment/a'),
      session.attachments.load('/attachment/a'),
    ]);

    expect(hits, 1);
  });
}
