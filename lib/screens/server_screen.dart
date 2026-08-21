import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../api/http_api.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/session.dart';
import '../util/text.dart';

class ServerScreen extends StatefulWidget {
  final StoredInstance instance;
  const ServerScreen({super.key, required this.instance});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final InstanceSession _session;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<String>? _noticeSub;

  @override
  void initState() {
    super.initState();
    _session = InstanceSession(widget.instance);
    _errorSub = _session.errors.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(switch (message) {
          'message content invalid' => strings.messageInvalid,
          'error saving message' => strings.couldNotSaveMessage,
          'invalid invite' => strings.inviteInvalid,
          'unauthorized' || 'auth failed' => strings.notAllowed,
          _ => message,
        }),
      ));
    });
    _noticeSub = _session.notices.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    });
    _session.connect();
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _noticeSub?.cancel();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _session,
      child: Consumer<InstanceSession>(
        builder: (context, session, _) {
          final title = session.selectedServer?.name.isNotEmpty == true
              ? session.selectedServer!.name
              : (widget.instance.name.isNotEmpty
                  ? widget.instance.name
                  : widget.instance.baseUrl);
          return Scaffold(
            appBar: AppBar(
              title: Text(title),
              automaticallyImplyLeading: false,
            ),
            body: switch (session.status) {
              SessionStatus.connecting =>
                const Center(child: CircularProgressIndicator()),
              SessionStatus.error ||
              SessionStatus.disconnected =>
                _DisconnectedView(session: session),
              SessionStatus.connected => const _ConnectedBody(),
            },
          );
        },
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
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
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
  const _ConnectedBody();

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
                  child: Text(strings.noServersForAccount,
                      textAlign: TextAlign.center),
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

    return Row(
      children: [
        const SizedBox(width: 240, child: _ChannelSidebar()),
        const VerticalDivider(width: 1),
        const Expanded(child: _ChatPane()),
        // Zero-visual renderers that actually play the remote voice audio.
        for (final renderer in session.voice?.remoteRenderers ?? const [])
          SizedBox(width: 1, height: 1, child: RTCVideoView(renderer)),
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
              _SidebarHeader(strings.textHeader),
              for (final channel in textChannels)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.tag, size: 18),
                  title: Text(channel.name),
                  selected: session.selectedChannel?.id == channel.id,
                  onTap: () => session.selectChannel(channel),
                ),
              _SidebarHeader(strings.voiceHeader),
              for (final channel in voiceChannels) ...[
                ListTile(
                  dense: true,
                  leading: Icon(
                    session.voiceChannel?.id == channel.id
                        ? Icons.volume_up
                        : Icons.volume_up_outlined,
                    size: 18,
                  ),
                  title: Text(channel.name),
                  trailing: session.voiceMembersFor(channel.id).isNotEmpty
                      ? Text(
                          '${session.voiceMembersFor(channel.id).length}',
                          style: Theme.of(context).textTheme.labelSmall,
                        )
                      : null,
                  selected: session.voiceChannel?.id == channel.id,
                  onTap: () => _joinVoice(context, session, channel),
                ),
                for (final member in session.voiceMembersFor(channel.id))
                  VoiceMemberTile(
                    member: member,
                    isSelf: member.id == session.userId,
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
                  ),
              ],
            ],
          ),
        ),
        if (session.voiceChannel != null) const _VoicePanel(),
        const Divider(height: 1),
        ListTile(
          dense: true,
          leading: const Icon(Icons.person_add, size: 18),
          title: Text(strings.createInvite),
          subtitle: Text(strings.ownerOnly),
          onTap: () => _createInvite(context, session),
        ),
      ],
    );
  }

  Future<void> _confirmKickServer(BuildContext context,
      InstanceSession session, VoiceMember member) async {
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

  Future<void> _joinVoice(BuildContext context, InstanceSession session,
      ChannelInfo channel) async {
    try {
      await session.joinVoice(channel);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotAccessMic(e))),
        );
      }
    }
  }

  Future<void> _createInvite(
      BuildContext context, InstanceSession session) async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(forbidden
                  ? strings.onlyOwnerCanInvite
                  : strings.couldNotCreateInvite(e))),
        );
      }
    }
  }
}

/// Ask for an invite link/token and redeem it as the logged-in account
/// (WS join-server); the invite becomes unusable afterwards (single-use).
Future<void> showJoinWithInviteDialog(
    BuildContext context, InstanceSession session) async {
  final controller = TextEditingController();
  final input = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.joinWithInvite),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: strings.inviteLinkLabel,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: Text(strings.join),
        ),
      ],
    ),
  );
  controller.dispose();
  if (input == null || input.trim().isEmpty) return;
  try {
    await session.joinServerWithInvite(input);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.joinedServer)));
    }
  } catch (e) {
    if (context.mounted) {
      final invalid = e is StateError && e.message == 'invalid invite';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(invalid
              ? strings.inviteInvalid
              : strings.couldNotJoinServer(e))));
    }
  }
}

