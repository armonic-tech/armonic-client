import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/http_api.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/attachment_cache.dart';
import '../state/instance_store.dart';
import '../state/session.dart';
import '../state/session_manager.dart';
import '../state/settings_store.dart';
import '../theme/armonic_theme.dart';
import '../util/mentions.dart';
import '../util/pick_image.dart';
import '../widgets/attachment_image.dart';
import '../widgets/member_card.dart';
import '../widgets/members_panel.dart';
import '../widgets/profile_dialog.dart';
import '../widgets/toast.dart';
import '../widgets/voice_status_panel.dart';
import 'settings_screen.dart';

/// One instance's channels and chat.
///
/// The [session] belongs to [SessionManager], not to this screen: the screen
/// is torn down whenever the rail moves elsewhere, and a call must not be.
/// All this state owns are the toast subscriptions of whatever session it is
/// currently showing.
class ServerScreen extends StatefulWidget {
  final InstanceSession session;
  const ServerScreen({super.key, required this.session});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  /// Whether the roster column is showing. Defaults on, and is ignored below
  /// the width where it would crowd the chat.
  bool _showMembers = true;

  StreamSubscription<String>? _errorSub;
  StreamSubscription<String>? _noticeSub;

  InstanceSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(ServerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Same URL, new session: the JWT died and a re-login replaced it.
    if (!identical(oldWidget.session, widget.session)) {
      _errorSub?.cancel();
      _noticeSub?.cancel();
      _listen();
    }
  }

