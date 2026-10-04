import 'dart:convert';
import 'dart:typed_data';

/// An image stored by the instance: the response of POST /server/{id}/upload
/// and POST /me/avatar.
///
/// [url] and [thumbUrl] are paths relative to the instance base URL, and both
/// require the Bearer JWT — the backend gates them on membership, so they
/// cannot be handed to a plain <img> tag.
class Attachment {
  final String id;
  final String serverId;
  final String userId;
  final String mime;
  final int size;
  final int thumbSize;
  final int width;
  final int height;
  final String url;
  final String thumbUrl;
  final DateTime createdAt;

  /// The server stored opaque ciphertext: it knows neither the format nor
  /// the dimensions, which travel inside the encrypted message instead.
  final bool encrypted;

  Attachment({
    required this.id,
    required this.serverId,
    required this.userId,
    required this.mime,
    required this.size,
    this.thumbSize = 0,
    required this.width,
    required this.height,
    required this.url,
    required this.thumbUrl,
    required this.createdAt,
    this.encrypted = false,
  });

  /// Falls back to a square when the server reported no dimensions, so a
  /// malformed row can never divide by zero in a layout constraint.
  double get aspectRatio => (width <= 0 || height <= 0) ? 1 : width / height;

  factory Attachment.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    return Attachment(
      id: id,
      serverId: json['serverId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      mime: json['mime'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      thumbSize: (json['thumbSize'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      url: json['url'] as String? ?? attachmentPath(id),
      thumbUrl: json['thumbUrl'] as String? ?? attachmentThumbPath(id),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      encrypted: json['encrypted'] as bool? ?? false,
    );
  }
}

/// What a recipient needs to fetch and open an end-to-end encrypted
/// attachment. It never touches the server in the clear: it travels inside
/// the MLS-encrypted message that references the attachment id.
class EncryptedAttachmentRef {
  final Uint8List key;
  final Uint8List nonce;
  final Uint8List thumbNonce;

  /// sha256 of each ciphertext, so a swapped blob is noticed before the
  /// AEAD even runs and the size on the wire can be trusted.
  final String digest;
  final String thumbDigest;
  final String mime;
  final String thumbMime;
  final int width;
  final int height;
  final int size;
  final int thumbSize;

  const EncryptedAttachmentRef({
    required this.key,
    required this.nonce,
    required this.thumbNonce,
    required this.digest,
    required this.thumbDigest,
    required this.mime,
    required this.thumbMime,
    required this.width,
    required this.height,
    required this.size,
    required this.thumbSize,
  });

  double get aspectRatio => (width <= 0 || height <= 0) ? 1 : width / height;

  Map<String, Object?> toJson() => {
    'k': base64Encode(key),
    'n': base64Encode(nonce),
    'tn': base64Encode(thumbNonce),
    'd': digest,
    'td': thumbDigest,
    'mime': mime,
    'tmime': thumbMime,
    'w': width,
    'h': height,
    'size': size,
    'tsize': thumbSize,
  };

  static EncryptedAttachmentRef? tryParse(Object? raw) {
    if (raw is! Map) return null;
    try {
      return EncryptedAttachmentRef(
        key: base64Decode(raw['k'] as String),
        nonce: base64Decode(raw['n'] as String),
        thumbNonce: base64Decode(raw['tn'] as String),
        digest: raw['d'] as String,
        thumbDigest: raw['td'] as String,
        mime: raw['mime'] as String? ?? '',
        thumbMime: raw['tmime'] as String? ?? '',
        width: (raw['w'] as num?)?.toInt() ?? 0,
        height: (raw['h'] as num?)?.toInt() ?? 0,
        size: (raw['size'] as num?)?.toInt() ?? 0,
        thumbSize: (raw['tsize'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

String attachmentPath(String id) => '/attachment/$id';

String attachmentThumbPath(String id) => '/attachment/$id/thumb';
