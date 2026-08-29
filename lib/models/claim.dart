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
