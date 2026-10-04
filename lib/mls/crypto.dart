import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The primitives the group protocol is built on. One ciphersuite, fixed:
/// X25519 for the tree (HPKE-style sealing), Ed25519 for identities,
/// HKDF-SHA256 for every derivation, AES-256-GCM for every AEAD.
class MlsCrypto {
  static final _x25519 = X25519();
  static final _ed25519 = Ed25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _rng = Random.secure();

  static const _label = 'armonic-mls/v1/';

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

  static Future<Uint8List> sha256(List<int> data) async =>
      Uint8List.fromList((await Sha256().hash(data)).bytes);

  // ---- key pairs -------------------------------------------------------

  static Future<HpkeKeyPair> newHpkeKeyPair() async {
    final kp = await _x25519.newKeyPair();
    return HpkeKeyPair(
      Uint8List.fromList(await kp.extractPrivateKeyBytes()),
      Uint8List.fromList((await kp.extractPublicKey()).bytes),
    );
  }

  /// Deterministic key pair from a 32-byte secret, so every member deriving
  /// the same path secret lands on the same node key.
  static Future<HpkeKeyPair> hpkeKeyPairFromSeed(Uint8List seed) async {
    final kp = await _x25519.newKeyPairFromSeed(seed);
    return HpkeKeyPair(
      Uint8List.fromList(await kp.extractPrivateKeyBytes()),
      Uint8List.fromList((await kp.extractPublicKey()).bytes),
    );
  }

  static Future<SigningKeyPair> newSigningKeyPair() async {
    final kp = await _ed25519.newKeyPair();
    return SigningKeyPair(
      Uint8List.fromList(await kp.extractPrivateKeyBytes()),
      Uint8List.fromList((await kp.extractPublicKey()).bytes),
    );
  }

  static Future<Uint8List> sign(SigningKeyPair key, List<int> message) async {
    final kp = await _ed25519.newKeyPairFromSeed(key.privateKey);
    final sig = await _ed25519.sign(message, keyPair: kp);
    return Uint8List.fromList(sig.bytes);
  }

  static Future<bool> verify(
    Uint8List publicKey,
    List<int> message,
    List<int> signature,
  ) => _ed25519.verify(
    message,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );

  // ---- derivation ------------------------------------------------------

  /// HKDF(ikm=[secret], salt=[salt], info=label||context) → 32 bytes.
  static Future<Uint8List> derive(
    List<int> secret,
    String label, {
    List<int> salt = const [],
    List<int> context = const [],
  }) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
      info: [...utf8.encode(_label + label), ...context],
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  // ---- AEAD ------------------------------------------------------------

  static Future<Uint8List> seal(
    List<int> key,
    List<int> nonce,
    List<int> plaintext, {
    List<int> aad = const [],
  }) async {
    final box = await _aes.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  /// Throws [SecretBoxAuthenticationError] on a wrong key, nonce, aad or a
  /// tampered ciphertext.
  static Future<Uint8List> open(
    List<int> key,
    List<int> nonce,
    List<int> sealed, {
    List<int> aad = const [],
  }) async {
    if (sealed.length < 16) throw SecretBoxAuthenticationError();
    final box = SecretBox(
      sealed.sublist(0, sealed.length - 16),
      nonce: nonce,
      mac: Mac(sealed.sublist(sealed.length - 16)),
    );
    return Uint8List.fromList(
      await _aes.decrypt(box, secretKey: SecretKey(key), aad: aad),
    );
  }

  // ---- HPKE-style public-key sealing ----------------------------------

  /// Encrypts [plaintext] to an X25519 public key: ephemeral key exchange,
  /// HKDF over the shared secret bound to both public keys, AES-GCM with a
  /// zero nonce — safe because the derived key is used exactly once.
  static Future<SealedBox> sealTo(
    Uint8List recipientPublicKey,
    List<int> plaintext, {
    List<int> context = const [],
  }) async {
    final eph = await _x25519.newKeyPair();
    final ephPub = Uint8List.fromList((await eph.extractPublicKey()).bytes);
    final shared = await _x25519.sharedSecretKey(
      keyPair: eph,
      remotePublicKey: SimplePublicKey(
        recipientPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final key = await derive(
      await shared.extractBytes(),
      'hpke',
      salt: [...ephPub, ...recipientPublicKey],
      context: context,
    );
    final ct = await seal(key, Uint8List(12), plaintext, aad: context);
    return SealedBox(ephPub, ct);
  }

  static Future<Uint8List> openWith(
    HpkeKeyPair recipient,
    SealedBox box, {
    List<int> context = const [],
  }) async {
    final kp = await _x25519.newKeyPairFromSeed(recipient.privateKey);
    final shared = await _x25519.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(
        box.ephemeralPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final key = await derive(
      await shared.extractBytes(),
      'hpke',
      salt: [...box.ephemeralPublicKey, ...recipient.publicKey],
      context: context,
    );
    return open(key, Uint8List(12), box.ciphertext, aad: context);
  }
}

class HpkeKeyPair {
  final Uint8List privateKey;
  final Uint8List publicKey;
  const HpkeKeyPair(this.privateKey, this.publicKey);

  Map<String, Object?> toJson() => {
    'priv': b64(privateKey),
    'pub': b64(publicKey),
  };

  factory HpkeKeyPair.fromJson(Map<String, Object?> json) =>
      HpkeKeyPair(unb64(json['priv'] as String), unb64(json['pub'] as String));
}

class SigningKeyPair {
  final Uint8List privateKey;
  final Uint8List publicKey;
  const SigningKeyPair(this.privateKey, this.publicKey);

  Map<String, Object?> toJson() => {
    'priv': b64(privateKey),
    'pub': b64(publicKey),
  };

  factory SigningKeyPair.fromJson(Map<String, Object?> json) => SigningKeyPair(
    unb64(json['priv'] as String),
    unb64(json['pub'] as String),
  );
}

class SealedBox {
  final Uint8List ephemeralPublicKey;
  final Uint8List ciphertext;
  const SealedBox(this.ephemeralPublicKey, this.ciphertext);

  Map<String, Object?> toJson() => {
    'epk': b64(ephemeralPublicKey),
    'ct': b64(ciphertext),
  };

  factory SealedBox.fromJson(Map<String, Object?> json) =>
      SealedBox(unb64(json['epk'] as String), unb64(json['ct'] as String));
}

String b64(List<int> bytes) => base64Encode(bytes);
Uint8List unb64(String s) => base64Decode(s);

bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Encodes a JSON map with sorted keys, so signing and verifying see the
/// same bytes regardless of insertion order.
Uint8List canonicalJson(Map<String, Object?> value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(_sorted(value))));

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is List) return [for (final e in v) _sorted(e)];
  return v;
}