  void _listen() {
    _errorSub = _session.errors.listen((message) {
      if (!mounted) return;
      showToast(context, switch (message) {
        'message content invalid' => strings.messageInvalid,
        'error saving message' => strings.couldNotSaveMessage,
        'could not delete message' => strings.couldNotDeleteMessage,
        'message not found' => strings.messageNotFound,
        'channel name taken' => strings.channelNameTaken,
        'channel name invalid' => strings.channelNameEmpty,
        'invalid invite' => strings.inviteInvalid,
        'unauthorized' || 'auth failed' => strings.notAllowed,
        _ => message,
      }, error: true);
    });
    _noticeSub = _session.notices.listen((message) {
      if (!mounted) return;
      showToast(context, message);
    });
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _noticeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _session,
      child: Consumer<InstanceSession>(
        builder: (context, session, _) {
          final instance = session.instance;
          final title = session.selectedServer?.name.isNotEmpty == true
              ? session.selectedServer!.name
              : (instance.name.isNotEmpty ? instance.name : instance.baseUrl);
          return Scaffold(
            appBar: AppBar(
              title: _ServerTitle(session: session, title: title),
              automaticallyImplyLeading: false,
              actions: _hasSidebar(session)
                  ? [
                      IconButton(
                        tooltip: _showMembers
                            ? strings.hideMembers
                            : strings.showMembers,
                        icon: Icon(
                          _showMembers ? Icons.people : Icons.people_outline,
                        ),
                        onPressed: () =>
                            setState(() => _showMembers = !_showMembers),
                      ),
                      IconButton(
                        tooltip: strings.profileTitle,
                        icon: UserAvatar(
                          cache: session.attachments,
                          avatarPath: session.myAvatarPath,
                          label: session.displayName ?? strings.you,
                          radius: 13,
                        ),
                        onPressed: () => showProfileDialog(context, session),
                      ),
                      const SizedBox(width: 4),
                    ]
                  : null,
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: switch (session.status) {
                    SessionStatus.connecting => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    SessionStatus.error || SessionStatus.disconnected =>
                      _DisconnectedView(session: session),
                    // Connected, authenticated, and GET /server came back
                    // empty: the account is fine but its membership is gone.
                    // Only once serversLoaded is true — before that the list
                    // is merely in flight, and a failed read leaves it false.
                    SessionStatus.connected =>
                      session.serversLoaded && session.servers.isEmpty
                          ? _NotAMemberView(session: session)
                          : _ConnectedBody(
                              showMembers: _showMembers,
                              onHideMembers: () =>
                                  setState(() => _showMembers = false),
                            ),
                  },
                ),
                // The call panel normally rides at the foot of the channel
                // sidebar; while this instance has no sidebar to hold it (still
                // connecting, unreachable, no membership, picking a server) it
                // keeps the same corner rather than blinking out mid-call.
                if (!_hasSidebar(session))
                  const SizedBox(width: 240, child: _CallPanel()),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Whether this screen is showing the channel sidebar — the one branch of the
/// body switch that reaches [_ChannelSidebar], and so the one that already
/// carries the call panel.
bool _hasSidebar(InstanceSession session) =>
    session.status == SessionStatus.connected &&
    !(session.serversLoaded && session.servers.isEmpty) &&
    session.selectedServer != null;

/// The app bar's server name, which doubles as the server menu for its admin.
///
/// Only actions the caller can actually perform go in it, so a plain member
/// gets plain text instead of a menu that only ever answers "403".
class _ServerTitle extends StatelessWidget {
  final InstanceSession session;
  final String title;
  const _ServerTitle({required this.session, required this.title});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: strings.serverOptions,
      // Opens *under* the title rather than over it: the default placement
      // covers the server name with the menu, which reads as the header
      // disappearing.
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        if (session.isOwner)
          PopupMenuItem(
            value: () => showCreateInviteDialog(context, session),
            child: Row(
              children: [
                const Icon(Icons.person_add, size: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    strings.createInvite,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        // Everyone gets settings: they are this client's own, not the
        // server's, so ownership has nothing to say about them.
        PopupMenuItem(
          value: () => showSettingsDialog(context),
          child: Row(
            children: [
              const Icon(Icons.tune, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  strings.settingsTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 20),
        ],
      ),
    );
  }
}

class _NotAMemberView extends StatelessWidget {
  final InstanceSession session;
  const _NotAMemberView({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_remove_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                strings.noLongerMember,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                strings.noLongerMemberHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => showJoinWithInviteDialog(context, session),
                icon: const Icon(Icons.mail_outline, size: 18),
                label: Text(strings.joinWithInvite),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => context.read<InstanceStore>().remove(
                  session.instance.baseUrl,
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(strings.removeFromList),
              ),
              const SizedBox(height: 16),
              Text(
                session.instance.baseUrl,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisconnectedView extends StatelessWidget {
  final InstanceSession session;
  const _DisconnectedView({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Headline in plain language, "what to check" underneath, and the
    // instance address as the only technical bit — the exception itself goes
    // to the debug console (see InstanceSession.connect), not to the user.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                session.errorMessage ?? strings.disconnectedFromInstance,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (session.errorHint != null) ...[
                const SizedBox(height: 8),
                Text(
                  session.errorHint!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: session.connect,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(strings.reconnect),
              ),
              const SizedBox(height: 16),
              Text(
                session.instance.baseUrl,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectedBody extends StatelessWidget {
  final bool showMembers;
  final VoidCallback onHideMembers;
  const _ConnectedBody({
    required this.showMembers,
    required this.onHideMembers,
  });

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();

    // Rare case: the user belongs to more than one server ID inside this
    // instance — offer a picker before showing channels.
    if (session.selectedServer == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ListView(
            shrinkWrap: true,
            children: [
              if (session.servers.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    strings.noServersForAccount,
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final server in session.servers)
                ListTile(
                  leading: const Icon(Icons.dns),
                  title: Text(server.name.isNotEmpty ? server.name : server.id),
                  onTap: () => session.selectServer(server),
                ),
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(strings.joinWithInvite),
                onTap: () => showJoinWithInviteDialog(context, session),
              ),
            ],
          ),
        ),
      );
    }

    // The call's controls and audio sinks live in the shell (see AppShell's
    // _CallFooter), not here — this screen goes away when the rail moves.
    return Row(
      children: [
        const SizedBox(width: 240, child: _ChannelSidebar()),
        const VerticalDivider(width: 1),
        const Expanded(child: ChatPane()),
        // The roster is a wide-screen luxury: on a phone it would leave the
        // chat a sliver, so it is dropped rather than squeezed.
        if (showMembers && MediaQuery.sizeOf(context).width >= 820) ...[
          const VerticalDivider(width: 1),
          SizedBox(
            width: membersPanelWidth,
            child: MembersPanel(onClose: onHideMembers),
          ),
        ],
      ],
    );
  }
}

class _ChannelSidebar extends StatelessWidget {
  const _ChannelSidebar();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();
    final textChannels = session.channels.where((c) => c.isText).toList();
    final voiceChannels = session.channels.where((c) => c.isVoice).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _SidebarHeader(
                strings.textHeader,
                onAdd: session.isOwner
                    ? () => _createChannel(context, session, 'text')
                    : null,
              ),
              for (final channel in textChannels)
                ChannelTile(
                  channel: channel,
                  // The canvas draws '#' as a mono glyph, not an icon. Sized
                  // to the voice rows' 18px icon, and a notch heavier: a thin
                  // glyph reads lighter than a filled icon at equal size.
                  leading: Text(
                    '#',
                    style: context.armonic.mono(
                      size: 18,
                      weight: FontWeight.w500,
                      color: session.selectedChannel?.id == channel.id
                          ? context.armonic.colors.accentSoft
                          : context.armonic.colors.textFaint,
                    ),
                  ),
                  selected: session.selectedChannel?.id == channel.id,
                  onTap: () => session.selectChannel(channel),
                  onDelete: session.isOwner
                      ? () => _confirmDeleteChannel(context, session, channel)
                      : null,
                ),
              _SidebarHeader(
                strings.voiceHeader,
                onAdd: session.isOwner
                    ? () => _createChannel(context, session, 'voice')
                    : null,
              ),
              for (final channel in voiceChannels) ...[
                ChannelTile(
                  channel: channel,
                  leading: Icon(
                    session.voiceChannel?.id == channel.id
                        ? Icons.volume_up
                        : Icons.volume_up_outlined,
                    size: 18,
                  ),
                  trailing: session.voiceMembersFor(channel.id).isNotEmpty
                      ? Text(
                          '${session.voiceMembersFor(channel.id).length}',
                          style: Theme.of(context).textTheme.labelSmall,
                        )
                      : null,
                  selected: session.voiceChannel?.id == channel.id,
                  onTap: () => _joinVoice(context, session, channel),
                  onDelete: session.isOwner
                      ? () => _confirmDeleteChannel(context, session, channel)
                      : null,
                ),
                for (final member in session.voiceMembersFor(channel.id))
                  VoiceMemberTile(
                    member: member,
                    isSelf: member.id == session.userId,
                    avatarPath: member.id == session.userId
                        ? session.myAvatarPath
                        : session.avatarPathFor(member.id),
                    attachments: session.attachments,
                    // For ourselves the local state wins (zero delay); for
                    // the rest, what the server last told us.
                    muted: member.id == session.userId
                        ? (session.voice?.muted ?? member.muted)
                        : member.muted,
                    deafened: member.id == session.userId
                        ? (session.voice?.deafened ?? member.deafened)
                        : member.deafened,
                    onKickVoice: session.isOwner && member.id != session.userId
                        ? () => session.kickFromVoice(channel.id, member.id)
                        : null,
                    onKickServer: session.isOwner && member.id != session.userId
                        ? () => _confirmKickServer(context, session, member)
                        : null,
                    onOpenCard: (anchor) => showMemberCard(
                      context,
                      anchor: anchor,
                      attachments: session.attachments,
                      member: MemberCardData(
                        id: member.id,
                        label: member.label,
                        avatarPath: member.id == session.userId
                            ? session.myAvatarPath
                            : session.avatarPathFor(member.id),
                        isOwner: session.memberFor(member.id)?.isOwner ?? false,
                        isSelf: member.id == session.userId,
                        // Being in the voice channel *is* being online, so
                        // the roster lookup is only a fallback.
                        online: session.memberFor(member.id)?.online ?? true,
                        voiceChannelName: channel.name,
                        muted: member.id == session.userId
                            ? (session.voice?.muted ?? member.muted)
                            : member.muted,
                        deafened: member.id == session.userId
                            ? (session.voice?.deafened ?? member.deafened)
                            : member.deafened,
                      ),
                      onKickVoice:
                          session.isOwner && member.id != session.userId
                          ? () => session.kickFromVoice(channel.id, member.id)
                          : null,
                      onKickServer:
                          session.isOwner && member.id != session.userId
                          ? () => _confirmKickServer(context, session, member)
                          : null,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const _CallPanel(),
      ],
    );
  }

  Future<void> _confirmKickServer(
    BuildContext context,
    InstanceSession session,
    VoiceMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.kickFromServerConfirmTitle),
        content: Text(strings.kickFromServerConfirmBody(member.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.kick),
          ),
        ],
      ),
    );
    if (confirmed == true) session.kickFromServer(member.id);
  }

  Future<void> _joinVoice(
    BuildContext context,
    InstanceSession session,
    ChannelInfo channel,
  ) async {
    // Through the manager: a call already running on *another* instance has
    // to be hung up first — one mic, one pair of ears.
    final sessions = context.read<SessionManager>();
    try {
      await sessions.joinVoice(
        session,
        channel,
        audio: context.read<SettingsStore>().settings.audio,
      );
    } catch (e) {
      if (context.mounted) {
        showToast(context, strings.couldNotAccessMic(e), error: true);
      }
    }
  }
}

/// Mint a single-use invite link and offer to copy it.
///
/// Top-level and public because the action has two entry points now: the
/// server-name menu of the instance on screen, and the right-click menu of any
/// instance in the rail. Owner-only — the backend answers 403 to anyone else,
/// which is what the forbidden branch reports.
Future<void> showCreateInviteDialog(
  BuildContext context,
  InstanceSession session,
) async {
  try {
    final url = await session.createInvite();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.inviteCreated),
        content: SelectableText(strings.inviteDetails(url)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.of(dialogContext).pop();
            },
            child: Text(strings.copyAndClose),
          ),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted) {
      final forbidden = e is ApiException && e.statusCode == 403;
      showToast(
        context,
        forbidden
            ? strings.onlyOwnerCanInvite
            : strings.couldNotCreateInvite(e),
        error: true,
      );
    }
  }
}

/// The call at the foot of the channel sidebar.
///
/// It follows [SessionManager.voiceSession], not the session this sidebar
/// belongs to: a call keeps running while you read another instance, and this
/// is where you see it and hang it up from.
class _CallPanel extends StatelessWidget {
  const _CallPanel();

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionManager>();
    final call = sessions.voiceSession;
    if (call == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: call,
      builder: (context, _) {
        final voice = call.voice;
        final channel = call.voiceChannel;
        if (voice == null || channel == null) return const SizedBox.shrink();
        final instance = call.instance;
        final server = call.servers
            .where((s) => s.id == channel.serverId)
            .firstOrNull;
        final elsewhere = !identical(call, context.read<InstanceSession>());

        // No divider above it: the panel is a self-contained card with its
        // own border, and a rule right on top of it reads as a seam.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VoiceStatusPanel(
              channelName: channel.name,
              instanceLabel: instance.name.isNotEmpty
                  ? instance.name
                  : instance.baseUrl,
              serverName: server?.name ?? '',
              memberLabels: [for (final m in call.voiceMembers) m.label],
              muted: voice.muted,
              deafened: voice.deafened,
              onToggleMute: call.toggleMute,
              onToggleDeafen: call.toggleDeafen,
              onLeave: call.leaveVoice,
              onOpen: elsewhere
                  ? () => sessions.select(instance.baseUrl)
                  : null,
            ),
          ],
        );
      },
    );
  }
}

/// Ask for an invite link/token and redeem it as the logged-in account
/// (WS join-server); the invite becomes unusable afterwards (single-use).
Future<void> showJoinWithInviteDialog(
  BuildContext context,
  InstanceSession session,
) async {
  final input = await promptForText(
    context,
    title: strings.joinWithInvite,
    label: strings.inviteLinkLabel,
    confirmLabel: strings.join,
  );
  if (input == null || input.trim().isEmpty) return;
  try {
    await session.joinServerWithInvite(input);
    if (context.mounted) {
      context.read<InstanceStore>().markMember(session.instance.baseUrl);
      showToast(context, strings.joinedServer);
    }
  } catch (e) {
    if (context.mounted) {
      final invalid = e is StateError && e.message == 'invalid invite';
      showToast(
        context,
        invalid ? strings.inviteInvalid : strings.couldNotJoinServer(e),
        error: true,
      );
    }
  }
}

/// One connected user, indented under its voice channel in the sidebar.
///
/// Tapping opens the member card ([onOpenCard]); right-click / long-press
/// still opens the kick menu when the moderation callbacks are non-null
/// (owner looking at someone else). Both are optional, so the tile renders
/// standalone in tests.
class VoiceMemberTile extends StatefulWidget {
  final VoiceMember member;
  final bool isSelf;
  final bool muted;
  final bool deafened;

