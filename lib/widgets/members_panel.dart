import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/session.dart';
import 'attachment_image.dart';

/// The server roster, split into who is connected right now and who is not.
///
/// `online` comes from the backend merging its live socket map into the
/// membership query, so it means "has a WebSocket open", not "was recently
/// active".
class MembersPanel extends StatelessWidget {
  /// Hides the panel. The app bar has the same toggle; this one is here so
  /// the way out is where the thing you want to close is.
  final VoidCallback? onClose;

  const MembersPanel({super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();
    final online = session.members.where((m) => m.online).toList();
    final offline = session.members.where((m) => !m.online).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.membersTitle.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: strings.hideMembers,
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                ),
            ],
          ),
        ),
        Expanded(
          child: session.members.isEmpty
              ? Center(
                  child: Text(strings.noMembers,
                      style: Theme.of(context).textTheme.bodySmall))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    if (online.isNotEmpty)
                      _Group(label: strings.onlineLabel, members: online),
                    if (offline.isNotEmpty)
                      _Group(label: strings.offlineLabel, members: offline),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  final String label;
  final List<Member> members;

  const _Group({required this.label, required this.members});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            '$label — ${members.length}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        for (final member in members) MemberTile(member: member),
      ],
    );
  }
}

class MemberTile extends StatelessWidget {
  final Member member;

  const MemberTile({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();
    final theme = Theme.of(context);

    return Opacity(
      // Offline members stay listed but recede, so the panel reads as a
      // roster rather than a presence list with holes in it.
      opacity: member.online ? 1 : 0.5,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: UserAvatar(
          cache: session.attachments,
          avatarPath: member.avatarPath,
          label: member.label,
          radius: 14,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(member.label, overflow: TextOverflow.ellipsis),
            ),
            if (member.isOwner) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  strings.ownerBadge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