/// One connected user, indented under its voice channel in the sidebar.
/// When the moderation callbacks are non-null (owner looking at someone
/// else), right-click / long-press opens a context menu with kick actions.
class VoiceMemberTile extends StatelessWidget {
  final VoiceMember member;
  final bool isSelf;
  final bool muted;
  final bool deafened;
  final VoidCallback? onKickVoice;
  final VoidCallback? onKickServer;
  const VoiceMemberTile({
    super.key,
    required this.member,
    required this.isSelf,
    required this.muted,
    required this.deafened,
    this.onKickVoice,
    this.onKickServer,
  });

  bool get _canModerate => onKickVoice != null || onKickServer != null;

  Future<void> _showMenu(BuildContext context, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (onKickVoice != null)
          PopupMenuItem(
            value: onKickVoice,
            child: Row(
              children: [
                const Icon(Icons.logout, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(strings.kickFromVoice,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        if (onKickServer != null)
          PopupMenuItem(
            value: onKickServer,
            child: Row(
              children: [
                Icon(Icons.person_remove,
                    size: 16, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(strings.kickFromServer,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
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
    final row = Row(
      children: [
        CircleAvatar(
          radius: 9,
          child: Text(initialsOf(member.label),
              style: const TextStyle(fontSize: 8)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            member.label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: isSelf ? FontWeight.w600 : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (muted)
          Icon(Icons.mic_off, size: 12, color: theme.colorScheme.outline),
        if (deafened) ...[
          const SizedBox(width: 4),
          Icon(Icons.headset_off,
              size: 12, color: theme.colorScheme.outline),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(left: 48, right: 16, top: 2, bottom: 2),
      child: _canModerate
          ? GestureDetector(
              // Desktop/web right-click and mobile long-press.
              onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
              onLongPressStart: (d) => _showMenu(context, d.globalPosition),
              behavior: HitTestBehavior.opaque,
              child: row,
            )
          : row,
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final String label;
  const _SidebarHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _VoicePanel extends StatelessWidget {
  const _VoicePanel();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();
    final voice = session.voice;
    if (voice == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.voiceLabel(session.voiceChannel?.name ?? ''),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          if (session.voiceMembers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                session.voiceMembers.map((m) => m.label).join(', '),
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: voice.muted ? strings.unmute : strings.mute,
                icon: Icon(voice.muted ? Icons.mic_off : Icons.mic),
                onPressed: session.toggleMute,
              ),
              IconButton(
                tooltip: voice.deafened ? strings.undeafen : strings.deafen,
                icon: Icon(voice.deafened ? Icons.headset_off : Icons.headset),
                onPressed: session.toggleDeafen,
              ),
              IconButton(
                tooltip: strings.leaveVoiceTooltip,
                icon: const Icon(Icons.call_end, color: Colors.redAccent),
                onPressed: session.leaveVoice,
              ),
              const Spacer(),
              Text('${voice.remoteRenderers.length} 🔊',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatPane extends StatefulWidget {
  const _ChatPane();

  @override
  State<_ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<_ChatPane> {
  final _input = TextEditingController();

  // Enter-to-send drops the field's focus by default, and the send button
  // would steal it on tap — both make you re-click the box to keep typing.
  final _inputFocus = FocusNode();
  final _sendFocus = FocusNode(canRequestFocus: false, skipTraversal: true);

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _sendFocus.dispose();
    super.dispose();
  }

  void _send(InstanceSession session) {
    final text = _input.text.trim();
    _inputFocus.requestFocus();
    if (text.isEmpty) return;
    session.sendText(text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();
    final channel = session.selectedChannel;
    if (channel == null) {
      return Center(child: Text(strings.pickTextChannel));
    }
    final messages = session.messagesFor(channel.id);

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
                    return _MessageTile(
                        message: m, isOwn: m.userId == session.userId);
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: strings.sendMessageTo(channel.name),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(session),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                focusNode: _sendFocus,
                icon: const Icon(Icons.send),
                onPressed: () => _send(session),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageTile extends StatelessWidget {
  final ChatMessage message;
  final bool isOwn;
  const _MessageTile({required this.message, required this.isOwn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.read<InstanceSession>();
    final author = isOwn
        ? (session.displayName?.isNotEmpty == true
            ? session.displayName!
            : strings.you)
        : _shortId(message.userId);
    final time = TimeOfDay.fromDateTime(message.createdAt).format(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            child: Text(initialsOf(author),
                style: const TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(author, style: theme.textTheme.labelLarge),
                    const SizedBox(width: 6),
                    Text(time, style: theme.textTheme.bodySmall),
                    if (message.pending) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.schedule,
                          size: 12, color: theme.colorScheme.outline),
                    ],
                  ],
                ),
                Text(message.content),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shortId(String userId) =>
      userId.length <= 8 ? userId : userId.substring(0, 8);
}
