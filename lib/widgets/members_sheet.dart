import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../screens/server_screen.dart';
import '../state/session.dart';
import '../theme/armonic_theme.dart';
import 'attachment_image.dart';
import 'member_card.dart';

/// The roster as a bottom sheet: the phone's stand-in for [MembersPanel],
/// which needs a column the chat cannot spare there.
Future<void> showMembersSheet(BuildContext context, InstanceSession session) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider.value(
      value: session,
      child: const MembersSheet(),
    ),
  );
}

class MembersSheet extends StatelessWidget {
  const MembersSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();
    final t = context.armonic;
    final c = t.colors;
    final online = session.members.where((m) => m.online).toList();
    final offline = session.members.where((m) => !m.online).toList();

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.72,
      decoration: BoxDecoration(
        color: c.backgroundSidebar,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.textFaint.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.membersTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    strings.membersTotal(session.members.length),
                    style: t.mono(size: 11, weight: FontWeight.w400),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            Expanded(
              child: session.members.isEmpty
                  ? Center(
                      child: Text(
                        strings.noMembers,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      children: [
                        if (online.isNotEmpty)
                          _Group(
                            label: strings.onlineLabel,
                            color: onlineGreen,
                            members: online,
                          ),
                        if (offline.isNotEmpty)
                          _Group(
                            label: strings.offlineLabel,
                            color: c.textFaint,
                            members: offline,
                          ),
                      ],
                    ),
            ),
            if (session.isOwner)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.accentSoft,
                    side: BorderSide(color: c.accent.withValues(alpha: 0.5)),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    showCreateInviteDialog(context, session);
                  },
                  child: Text(strings.inviteToInstance),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String label;
  final Color color;
  final List<Member> members;

  const _Group({
    required this.label,
    required this.color,
    required this.members,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
          child: Text(
            '$label — ${members.length}'.toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
        for (final member in members) _MemberRow(member: member),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final Member member;
  const _MemberRow({required this.member});

  /// The roster does not say which voice channel someone is in, so it is
  /// looked up in the live presence map the session already polls.
  String? _voiceChannelOf(InstanceSession session) {
    for (final channel in session.channels.where((c) => c.isVoice)) {
      if (session.voiceMembersFor(channel.id).any((m) => m.id == member.id)) {
        return channel.name;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();
    final t = context.armonic;
    final c = t.colors;
    final voiceChannel = _voiceChannelOf(session);
    final isSelf = member.id == session.userId;

    final (String subtitle, Color subtitleColor) = voiceChannel != null
        ? (strings.inVoiceStatus(voiceChannel), c.accentSoft)
        : member.online
        ? (strings.connectedLabel, c.textMuted)
        : (strings.offlineLabel, c.textFaint);

    return Builder(
      builder: (rowContext) => Material(
        color: member.online
            ? c.panel.withValues(alpha: 0.6)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            final anchor = globalRectOf(rowContext);
            if (anchor == null) return;
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
          },
          child: Opacity(
            opacity: member.online ? 1 : 0.55,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      UserAvatar(
                        cache: session.attachments,
                        avatarPath: member.avatarPath,
                        label: member.label,
                        radius: 22,
                      ),
                      if (member.online)
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: onlineGreen,
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
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                member.label,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: c.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (member.isOwner) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: c.accentDeep,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  strings.ownerBadge.toUpperCase(),
                                  style: t.mono(
                                    size: 9,
                                    weight: FontWeight.w600,
                                    letterSpacing: 1,
                                    color: c.accentPale,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: t.mono(
                            size: 11,
                            weight: FontWeight.w400,
                            color: subtitleColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
