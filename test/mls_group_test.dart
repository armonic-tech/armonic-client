import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/mls/crypto.dart';
import 'package:armonic_client/mls/group.dart';
import 'package:armonic_client/mls/key_package.dart';
import 'package:armonic_client/mls/tree.dart';

/// A member as the tests see it: its identity, its group state and the
/// key-package private keys it still holds.
class Peer {
  final String user;
  final String device;
  final SigningKeyPair identity;
  MlsGroup? group;
  final Map<String, HpkeKeyPair> packageKeys = {};

  Peer(this.user, this.device, this.identity);

  static Future<Peer> make(String user) async =>
      Peer(user, 'dev-$user', await MlsCrypto.newSigningKeyPair());

  Future<KeyPackage> keyPackage() async {
    final key = await MlsCrypto.newHpkeKeyPair();
    final id = 'kp-$device-${packageKeys.length}';
    packageKeys[id] = key;
    return KeyPackage.create(
      id: id,
      deviceId: device,
      userId: user,
      hpkeKey: key.publicKey,
      identity: identity,
    );
  }

  Future<void> join(Map<String, Object?> welcome) async {
    final kpId = welcome['keyPackageId'] as String;
    group = await MlsGroup.fromWelcome(
      welcome,
      deviceId: device,
      identity: identity,
      keyPackageKey: packageKeys.remove(kpId)!,
    );
  }
}

/// Runs a commit end to end: builds it on [committer], applies it on every
/// other current member, hands welcomes to the joiners.
Future<void> commit(
  Peer committer,
  List<Peer> others, {
  List<Peer> add = const [],
  List<Peer> remove = const [],
}) async {
  final packages = [for (final p in add) await p.keyPackage()];
  final bundle = await committer.group!.createCommit(
    adds: packages,
    removeDevices: [for (final p in remove) p.device],
  );
  // Round-trip through JSON: that is what the server relays.
  final wire = jsonDecode(jsonEncode(bundle.payload)) as Map<String, dynamic>;
  for (final other in others) {
    if (other.group == null) continue;
    final stillIn = await other.group!.applyCommit(
      Map<String, Object?>.from(wire),
    );
    if (!stillIn) other.group = null;
  }
  committer.group = bundle.next;
  for (final joiner in add) {
    final welcome = jsonDecode(jsonEncode(bundle.welcomes[joiner.device]));
    await joiner.join(Map<String, Object?>.from(welcome as Map));
  }
}

void expectSameEpoch(List<Peer> peers) {
  final first = peers.first.group!;
  for (final p in peers) {
    expect(p.group!.epoch, first.epoch, reason: '${p.user} epoch');
    expect(
      b64(p.group!.epochSecrets[p.group!.epoch]!),
      b64(first.epochSecrets[first.epoch]!),
      reason: '${p.user} epoch secret',
    );
    expect(
      p.group!.tree.toJson(),
      first.tree.toJson(),
      reason: '${p.user} tree',
    );
  }
}

Future<void> expectCanTalk(List<Peer> peers) async {
  for (final sender in peers) {
    final env = await sender.group!.encrypt(
      'chan',
      utf8.encode('hola de ${sender.user}'),
    );
    final decoded = Envelope.tryDecode(env.encode())!;
    for (final receiver in peers) {
      final plain = await receiver.group!.decrypt('chan', decoded);
      expect(utf8.decode(plain), 'hola de ${sender.user}');
    }
  }
}

