import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/session.dart';
import '../state/session_manager.dart';
import '../theme/armonic_theme.dart';
import '../voice/voice_session.dart';
import '../widgets/attachment_image.dart';
import '../widgets/member_card.dart';
import 'server_screen.dart';

/// The call, full screen: one card per person in the voice channel and the
/// controls along the bottom.
///
/// Pushed over the shell, so going back keeps the call running — the shell's
/// [CallBar] is where it lives from then on. The screen follows
/// [SessionManager.voiceSession] and leaves on its own when the call ends
/// under it (hung up from the bar, kicked, socket lost).
class VoiceScreen extends StatelessWidget {
  const VoiceScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const VoiceScreen()));

  /// Pops this route once the frame is done, only if it is still the one on
  /// top: the same call end can rebuild this twice (session, then manager),
  /// and the second must not pop whatever is underneath.
  void _leaveWhenGone(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionManager>();
    final call = sessions.voiceSession;
    if (call == null) {
      _leaveWhenGone(context);
      return const Scaffold(body: SizedBox.shrink());
    }
    return ListenableBuilder(
      listenable: call,
      builder: (context, _) {
        final voice = call.voice;
        final channel = call.voiceChannel;
        if (voice == null || channel == null) {
          _leaveWhenGone(context);
          return const Scaffold(body: SizedBox.shrink());
        }
        return _CallView(session: call, channel: channel, voice: voice);
      },
    );
  }
}

class _CallView extends StatelessWidget {
  final InstanceSession session;
  final ChannelInfo channel;
  final VoiceSession voice;

  const _CallView({
    required this.session,
    required this.channel,
    required this.voice,
  });

  /// Everyone in the channel, ourselves first. The presence poll may not
  /// have caught up with our own join yet, so we are added by hand from what
  /// the session knows locally.
  List<VoiceMember> _members() {
    final me = session.userId;
    final others = session.voiceMembers.where((m) => m.id != me).toList();
    final self = VoiceMember(
      id: me ?? '',
      displayName: session.displayName ?? strings.you,
      muted: voice.muted,
      deafened: voice.deafened,
    );
    return [self, ...others];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.armonic;
    final c = t.colors;
    final instance = session.instance;
    final members = _members();
    final textChannel = session.selectedChannel;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              channel.name,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${strings.voiceMembersCount(members.length)} · '
              '${instance.name.isNotEmpty ? instance.name : hostOf(instance.baseUrl)}',
              style: t.mono(
                size: 10.5,
                weight: FontWeight.w400,
                color: c.accentSoft,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                // A touch taller than square: avatar, name and status do
                // not fit in a square cell at the phone's narrowest width.
                childAspectRatio: 0.86,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
              ),
              itemCount: members.length,
              itemBuilder: (context, i) {
                final member = members[i];
                final isSelf = member.id == session.userId;
                return _MemberTile(
                  member: member,
                  isSelf: isSelf,
                  avatarPath: isSelf
                      ? session.myAvatarPath
                      : session.avatarPathFor(member.id),
                  session: session,
                  channel: channel,
                );
              },
            ),
          ),
          if (members.length == 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(
                strings.nobodyElseInVoice,
                style: t.mono(size: 11, weight: FontWeight.w400),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: c.backgroundSidebar,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _BigButton(
                          tooltip: voice.muted ? strings.unmute : strings.mute,
                          icon: voice.muted ? Icons.mic_off : Icons.mic,
                          active: voice.muted,
                          onPressed: session.toggleMute,
                        ),
                        const SizedBox(width: 18),
                        _BigButton(
                          tooltip: voice.deafened
                              ? strings.undeafen
                              : strings.deafen,
                          icon: voice.deafened
                              ? Icons.headset_off
                              : Icons.headset,
                          active: voice.deafened,
                          onPressed: session.toggleDeafen,
                        ),
                        const SizedBox(width: 18),
                        _BigButton(
                          tooltip: strings.leaveVoiceTooltip,
                          icon: Icons.call_end,
                          danger: true,
                          onPressed: () {
                            Navigator.of(context).pop();
                            session.leaveVoice();
                          },
                        ),
                      ],
                    ),
                    if (textChannel != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        strings.backToChatHint(textChannel.name),
                        style: t.mono(size: 10.5, weight: FontWeight.w400),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One person in the call: avatar, name, mic state. Tapping opens their
/// member card; for the owner that card carries the kick actions.
class _MemberTile extends StatelessWidget {
  final VoiceMember member;
  final bool isSelf;
  final String? avatarPath;
  final InstanceSession session;
  final ChannelInfo channel;

  const _MemberTile({
    required this.member,
    required this.isSelf,
    required this.avatarPath,
    required this.session,
    required this.channel,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.armonic;
    final c = t.colors;
    final (String status, Color statusColor) = member.deafened
        ? (strings.deafenedStatus, c.textMuted)
        : member.muted
        ? (strings.mutedStatus, c.textMuted)
        : (strings.voiceConnectedStatus, onlineGreen);
    final canModerate = session.isOwner && !isSelf;

    return Builder(
      builder: (tileContext) => Material(
        color: c.panel.withValues(alpha: isSelf ? 0.9 : 0.6),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            final anchor = globalRectOf(tileContext);
            if (anchor == null) return;
            showMemberCard(
              context,
              anchor: anchor,
              attachments: session.attachments,
              member: MemberCardData(
                id: member.id,
                label: member.label,
                avatarPath: avatarPath,
                isOwner: session.memberFor(member.id)?.isOwner ?? false,
                isSelf: isSelf,
                online: true,
                voiceChannelName: channel.name,
                muted: member.muted,
                deafened: member.deafened,
              ),
              onKickVoice: canModerate
                  ? () => session.kickFromVoice(channel.id, member.id)
                  : null,
              onKickServer: canModerate
                  ? () => confirmKickFromServer(context, session, member)
                  : null,
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelf ? c.accent.withValues(alpha: 0.6) : c.border,
                width: isSelf ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UserAvatar(
                      cache: session.attachments,
                      avatarPath: avatarPath,
                      label: member.label,
                      radius: 36,
                    ),
                    if (member.muted || member.deafened)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: c.mention,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.panel, width: 2),
                          ),
                          child: Icon(
                            member.deafened ? Icons.headset_off : Icons.mic_off,
                            size: 13,
                            color: c.onMention,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  member.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: t.mono(
                    size: 10.5,
                    weight: FontWeight.w400,
                    color: statusColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool active;
  final bool danger;
  final VoidCallback onPressed;

  const _BigButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    final (Color background, Color foreground) = danger
        ? (c.mention, c.onMention)
        : active
        ? (c.mention.withValues(alpha: 0.18), c.mention)
        : (c.chip, c.accentPale);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 64,
            height: 60,
            child: Icon(icon, size: 24, color: foreground),
          ),
        ),
      ),
    );
  }
}
