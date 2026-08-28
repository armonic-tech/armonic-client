import 'dart:typed_data';

import '../api/http_api.dart';

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

  Future<Uint8List> load(String path) {
    final cached = _cached[path];
    if (cached != null) return Future.value(cached);
    // Several tiles can ask for the same avatar in one frame; they share the
    // one request rather than each opening their own.
    return _inFlight[path] ??= _fetch(path);
  }

  Future<Uint8List> _fetch(String path) async {
    try {
      final bytes = await _api.attachmentBytes(_token(), path);
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

  void clear() {
    _cached.clear();
    _inFlight.clear();
    _heldBytes = 0;
  }
}
