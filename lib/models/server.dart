/// One entry of GET /server (the servers the user is a member of).
class ServerInfo {
  final String id;
  final String name;

  /// Absent until the backend exposes owner_id on GET /server; while null the
  /// client hides every admin-only action instead of guessing.
  final String? ownerId;

  /// Attachment id of the server logo, set by its owner through
  /// POST /server/{id}/logo. Null means the client draws initials instead.
  final String? logoId;

  /// Path of the logo thumbnail on that instance, as the backend built it
  /// (it carries the attachment id as ?v=). Never composed here: the public
  /// logo path and the membership-gated attachment path are different URLs,
  /// and only the server is entitled to say which is which.
  final String? logoThumbPath;

  ServerInfo({
    required this.id,
    required this.name,
    this.ownerId,
    this.logoId,
    this.logoThumbPath,
  });

  ServerInfo withLogo(String? logoId, String? logoThumbPath) => ServerInfo(
    id: id,
    name: name,
    ownerId: ownerId,
    logoId: logoId,
    logoThumbPath: logoThumbPath,
  );

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    ownerId: json['ownerId'] as String?,
    logoId: json['logoId'] as String?,
    logoThumbPath: json['logoThumbUrl'] as String?,
  );
}
