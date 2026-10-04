import 'dart:typed_data';

import 'crypto.dart';

/// A device's one-time offer to be added to a group: a fresh HPKE key the
/// committer encrypts the welcome to, bound to the device's signing key by
/// a signature. The private half stays on the device until the welcome
/// that consumes it arrives.
class KeyPackage {
  final String id;
  final String deviceId;
  final String userId;
  final Uint8List hpkeKey;
  final Uint8List signingKey;
  final Uint8List signature;

  const KeyPackage({
    required this.id,
    required this.deviceId,
    required this.userId,
    required this.hpkeKey,
    required this.signingKey,
    required this.signature,
  });

  static Map<String, Object?> _body(
    String id,
    String deviceId,
    String userId,
    Uint8List hpkeKey,
    Uint8List signingKey,
  ) => {
    'id': id,
    'deviceId': deviceId,
    'userId': userId,
    'hpke': b64(hpkeKey),
    'sig': b64(signingKey),
  };

  static Future<KeyPackage> create({
    required String id,
    required String deviceId,
    required String userId,
    required Uint8List hpkeKey,
    required SigningKeyPair identity,
  }) async {
    final body = _body(id, deviceId, userId, hpkeKey, identity.publicKey);
    return KeyPackage(
      id: id,
      deviceId: deviceId,
      userId: userId,
      hpkeKey: hpkeKey,
      signingKey: identity.publicKey,
      signature: await MlsCrypto.sign(identity, canonicalJson(body)),
    );
  }

  Future<bool> verify() => MlsCrypto.verify(
    signingKey,
    canonicalJson(_body(id, deviceId, userId, hpkeKey, signingKey)),
    signature,
  );

  Map<String, Object?> toJson() => {
    ..._body(id, deviceId, userId, hpkeKey, signingKey),
    'signature': b64(signature),
  };

  factory KeyPackage.fromJson(Map<String, Object?> json) => KeyPackage(
    id: json['id'] as String,
    deviceId: json['deviceId'] as String,
    userId: json['userId'] as String,
    hpkeKey: unb64(json['hpke'] as String),
    signingKey: unb64(json['sig'] as String),
    signature: unb64(json['signature'] as String),
  );
}
