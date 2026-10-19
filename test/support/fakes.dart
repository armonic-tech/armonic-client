import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/api/ws_client.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/mls/client.dart';
import 'package:armonic_client/mls/store.dart';
import 'package:armonic_client/state/session.dart';

import 'fake_mls.dart';

/// FlutterSecureStorage talks over a platform channel that doesn't exist in
/// `flutter test`. Answer it from an in-memory map so InstanceStore can be
/// driven directly; call from `setUp`.
void fakeSecureStorage() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final values = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => switch (call.method) {
          'write' =>
            values[call.arguments['key'] as String] =
                call.arguments['value'] as String,
          'read' => values[call.arguments['key'] as String],
          'delete' => values.remove(call.arguments['key'] as String),
          'readAll' => Map<String, String>.from(values),
          'deleteAll' => values.clear(),
          _ => null,
        },
      );
}

/// In-memory [SignalingSocket]: records every frame the session sends and
/// lets the test emit server frames. Replies auth-ok to the auth frame.
class FakeSocket implements SignalingSocket {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  bool _closed = false;
  final String userId;

  final String? authError;

  FakeSocket({this.userId = 'me', this.authError});

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  bool get isClosed => _closed;

  @override
  String? get closeReason => null;

  @override
  void send(Map<String, dynamic> message) {
    sent.add(message);
    if (message['type'] == 'auth') {
      emit(
        authError != null
            ? {'type': 'error', 'message': authError}
            : {'type': 'auth-ok', 'userId': userId, 'displayName': 'Yo'},
      );
    }
  }

  void emit(Map<String, dynamic> frame) => _controller.add(frame);

  Map<String, dynamic>? lastOfType(String type) =>
      sent.where((m) => m['type'] == type).lastOrNull;

  @override
  Future<void> close() async {
    _closed = true;
    await _controller.close();
  }
}

/// Mutable backend state served over a MockClient: one instance whose
/// servers/channels/presence the test can rewrite mid-flight.
class FakeBackend {
  final List<Map<String, dynamic>> servers;
  final Map<String, List<Map<String, dynamic>>> channelsByServer;
  final Map<String, List<Map<String, dynamic>>> connectedByChannel;
  final Map<String, List<Map<String, dynamic>>> membersByServer;

  /// Attachment bytes keyed by path, so a test can serve a real image for
  /// /attachment/{id} and its /thumb.
  final Map<String, List<int>> blobs;

  /// When true, GET /server/{id}/members answers 500 — a polled refresh must
  /// survive that without toasting or dropping the roster it already has.
  bool membersFail = false;

  /// The next POST /server/{id}/upload response, or null to answer 500.
  Map<String, dynamic>? uploadResponse;

  /// History served by GET /channel/{id}/messages, newest first.
  final List<Map<String, dynamic>> messages = [];

  /// When set, uploads fail with this status instead of succeeding — the
  /// backend types its upload rejections (413/415/422/400/429) and the client
  /// maps each to its own message.
  int? uploadStatus;

  /// Records every multipart upload the client made.
  final List<String> uploadedPaths = [];

  /// How many invites POST /server/{id}/invite has minted, and the body of
  /// the last request ('' when it had none).
  int invitesCreated = 0;
  String lastInviteBody = '';

  /// Paths the client sent a DELETE to (the server logo is the only one).
  final List<String> deletedPaths = [];

  /// Bytes of the last encrypted upload (file part, thumb part).
  List<int>? lastEncryptedBlob;
  List<int>? lastEncryptedThumb;

  /// When set, the MLS routes are served by this delivery service; the
  /// identity is taken from the bearer token (`jwt-<user>`, or `me`).
  FakeDeliveryService? mls;

  FakeBackend({
    required this.servers,
    required this.channelsByServer,
    Map<String, List<Map<String, dynamic>>>? connectedByChannel,
    Map<String, List<Map<String, dynamic>>>? membersByServer,
    Map<String, List<int>>? blobs,
    this.uploadResponse,
  }) : connectedByChannel = connectedByChannel ?? {},
       membersByServer = membersByServer ?? {},
       blobs = blobs ?? {};

