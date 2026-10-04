import 'dart:typed_data';

import 'crypto.dart';

/// Who sits on a leaf: one device of one user, with the keys the rest of
/// the group encrypts to (HPKE) and verifies its commits with (signing).
class LeafInfo {
  final String deviceId;
  final String userId;
  final Uint8List signingKey;
  final String keyPackageId;

  const LeafInfo({
    required this.deviceId,
    required this.userId,
    required this.signingKey,
    required this.keyPackageId,
  });

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'userId': userId,
    'sig': b64(signingKey),
    'kp': keyPackageId,
  };

  factory LeafInfo.fromJson(Map<String, Object?> json) => LeafInfo(
    deviceId: json['deviceId'] as String,
    userId: json['userId'] as String,
    signingKey: unb64(json['sig'] as String),
    keyPackageId: json['kp'] as String? ?? '',
  );
}

/// A non-blank tree node: a public key, plus the leaf's identity when the
/// node is a leaf.
class TreeNode {
  final Uint8List publicKey;
  final LeafInfo? leaf;

  const TreeNode(this.publicKey, {this.leaf});

  Map<String, Object?> toJson() => {
    'pub': b64(publicKey),
    if (leaf != null) 'leaf': leaf!.toJson(),
  };

  factory TreeNode.fromJson(Map<String, Object?> json) => TreeNode(
    unb64(json['pub'] as String),
    leaf: json['leaf'] == null
        ? null
        : LeafInfo.fromJson(Map<String, Object?>.from(json['leaf'] as Map)),
  );
}

/// The public half of a TreeKEM ratchet tree (RFC 9420 §7), array-based:
/// leaf `i` lives at node `2i`, internal nodes at odd indices, and the tree
/// is left-balanced so appending a leaf never moves an existing node.
///
/// Blank nodes are `null`. A node's *resolution* is the set of keys one has
/// to encrypt to in order to reach every member under it: the node itself
/// if it has a key, otherwise its children's resolutions.
class RatchetTree {
  final List<TreeNode?> nodes;

  RatchetTree(this.nodes);

  RatchetTree.empty() : nodes = [];

  RatchetTree clone() => RatchetTree(List.of(nodes));

  int get leafCount => nodes.isEmpty ? 0 : (nodes.length + 1) ~/ 2;

  static int leafToNode(int leaf) => 2 * leaf;
  static int nodeToLeaf(int node) => node ~/ 2;
  static bool isLeaf(int node) => node.isEven;

  static int _level(int node) {
    var x = node, k = 0;
    while (x & 1 == 1) {
      x >>= 1;
      k++;
    }
    return k;
  }

  int get root {
    var w = nodes.length;
    var k = 0;
    while ((1 << (k + 1)) <= w) {
      k++;
    }
    return (1 << k) - 1;
  }

  int left(int node) {
    final k = _level(node);
    if (k == 0) throw StateError('leaf has no children');
    return node ^ (1 << (k - 1));
  }

  int right(int node) {
    final k = _level(node);
    if (k == 0) throw StateError('leaf has no children');
    var r = node ^ (3 << (k - 1));
    while (r >= nodes.length) {
      r = left(r);
    }
    return r;
  }

  int? parent(int node) {
    if (node == root) return null;
    final k = _level(node);
    final b = (node >> (k + 1)) & 1;
    var p = (node | (1 << k)) ^ (b << (k + 1));
    while (p >= nodes.length) {
      p = _parentStep(p);
    }
    return p;
  }

  static int _parentStep(int node) {
    final k = _level(node);
    final b = (node >> (k + 1)) & 1;
    return (node | (1 << k)) ^ (b << (k + 1));
  }

  int sibling(int node) {
    final p = parent(node)!;
    return node < p ? right(p) : left(p);
  }

  /// Nodes from the leaf's parent up to (and including) the root.
  List<int> directPath(int leaf) {
    final out = <int>[];
    if (nodes.isEmpty) return out;
    var n = parent(leafToNode(leaf));
    while (n != null) {
      out.add(n);
      n = parent(n);
    }
    return out;
  }

  bool isAncestorOf(int node, int leaf) {
    var n = leafToNode(leaf);
    while (true) {
      if (n == node) return true;
      final p = parent(n);
      if (p == null) return false;
      n = p;
    }
  }

  /// The first node on [a]'s direct path that also covers [b].
  int lowestCommonAncestor(int a, int b) {
    for (final n in directPath(a)) {
      if (isAncestorOf(n, b)) return n;
    }
    return root;
  }

  List<int> resolution(int node) {
    if (nodes[node] != null) return [node];
    if (isLeaf(node)) return const [];
    return [...resolution(left(node)), ...resolution(right(node))];
  }

  /// Leaves under [node] that are occupied.
  List<int> leavesUnder(int node) {
    if (isLeaf(node))
      return nodes[node] == null ? const [] : [nodeToLeaf(node)];
    return [...leavesUnder(left(node)), ...leavesUnder(right(node))];
  }

  int? leafOfDevice(String deviceId) {
    for (var i = 0; i < leafCount; i++) {
      if (nodes[leafToNode(i)]?.leaf?.deviceId == deviceId) return i;
    }
    return null;
  }

  List<LeafInfo> get members => [
    for (var i = 0; i < leafCount; i++)
      if (nodes[leafToNode(i)]?.leaf != null) nodes[leafToNode(i)]!.leaf!,
  ];

  /// Blanks every node on a leaf's direct path (the leaf itself untouched).
  void blankPath(int leaf) {
    for (final n in directPath(leaf)) {
      nodes[n] = null;
    }
  }

  /// Seats a new member: first blank leaf, else one appended on the right.
  /// Its direct path is blanked — the nodes above it were keyed without it,
  /// so they cannot be reused until someone re-keys them.
  int addLeaf(TreeNode leafNode) {
    for (var i = 0; i < leafCount; i++) {
      if (nodes[leafToNode(i)] == null) {
        nodes[leafToNode(i)] = leafNode;
        blankPath(i);
        return i;
      }
    }
    if (nodes.isEmpty) {
      nodes.add(leafNode);
      return 0;
    }
    nodes.add(null);
    nodes.add(leafNode);
    final leaf = leafCount - 1;
    blankPath(leaf);
    return leaf;
  }

  void removeLeaf(int leaf) {
    nodes[leafToNode(leaf)] = null;
    blankPath(leaf);
    truncate();
  }

  /// Drops trailing blank leaves so the tree does not grow forever.
  void truncate() {
    while (leafCount > 1 && nodes[leafToNode(leafCount - 1)] == null) {
      nodes.removeLast();
      nodes.removeLast();
    }
    if (leafCount == 1 && nodes[0] == null) nodes.clear();
  }

  Future<Uint8List> hash() => MlsCrypto.sha256(canonicalJson(toJson()));

  Map<String, Object?> toJson() => {
    'nodes': [for (final n in nodes) n?.toJson()],
  };

  factory RatchetTree.fromJson(Map<String, Object?> json) => RatchetTree([
    for (final n in json['nodes'] as List)
      n == null ? null : TreeNode.fromJson(Map<String, Object?>.from(n as Map)),
  ]);
}
