import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/state/instance_store.dart';

import 'support/fakes.dart';

void main() {
  setUp(fakeSecureStorage);

  /// A store holding one instance, whose GET /server answers with [respond].
  InstanceStore storeWith(
    http.Response Function() respond, {
    String? token = 'jwt',
  }) {
    final store = InstanceStore(
      apiFor: (baseUrl) => ArmonicHttpApi(
        baseUrl,
        client: MockClient((req) async {
          expect(req.url.path, '/server');
          expect(req.headers['Authorization'], 'Bearer $token');
          return respond();
        }),
      ),
    );
    store.upsert(StoredInstance(baseUrl: 'http://test', token: token));
    return store;
  }

  test('an empty server list marks the instance as kicked', () async {
    final store = storeWith(() => http.Response(jsonEncode([]), 200));

    await store.refreshMemberships();

    expect(store.membershipOf('http://test'), Membership.notMember);
  });

  test('a server in the list marks the instance as a membership', () async {
    final store = storeWith(() => http.Response(
        jsonEncode([
          {'id': 's1', 'name': 'Test', 'ownerId': 'me'}
        ]),
        200));

    await store.refreshMemberships();

    expect(store.membershipOf('http://test'), Membership.member);
  });

  test('an unreachable instance is never mistaken for a kick', () async {
    final store = storeWith(() => throw Exception('connection refused'));

    await store.refreshMemberships();

    // unknown, not notMember: the rail must not accuse a server that is
    // merely down of having removed the user.
    expect(store.membershipOf('http://test'), Membership.unknown);
    expect(store.instances.single.token, 'jwt', reason: 'token kept');
  });

  test('a 500 is also unknown, not a kick', () async {
    final store = storeWith(() => http.Response('boom', 500));

    await store.refreshMemberships();

    expect(store.membershipOf('http://test'), Membership.unknown);
  });

  test('a 401 clears the token instead of marking a kick', () async {
    final store = storeWith(() => http.Response('unauthorized', 401));

    await store.refreshMemberships();

    expect(store.membershipOf('http://test'), Membership.unknown);
    expect(store.instances.single.token, isNull);
    expect(store.instances.single.baseUrl, 'http://test',
        reason: 'the entry stays in the rail');
  });

  test('an instance with no token is not probed at all', () async {
    var probed = false;
    final store = InstanceStore(apiFor: (baseUrl) {
      probed = true;
      return ArmonicHttpApi(baseUrl);
    });
    await store.upsert(StoredInstance(baseUrl: 'http://test'));

    await store.refreshMemberships();

    expect(probed, isFalse);
    expect(store.membershipOf('http://test'), Membership.unknown);
  });

  test('a redeemed invite un-marks the kick without another probe', () async {
    final store = storeWith(() => http.Response(jsonEncode([]), 200));
    await store.refreshMemberships();
    expect(store.membershipOf('http://test'), Membership.notMember);

    store.markMember('http://test');

    expect(store.membershipOf('http://test'), Membership.member);
  });

  test('re-adding an instance drops the stale kick', () async {
    final store = storeWith(() => http.Response(jsonEncode([]), 200));
    await store.refreshMemberships();
    expect(store.membershipOf('http://test'), Membership.notMember);

    await store.upsert(
        StoredInstance(baseUrl: 'http://test', token: 'fresh-jwt'));

    expect(store.membershipOf('http://test'), Membership.unknown);
  });
}