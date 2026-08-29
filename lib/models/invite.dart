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

/// POST /server/{id}/invite
class InviteCreated {
  final String inviteToken;
  final String url;

  InviteCreated({required this.inviteToken, required this.url});

  factory InviteCreated.fromJson(Map<String, dynamic> json) => InviteCreated(
    inviteToken: json['inviteToken'] as String? ?? '',
    url: json['url'] as String? ?? '',
  );
}
