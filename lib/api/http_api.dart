import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../util/log.dart';

/// Cap on every request. A backend that accepts the TCP connection and then
/// never answers (or a host that swallows packets) leaves `http` waiting on
/// the OS timeout, which is minutes — long enough that the UI looks hung.
const Duration defaultRequestTimeout = Duration(seconds: 10);

/// Uploads and attachment downloads move real bytes over the same link, so
/// they get their own, much longer budget.
const Duration defaultTransferTimeout = Duration(seconds: 60);

class ApiException implements Exception {
  final int statusCode;
  final String message;

  /// Seconds from the 429 response's Retry-After header, so the UI can say
  /// how long to wait instead of just "too many requests".
  final int? retryAfter;

  ApiException(this.statusCode, this.message, {this.retryAfter});

  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => message.isEmpty ? 'HTTP $statusCode' : message;
}

/// An `ApiException` so every existing `on ApiException` / `switch
/// (e.statusCode)` site keeps working; 408 is the status nobody else uses.
/// Its `toString` is localized because most screens fall back to printing it.
class ApiTimeoutException extends ApiException {
  ApiTimeoutException() : super(408, '');

  @override
  String toString() => strings.requestTimedOut;
}

String normalizeBaseUrl(String input) {
  var url = input.trim();
  if (url.isEmpty) return url;
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'http://$url';
  }
  final uri = Uri.parse(url);

  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  ).toString();
}

String? inviteTokenFromUrl(String input) {
  var url = input.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'http://$url';
  }
  return Uri.tryParse(url)?.queryParameters['invite'];
}

String wsUrlFor(String baseUrl) {
  final uri = Uri.parse(baseUrl);
  final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
  return uri.replace(scheme: scheme, path: '/ws').toString();
}

class ArmonicHttpApi {
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;
  final Duration transferTimeout;

  ArmonicHttpApi(
    this.baseUrl, {
    http.Client? client,
    this.timeout = defaultRequestTimeout,
    this.transferTimeout = defaultTransferTimeout,
  }) : _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  /// Every request goes through here, so no call site can forget the
  /// deadline and every failure leaves a log line. [what] is method + path,
  /// never the query string: invite status carries its token there.
  Future<http.Response> _timed(
    String what,
    Future<http.Response> request, [
    Duration? limit,
  ]) async {
    final sw = Stopwatch()..start();
    final http.Response resp;
    try {
      resp = await request.timeout(
        limit ?? timeout,
        onTimeout: () => throw ApiTimeoutException(),
      );
    } catch (e) {
      Log.w('http', '$what failed after ${sw.elapsedMilliseconds}ms', e);
      rethrow;
    }
    _logResponse(what, resp, sw.elapsedMilliseconds);
    return resp;
  }

  /// The server echoes X-Request-ID; quoting it finds the matching line in
  /// the backend log (`jq 'select(.req_id=="...")'`).
  void _logResponse(String what, http.Response resp, int ms) {
    final code = resp.statusCode;
    final reqId = resp.headers['x-request-id'];
    final line =
        '$what -> $code in ${ms}ms${reqId == null ? '' : ' (req $reqId)'}';
    if (code >= 500) {
      Log.e('http', line, _excerpt(resp));
    } else if (code >= 400 && code != 404) {
      Log.w('http', line, _excerpt(resp));
    } else {
      Log.d('http', line);
    }
  }

  static String _excerpt(http.Response resp) {
    final body = resp.body.trim();
    return body.length <= 200 ? body : '${body.substring(0, 200)}…';
  }

