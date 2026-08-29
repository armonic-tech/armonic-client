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
  final int width;
  final int height;
  final String url;
  final String thumbUrl;
  final DateTime createdAt;

  Attachment({
    required this.id,
    required this.serverId,
    required this.userId,
    required this.mime,
    required this.size,
    required this.width,
    required this.height,
    required this.url,
    required this.thumbUrl,
    required this.createdAt,
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
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      url: json['url'] as String? ?? attachmentPath(id),
      thumbUrl: json['thumbUrl'] as String? ?? attachmentThumbPath(id),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

String attachmentPath(String id) => '/attachment/$id';

String attachmentThumbPath(String id) => '/attachment/$id/thumb';
