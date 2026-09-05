import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/instance_store.dart';
import '../state/session.dart';
import '../state/session_manager.dart';
import '../theme/armonic_theme.dart';
import '../widgets/attachment_image.dart';
import '../widgets/instance_rail.dart';
import '../widgets/voice_status_panel.dart';
import 'app_shell.dart';
import 'profile_screen.dart';
import 'server_screen.dart';
import 'voice_screen.dart';

/// The phone shell: the chat fills the screen and everything the wide layout
/// keeps in columns — the instance rail and the channel list — folds into a
/// drawer that swipes in from the left edge.
///
/// The drawer belongs to this widget rather than to [ServerScreen] because it
/// exists even when there is no session to show (an instance still needing
/// sign-in): switching instances must stay one swipe away in every state.
class MobileShell extends StatelessWidget {
  final List<StoredInstance> instances;
  final StoredInstance selected;
  final ValueChanged<StoredInstance> onSelect;
  final ValueChanged<StoredInstance> onRemove;
  final VoidCallback onAdd;
  final Membership Function(String baseUrl) membershipOf;
  final bool Function(String baseUrl) canInvite;
  final ValueChanged<StoredInstance> onCreateInvite;
  final VoidCallback onSignIn;

  const MobileShell({
    super.key,
    required this.instances,
    required this.selected,
    required this.onSelect,
    required this.onRemove,
    required this.onAdd,
    required this.membershipOf,
    required this.canInvite,
    required this.onCreateInvite,
    required this.onSignIn,
  });

