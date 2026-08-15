/// One chat message: the WS "text-message" event and each entry of
/// GET /channel/{id}/messages (which returns newest first).
class ChatMessage {
  final String id;
  final String channelId;
  final String serverId;
  final String userId;
  final String content;
  final DateTime createdAt;
  final bool pending;

  ChatMessage({
    required this.id,
    required this.channelId,
    required this.serverId,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.pending = false,
  });

  ChatMessage copyWith({bool? pending}) => ChatMessage(
        id: id,
        channelId: channelId,
        serverId: serverId,
        userId: userId,
        content: content,
        createdAt: createdAt,
        pending: pending ?? this.pending,
      );

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? '',
        channelId: json['channelId'] as String? ?? '',
        serverId: json['serverId'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        content: json['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
}
