import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/util/invite_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('backendInviteLink', () {
    test('turns a web-client link back into the backend invite', () {
      final link = backendInviteLink(
        'https://chat.example.com/?instance=https%3A%2F%2Fapi.example.com%3A8443&invite=tok-1',
      );
      expect(link, 'https://api.example.com:8443?invite=tok-1');
      expect(normalizeBaseUrl(link), 'https://api.example.com:8443');
      expect(inviteTokenFromUrl(link), 'tok-1');
    });

    test('leaves a plain backend invite link untouched', () {
      const link = 'https://chat.example.com?invite=tok-2';
      expect(backendInviteLink(link), link);
    });

    test('leaves unrelated text untouched', () {
      expect(backendInviteLink('hello'), 'hello');
    });
  });

  test('a native build without ARMONIC_WEB_URL shares the backend link', () {
    const link = 'https://chat.example.com?invite=tok-3';
    expect(joinLinkFor(link), link);
  });

  test('a native build has no page invite', () {
    expect(pageInviteLink(), isNull);
  });
}
