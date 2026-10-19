import 'package:flutter/foundation.dart';

import '../api/http_api.dart';

/// The web client a QR should open, for a build not served from it (desktop,
/// Android): `--dart-define=ARMONIC_WEB_URL=https://chat.example.com`.
const String webClientUrl = String.fromEnvironment('ARMONIC_WEB_URL');

/// What an invite QR carries. A phone scanning it with its camera app just
/// opens the URL in a browser, so it must land on the web client, not on the
/// backend the invite names. When the two share an origin the link is
/// `<web>?invite=<token>`; otherwise the backend rides along as `instance`.
String joinLinkFor(String inviteUrl) {
  final token = inviteTokenFromUrl(inviteUrl);
  if (token == null || token.isEmpty) return inviteUrl;
  final web = webClientUrl.isNotEmpty
      ? Uri.parse(webClientUrl)
      : kIsWeb
      ? Uri.base
      : null;
  if (web == null) return inviteUrl;
  final backend = normalizeBaseUrl(inviteUrl);
  final sameOrigin = web.origin == Uri.parse(backend).origin;
  return Uri(
    scheme: web.scheme,
    host: web.host,
    port: web.hasPort ? web.port : null,
    path: web.path.isEmpty ? '/' : web.path,
    queryParameters: {if (!sameOrigin) 'instance': backend, 'invite': token},
  ).toString();
}

/// Turns a link made by [joinLinkFor] back into the `<backend>?invite=<token>`
/// shape onboarding understands. Anything else is returned untouched.
String backendInviteLink(String input) {
  final uri = Uri.tryParse(input.trim());
  final token = uri?.queryParameters['invite'];
  final instance = uri?.queryParameters['instance'];
  if (token == null || token.isEmpty || instance == null || instance.isEmpty) {
    return input;
  }
  return _inviteAt(normalizeBaseUrl(instance), token);
}

/// The invite this page was opened with (web only): the QR flow lands here.
String? pageInviteLink() {
  if (!kIsWeb) return null;
  final params = Uri.base.queryParameters;
  final token = params['invite'];
  if (token == null || token.isEmpty) return null;
  final instance = params['instance'];
  final backend = instance == null || instance.isEmpty
      ? Uri.base.origin
      : normalizeBaseUrl(instance);
  return _inviteAt(backend, token);
}

String _inviteAt(String backend, String token) =>
    '$backend?invite=${Uri.encodeQueryComponent(token)}';
