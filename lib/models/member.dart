import 'attachment.dart';

/// One entry of GET /server/{id}/members.
///
/// This is what lets the chat show a real name and picture for a message's
/// author: the socket only ever sends a userId, so the client fetches the
/// roster once per server and maps through it.
class Member {
  final String id;
  final String displayName;
  final String? avatarId;
  final bool isOwner;
  final bool online;

  Member({
    required this.id,
    required this.displayName,
    this.avatarId,
    this.isOwner = false,
    this.online = false,
  });

  String get label => displayName.isNotEmpty ? displayName : shortId(id);

  String? get avatarPath =>
      avatarId == null || avatarId!.isEmpty ? null : attachmentPath(avatarId!);

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        avatarId: json['avatarId'] as String?,
        isOwner: json['isOwner'] as bool? ?? false,
        online: json['online'] as bool? ?? false,
      );
}

/// GET /me: the authenticated caller's own profile.
class MeProfile {
  final String id;
  final String displayName;
  final String? avatarId;

  MeProfile({required this.id, required this.displayName, this.avatarId});

  String? get avatarPath =>
      avatarId == null || avatarId!.isEmpty ? null : attachmentPath(avatarId!);

  MeProfile copyWith({String? avatarId}) => MeProfile(
        id: id,
        displayName: displayName,
        avatarId: avatarId ?? this.avatarId,
      );

  factory MeProfile.fromJson(Map<String, dynamic> json) => MeProfile(
        id: json['id'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        avatarId: json['avatarId'] as String?,
      );
}

/// Ids are UUIDs; when there is no display name to show, a prefix is the least
/// misleading placeholder.
String shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);