  /// Resolved through the server roster rather than through
  /// [VoiceMember.avatarId]: the socket's copy is read once when a connection
  /// authenticates and never updated, so it goes stale the moment anyone
  /// changes their picture mid-session. The roster is re-read from the
  /// database, so it is the one that stays current.
  final String? avatarPath;
  final AttachmentCache? attachments;
  final VoidCallback? onKickVoice;
  final VoidCallback? onKickServer;

  /// Opens this member's card, given the tile's own global rect so the card
  /// can sit beside it.
  final void Function(Rect anchor)? onOpenCard;

  const VoiceMemberTile({
    super.key,
    required this.member,
    required this.isSelf,
    required this.muted,
    required this.deafened,
    this.avatarPath,
    this.attachments,
    this.onKickVoice,
    this.onKickServer,
    this.onOpenCard,
  });

  @override
  State<VoiceMemberTile> createState() => _VoiceMemberTileState();
}

class _VoiceMemberTileState extends State<VoiceMemberTile> {
  bool _hovered = false;

  bool get _canModerate =>
      widget.onKickVoice != null || widget.onKickServer != null;

  Future<void> _showMenu(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.onKickVoice != null)
          PopupMenuItem(
            value: widget.onKickVoice,
            child: Row(
              children: [
                const Icon(Icons.logout, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    strings.kickFromVoice,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (widget.onKickServer != null)
          PopupMenuItem(
            value: widget.onKickServer,
            child: Row(
              children: [
                Icon(
                  Icons.person_remove,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    strings.kickFromServer,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    final row = Row(
      children: [
        UserAvatar(
          cache: widget.attachments,
          avatarPath: widget.avatarPath,
          label: widget.member.label,
          radius: 14,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            widget.member.label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: widget.isSelf ? FontWeight.w600 : FontWeight.w400,
              color: widget.isSelf ? c.textPrimary : c.textBody,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.muted) Icon(Icons.mic_off, size: 14, color: c.textFaint),
        if (widget.deafened) ...[
          const SizedBox(width: 5),
          Icon(Icons.headset_off, size: 14, color: c.textFaint),
        ],
      ],
    );

    return Padding(
      // Flush with the channel rows above it: same 6px gutter, and the inner
      // 10px matches the ListTile contentPadding those rows get from the
      // theme, so avatars and channel icons share one left edge.
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: MouseRegion(
        cursor: widget.onOpenCard != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () {
            final open = widget.onOpenCard;
            final anchor = globalRectOf(context);
            if (open != null && anchor != null) open(anchor);
          },
          // Desktop/web right-click and mobile long-press.
          onSecondaryTapDown: _canModerate
              ? (d) => _showMenu(context, d.globalPosition)
              : null,
          onLongPressStart: _canModerate
              ? (d) => _showMenu(context, d.globalPosition)
              : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _hovered ? c.surfaceHover : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: row,
          ),
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final String label;

  final VoidCallback? onAdd;
  const _SidebarHeader(this.label, {this.onAdd});

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: Theme.of(context).textTheme.labelSmall);
    if (onAdd == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: text,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(child: text),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            tooltip: label,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

/// A channel row in the sidebar. When [onDelete] is non-null (admin),
/// right-click / long-press opens the delete menu — same interaction as
/// [VoiceMemberTile] and [MessageTile]. The tap target itself stays on the
/// wrapped [ListTile].
class ChannelTile extends StatelessWidget {
  final ChannelInfo channel;
  final Widget leading;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const ChannelTile({
    super.key,
    required this.channel,
    required this.leading,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.onDelete,
  });

  Future<void> _showMenu(BuildContext context, Offset globalPosition) async {
    final delete = onDelete;
    if (delete == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: delete,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  strings.deleteChannel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    // The selected row carries a short accent bar hugging its left edge, the
    // redesign's selection mark; the row itself is a flat tinted panel.
    final tile = Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: ListTile(
            dense: true,
            leading: leading,
            title: Text(
              channel.name,
              style: selected
                  ? const TextStyle(fontWeight: FontWeight.w500)
                  : null,
            ),
            trailing: trailing,
            selected: selected,
            onTap: onTap,
          ),
        ),
        if (selected)
          Positioned(
            left: 0,
            top: 9,
            bottom: 9,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: context.armonic.colors.accentSoft,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
    if (onDelete == null) return tile;
    return GestureDetector(
      // Desktop/web right-click and mobile long-press.
      onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
      onLongPressStart: (d) => _showMenu(context, d.globalPosition),
      child: tile,
    );
  }
}

/// Ask for a name and create a channel of [type] ("text" | "voice").
Future<void> _createChannel(
  BuildContext context,
  InstanceSession session,
  String type,
) async {
  final name = await promptForText(
    context,
    title: type == 'voice' ? strings.newVoiceChannel : strings.newTextChannel,
    label: strings.channelNameLabel,
    confirmLabel: strings.create,
    maxLength: 64,
    validator: (input) => channelNameError(session.channels, input, type),
  );
  if (name == null || name.trim().isEmpty) return;
  session.createChannel(name.trim(), type);
}

/// Why [name] can't be a new [type] channel, or null if it can.
///
/// Mirrors handleCreateChannel server-side: same trim, same 64-char cap, and
/// the same case-insensitive collision scoped to one type — a server ships
/// "general" (text) next to "General" (voice), so those must not clash. This
/// is only a courtesy check; the backend re-validates and a unique index has
/// the final word, since [channels] is whatever this client last heard about.
String? channelNameError(List<ChannelInfo> channels, String name, String type) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return strings.channelNameEmpty;
  if (trimmed.length > 64) return strings.channelNameTooLong;
  final clash = channels.any(
    (c) => c.type == type && c.name.toLowerCase() == trimmed.toLowerCase(),
  );
  return clash ? strings.channelNameTaken : null;
}

/// Single-field prompt, returning what was typed (or null if cancelled).
///
/// The controller lives in a [State] rather than in the calling function on
/// purpose. `showDialog`'s future completes the instant `pop` is called, but
/// the route keeps animating out for ~200ms with its [TextField] still mounted
/// and still listening; disposing the controller right after the `await` kills
/// it out from under the transition, which re-subscribes on rebuild and throws
/// "A TextEditingController was used after being disposed" — followed by a
/// corrupted element tree. Tying it to the dialog's own State disposes it once
/// the route is actually gone.
/// [validator] returns an error message to show under the field, or null to
/// accept; it runs on every keystroke and blocks confirming while it fails.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  int? maxLength,
  String? Function(String value)? validator,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPromptDialog(
    title: title,
    label: label,
    confirmLabel: confirmLabel,
    maxLength: maxLength,
    validator: validator,
  ),
);

class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String label;
  final String confirmLabel;
  final int? maxLength;
  final String? Function(String value)? validator;

  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    this.maxLength,
    this.validator,
  });

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();

  /// Null until the user types: an empty field shouldn't open with an error
  /// already shouting at them, but confirming it is still blocked below.
  String? _error;
  var _touched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final error = widget.validator?.call(value);
    if (_touched && error == _error) return;
    setState(() {
      _touched = true;
      _error = error;
    });
  }

  /// Rejects on an untouched field too, so Enter on an empty dialog can't
  /// submit past a validator that never ran.
  void _submit() {
    final value = _controller.text;
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() {
        _touched = true;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _touched && _error != null;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          errorText: blocked ? _error : null,
        ),
        onChanged: _onChanged,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: blocked ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

Future<void> _confirmDeleteChannel(
  BuildContext context,
  InstanceSession session,
  ChannelInfo channel,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.deleteChannelConfirmTitle),
      content: Text(
        channel.isVoice
            ? strings.deleteVoiceChannelConfirmBody(channel.name)
            : strings.deleteTextChannelConfirmBody(channel.name),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(strings.delete),
        ),
      ],
    ),
  );
  if (confirmed == true) session.deleteChannel(channel);
}

class ChatPane extends StatefulWidget {
  /// Injectable so widget tests can attach an image without a file dialog.
  final ImagePicker pickImage;

  const ChatPane({super.key, this.pickImage = pickImageFile});

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final _input = TextEditingController();

  // Enter-to-send drops the field's focus by default, and the send button
  // would steal it on tap — both make you re-click the box to keep typing.
  final _inputFocus = FocusNode();
  final _sendFocus = FocusNode(canRequestFocus: false, skipTraversal: true);

  /// Uploaded and waiting to be attached to the next message. Uploading on
  /// pick rather than on send means the image is already validated (and
  /// rejected, if it fails) before the user commits to sending anything.
  Attachment? _attachment;
  bool _uploading = false;

  /// The `@…` being typed, if any, and which suggestion Enter would take.
  /// The index follows the mouse, so "the highlighted one" and "the one the
  /// pointer is on" are never two different rows.
  MentionQuery? _mention;
  int _mentionIndex = 0;

  @override
  void initState() {
    super.initState();
    // Driven by the controller rather than by onChanged: moving the caret
    // with the arrows or the mouse also changes whether we are inside a
    // mention, and onChanged never fires for that.
    _input.addListener(_syncMention);
  }

  @override
  void dispose() {
    _input.removeListener(_syncMention);
    _input.dispose();
    _inputFocus.dispose();
    _sendFocus.dispose();
    super.dispose();
  }

  void _syncMention() {
    final selection = _input.selection;
    // A range selection has no single caret to complete at.
    final mention = selection.isValid && selection.isCollapsed
        ? mentionQueryAt(_input.text, selection.baseOffset)
        : null;
    if (mention == _mention) return;
    setState(() {
      _mention = mention;
      _mentionIndex = 0;
    });
  }

  /// Labels of everyone in the roster that the current `@…` matches.
  List<String> _mentionCandidates(InstanceSession session) {
    final mention = _mention;
    if (mention == null) return const [];
    return rankMentionCandidates(
      session.members.map((m) => m.label),
      mention.query,
    );
  }

  void _completeMention(String label) {
    final mention = _mention;
    if (mention == null) return;
    final result = applyMention(
      _input.text,
      mention,
      label,
      _input.selection.baseOffset,
    );
    _input.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.caret),
    );
    _inputFocus.requestFocus();
  }

  Future<void> _attach(InstanceSession session) async {
    final picked = await widget.pickImage();
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final uploaded = await session.uploadImage(picked.bytes, picked.name);
      if (!mounted) return;
      setState(() {
        _attachment = uploaded;
        _uploading = false;
      });
      _inputFocus.requestFocus();
    } on UploadFailure catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      showToast(context, e.message, error: true);
    }
  }

