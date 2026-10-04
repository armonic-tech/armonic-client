import 'dart:typed_data';

import '../mls/crypto.dart';
import '../models/attachment.dart';
import 'image_pipeline.dart';

/// Both ciphertexts of an attachment plus the reference that opens them.
class EncryptedAttachment {
  final Uint8List blob;
  final Uint8List thumb;
  final EncryptedAttachmentRef ref;
  const EncryptedAttachment(this.blob, this.thumb, this.ref);
}

/// One random key per attachment, one nonce per blob, AES-256-GCM. The
/// ciphertext digest goes into the reference so the receiver can refuse a
/// swapped blob before decrypting.
Future<EncryptedAttachment> encryptAttachment(PreparedImage image) async {
  final key = MlsCrypto.randomBytes(32);
  final nonce = MlsCrypto.randomBytes(12);
  final thumbNonce = MlsCrypto.randomBytes(12);
  final blob = await MlsCrypto.seal(key, nonce, image.bytes);
  final thumb = await MlsCrypto.seal(key, thumbNonce, image.thumb);
  return EncryptedAttachment(
    blob,
    thumb,
    EncryptedAttachmentRef(
      key: key,
      nonce: nonce,
      thumbNonce: thumbNonce,
      digest: b64(await MlsCrypto.sha256(blob)),
      thumbDigest: b64(await MlsCrypto.sha256(thumb)),
      mime: image.mime,
      thumbMime: image.thumbMime,
      width: image.width,
      height: image.height,
      size: image.bytes.length,
      thumbSize: image.thumb.length,
    ),
  );
}

class AttachmentTampered implements Exception {
  const AttachmentTampered();
}

/// Opens one variant (full or thumbnail) and checks the plaintext is an
/// image this client is willing to render.
Future<Uint8List> decryptAttachment(
  Uint8List ciphertext,
  EncryptedAttachmentRef ref, {
  required bool thumb,
  ImageLimits limits = const ImageLimits(),
}) async {
  final expected = thumb ? ref.thumbDigest : ref.digest;
  if (b64(await MlsCrypto.sha256(ciphertext)) != expected) {
    throw const AttachmentTampered();
  }
  final plain = await MlsCrypto.open(
    ref.key,
    thumb ? ref.thumbNonce : ref.nonce,
    ciphertext,
  );
  assertRenderable(plain, limits: limits);
  return plain;
}
