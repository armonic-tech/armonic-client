import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/api/ws_client.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/state/session.dart';

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

  /// When set, uploads fail with this status instead of succeeding — the
  /// backend types its upload rejections (413/415/422/400/429) and the client
  /// maps each to its own message.
  int? uploadStatus;

  /// Records every multipart upload the client made.
  final List<String> uploadedPaths = [];

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
    if (path == '/server') {
      return http.Response(jsonEncode(servers), 200);
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
      return http.Response(jsonEncode([]), 200);
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
}) async {
  final session = InstanceSession(
    StoredInstance(baseUrl: 'http://test', token: 'jwt'),
    api: ArmonicHttpApi('http://test', client: backend.client()),
    connectSocket: (_) async => socket,
    pollInterval: pollInterval,
  );
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
