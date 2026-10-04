import 'dart:convert';

import 'package:http/http.dart' as http;

/// An in-memory MLS delivery service with the same rules as the backend's
/// MLSRepo: epoch sequencing, one key package per add, welcomes per device.
/// Shared between the FakeBackends of several sessions so they can talk.
class FakeDeliveryService {
  final Map<String, String> devices = {}; // deviceId -> userId
  final Map<String, List<Map<String, String>>> packages = {}; // deviceId
  final Map<String, int> epochs = {};
  final Map<String, Map<String, String>> members = {}; // server -> dev -> user
  final Map<String, List<Map<String, dynamic>>> commits = {};
  final Map<String, Map<String, Map<String, dynamic>>> welcomes = {};

  /// Server memberships as the backend would know them.
  final Map<String, Set<String>> memberships = {};

  /// Who is online, for the coordinator pick; the owner of every server.
  Set<String> online = {};
  String owner = 'me';

  /// Every frame the "server" would broadcast over the WebSocket.
  final List<Map<String, dynamic>> broadcasts = [];

  /// Sockets the broadcasts are delivered to, as the real server pushes to
  /// every connected member. Registered by connectedSession.
  final List<void Function(Map<String, dynamic>)> listeners = [];

  void _broadcast(Map<String, dynamic> frame) {
    broadcasts.add(frame);
    for (final l in List.of(listeners)) {
      l(frame);
    }
  }

  http.Response? handle(http.Request request, String userId) {
    final path = request.url.path;
    Map<String, dynamic> body() =>
        request.body.isEmpty ? {} : jsonDecode(request.body);

    if (path == '/me/mls/device') {
      final b = body();
      final id = b['deviceId'] as String;
      if (devices[id] != null && devices[id] != userId) {
        return http.Response('taken', 409);
      }
      devices[id] = userId;
      return http.Response('', 204);
    }
    if (path == '/me/mls/keypackages') {
      final b = body();
      final dev = b['deviceId'] as String;
      if (devices[dev] != userId) return http.Response('forbidden', 403);
      for (final kp in b['keyPackages'] as List) {
        (packages[dev] ??= []).add({
          'id': kp['id'] as String,
          'payload': kp['payload'] as String,
        });
      }
      // The backend nudges every server the publisher belongs to, so a
      // committer notices the new device without polling.
      for (final entry in memberships.entries) {
        if (entry.value.contains(userId)) {
          _broadcast({'type': 'mls-sync', 'serverId': entry.key});
        }
      }
      return http.Response('', 204);
    }
    final state = RegExp(r'^/server/([^/]+)/mls$').firstMatch(path);
    if (state != null) {
      final sid = state.group(1)!;
      final dev = request.url.queryParameters['deviceId']!;
      if (devices[dev] != userId) return http.Response('forbidden', 403);
      final group = members[sid] ?? {};
      final adds = <Map<String, dynamic>>[];
      for (final d in devices.entries) {
        if (!(memberships[sid] ?? {}).contains(d.value)) continue;
        if (group.containsKey(d.key)) continue;
        final kp = (packages[d.key] ?? []).firstOrNull;
        if (kp == null) continue;
        adds.add({
          'deviceId': d.key,
          'userId': d.value,
          'keyPackageId': kp['id'],
          'keyPackage': kp['payload'],
        });
      }
      final removes = [
        for (final m in group.entries)
          if (!(memberships[sid] ?? {}).contains(m.value))
            {'deviceId': m.key, 'userId': m.value},
      ];
      final eligible = group.isEmpty
          ? adds.map((a) => a['userId'] as String).toSet()
          : group.values.toSet();
      final candidates = online.where(eligible.contains).toList()..sort();
      final coordinator = candidates.contains(owner)
          ? owner
          : candidates.firstOrNull;
      final welcome = welcomes[sid]?[dev];
      return http.Response(
        jsonEncode({
          'epoch': epochs[sid] ?? 0,
          'members': [
            for (final m in group.entries)
              {'deviceId': m.key, 'userId': m.value},
          ],
          'pendingAdds': adds,
          'pendingRemoves': removes,
          'coordinatorUserId': ?coordinator,
          'welcome': ?welcome,
          'keyPackagesLeft': (packages[dev] ?? []).length,
        }),
        200,
      );
    }
    final commitsMatch = RegExp(
      r'^/server/([^/]+)/mls/commits$',
    ).firstMatch(path);
    if (commitsMatch != null) {
      final sid = commitsMatch.group(1)!;
      final after = int.parse(request.url.queryParameters['after'] ?? '0');
      return http.Response(
        jsonEncode([
          for (final c in commits[sid] ?? [])
            if ((c['epoch'] as int) > after) c,
        ]),
        200,
      );
    }
    final commitMatch = RegExp(
      r'^/server/([^/]+)/mls/commit$',
    ).firstMatch(path);
    if (commitMatch != null) {
      final sid = commitMatch.group(1)!;
      final b = body();
      final dev = b['deviceId'] as String;
      if (devices[dev] != userId) return http.Response('forbidden', 403);
      final epoch = epochs[sid] ?? 0;
      if (b['epoch'] != epoch) return http.Response('stale epoch', 409);
      final group = members[sid] ??= {};
      if (!group.containsKey(dev)) {
        if (epoch != 0) return http.Response('not in group', 400);
        group[dev] = userId;
      }
      for (final r in b['removes'] as List) {
        if (group.remove(r) == null) return http.Response('bad remove', 400);
      }
      final ws = Map<String, dynamic>.from(b['welcomes'] as Map? ?? {});
      for (final a in b['adds'] as List) {
        final adDev = a['deviceId'] as String;
        final list = packages[adDev] ?? [];
        final i = list.indexWhere((kp) => kp['id'] == a['keyPackageId']);
        if (i == -1) return http.Response('bad add', 400);
        if (!ws.containsKey(adDev)) return http.Response('no welcome', 400);
        list.removeAt(i);
        group[adDev] = devices[adDev]!;
        (welcomes[sid] ??= {})[adDev] = {
          'id': 'w-${epoch + 1}-$adDev',
          'epoch': epoch + 1,
          'payload': ws[adDev],
        };
      }
      epochs[sid] = epoch + 1;
      (commits[sid] ??= []).add({
        'epoch': epoch + 1,
        'senderDeviceId': dev,
        'payload': b['payload'],
        'createdAt': '2026-01-01T00:00:00Z',
      });
      _broadcast({
        'type': 'mls-commit',
        'serverId': sid,
        'epoch': epoch + 1,
        'senderDeviceId': dev,
        'payload': b['payload'],
      });
      return http.Response(jsonEncode({'epoch': epoch + 1}), 200);
    }
    final ack = RegExp(r'^/server/([^/]+)/mls/welcome/ack$').firstMatch(path);
    if (ack != null) {
      final b = body();
      welcomes[ack.group(1)!]?.remove(b['deviceId']);
      return http.Response('', 204);
    }
    return null;
  }
}