  Future<http.Response> _get(
    String path, {
    Map<String, String>? query,
    String? token,
    Duration? limit,
  }) => _timed(
    'GET $path',
    _client.get(
      _uri(path, query),
      headers: token == null ? null : _authHeaders(token),
    ),
    limit,
  );

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final resp = await _postRaw(path, body, token: token);
    return _decode(resp);
  }

  Future<http.Response> _postRaw(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) => _timed(
    'POST $path',
    _client.post(
      _uri(path),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) ..._authHeaders(token),
      },
      body: jsonEncode(body),
    ),
  );

  Map<String, dynamic> _decode(http.Response resp) {
    _ensureOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(
        resp.statusCode,
        resp.body.trim(),
        retryAfter: int.tryParse(resp.headers['retry-after'] ?? ''),
      );
    }
  }

  Map<String, String> _authHeaders(String token) => {
    'Authorization': 'Bearer $token',
  };

  Future<List<dynamic>> _getList(
    String path,
    String token, [
    Map<String, String>? query,
  ]) async {
    final resp = await _get(path, query: query, token: token);
    _ensureOk(resp);
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<InstanceInfo> info() async {
    final resp = await _get('/info');
    return InstanceInfo.fromJson(_decode(resp));
  }

  /// GET /pow/challenge. Returns null when the instance has proof of work
  /// turned off (404), which is what lets one client talk to instances with
  /// it both on and off.
  Future<PowChallenge?> powChallenge() async {
    final resp = await _get('/pow/challenge');
    if (resp.statusCode == 404) return null;
    return PowChallenge.fromJson(_decode(resp));
  }

  /// step 1 claim
  Future<ClaimTicket> claimPassword(String password, {String? altcha}) async {
    final json = await _post('/claim/password', {
      'password': password,
      'altcha': ?altcha,
    });
    return ClaimTicket.fromJson(json);
  }

  /// step 2 of the claim flow
  Future<String> claimRegister(
    String ticket,
    String username,
    String password,
  ) async {
    final json = await _post('/claim/register', {
      'ticket': ticket,
      'username': username,
      'password': password,
    });
    return json['token'] as String;
  }

  /// returns the JWT
  Future<String> login(
    String username,
    String password, {
    String? altcha,
  }) async {
    final json = await _post('/auth/login', {
      'username': username,
      'password': password,
      'altcha': ?altcha,
    });
    return json['token'] as String;
  }

  /// 410 = invalid/expired/already-used invite.
  Future<InviteStatus> inviteStatus(String token) async {
    final resp = await _get('/invite/status', query: {'token': token});
    return InviteStatus.fromJson(_decode(resp));
  }

  /// 410 Gone = invite no longer valid, 409 = username taken.
  Future<String> inviteSignup(
    String token,
    String username,
    String password, {
    String? altcha,
  }) async {
    final json = await _post('/invite/signup', {
      'token': token,
      'username': username,
      'password': password,
      'altcha': ?altcha,
    });
    return json['token'] as String;
  }

  // --- Authenticated reads (Bearer JWT). These replaced the old
  // get-servers / get-channels / get-messages WS messages. ---

  /// GET /server: the servers the authenticated user is a member of.
  Future<List<ServerInfo>> myServers(String token) async {
    final list = await _getList('/server', token);
    return [
      for (final s in list) ServerInfo.fromJson(s as Map<String, dynamic>),
    ];
  }

  /// GET /server/{id}: the channels of a server (member only).
  /// The backend answers 404 when the server has no channels — mapped to [].
  Future<List<ChannelInfo>> serverChannels(
    String token,
    String serverId,
  ) async {
    try {
      final list = await _getList('/server/$serverId', token);
      return [
        for (final c in list) ChannelInfo.fromJson(c as Map<String, dynamic>),
      ];
    } on ApiException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  /// GET /channel/{id}: one channel enriched with live voice presence.
  Future<ChannelDetail> channelDetail(String token, String channelId) async {
    final resp = await _get('/channel/$channelId', token: token);
    return ChannelDetail.fromJson(_decode(resp));
  }

  /// GET /channel/{id}/messages: a page of messages, NEWEST FIRST
  /// (the caller must reverse for display). Default 50, max 100.
  Future<List<ChatMessage>> channelMessages(
    String token,
    String channelId, {
    int limit = 50,
  }) async {
    final list = await _getList('/channel/$channelId/messages', token, {
      'limit': '$limit',
    });
    return [
      for (final m in list) ChatMessage.fromJson(m as Map<String, dynamic>),
    ];
  }

  /// POST /server/{id}/invite: owner only (403 otherwise). Single use, 24h.
  /// [bot] makes the account it creates a bot account.
  Future<InviteCreated> createInvite(
    String token,
    String serverId, {
    bool bot = false,
  }) async {
    final resp = await _timed(
      'POST /server/$serverId/invite',
      _client.post(
        _uri('/server/$serverId/invite'),
        headers: bot
            ? {..._authHeaders(token), 'Content-Type': 'application/json'}
            : _authHeaders(token),
        body: bot ? jsonEncode({'bot': true}) : null,
      ),
    );
    return InviteCreated.fromJson(_decode(resp));
  }

  /// GET /me: the caller's own profile, including their avatar.
  Future<MeProfile> me(String token) async {
    final resp = await _get('/me', token: token);
    return MeProfile.fromJson(_decode(resp));
  }

  /// GET /server/{id}/members: the roster, with display names, avatars, the
  /// owner flag and who is online right now.
  Future<List<Member>> serverMembers(String token, String serverId) async {
    final list = await _getList('/server/$serverId/members', token);
    return [for (final m in list) Member.fromJson(m as Map<String, dynamic>)];
  }

  /// POST /server/{id}/upload. The backend decides the format from the file's
  /// magic bytes and ignores both the filename and the declared content type,
  /// so neither has to be honest here.
  Future<Attachment> uploadImage(
    String token,
    String serverId,
    Uint8List bytes,
    String filename,
  ) => _upload('/server/$serverId/upload', token, bytes, filename);

  /// POST /server/{id}/logo: owner only (403 otherwise). Same pipeline as an
  /// attachment, then points the server's logo at it. The response carries
  /// the public logo URLs — the attachment's own URL needs a token, so it is
  /// no use to the rail.
  Future<ServerLogo> uploadServerLogo(
    String token,
    String serverId,
    Uint8List bytes,
    String filename,
  ) async {
    final request =
        http.MultipartRequest('POST', _uri('/server/$serverId/logo'))
          ..headers.addAll(_authHeaders(token))
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: filename.isEmpty ? 'logo' : filename,
            ),
          );
    final resp = await _timed(
      'POST /server/$serverId/logo (${bytes.length} bytes)',
      _client.send(request).then(http.Response.fromStream),
      transferTimeout,
    );
    return ServerLogo.fromJson(_decode(resp));
  }

  /// DELETE /server/{id}/logo: owner only. Leaves the server with no logo;
  /// 204 even when it had none.
  Future<void> deleteServerLogo(String token, String serverId) async {
    final resp = await _timed(
      'DELETE /server/$serverId/logo',
      _client.delete(
        _uri('/server/$serverId/logo'),
        headers: _authHeaders(token),
      ),
    );
    _ensureOk(resp);
  }

  /// POST /me/avatar: same pipeline, then points the caller's avatar at it.
  Future<Attachment> uploadAvatar(
    String token,
    Uint8List bytes,
    String filename,
  ) => _upload('/me/avatar', token, bytes, filename);

  Future<Attachment> _upload(
    String path,
    String token,
    Uint8List bytes,
    String filename,
  ) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_authHeaders(token))
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename.isEmpty ? 'upload' : filename,
        ),
      );
    final resp = await _timed(
      'POST $path (${bytes.length} bytes)',
      _client.send(request).then(http.Response.fromStream),
      transferTimeout,
    );
    return Attachment.fromJson(_decode(resp));
  }

  /// POST /server/{id}/upload/encrypted: two opaque ciphertexts the server
  /// stores without looking at them. 507 = storage quota exceeded.
  Future<Attachment> uploadEncrypted(
    String token,
    String serverId,
    Uint8List ciphertext,
    Uint8List thumbCiphertext,
  ) async {
    final request =
        http.MultipartRequest(
            'POST',
            _uri('/server/$serverId/upload/encrypted'),
          )
          ..headers.addAll(_authHeaders(token))
          ..files.add(
            http.MultipartFile.fromBytes('file', ciphertext, filename: 'blob'),
          )
          ..files.add(
            http.MultipartFile.fromBytes(
              'thumb',
              thumbCiphertext,
              filename: 'thumb',
            ),
          );
    final resp = await _timed(
      'POST /server/$serverId/upload/encrypted '
      '(${ciphertext.length}+${thumbCiphertext.length} bytes)',
      _client.send(request).then(http.Response.fromStream),
      transferTimeout,
    );
    return Attachment.fromJson(_decode(resp));
  }

  /// The bytes behind an attachment path (/attachment/{id} or its /thumb).
  /// Membership-gated, so this cannot be an unauthenticated image URL.
  Future<Uint8List> attachmentBytes(String token, String path) async {
    final resp = await _get(path, token: token, limit: transferTimeout);
    _ensureOk(resp);
    return resp.bodyBytes;
  }

  /// GET /me/storage: bytes used against the per-user upload quota.
  Future<StorageUsage> storage(String token) async {
    final resp = await _get('/me/storage', token: token);
    return StorageUsage.fromJson(_decode(resp));
  }

  // --- MLS delivery service. The payloads are opaque to the server and to
  // this class: it moves JSON strings, the MLS layer owns their meaning. ---

  Future<void> registerDevice(
    String token,
    String deviceId,
    String signingKey,
  ) async {
    _ensureOk(
      await _postRaw('/me/mls/device', {
        'deviceId': deviceId,
        'signingKey': signingKey,
      }, token: token),
    );
  }

  Future<void> publishKeyPackages(
    String token,
    String deviceId,
    Map<String, String> packagesById,
  ) async {
    _ensureOk(
      await _postRaw('/me/mls/keypackages', {
        'deviceId': deviceId,
        'keyPackages': [
          for (final e in packagesById.entries)
            {'id': e.key, 'payload': e.value},
        ],
      }, token: token),
    );
  }

  Future<MlsGroupState> mlsState(
    String token,
    String serverId,
    String deviceId,
  ) async {
    final resp = await _get(
      '/server/$serverId/mls',
      query: {'deviceId': deviceId},
      token: token,
    );
    return MlsGroupState.fromJson(_decode(resp));
  }

  Future<List<MlsCommit>> mlsCommits(
    String token,
    String serverId,
    int after,
  ) async {
    final list = await _getList('/server/$serverId/mls/commits', token, {
      'after': '$after',
    });
    return [
      for (final c in list) MlsCommit.fromJson(c as Map<String, dynamic>),
    ];
  }

  /// 409 = stale epoch: fetch the commits you missed and rebuild.
  Future<int> mlsCommit(
    String token,
    String serverId,
    Map<String, dynamic> body,
  ) async {
    final json = await _post(
      '/server/$serverId/mls/commit',
      body,
      token: token,
    );
    return (json['epoch'] as num).toInt();
  }

  Future<void> mlsAckWelcome(
    String token,
    String serverId,
    String welcomeId,
    String deviceId,
  ) async {
    _ensureOk(
      await _postRaw('/server/$serverId/mls/welcome/ack', {
        'id': welcomeId,
        'deviceId': deviceId,
      }, token: token),
    );
  }
}
