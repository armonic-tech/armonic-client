import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

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
      String path, Map<String, dynamic> body) async {
    final resp = await _client.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(resp);
  }

  Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(resp.statusCode, resp.body.trim());
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<InstanceInfo> info() async {
    final resp = await _client.get(_uri('/info'));
    return InstanceInfo.fromJson(_decode(resp));
  }

  /// step 1 claim
  Future<ClaimTicket> claimPassword(String password) async {
    final json = await _post('/claim/password', {'password': password});
    return ClaimTicket.fromJson(json);
  }

  /// step 2 of the claim flow
  Future<String> claimRegister(
      String ticket, String username, String password) async {
    final json = await _post('/claim/register', {
      'ticket': ticket,
      'username': username,
      'password': password,
    });
    return json['token'] as String;
  }

  /// returns the JWT
  Future<String> login(String username, String password) async {
    final json = await _post('/auth/login', {
      'username': username,
      'password': password,
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
      String token, String username, String password) async {
    final json = await _post('/invite/signup', {
      'token': token,
      'username': username,
      'password': password,
    });
    return json['token'] as String;
  }
}