void main() {
  group('ratchet tree layout (RFC 9420 §7.2 with 5 leaves)', () {
    final t = RatchetTree(List<TreeNode?>.filled(9, null));
    test('root, parents and children', () {
      expect(t.root, 7);
      expect(t.parent(0), 1);
      expect(t.parent(1), 3);
      expect(t.parent(3), 7);
      expect(t.parent(8), 7);
      expect(t.parent(7), isNull);
      expect(t.left(7), 3);
      expect(t.right(7), 8);
      expect(t.left(3), 1);
      expect(t.right(3), 5);
      expect(t.sibling(8), 3);
      expect(t.directPath(2), [5, 3, 7]);
      expect(t.directPath(4), [7]);
      expect(t.directPath(0), [1, 3, 7]);
      expect(t.lowestCommonAncestor(0, 2), 3);
      expect(t.lowestCommonAncestor(0, 4), 7);
      expect(t.lowestCommonAncestor(0, 1), 1);
      expect(t.isAncestorOf(3, 2), isTrue);
      expect(t.isAncestorOf(3, 4), isFalse);
    });
  });

  test('two members agree on the epoch secret after the first add', () async {
    final alice = await Peer.make('alice');
    final bob = await Peer.make('bob');
    alice.group = await MlsGroup.create(
      groupId: 'srv',
      deviceId: alice.device,
      userId: alice.user,
      identity: alice.identity,
    );
    expect(alice.group!.canSend, isFalse);

    await commit(alice, [], add: [bob]);

    expect(alice.group!.epoch, 1);
    expect(bob.group!.epoch, 1);
    expectSameEpoch([alice, bob]);
    await expectCanTalk([alice, bob]);
  });

  test(
    'adds, a non-creator commit and a removal keep everyone in sync',
    () async {
      final alice = await Peer.make('alice');
      final bob = await Peer.make('bob');
      final carol = await Peer.make('carol');
      final dave = await Peer.make('dave');
      alice.group = await MlsGroup.create(
        groupId: 'srv',
        deviceId: alice.device,
        userId: alice.user,
        identity: alice.identity,
      );
      await commit(alice, [], add: [bob]);
      await commit(bob, [alice], add: [carol, dave]);
      final all = [alice, bob, carol, dave];
      expectSameEpoch(all);
      await expectCanTalk(all);
      expect(alice.group!.members.map((m) => m.userId), [
        'alice',
        'bob',
        'carol',
        'dave',
      ]);

      // Carol evicts bob. Bob learns he is out; the rest move on without him.
      final bobBefore = bob.group!;
      await commit(carol, [alice, bob, dave], remove: [bob]);
      expect(bob.group, isNull);
      final rest = [alice, carol, dave];
      expectSameEpoch(rest);
      await expectCanTalk(rest);
      expect(alice.group!.epoch, 3);

      // A message from the new epoch is opaque to bob's last state.
      final env = await alice.group!.encrypt('chan', utf8.encode('secret'));
      await expectLater(
        () => bobBefore.decrypt('chan', env),
        throwsA(isA<MlsException>()),
      );

      // Old epochs stay readable for history.
      final old = Envelope(1, 0, MlsCrypto.randomBytes(12), Uint8List(0));
      expect(alice.group!.epochSecrets.containsKey(old.epoch), isTrue);
    },
  );

  test('a freed leaf is reused and the tree truncates', () async {
    final peers = [
      for (final n in ['a', 'b', 'c', 'd', 'e']) await Peer.make(n),
    ];
    peers[0].group = await MlsGroup.create(
      groupId: 'srv',
      deviceId: peers[0].device,
      userId: peers[0].user,
      identity: peers[0].identity,
    );
    await commit(peers[0], [], add: peers.sublist(1));
    expect(peers[0].group!.tree.leafCount, 5);

    // Remove the middle one: leaf 2 goes blank, tree keeps its width.
    await commit(peers[4], peers.sublist(0, 4), remove: [peers[2]]);
    expect(peers[0].group!.tree.leafCount, 5);
    expect(peers[0].group!.tree.nodes[4], isNull);

    // Remove the last one: the tree shrinks.
    await commit(peers[0], [peers[1], peers[3], peers[4]], remove: [peers[4]]);
    expect(peers[0].group!.tree.leafCount, 4);

    // A newcomer takes the blank leaf 2 rather than growing the tree.
    final f = await Peer.make('f');
    await commit(peers[1], [peers[0], peers[3]], add: [f]);
    expect(f.group!.leafIndex, 2);
    final live = [peers[0], peers[1], peers[3], f];
    expectSameEpoch(live);
    await expectCanTalk(live);
  });

  test('state survives a JSON round trip', () async {
    final alice = await Peer.make('alice');
    final bob = await Peer.make('bob');
    alice.group = await MlsGroup.create(
      groupId: 'srv',
      deviceId: alice.device,
      userId: alice.user,
      identity: alice.identity,
    );
    await commit(alice, [], add: [bob]);
    final restored = MlsGroup.fromJson(
      jsonDecode(jsonEncode(bob.group!.toJson())) as Map<String, Object?>,
    );
    bob.group = restored;
    final carol = await Peer.make('carol');
    await commit(bob, [alice], add: [carol]);
    expectSameEpoch([alice, bob, carol]);
    await expectCanTalk([alice, bob, carol]);
  });

  test(
    'a tampered commit is rejected and leaves the state untouched',
    () async {
      final alice = await Peer.make('alice');
      final bob = await Peer.make('bob');
      alice.group = await MlsGroup.create(
        groupId: 'srv',
        deviceId: alice.device,
        userId: alice.user,
        identity: alice.identity,
      );
      await commit(alice, [], add: [bob]);
      final carol = await Peer.make('carol');
      final bundle = await alice.group!.createCommit(
        adds: [await carol.keyPackage()],
      );
      final wire =
          jsonDecode(jsonEncode(bundle.payload)) as Map<String, Object?>;
      wire['removes'] = ['dev-bob'];
      final before = jsonEncode(bob.group!.toJson());
      await expectLater(
        () => bob.group!.applyCommit(wire),
        throwsA(isA<MlsException>()),
      );
      expect(jsonEncode(bob.group!.toJson()), before);
    },
  );
}