  Future<void> _confirmDeleteMessage(
    BuildContext context,
    InstanceSession session,
    ChatMessage message,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteMessageConfirmTitle),
        content: Text(strings.deleteMessageConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) session.deleteMessage(message);
  }

  /// What Enter does: complete the highlighted mention while the picker is
  /// open, send otherwise. Handled here rather than by intercepting the key
  /// event, because a single-line field already routes Enter to
  /// `onSubmitted` and two handlers for one key would race.
  void _onSubmit(InstanceSession session) {
    final candidates = _mentionCandidates(session);
    if (candidates.isNotEmpty) {
      _completeMention(
        candidates[_mentionIndex.clamp(0, candidates.length - 1)],
      );
      return;
    }
    _send(session);
  }

  /// The card for a message's author. Everything but the id comes from the
  /// roster: a message frame carries only `userId`.
  void _openAuthorCard(
    BuildContext context,
    InstanceSession session,
    String userId,
    Rect anchor,
  ) {
    final isSelf = userId == session.userId;
    final member = session.memberFor(userId);
    String? voiceChannel;
    for (final channel in session.channels.where((c) => c.isVoice)) {
      if (session.voiceMembersFor(channel.id).any((m) => m.id == userId)) {
        voiceChannel = channel.name;
        break;
      }
    }
    showMemberCard(
      context,
      anchor: anchor,
      attachments: session.attachments,
      member: MemberCardData(
        id: userId,
        label: isSelf
            ? (session.displayName?.isNotEmpty == true
                  ? session.displayName!
                  : strings.you)
            : session.authorLabel(userId),
        avatarPath: isSelf
            ? session.myAvatarPath
            : session.avatarPathFor(userId),
        isOwner: member?.isOwner ?? false,
        isSelf: isSelf,
        online: member?.online,
        voiceChannelName: voiceChannel,
      ),
      onKickServer: session.isOwner && !isSelf
          ? () => session.kickFromServer(userId)
          : null,
    );
  }

  void _send(InstanceSession session) {
    final text = _input.text.trim();
    final attachment = _attachment;
    _inputFocus.requestFocus();
    // An image on its own is a complete message; text on its own still is too.
    if (text.isEmpty && attachment == null) return;
    session.sendText(text, attachmentId: attachment?.id);
    _input.clear();
    if (attachment != null) setState(() => _attachment = null);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();
    final channel = session.selectedChannel;
    if (channel == null) {
      return Center(child: Text(strings.pickTextChannel));
    }
    final messages = session.messagesFor(channel.id);
    final mentionCandidates = _mentionCandidates(session);
    // Computed once per build, not per message: every tile needs the same
    // roster to resolve the same names.
    final mentionLabels = [for (final m in session.members) m.label];
    // Our own roster entry, so "did this mention me" survives a display name
    // the socket never echoed back.
    final myLabel =
        session.members
            .where((m) => m.id == session.userId)
            .firstOrNull
            ?.label ??
        session.displayName;

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(child: Text(strings.channelStart(channel.name)))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    // reverse:true keeps the view pinned to the newest
                    // message; index 0 is the latest.
                    final m = messages[messages.length - 1 - i];
                    final isOwn = m.userId == session.userId;
                    return MessageTile(
                      message: m,
                      isOwn: isOwn,
                      // The roster is the only place a userId becomes a name;
                      // our own row is labelled "you" regardless.
                      author: isOwn
                          ? (session.displayName?.isNotEmpty == true
                                ? session.displayName!
                                : strings.you)
                          : session.authorLabel(m.userId),
                      avatarPath: isOwn
                          ? session.myAvatarPath
                          : session.avatarPathFor(m.userId),
                      attachments: session.attachments,
                      onDelete: session.isOwner && !m.pending
                          ? () => _confirmDeleteMessage(context, session, m)
                          : null,
                      onOpenAuthor: (anchor) =>
                          _openAuthorCard(context, session, m.userId, anchor),
                      mentionLabels: mentionLabels,
                      myLabel: myLabel,
                    );
                  },
                ),
        ),
        if (mentionCandidates.isNotEmpty)
          _MentionPicker(
            candidates: mentionCandidates,
            activeIndex: _mentionIndex,
            session: session,
            onHover: (i) => setState(() => _mentionIndex = i),
            onPick: _completeMention,
          ),
        if (_attachment != null)
          _AttachmentPreview(
            attachment: _attachment!,
            cache: session.attachments,
            onRemove: () => setState(() => _attachment = null),
          ),
        // One flat composer panel floating over the chat background — no
        // divider above it, the hairline border is the panel's own.
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: context.armonic.colors.backgroundSidebar,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: context.armonic.colors.border),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: strings.attachImage,
                icon: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined),
                onPressed: _uploading ? null : () => _attach(session),
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: _attachment != null
                        ? strings.imageOnlyMessageHint
                        : strings.sendMessageTo(channel.name),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _onSubmit(session),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 34,
                height: 34,
                child: IconButton.filled(
                  focusNode: _sendFocus,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: context.armonic.colors.accent,
                    foregroundColor: context.armonic.colors.onAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  icon: const Icon(Icons.send, size: 16),
                  onPressed: () => _send(session),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Makes the author's avatar and name open their card.
///
/// A wrapper rather than two copies of the same gesture code, and it also
/// reports its own rect, so the card is anchored to whichever of the two was
/// actually clicked.
class _AuthorTarget extends StatelessWidget {
  final void Function(Rect anchor)? onOpen;
  final Widget child;

  const _AuthorTarget({required this.onOpen, required this.child});

  @override
  Widget build(BuildContext context) {
    final open = onOpen;
    if (open == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Builder(
        builder: (innerContext) => GestureDetector(
          onTap: () {
            final anchor = globalRectOf(innerContext);
            if (anchor != null) open(anchor);
          },
          child: child,
        ),
      ),
    );
  }
}

/// The `@` autocomplete, stacked above the composer.
///
/// It grows upward from the chat bar and is capped at five rows: the roster
/// can be long, and a picker taller than that starts hiding the conversation
/// it is meant to help you write about.
class _MentionPicker extends StatelessWidget {
  final List<String> candidates;
  final int activeIndex;
  final InstanceSession session;
  final ValueChanged<int> onHover;
  final ValueChanged<String> onPick;

  static const maxVisible = 5;

  const _MentionPicker({
    required this.candidates,
    required this.activeIndex,
    required this.session,
    required this.onHover,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.armonic;
    final c = t.colors;
    final shown = candidates.take(maxVisible).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.accent.withValues(alpha: 0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 5),
            child: Text(
              strings.mentionPickerTitle,
              style: t.mono(size: 9, letterSpacing: 1.6),
            ),
          ),
          for (final (i, label) in shown.indexed)
            _MentionRow(
              label: label,
              active: i == activeIndex,
              avatarPath: session.members
                  .where((m) => m.label == label)
                  .firstOrNull
                  ?.avatarPath,
              attachments: session.attachments,
              onHover: () => onHover(i),
              onTap: () => onPick(label),
            ),
          if (candidates.length > maxVisible)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                strings.mentionPickerMore(candidates.length - maxVisible),
                style: t.mono(size: 9.5, weight: FontWeight.w400),
              ),
            ),
        ],
      ),
    );
  }
}

