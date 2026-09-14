import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:armonic_client/api/http_api.dart';

void main() {
  test('a backend that never answers fails instead of hanging', () async {
    final api = ArmonicHttpApi(
      'http://example.test',
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      api.info(),
      throwsA(
        isA<ApiTimeoutException>().having((e) => e.statusCode, 'status', 408),
      ),
    );
  });

  test('an answer within the deadline is unaffected', () async {
    final api = ArmonicHttpApi(
      'http://example.test',
      client: MockClient(
        (_) async =>
            http.Response('{"name":"n","description":"d","claimed":true}', 200),
      ),
      timeout: const Duration(milliseconds: 50),
    );

    expect((await api.info()).name, 'n');
  });
}
