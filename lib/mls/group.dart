import 'dart:convert';
import 'dart:typed_data';

import 'crypto.dart';
import 'key_package.dart';
import 'tree.dart';

class MlsException implements Exception {
  final String message;
  const MlsException(this.message);
  @override
  String toString() => 'MlsException: $message';
}

/// The result of building a commit locally: what to post to the server and
/// the state to adopt once the server accepts it.
class CommitBundle {
  final Map<String, Object?> payload;
  final Map<String, Map<String, Object?>> welcomes;
  final List<({String deviceId, String keyPackageId})> adds;
  final List<String> removes;
  final MlsGroup next;

  const CommitBundle({
    required this.payload,
    required this.welcomes,
    required this.adds,
    required this.removes,
    required this.next,
  });
}

/// The wire shape of an encrypted application message.
class Envelope {
  final int epoch;
  final int senderLeaf;
  final Uint8List nonce;
  final Uint8List ciphertext;

  const Envelope(this.epoch, this.senderLeaf, this.nonce, this.ciphertext);

  String encode() => jsonEncode({
    'v': 1,
    'e': epoch,
    's': senderLeaf,
    'n': b64(nonce),
    'c': b64(ciphertext),
  });

  static Envelope? tryDecode(String content) {
    try {
      final json = jsonDecode(content);
      if (json is! Map || json['v'] != 1) return null;
      return Envelope(
        json['e'] as int,
        json['s'] as int,
        unb64(json['n'] as String),
        unb64(json['c'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// One device's view of one group: the public tree, the private keys it
/// holds for nodes on its own path, and the secret of every epoch it has
/// lived through.
///
/// Epoch secrets are *kept*, not deleted as RFC 9420 prescribes: the chat
/// re-reads history from the server, and a member must be able to decrypt
/// the messages of the epochs it was present for after a restart. That
/// trades forward secrecy on the device for a usable history; a wiped
/// device loses both.
class MlsGroup {
  final String groupId;
  final String deviceId;
  final SigningKeyPair identity;
  int epoch;
  RatchetTree tree;
  int leafIndex;

  /// Node index → private key, for the leaf and the path nodes we derived.
  final Map<int, HpkeKeyPair> privateKeys;
  final Map<int, Uint8List> epochSecrets;

  MlsGroup({
    required this.groupId,
    required this.deviceId,
    required this.identity,
    required this.epoch,
    required this.tree,
    required this.leafIndex,
    required this.privateKeys,
    required this.epochSecrets,
  });

  static final _zeroSecret = Uint8List(32);

  LeafInfo get me => tree.nodes[RatchetTree.leafToNode(leafIndex)]!.leaf!;

  bool get canSend => epochSecrets.containsKey(epoch);

  List<LeafInfo> get members => tree.members;

  MlsGroup _copy() => MlsGroup(
    groupId: groupId,
    deviceId: deviceId,
    identity: identity,
    epoch: epoch,
    tree: tree.clone(),
    leafIndex: leafIndex,
    privateKeys: Map.of(privateKeys),
    epochSecrets: Map.of(epochSecrets),
  );

  // ---- creation ----------------------------------------------------------

  /// A brand-new group with only this device in it. The first commit it
  /// posts (epoch 0 → 1) is what makes the group exist for everyone else.
  static Future<MlsGroup> create({
    required String groupId,
    required String deviceId,
    required String userId,
    required SigningKeyPair identity,
  }) async {
    final leafKey = await MlsCrypto.newHpkeKeyPair();
    final tree = RatchetTree.empty();
    final leaf = tree.addLeaf(
      TreeNode(
        leafKey.publicKey,
        leaf: LeafInfo(
          deviceId: deviceId,
          userId: userId,
          signingKey: identity.publicKey,
          keyPackageId: '',
        ),
      ),
    );
    return MlsGroup(
      groupId: groupId,
      deviceId: deviceId,
      identity: identity,
      epoch: 0,
      tree: tree,
      leafIndex: leaf,
      privateKeys: {RatchetTree.leafToNode(leaf): leafKey},
      epochSecrets: {},
    );
  }

  // ---- commits -----------------------------------------------------------

  /// Builds a commit that removes [removeDevices], adds [adds] and re-keys
  /// this member's path. Nothing is applied here — [CommitBundle.next] is
  /// the state to switch to once the server accepts the commit.
  Future<CommitBundle> createCommit({
    List<KeyPackage> adds = const [],
    List<String> removeDevices = const [],
  }) async {
    if (!canSend && epoch != 0) {
      throw const MlsException('no secret for the current epoch');
    }
    final next = _copy();
    final t = next.tree;

    final removes = <String>[];
    for (final dev in removeDevices) {
      final leaf = t.leafOfDevice(dev);
      if (leaf == null || leaf == leafIndex) continue;
      t.removeLeaf(leaf);
      removes.add(dev);
    }
    final addedLeaves = <int>[];
    final addedPackages = <KeyPackage>[];
    for (final kp in adds) {
      if (!await kp.verify()) throw const MlsException('bad key package');
      if (t.leafOfDevice(kp.deviceId) != null) continue;
      final leaf = t.addLeaf(
        TreeNode(
          kp.hpkeKey,
          leaf: LeafInfo(
            deviceId: kp.deviceId,
            userId: kp.userId,
            signingKey: kp.signingKey,
            keyPackageId: kp.id,
          ),
        ),
      );
      addedLeaves.add(leaf);
      addedPackages.add(kp);
    }
    // Removing/adding may have moved nothing of ours, but every private key
    // we held on a now-blank node is gone.
    next.privateKeys.removeWhere(
      (node, _) => node < t.nodes.length && t.nodes[node] == null,
    );
    next.privateKeys.removeWhere((node, _) => node >= t.nodes.length);

    // Fresh leaf secret, then one path secret per ancestor, each one derived
    // from the last so a single decryption unlocks everything above it.
    final myNode = RatchetTree.leafToNode(leafIndex);
    var pathSecret = MlsCrypto.randomBytes(32);
    final leafKey = await MlsCrypto.hpkeKeyPairFromSeed(
      await MlsCrypto.derive(pathSecret, 'node'),
    );
    t.nodes[myNode] = TreeNode(leafKey.publicKey, leaf: me);
    next.privateKeys[myNode] = leafKey;

    final pathSecrets = <int, Uint8List>{};
    final pathNodes = <Map<String, Object?>>[];
    final excluded = addedLeaves.toSet();
    for (final node in t.directPath(leafIndex)) {
      pathSecret = await MlsCrypto.derive(pathSecret, 'path');
      pathSecrets[node] = pathSecret;
      final nodeKey = await MlsCrypto.hpkeKeyPairFromSeed(
        await MlsCrypto.derive(pathSecret, 'node'),
      );
      t.nodes[node] = TreeNode(nodeKey.publicKey);
      next.privateKeys[node] = nodeKey;

      // The copath child is the subtree that does not contain us; every key
      // in its resolution gets the secret, except leaves joining right now —
      // they learn it from their welcome instead.
      final copathChild = t.left(node) == _childToward(t, node, leafIndex)
          ? t.right(node)
          : t.left(node);
      final cts = <Map<String, Object?>>[];
      for (final target in t.resolution(copathChild)) {
        if (RatchetTree.isLeaf(target) &&
            excluded.contains(RatchetTree.nodeToLeaf(target))) {
          continue;
        }
        final box = await MlsCrypto.sealTo(
          t.nodes[target]!.publicKey,
          pathSecret,
          context: _pathContext(node),
        );
        cts.add({'to': target, ...box.toJson()});
      }
      pathNodes.add({'node': node, 'pub': b64(nodeKey.publicKey), 'cts': cts});
    }
    final commitSecret = await MlsCrypto.derive(pathSecret, 'path');

    next.epoch = epoch + 1;
    final treeHash = await t.hash();
    final newSecret = await _nextEpochSecret(
      epochSecrets[epoch] ?? _zeroSecret,
      commitSecret,
      next.epoch,
      treeHash,
    );
    next.epochSecrets[next.epoch] = newSecret;

    final body = <String, Object?>{
      'v': 1,
      'groupId': groupId,
      'epoch': epoch,
      'sender': leafIndex,
      'senderDeviceId': deviceId,
      'removes': removes,
      'adds': [
        for (var i = 0; i < addedPackages.length; i++)
          {'leaf': addedLeaves[i], 'kp': addedPackages[i].toJson()},
      ],
      'leafPub': b64(leafKey.publicKey),
      'path': pathNodes,
      'treeHash': b64(treeHash),
    };
    final signature = await MlsCrypto.sign(identity, canonicalJson(body));
    final payload = {...body, 'signature': b64(signature)};
    final welcomes = <String, Map<String, Object?>>{};
    for (var i = 0; i < addedPackages.length; i++) {
      final leaf = addedLeaves[i];
      final lca = t.lowestCommonAncestor(leafIndex, leaf);
      final secret = pathSecrets[lca];
      final sealed = await MlsCrypto.sealTo(
        addedPackages[i].hpkeKey,
        canonicalJson({
          'epochSecret': b64(newSecret),
          'lca': lca,
          'lcaSecret': secret == null ? null : b64(secret),
        }),
        context: utf8.encode('welcome/$groupId/${next.epoch}'),
      );
      welcomes[addedPackages[i].deviceId] = {
        'v': 1,
        'groupId': groupId,
        'epoch': next.epoch,
        'leaf': leaf,
        'keyPackageId': addedPackages[i].id,
        'senderDeviceId': deviceId,
        'tree': t.toJson(),
        'sealed': sealed.toJson(),
      };
    }

    return CommitBundle(
      payload: payload,
      welcomes: welcomes,
      adds: [
        for (final kp in addedPackages)
          (deviceId: kp.deviceId, keyPackageId: kp.id),
      ],
      removes: removes,
      next: next,
    );
  }

  static int _childToward(RatchetTree t, int node, int leaf) =>
      t.isAncestorOf(t.left(node), leaf) ? t.left(node) : t.right(node);

  List<int> _pathContext(int node) =>
      utf8.encode('path/$groupId/${epoch + 1}/$node');

  static Future<Uint8List> _nextEpochSecret(
    Uint8List previous,
    Uint8List commitSecret,
    int epoch,
    Uint8List treeHash,
  ) => MlsCrypto.derive(
    commitSecret,
    'epoch',
    salt: previous,
    context: [...utf8.encode('$epoch/'), ...treeHash],
  );

  /// Applies a commit someone else posted. Returns false when the commit
  /// removed *this* device — the caller should drop the group.
  Future<bool> applyCommit(Map<String, Object?> payload) async {
    if (payload['groupId'] != groupId || payload['epoch'] != epoch) {
      throw MlsException(
        'commit for epoch ${payload['epoch']}, group is at $epoch',
      );
    }
    final senderLeaf = payload['sender'] as int;
    final senderNode = RatchetTree.leafToNode(senderLeaf);
    final sender = senderNode < tree.nodes.length
        ? tree.nodes[senderNode]?.leaf
        : null;
    if (sender == null || sender.deviceId != payload['senderDeviceId']) {
      throw const MlsException('commit from a device not in the group');
    }
    final body = Map<String, Object?>.from(payload)..remove('signature');
    final ok = await MlsCrypto.verify(
      sender.signingKey,
      canonicalJson(body),
      unb64(payload['signature'] as String),
    );
    if (!ok) throw const MlsException('bad commit signature');

    final removes = (payload['removes'] as List).cast<String>();
    if (removes.contains(deviceId)) return false;

    // Work on a copy: a malformed commit must not leave the state half
    // applied, or every later commit fails too.
    final next = _copy();
    final t = next.tree;
    final privateKeys = next.privateKeys;
    for (final dev in removes) {
      final leaf = t.leafOfDevice(dev);
      if (leaf != null) t.removeLeaf(leaf);
    }
    for (final raw in payload['adds'] as List) {
      final add = Map<String, Object?>.from(raw as Map);
      final kp = KeyPackage.fromJson(
        Map<String, Object?>.from(add['kp'] as Map),
      );
      if (!await kp.verify()) throw const MlsException('bad key package');
      final leaf = t.addLeaf(
        TreeNode(
          kp.hpkeKey,
          leaf: LeafInfo(
            deviceId: kp.deviceId,
            userId: kp.userId,
            signingKey: kp.signingKey,
            keyPackageId: kp.id,
          ),
        ),
      );
      if (leaf != add['leaf']) {
        throw const MlsException('leaf placement diverged from the committer');
      }
    }
    privateKeys.removeWhere(
      (node, _) => node >= t.nodes.length || t.nodes[node] == null,
    );

    t.nodes[senderNode] = TreeNode(
      unb64(payload['leafPub'] as String),
      leaf: sender,
    );
    final lca = t.lowestCommonAncestor(senderLeaf, leafIndex);
    Uint8List? pathSecret;
    for (final raw in payload['path'] as List) {
      final entry = Map<String, Object?>.from(raw as Map);
      final node = entry['node'] as int;
      final pub = unb64(entry['pub'] as String);
      if (pathSecret == null && node == lca) {
        for (final rawCt in entry['cts'] as List) {
          final ct = Map<String, Object?>.from(rawCt as Map);
          final key = privateKeys[ct['to'] as int];
          if (key == null) continue;
          pathSecret = await MlsCrypto.openWith(
            key,
            SealedBox.fromJson(ct),
            context: _pathContext(node),
          );
          break;
        }
        if (pathSecret == null) {
          throw const MlsException('no ciphertext addressed to this device');
        }
      } else if (pathSecret != null) {
        pathSecret = await MlsCrypto.derive(pathSecret, 'path');
      }
      if (pathSecret != null) {
        final nodeKey = await MlsCrypto.hpkeKeyPairFromSeed(
          await MlsCrypto.derive(pathSecret, 'node'),
        );
        if (!bytesEqual(nodeKey.publicKey, pub)) {
          throw const MlsException('derived node key does not match');
        }
        privateKeys[node] = nodeKey;
      } else {
        privateKeys.remove(node);
      }
      t.nodes[node] = TreeNode(pub);
    }
    if (pathSecret == null) throw const MlsException('empty update path');
    final commitSecret = await MlsCrypto.derive(pathSecret, 'path');

    final treeHash = await t.hash();
    if (!bytesEqual(treeHash, unb64(payload['treeHash'] as String))) {
      throw const MlsException('tree hash mismatch');
    }
    final newEpoch = epoch + 1;
    final newSecret = await _nextEpochSecret(
      epochSecrets[epoch] ?? _zeroSecret,
      commitSecret,
      newEpoch,
      treeHash,
    );
    tree = t;
    this.privateKeys
      ..clear()
      ..addAll(privateKeys);
    epochSecrets[newEpoch] = newSecret;
    epoch = newEpoch;
    return true;
  }

  // ---- joining -----------------------------------------------------------

  static Future<MlsGroup> fromWelcome(
    Map<String, Object?> welcome, {
    required String deviceId,
    required SigningKeyPair identity,
    required HpkeKeyPair keyPackageKey,
  }) async {
    final groupId = welcome['groupId'] as String;
    final epoch = welcome['epoch'] as int;
    final leaf = welcome['leaf'] as int;
    final tree = RatchetTree.fromJson(
      Map<String, Object?>.from(welcome['tree'] as Map),
    );
    final myNode = RatchetTree.leafToNode(leaf);
    final mine = tree.nodes[myNode];
    if (mine?.leaf?.deviceId != deviceId ||
        !bytesEqual(mine!.publicKey, keyPackageKey.publicKey)) {
      throw const MlsException('welcome does not match this device');
    }
    final opened = jsonDecode(
      utf8.decode(
        await MlsCrypto.openWith(
          keyPackageKey,
          SealedBox.fromJson(
            Map<String, Object?>.from(welcome['sealed'] as Map),
          ),
          context: utf8.encode('welcome/$groupId/$epoch'),
        ),
      ),
    );
    final privateKeys = {myNode: keyPackageKey};
    final lcaSecret = opened['lcaSecret'] as String?;
    if (lcaSecret != null) {
      var secret = unb64(lcaSecret);
      var reached = false;
      for (final node in tree.directPath(leaf)) {
        if (node == opened['lca']) reached = true;
        if (!reached) continue;
        final key = await MlsCrypto.hpkeKeyPairFromSeed(
          await MlsCrypto.derive(secret, 'node'),
        );
        if (!bytesEqual(key.publicKey, tree.nodes[node]!.publicKey)) {
          throw const MlsException('welcome path does not match the tree');
        }
        privateKeys[node] = key;
        secret = await MlsCrypto.derive(secret, 'path');
      }
    }
    return MlsGroup(
      groupId: groupId,
      deviceId: deviceId,
      identity: identity,
      epoch: epoch,
      tree: tree,
      leafIndex: leaf,
      privateKeys: privateKeys,
      epochSecrets: {epoch: unb64(opened['epochSecret'] as String)},
    );
  }

  // ---- application messages ---------------------------------------------

  Future<Uint8List> _messageKey(int epoch, int senderLeaf) async {
    final secret = epochSecrets[epoch];
    if (secret == null) throw MlsException('no secret for epoch $epoch');
    return MlsCrypto.derive(secret, 'msg', context: utf8.encode('$senderLeaf'));
  }

  List<int> _aad(int epoch, int senderLeaf, String channelId) =>
      utf8.encode('$groupId/$epoch/$senderLeaf/$channelId');

  Future<Envelope> encrypt(String channelId, List<int> plaintext) async {
    final nonce = MlsCrypto.randomBytes(12);
    final ct = await MlsCrypto.seal(
      await _messageKey(epoch, leafIndex),
      nonce,
      plaintext,
      aad: _aad(epoch, leafIndex, channelId),
    );
    return Envelope(epoch, leafIndex, nonce, ct);
  }

  Future<Uint8List> decrypt(String channelId, Envelope env) async =>
      MlsCrypto.open(
        await _messageKey(env.epoch, env.senderLeaf),
        env.nonce,
        env.ciphertext,
        aad: _aad(env.epoch, env.senderLeaf, channelId),
      );

  // ---- persistence -------------------------------------------------------

  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'deviceId': deviceId,
    'identity': identity.toJson(),
    'epoch': epoch,
    'tree': tree.toJson(),
    'leaf': leafIndex,
    'priv': {for (final e in privateKeys.entries) '${e.key}': e.value.toJson()},
    'secrets': {for (final e in epochSecrets.entries) '${e.key}': b64(e.value)},
  };

  factory MlsGroup.fromJson(Map<String, Object?> json) => MlsGroup(
    groupId: json['groupId'] as String,
    deviceId: json['deviceId'] as String,
    identity: SigningKeyPair.fromJson(
      Map<String, Object?>.from(json['identity'] as Map),
    ),
    epoch: json['epoch'] as int,
    tree: RatchetTree.fromJson(Map<String, Object?>.from(json['tree'] as Map)),
    leafIndex: json['leaf'] as int,
    privateKeys: {
      for (final e in (json['priv'] as Map).entries)
        int.parse(e.key as String): HpkeKeyPair.fromJson(
          Map<String, Object?>.from(e.value as Map),
        ),
    },
    epochSecrets: {
      for (final e in (json['secrets'] as Map).entries)
        int.parse(e.key as String): unb64(e.value as String),
    },
  );
}