  /// Joins from the shell's own context, which outlives the drawer that
  /// asked: the mic prompt can take longer than the drawer's closing
  /// animation, and the call screen still has to open afterwards.
  Future<void> _joinVoice(
    BuildContext context,
    InstanceSession session,
    ChannelInfo channel,
  ) async {
    if (session.voiceChannel?.id != channel.id) {
      await joinVoiceChannel(context, session, channel);
    }
    if (context.mounted && session.voiceChannel?.id == channel.id) {
      VoiceScreen.open(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionManager>();
    final session = selected.token == null
        ? null
        : sessions.sessionFor(selected);
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      drawer: Drawer(
        width: math.min(360, width * 0.88),
        backgroundColor: context.armonic.colors.backgroundSidebar,
        shape: const RoundedRectangleBorder(),
        child: Builder(
          builder: (drawerContext) => MobileDrawer(
            instances: instances,
            selected: selected,
            session: session,
            voiceUrl: sessions.voiceSession?.instance.baseUrl,
            onSelect: onSelect,
            onRemove: onRemove,
            onAdd: onAdd,
            membershipOf: membershipOf,
            canInvite: canInvite,
            onCreateInvite: onCreateInvite,
            onJoinVoice: session == null
                ? null
                : (channel) => _joinVoice(context, session, channel),
          ),
        ),
      ),
      body: Builder(
        builder: (bodyContext) => session == null
            ? Column(
                children: [
                  AppBar(
                    leading: IconButton(
                      tooltip: strings.openMenu,
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(bodyContext).openDrawer(),
                    ),
                    title: Text(
                      selected.name.isNotEmpty
                          ? selected.name
                          : selected.baseUrl,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: NeedsLoginPane(
                      instance: selected,
                      onSignIn: onSignIn,
                    ),
                  ),
                ],
              )
            : ServerScreen(
                key: ValueKey(selected.baseUrl),
                session: session,
                compact: true,
                onOpenMenu: () => Scaffold.of(bodyContext).openDrawer(),
              ),
      ),
    );
  }
}

/// Rail on the left, the selected instance's channels on the right, and the
/// signed-in user at the foot — the phone design's home panel.
class MobileDrawer extends StatelessWidget {
  final List<StoredInstance> instances;
  final StoredInstance selected;

  /// Null while the selected instance has no credential: the rail still
  /// works, the channel column explains why it is empty.
  final InstanceSession? session;
  final String? voiceUrl;
  final ValueChanged<StoredInstance> onSelect;
  final ValueChanged<StoredInstance> onRemove;
  final VoidCallback onAdd;
  final Membership Function(String baseUrl) membershipOf;
  final bool Function(String baseUrl) canInvite;
  final ValueChanged<StoredInstance> onCreateInvite;
  final ValueChanged<ChannelInfo>? onJoinVoice;

  const MobileDrawer({
    super.key,
    required this.instances,
    required this.selected,
    required this.session,
    required this.voiceUrl,
    required this.onSelect,
    required this.onRemove,
    required this.onAdd,
    required this.membershipOf,
    required this.canInvite,
    required this.onCreateInvite,
    required this.onJoinVoice,
  });

  @override
  Widget build(BuildContext context) {
    final session = this.session;
    return SafeArea(
      child: Row(
        children: [
          InstanceRail(
            instances: instances,
            selectedUrl: selected.baseUrl,
            voiceUrl: voiceUrl,
            onSelect: onSelect,
            onRemove: onRemove,
            onAdd: onAdd,
            membershipOf: membershipOf,
            canInvite: canInvite,
            onCreateInvite: onCreateInvite,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: session == null
                ? _NoSessionPane(instance: selected)
                : ChangeNotifierProvider.value(
                    value: session,
                    child: _ChannelColumn(onJoinVoice: onJoinVoice),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoSessionPane extends StatelessWidget {
  final StoredInstance instance;
  const _NoSessionPane({required this.instance});

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            instance.name.isNotEmpty ? instance.name : instance.baseUrl,
            style: Theme.of(context).textTheme.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            strings.instanceNeedsLogin,
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ChannelColumn extends StatelessWidget {
  final ValueChanged<ChannelInfo>? onJoinVoice;
  const _ChannelColumn({required this.onJoinVoice});

  void _closeDrawer(BuildContext context) =>
      Scaffold.maybeOf(context)?.closeDrawer();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();
    final t = context.armonic;
    final c = t.colors;
    final instance = session.instance;
    final title = session.selectedServer?.name.isNotEmpty == true
        ? session.selectedServer!.name
        : (instance.name.isNotEmpty ? instance.name : instance.baseUrl);
    final textChannels = session.channels.where((ch) => ch.isText).toList();
    final voiceChannels = session.channels.where((ch) => ch.isVoice).toList();
    final connected = session.status == SessionStatus.connected;
    final name = session.displayName?.isNotEmpty == true
        ? session.displayName!
        : strings.you;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: c.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: connected ? onlineGreen : c.mention,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${connected ? strings.connectedLabel : strings.offline}'
                      ' · ${hostOf(instance.baseUrl)}',
                      style: t.mono(
                        size: 11,
                        weight: FontWeight.w400,
                        color: connected ? onlineGreen : c.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1, color: c.border),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              SidebarHeader(
                strings.textHeader,
                onAdd: session.isOwner
                    ? () => promptCreateChannel(context, session, 'text')
                    : null,
              ),
              for (final channel in textChannels)
                ChannelTile(
                  channel: channel,
                  leading: Text(
                    '#',
                    style: t.mono(
                      size: 18,
                      weight: FontWeight.w500,
                      color: session.selectedChannel?.id == channel.id
                          ? c.accentSoft
                          : c.textFaint,
                    ),
                  ),
                  selected: session.selectedChannel?.id == channel.id,
                  onTap: () {
                    session.selectChannel(channel);
                    _closeDrawer(context);
                  },
                  onDelete: session.isOwner
                      ? () => confirmDeleteChannel(context, session, channel)
                      : null,
                ),
              SidebarHeader(
                strings.voiceHeader,
                onAdd: session.isOwner
                    ? () => promptCreateChannel(context, session, 'voice')
                    : null,
              ),
              for (final channel in voiceChannels)
                _VoiceChannelRow(
                  channel: channel,
                  session: session,
                  onTap: onJoinVoice == null
                      ? null
                      : () {
                          _closeDrawer(context);
                          onJoinVoice!(channel);
                        },
                ),
            ],
          ),
        ),
        Divider(height: 1, color: c.border),
        InkWell(
          onTap: () {
            _closeDrawer(context);
            ProfileScreen.open(context, session);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                UserAvatar(
                  cache: session.attachments,
                  avatarPath: session.myAvatarPath,
                  label: name,
                  radius: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        session.isOwner
                            ? strings.ownerBadge
                            : hostOf(instance.baseUrl),
                        style: t.mono(size: 10.5, weight: FontWeight.w400),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.more_horiz, color: c.textFaint),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A voice channel with the people in it listed underneath, so the drawer
/// answers "who is talking where" without opening anything. The channel we
/// are in gets an accent frame.
class _VoiceChannelRow extends StatelessWidget {
  final ChannelInfo channel;
  final InstanceSession session;
  final VoidCallback? onTap;

  const _VoiceChannelRow({
    required this.channel,
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.armonic;
    final c = t.colors;
    final members = session.voiceMembersFor(channel.id);
    final inHere = session.voiceChannel?.id == channel.id;

    final tile = ChannelTile(
      channel: channel,
      leading: inHere
          ? const LiveBars()
          : Icon(Icons.volume_up_outlined, size: 18, color: c.textFaint),
      trailing: members.isNotEmpty
          ? Text(
              '${members.length}',
              style: t.mono(size: 12, color: c.accentSoft),
            )
          : null,
      selected: inHere,
      onTap: onTap ?? () {},
      onDelete: session.isOwner
          ? () => confirmDeleteChannel(context, session, channel)
          : null,
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        if (members.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 12, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                for (final member in members)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(
                        cache: session.attachments,
                        avatarPath: member.id == session.userId
                            ? session.myAvatarPath
                            : session.avatarPathFor(member.id),
                        label: member.label,
                        radius: 11,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        member.label,
                        style: TextStyle(fontSize: 13, color: c.textSecondary),
                      ),
                      if (member.muted) ...[
                        const SizedBox(width: 3),
                        Icon(Icons.mic_off, size: 12, color: c.textFaint),
                      ],
                    ],
                  ),
              ],
            ),
          ),
      ],
    );

    if (!inHere) return body;
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 2, 6, 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.accent.withValues(alpha: 0.45)),
      ),
      child: body,
    );
  }
}
