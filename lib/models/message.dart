import 'attachment.dart';

/// One chat message: the WS "text-message" event and each entry of
/// GET /channel/{id}/messages (which returns newest first).
///
/// For an end-to-end encrypted message [content] is the *decrypted* text
/// once the session has opened it; until then (or forever, when the device
/// has no key for that epoch) it is empty and [locked] is set.
class ChatMessage {
  final String id;
  final String channelId;
  final String serverId;
  final String userId;
  final String content;

  /// Set when the message carries an image; omitted on the wire otherwise, so
  /// a text-only message is byte-identical to before attachments existed.
  final String? attachmentId;
  final DateTime createdAt;
  final bool pending;

  /// The wire content is an MLS envelope rather than plaintext.
  final bool encrypted;

  /// Encrypted and not (yet) decryptable on this device.
  final bool locked;

  /// Keys for the attachment, carried inside the encrypted body.
  final EncryptedAttachmentRef? attachmentRef;

  ChatMessage({
    required this.id,
    required this.channelId,
    required this.serverId,
    required this.userId,
    required this.content,
    this.attachmentId,
    required this.createdAt,
    this.pending = false,
    this.encrypted = false,
    this.locked = false,
    this.attachmentRef,
  });

  bool get hasAttachment => attachmentId != null && attachmentId!.isNotEmpty;

  /// Prefix of the id an optimistic bubble carries until `message-ack`
  /// replaces it with the persisted one.
  static const localIdPrefix = 'local-';

  /// Only a message with its persisted id can be deleted: the server matches
  /// `delete-message` on the row id, so a local id always comes back as
  /// "message not found". [pending] alone is not enough — the fallback timer
  /// clears it on backends that never ack, while the id stays local.
  bool get deletable => !pending && !id.startsWith(localIdPrefix);

  ChatMessage copyWith({
    String? id,
    bool? pending,
    String? content,
    bool? locked,
    EncryptedAttachmentRef? attachmentRef,
  }) => ChatMessage(
    id: id ?? this.id,
    channelId: channelId,
    serverId: serverId,
    userId: userId,
    content: content ?? this.content,
    attachmentId: attachmentId,
    createdAt: createdAt,
    pending: pending ?? this.pending,
    encrypted: encrypted,
    locked: locked ?? this.locked,
    attachmentRef: attachmentRef ?? this.attachmentRef,
  );

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String? ?? '',
    channelId: json['channelId'] as String? ?? '',
    serverId: json['serverId'] as String? ?? '',
    userId: json['userId'] as String? ?? '',
    content: json['content'] as String? ?? '',
    attachmentId: json['attachmentId'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    encrypted: json['encrypted'] as bool? ?? false,
    locked: json['encrypted'] as bool? ?? false,
  );
}
