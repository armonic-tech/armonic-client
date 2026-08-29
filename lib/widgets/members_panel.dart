import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/session.dart';
import '../theme/armonic_theme.dart';
import 'attachment_image.dart';
import 'member_card.dart';

/// Width the server screen gives this column. Sized for a 36px avatar plus a
/// name at the roster's font size without truncating most of them.
const double membersPanelWidth = 236;

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
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 4),
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
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                ),
            ],
          ),
        ),
        Expanded(
          child: session.members.isEmpty
              ? Center(
                  child: Text(
                    strings.noMembers,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
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
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Text(
            // "EN LÍNEA — 3": the redesign's letterspaced mono section header.
            '$label — ${members.length}'.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        for (final member in members) MemberTile(member: member),
      ],
    );
  }
}

class MemberTile extends StatefulWidget {
  final Member member;

  const MemberTile({super.key, required this.member});

  @override
  State<MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends State<MemberTile> {
  bool _hovered = false;

  void _openCard(InstanceSession session) {
    final anchor = globalRectOf(context);
    if (anchor == null) return;
    final member = widget.member;
    final isSelf = member.id == session.userId;
    // The roster does not say which voice channel someone is in, so it is
    // looked up in the live presence map the sidebar already polls.
    String? voiceChannel;
    for (final channel in session.channels.where((c) => c.isVoice)) {
      if (session.voiceMembersFor(channel.id).any((m) => m.id == member.id)) {
        voiceChannel = channel.name;
        break;
      }
    }
    showMemberCard(
      context,
      anchor: anchor,
      attachments: session.attachments,
      member: MemberCardData(
        id: member.id,
        label: member.label,
        avatarPath: member.avatarPath,
        isOwner: member.isOwner,
        isSelf: isSelf,
        online: member.online,
        voiceChannelName: voiceChannel,
      ),
      onKickServer: session.isOwner && !isSelf
          ? () => session.kickFromServer(member.id)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();
    final theme = Theme.of(context);
    final c = context.armonic.colors;
    final member = widget.member;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => _openCard(session),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered ? c.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Opacity(
            // Offline members stay listed but recede, so the panel reads as a
            // roster rather than a presence list with holes in it.
            opacity: member.online ? 1 : 0.5,
            child: Row(
              children: [
                // The online dot rides on the avatar (design canvas 1g), so
                // presence survives the group headers scrolling out of view.
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UserAvatar(
                      cache: session.attachments,
                      avatarPath: member.avatarPath,
                      label: member.label,
                      radius: 18,
                    ),
                    if (member.online)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c.backgroundSidebar,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 11),
                Flexible(
                  child: Text(
                    member.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: member.online
                          ? FontWeight.w500
                          : FontWeight.w400,
                      color: member.online ? c.textPrimary : c.textBody,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (member.isOwner) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      strings.ownerBadge,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