  http.Client client() => MockClient((request) async {
    final path = request.url.path;
    final auth = request.headers['Authorization'] ?? '';
    final userId = auth.startsWith('Bearer jwt-') ? auth.substring(11) : 'me';
    if (mls != null && path.contains('/mls')) {
      final handled = mls!.handle(request, userId);
      if (handled != null) return handled;
    }
    if (RegExp(r'^/server/[^/]+/upload/encrypted$').hasMatch(path)) {
      uploadedPaths.add(path);
      final status = uploadStatus;
      if (status != null) return http.Response('rejected', status);
      final parts = _multipartParts(request);
      lastEncryptedBlob = parts['file'];
      lastEncryptedThumb = parts['thumb'];
      final id = 'enc-${uploadedPaths.length}';
      blobs['/attachment/$id'] = parts['file']!;
      blobs['/attachment/$id/thumb'] = parts['thumb'] ?? parts['file']!;
      return http.Response(
        jsonEncode({
          'id': id,
          'serverId': 's1',
          'userId': userId,
          'mime': 'application/octet-stream',
          'size': parts['file']!.length,
          'thumbSize': (parts['thumb'] ?? parts['file'])!.length,
          'width': 0,
          'height': 0,
          'encrypted': true,
          'url': '/attachment/$id',
          'thumbUrl': '/attachment/$id/thumb',
          'createdAt': '2026-01-01T10:00:00Z',
        }),
        201,
      );
    }
    if (request.method == 'DELETE' &&
        RegExp(r'^/server/[^/]+/logo$').hasMatch(path)) {
      deletedPaths.add(path);
      return http.Response('', 204);
    }
    if (RegExp(r'^/server/[^/]+/logo$').hasMatch(path)) {
      uploadedPaths.add(path);
      final status = uploadStatus;
      if (status != null) return http.Response('rejected', status);
      // ServerLogoResponse: the public logo paths, not the attachment's own
      // (which needs a token).
      return http.Response(
        jsonEncode({
          'attachmentId': 'att-logo-new',
          'logoId': 'att-logo-new',
          'logoUrl': '/server/s1/logo?v=att-logo-new',
          'logoThumbUrl': '/server/s1/logo/thumb?v=att-logo-new',
        }),
        200,
      );
    }
    if (path == '/server') {
      return http.Response(jsonEncode(servers), 200);
    }
    if (RegExp(r'^/server/[^/]+/invite$').hasMatch(path)) {
      final token = 'tok-qr-${++invitesCreated}';
      lastInviteBody = request.body;
      return http.Response(
        jsonEncode({
          'inviteToken': token,
          'url': 'http://host:4000?invite=$token',
        }),
        201,
      );
    }
    final membersMatch = RegExp(r'^/server/([^/]+)/members$').firstMatch(path);
    if (membersMatch != null) {
      if (membersFail) return http.Response('boom', 500);
      return http.Response(
        jsonEncode(membersByServer[membersMatch.group(1)] ?? []),
        200,
      );
    }
    if (RegExp(r'^/server/[^/]+/upload$').hasMatch(path) ||
        path == '/me/avatar') {
      uploadedPaths.add(path);
      final status = uploadStatus;
      if (status != null) {
        return http.Response(
          'rejected',
          status,
          headers: status == 429 ? {'retry-after': '7'} : const {},
        );
      }
      final response = uploadResponse;
      if (response == null) return http.Response('boom', 500);
      return http.Response(jsonEncode(response), 201);
    }
    if (path.startsWith('/attachment/')) {
      final bytes = blobs[path];
      if (bytes == null) return http.Response('not found', 404);
      return http.Response.bytes(bytes, 200);
    }
    final serverMatch = RegExp(r'^/server/([^/]+)$').firstMatch(path);
    if (serverMatch != null) {
      final channels = channelsByServer[serverMatch.group(1)] ?? [];
      if (channels.isEmpty) return http.Response('not found', 404);
      return http.Response(jsonEncode(channels), 200);
    }
    if (path.endsWith('/messages')) {
      return http.Response(jsonEncode(messages), 200);
    }
    final channelMatch = RegExp(r'^/channel/([^/]+)$').firstMatch(path);
    if (channelMatch != null) {
      final id = channelMatch.group(1)!;
      final channel = channelsByServer.values
          .expand((list) => list)
          .where((c) => c['id'] == id)
          .firstOrNull;
      if (channel == null) return http.Response('not found', 404);
      final connected = connectedByChannel[id] ?? [];
      return http.Response(
        jsonEncode({
          ...channel,
          'connected': connected,
          'connectedCount': connected.length,
        }),
        200,
      );
    }
    return http.Response('unexpected: $path', 500);
  });
}

