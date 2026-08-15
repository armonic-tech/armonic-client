/// One entry of GET /server (the servers the user is a member of).
class ServerInfo {
  final String id;
  final String name;

  /// Absent until the backend exposes owner_id on GET /server; while null the
  /// client hides every admin-only action instead of guessing.
  final String? ownerId;

  ServerInfo({required this.id, required this.name, this.ownerId});

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        ownerId: json['ownerId'] as String?,
      );
}
