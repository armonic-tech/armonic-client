import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/models.dart';

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

  ArmonicHttpApi(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _client.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(resp);
  }

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
    final resp = await _client.get(
      _uri(path, query),
      headers: _authHeaders(token),
    );
    _ensureOk(resp);
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<InstanceInfo> info() async {
    final resp = await _client.get(_uri('/info'));
    return InstanceInfo.fromJson(_decode(resp));
  }

  /// GET /pow/challenge. Returns null when the instance has proof of work
  /// turned off (404), which is what lets one client talk to instances with
  /// it both on and off.
  Future<PowChallenge?> powChallenge() async {
    final resp = await _client.get(_uri('/pow/challenge'));
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
    final resp = await _client.get(_uri('/invite/status', {'token': token}));
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
    final resp = await _client.get(
      _uri('/channel/$channelId'),
      headers: _authHeaders(token),
    );
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
  Future<InviteCreated> createInvite(String token, String serverId) async {
    final resp = await _client.post(
      _uri('/server/$serverId/invite'),
      headers: _authHeaders(token),
    );
    return InviteCreated.fromJson(_decode(resp));
  }

  /// GET /me: the caller's own profile, including their avatar.
  Future<MeProfile> me(String token) async {
    final resp = await _client.get(_uri('/me'), headers: _authHeaders(token));
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
    final resp = await http.Response.fromStream(await _client.send(request));
    return Attachment.fromJson(_decode(resp));
  }

  /// The bytes behind an attachment path (/attachment/{id} or its /thumb).
  /// Membership-gated, so this cannot be an unauthenticated image URL.
  Future<Uint8List> attachmentBytes(String token, String path) async {
    final resp = await _client.get(_uri(path), headers: _authHeaders(token));
    _ensureOk(resp);
    return resp.bodyBytes;
  }
}