class _MentionRow extends StatelessWidget {
  final String label;
  final bool active;
  final String? avatarPath;
  final AttachmentCache? attachments;
  final VoidCallback onHover;
  final VoidCallback onTap;

  const _MentionRow({
    required this.label,
    required this.active,
    required this.avatarPath,
    required this.attachments,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      // Hovering moves the selection, so the row Enter takes and the row the
      // pointer is over are always the same one.
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: active ? c.selection : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              UserAvatar(
                cache: attachments,
                avatarPath: avatarPath,
                label: label,
                radius: 13,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? c.textPrimary : c.textBody,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (active)
                Text(
                  strings.mentionPickerEnterHint,
                  style: context.armonic.mono(size: 9, color: c.accentSoft),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The image staged for the next message: already uploaded and validated, so
/// what is shown here is exactly what the server stored (sanitized and
/// re-encoded), not the local file.
class _AttachmentPreview extends StatelessWidget {
  final Attachment attachment;
  final AttachmentCache cache;
  final VoidCallback onRemove;

  const _AttachmentPreview({
    required this.attachment,
    required this.cache,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: AttachmentImage(
              cache: cache,
              path: attachment.thumbUrl,
              width: 48,
              height: 48,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${attachment.width}x${attachment.height}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: strings.removeAttachment,
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class MessageTile extends StatefulWidget {
  final ChatMessage message;
  final bool isOwn;
  final String author;

  /// The author's avatar, resolved through the server roster. Null falls back
  /// to their initials.
  final String? avatarPath;

  /// Needed to fetch the avatar and the message's image, both of which sit
  /// behind the instance's JWT. Null in tests that render text only.
  final AttachmentCache? attachments;
  final VoidCallback? onDelete;

  /// Opens the author's card, given the tapped widget's global rect. Optional
  /// so the tile still renders standalone (tests, and any future read-only
  /// context with no roster behind it).
  final void Function(Rect anchor)? onOpenAuthor;

  /// Display names the roster knows, so `@name` in the body can be told apart
  /// from an ordinary word starting with `@`.
  final List<String> mentionLabels;

  /// The reader's own display name. A message mentioning it is highlighted.
  final String? myLabel;

  const MessageTile({
    super.key,
    required this.message,
    required this.isOwn,
    required this.author,
    this.avatarPath,
    this.attachments,
    this.onDelete,
    this.onOpenAuthor,
    this.mentionLabels = const [],
    this.myLabel,
  });

  static const imageKey = ValueKey('message-image');

  static const hoverBandKey = ValueKey('message-hover-band');

  /// The accent bar down the left edge of a message that mentions the reader.
  static const mentionBarKey = ValueKey('message-mention-bar');

  @override
  State<MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<MessageTile> {
  bool _hovered = false;

  Future<void> _showMenu(BuildContext context, Offset globalPosition) async {
    final delete = widget.onDelete;
    if (delete == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: delete,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  strings.deleteMessage,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = TimeOfDay.fromDateTime(
      widget.message.createdAt,
    ).format(context);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AuthorTarget(
          onOpen: widget.onOpenAuthor,
          child: UserAvatar(
            cache: widget.attachments,
            avatarPath: widget.avatarPath,
            label: widget.author,
            radius: context.armonic.chatAvatarRadius,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AuthorTarget(
                    onOpen: widget.onOpenAuthor,
                    child: Text(
                      widget.author,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Timestamps are mono microcopy in the redesign, sitting on
                  // the author's baseline.
                  Text(
                    time,
                    style: context.armonic.mono(
                      weight: FontWeight.w400,
                      color: context.armonic.colors.textMuted,
                    ),
                  ),
                  if (widget.message.pending) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.schedule,
                      size: 12,
                      color: theme.colorScheme.outline,
                    ),
                  ],
                ],
              ),
              // An image-only message has no text to draw.
              if (widget.message.content.isNotEmpty)
                _MessageBody(
                  content: widget.message.content,
                  labels: widget.mentionLabels,
                  myLabel: widget.myLabel,
                ),
              if (widget.message.hasAttachment && widget.attachments != null)
                _MessageImage(
                  key: MessageTile.imageKey,
                  cache: widget.attachments!,
                  attachmentId: widget.message.attachmentId!,
                ),
            ],
          ),
        ),
      ],
    );

    const insets = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    final c = context.armonic.colors;
    final mentioned =
        widget.myLabel != null &&
        mentionsLabel(widget.message.content, widget.myLabel!);

    // A message calling you out has to be findable while scrolling past, so
    // it keeps a tint of its own plus a bar down its left edge — and it wins
    // over the hover band rather than being erased by it.
    Widget banded(Widget child) => mentioned
        ? Stack(
            children: [
              child,
              PositionedDirectional(
                key: MessageTile.mentionBarKey,
                start: 0,
                top: 3,
                bottom: 3,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: c.warning,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          )
        : child;

    if (widget.onDelete == null) {
      return banded(
        Container(
          padding: insets,
          decoration: BoxDecoration(
            color: mentioned
                ? c.warning.withValues(alpha: 0.09)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: row,
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // Desktop/web right-click and mobile long-press.
        onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
        onLongPressStart: (d) => _showMenu(context, d.globalPosition),
        behavior: HitTestBehavior.opaque,
        child: banded(
          AnimatedContainer(
            key: MessageTile.hoverBandKey,
            duration: const Duration(milliseconds: 120),
            padding: insets,
            decoration: BoxDecoration(
              // theme.hoverColor is the Material overlay tuned for this, so it
              // stays legible if the app ever ships a light theme.
              color: mentioned
                  ? c.warning.withValues(alpha: _hovered ? 0.14 : 0.09)
                  : (_hovered ? theme.hoverColor : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
            ),
            child: row,
          ),
        ),
      ),
    );
  }
}

/// A message's text, with any `@name` that resolves to a real member painted
/// as a chip.
///
/// The mention is styled, not linked: the backend has no mention entity, so
/// this is a reading aid over plain text — which is also why an unrecognized
/// `@word` stays ordinary text rather than being dressed up as a person.
class _MessageBody extends StatelessWidget {
  final String content;
  final List<String> labels;
  final String? myLabel;

  const _MessageBody({
    required this.content,
    required this.labels,
    required this.myLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    final mentions = labels.isEmpty
        ? const <FoundMention>[]
        : findMentions(content, labels);
    if (mentions.isEmpty) return Text(content);

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final mention in mentions) {
      if (mention.start > cursor) {
        spans.add(TextSpan(text: content.substring(cursor, mention.start)));
      }
      // The one aimed at the reader is louder than the rest: in a message
      // naming several people, "which one is me" should not need reading.
      final isMe =
          myLabel != null &&
          mention.label.toLowerCase() == myLabel!.toLowerCase();
      spans.add(
        TextSpan(
          text: content.substring(mention.start, mention.end),
          style: TextStyle(
            color: isMe ? c.warning : c.accentSoft,
            fontWeight: FontWeight.w600,
            backgroundColor: (isMe ? c.warning : c.accent).withValues(
              alpha: 0.16,
            ),
          ),
        ),
      );
      cursor = mention.end;
    }
    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor)));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

/// The thumbnail in the message list, opening the full image on tap.
///
/// The list shows the server-generated thumbnail rather than the original: a
/// channel full of 25MB photos would otherwise pull every one of them over the
/// wire just to scroll past.
class _MessageImage extends StatelessWidget {
  final AttachmentCache cache;
  final String attachmentId;

  const _MessageImage({
    super.key,
    required this.cache,
    required this.attachmentId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: strings.openImage,
          child: InkWell(
            onTap: () => showAttachmentViewer(context, cache, attachmentId),
            borderRadius: BorderRadius.circular(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  maxHeight: 240,
                  minWidth: 64,
                  minHeight: 64,
                ),
                child: AttachmentImage(
                  cache: cache,
                  path: attachmentThumbPath(attachmentId),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-size view of an attachment, fetched only when actually opened.
Future<void> showAttachmentViewer(
  BuildContext context,
  AttachmentCache cache,
  String attachmentId,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: InteractiveViewer(
              maxScale: 5,
              child: AttachmentImage(
                cache: cache,
                path: attachmentPath(attachmentId),
                fit: BoxFit.contain,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(strings.closeImage),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