/// Splits a multipart body by the boundary in the content type, keeping the
/// raw bytes of each named part.
Map<String, List<int>> _multipartParts(http.Request request) {
  final contentType = request.headers['content-type'] ?? '';
  final boundary = RegExp(r'boundary=(.+)$').firstMatch(contentType)!.group(1)!;
  final bytes = request.bodyBytes;
  final sep = utf8.encode('--$boundary');
  final out = <String, List<int>>{};
  var start = _indexOf(bytes, sep, 0);
  while (start != -1) {
    start += sep.length;
    if (bytes.length >= start + 2 &&
        bytes[start] == 0x2D &&
        bytes[start + 1] == 0x2D) {
      break; // closing boundary
    }
    final headerEnd = _indexOf(bytes, utf8.encode('\r\n\r\n'), start);
    final headers = utf8.decode(bytes.sublist(start, headerEnd));
    final name = RegExp(r'name="([^"]+)"').firstMatch(headers)!.group(1)!;
    final next = _indexOf(bytes, sep, headerEnd);
    out[name] = bytes.sublist(headerEnd + 4, next - 2); // strip trailing CRLF
    start = next;
  }
  return out;
}

int _indexOf(List<int> haystack, List<int> needle, int from) {
  outer:
  for (var i = from; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// One server ("s1") with a text and a voice channel; "u2" (Bob) is sitting
/// in the voice channel.
FakeBackend defaultBackend({String ownerId = 'me'}) => FakeBackend(
  servers: [
    {'id': 's1', 'name': 'Test', 'ownerId': ownerId},
  ],
  channelsByServer: {
    's1': [
      {'id': 'c-text', 'serverId': 's1', 'name': 'general', 'type': 'text'},
      {'id': 'c-voice', 'serverId': 's1', 'name': 'General', 'type': 'voice'},
    ],
  },
  connectedByChannel: {
    'c-voice': [
      {'id': 'u2', 'displayName': 'Bob'},
    ],
  },
  membersByServer: {
    's1': [
      {
        'id': 'me',
        'displayName': 'Yo',
        'isOwner': ownerId == 'me',
        'online': true,
      },
      {
        'id': 'u2',
        'displayName': 'Bob',
        'isOwner': ownerId == 'u2',
        'online': false,
      },
    ],
  },
);

/// Fully connected session against [backend] and [socket] (auth handshake
/// done, servers/channels loaded).
Future<InstanceSession> connectedSession(
  FakeBackend backend,
  FakeSocket socket, {
  Duration pollInterval = const Duration(seconds: 10),
  String token = 'jwt',
  MlsStore? mlsStore,
}) async {
  final session = InstanceSession(
    StoredInstance(baseUrl: 'http://test', token: token),
    api: ArmonicHttpApi('http://test', client: backend.client()),
    connectSocket: (_) async => socket,
    pollInterval: pollInterval,
    // Without a delivery service the fake backend has no MLS routes, so the
    // session runs the clear-text protocol the older tests were written for.
    mlsFor: (api, tok) => backend.mls == null
        ? null
        : MlsClient(
            api,
            tok,
            baseUrl: 'http://test',
            store: mlsStore ?? MemoryMlsStore(),
          ),
  );
  // Deliver the instance's broadcasts to this socket, the way the real
  // server pushes them to every connected member.
  backend.mls?.listeners.add(socket.emit);
  await session.connect();
  // Drain the fire-and-forget loads (history, presence poll) so nothing
  // notifies after the test disposes the session.
  await drainEvents();
  return session;
}

/// Let queued async work (unawaited futures, stream deliveries) settle.
Future<void> drainEvents([int rounds = 20]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
