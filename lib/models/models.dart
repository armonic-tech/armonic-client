library;

class InstanceInfo {
  final String id;
  final String name;
  final String description;
  final int memberCount;
  final String host;
  final bool claimed;

  InstanceInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.memberCount,
    required this.host,
    required this.claimed,
  });

  factory InstanceInfo.fromJson(Map<String, dynamic> json) => InstanceInfo(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
        host: json['host'] as String? ?? '',
        claimed: json['claimed'] as bool? ?? false,
      );
}

class StoredInstance {
  final String baseUrl;
  final String name;
  final String description;
  final String? token;
  final String? displayName;

  StoredInstance({
    required this.baseUrl,
    this.name = '',
    this.description = '',
    this.token,
    this.displayName,
  });

  StoredInstance copyWith({
    String? name,
    String? description,
    String? token,
    String? displayName,
  }) =>
      StoredInstance(
        baseUrl: baseUrl,
        name: name ?? this.name,
        description: description ?? this.description,
        token: token ?? this.token,
        displayName: displayName ?? this.displayName,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'name': name,
        'description': description,
        'token': token,
        'displayName': displayName,
      };

  factory StoredInstance.fromJson(Map<String, dynamic> json) => StoredInstance(
        baseUrl: json['baseUrl'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        token: json['token'] as String?,
        displayName: json['displayName'] as String?,
      );
}

/// POST /claim/password
class ClaimTicket {
  final String ticket;
  final DateTime? expiresAt;

  ClaimTicket({required this.ticket, this.expiresAt});

  factory ClaimTicket.fromJson(Map<String, dynamic> json) => ClaimTicket(
        ticket: json['ticket'] as String,
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      );
}

/// GET /invite/status
class InviteStatus {
  final String serverId;
  final DateTime? expiresAt;

  InviteStatus({required this.serverId, this.expiresAt});

  factory InviteStatus.fromJson(Map<String, dynamic> json) => InviteStatus(
        serverId: json['serverId'] as String,
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      );
}

/// One entry of the WS "servers" reply.
class ServerInfo {
  final String id;
  final String name;

  ServerInfo({required this.id, required this.name});

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
      );
}

class ChannelInfo {
  final String id;
  final String serverId;
  final String name;
  final String type; // "text" | "voice"

  ChannelInfo({
    required this.id,
    required this.serverId,
    required this.name,
    required this.type,
  });

  bool get isText => type == 'text';
  bool get isVoice => type == 'voice';

  factory ChannelInfo.fromJson(Map<String, dynamic> json) => ChannelInfo(
        id: json['id'] as String,
        serverId: json['serverId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'text',
      );
}

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
