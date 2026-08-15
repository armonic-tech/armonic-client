/// One entry of GET /server/{id} (a server's channels).
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

/// A user currently connected to a voice channel (GET /channel/{id} and the
/// WS "voice-state" broadcast). The server enforces deafened ⇒ muted.
class VoiceMember {
  final String id;
  final String displayName;
  final bool muted;
  final bool deafened;

  VoiceMember({
    required this.id,
    required this.displayName,
    this.muted = false,
    this.deafened = false,
  });

  String get label => displayName.isNotEmpty
      ? displayName
      : (id.length <= 8 ? id : id.substring(0, 8));

  VoiceMember copyWith({bool? muted, bool? deafened}) => VoiceMember(
        id: id,
        displayName: displayName,
        muted: muted ?? this.muted,
        deafened: deafened ?? this.deafened,
      );

  factory VoiceMember.fromJson(Map<String, dynamic> json) => VoiceMember(
        id: json['id'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        muted: json['muted'] as bool? ?? false,
        deafened: json['deafened'] as bool? ?? false,
      );
}

/// GET /channel/{id}: the channel plus live voice presence
/// (connected is only populated for voice channels).
class ChannelDetail {
  final ChannelInfo channel;
  final List<VoiceMember> connected;
  final int connectedCount;

  ChannelDetail({
    required this.channel,
    required this.connected,
    required this.connectedCount,
  });

  factory ChannelDetail.fromJson(Map<String, dynamic> json) => ChannelDetail(
        channel: ChannelInfo.fromJson(json),
        connected: [
          for (final m in json['connected'] as List? ?? const [])
            VoiceMember.fromJson(m as Map<String, dynamic>)
        ],
        connectedCount: (json['connectedCount'] as num?)?.toInt() ?? 0,
      );
}
