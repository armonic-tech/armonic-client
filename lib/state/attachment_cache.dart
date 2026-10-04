import 'dart:typed_data';

import '../api/http_api.dart';
import '../media/attachment_crypto.dart';
import '../models/attachment.dart';

/// Fetches and remembers attachment bytes for one instance.
///
/// Attachments are membership-gated, so they need the Bearer JWT and cannot
/// be loaded by `Image.network` — the header would be dropped by the HTML
/// renderer on web. Fetching the bytes ourselves and handing them to
/// `Image.memory` behaves the same on every platform.
///
/// The bytes are content-addressed server-side and served immutable, so once
/// fetched an entry never goes stale.
class AttachmentCache {
  static const maxBytes = 32 * 1024 * 1024;

  final ArmonicHttpApi _api;
  final String Function() _token;

  /// Insertion-ordered, which is what makes the eviction below oldest-first.
  final Map<String, Uint8List> _cached = {};
  final Map<String, Future<Uint8List>> _inFlight = {};
  int _heldBytes = 0;

  AttachmentCache(this._api, this._token);

  /// Bytes already in memory, for a synchronous first paint without a spinner.
  Uint8List? peek(String path) => _cached[path];

  /// [ref] opens an end-to-end encrypted attachment: the fetched bytes are
  /// checked against the digest, decrypted, and refused unless they turn
  /// out to be an image within the client's own limits. What is cached is
  /// the plaintext.
  Future<Uint8List> load(String path, {EncryptedAttachmentRef? ref}) {
    final cached = _cached[path];
    if (cached != null) return Future.value(cached);
    // Several tiles can ask for the same avatar in one frame; they share the
    // one request rather than each opening their own.
    return _inFlight[path] ??= _fetch(path, ref);
  }

  Future<Uint8List> _fetch(String path, EncryptedAttachmentRef? ref) async {
    try {
      var bytes = await _api.attachmentBytes(_token(), path);
      if (ref != null) {
        bytes = await decryptAttachment(
          bytes,
          ref,
          thumb: path.endsWith('/thumb'),
        );
      }
      _cached[path] = bytes;
      _heldBytes += bytes.lengthInBytes;
      _evict();
      return bytes;
    } finally {
      _inFlight.remove(path);
    }
  }

  void _evict() {
    while (_heldBytes > maxBytes && _cached.isNotEmpty) {
      final oldest = _cached.keys.first;
      _heldBytes -= _cached.remove(oldest)!.lengthInBytes;
    }
  }

  /// Puts bytes produced locally (an image just uploaded) into the cache.
  void seed(String path, Uint8List bytes) {
    if (_cached.containsKey(path)) return;
    _cached[path] = bytes;
    _heldBytes += bytes.lengthInBytes;
    _evict();
  }

  void clear() {
    _cached.clear();
    _inFlight.clear();
    _heldBytes = 0;
  }
}
