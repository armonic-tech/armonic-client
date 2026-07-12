import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/session.dart';

class ServerScreen extends StatefulWidget {
  final StoredInstance instance;
  const ServerScreen({super.key, required this.instance});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final InstanceSession _session;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    _session = InstanceSession(widget.instance);
    _errorSub = _session.errors.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message == 'message content invalid'
            ? 'Mensaje inválido (vacío o demasiado largo)'
            : message),
      ));
    });
    _session.connect();
  }

  @override
  void dispose() {
    _errorSub?.cancel();
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
            appBar: AppBar(title: Text(title)),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text(session.errorMessage ?? 'Desconectado de la instancia'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: session.connect,
            child: const Text('Reconectar'),
          ),
        ],
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
      if (session.servers.isEmpty) {
        return const Center(child: Text('Sin servidores para esta cuenta'));
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final server in session.servers)
                ListTile(
                  leading: const Icon(Icons.dns),
                  title: Text(server.name.isNotEmpty ? server.name : server.id),
                  onTap: () => session.selectServer(server),
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
              const _SidebarHeader('TEXTO'),
              for (final channel in textChannels)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.tag, size: 18),
                  title: Text(channel.name),
                  selected: session.selectedChannel?.id == channel.id,
                  onTap: () => session.selectChannel(channel),
                ),
              const _SidebarHeader('VOZ'),
              for (final channel in voiceChannels)
                ListTile(
                  dense: true,
                  leading: Icon(
                    session.voiceChannel?.id == channel.id
                        ? Icons.volume_up
                        : Icons.volume_up_outlined,
                    size: 18,
                  ),
                  title: Text(channel.name),
                  selected: session.voiceChannel?.id == channel.id,
                  onTap: () => _joinVoice(context, session, channel),
                ),
            ],
          ),
        ),
        if (session.voiceChannel != null) const _VoicePanel(),
        const Divider(height: 1),
        ListTile(
          dense: true,
          leading: const Icon(Icons.person_add, size: 18),
          title: const Text('Crear invitación'),
          subtitle: const Text('solo dueño'),
          onTap: () => _createInvite(context, session),
        ),
      ],
    );
  }

  Future<void> _joinVoice(BuildContext context, InstanceSession session,
      ChannelInfo channel) async {
    try {
      await session.joinVoice(channel);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo acceder al micrófono: $e')),
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
          title: const Text('Invitación creada'),
          content: SelectableText(
            '$url\n\nEs de un solo uso y vence en 24 horas.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Copiar y cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().contains('unauthorized')
                  ? 'Solo el dueño de la instancia puede crear invitaciones'
                  : 'No se pudo crear la invitación: $e')),
        );
      }
    }
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
            'Voz: ${session.voiceChannel?.name ?? ''}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Row(
            children: [
              IconButton(
                tooltip: voice.muted ? 'Activar micrófono' : 'Silenciar',
                icon: Icon(voice.muted ? Icons.mic_off : Icons.mic),
                onPressed: voice.toggleMute,
              ),
              IconButton(
                tooltip: 'Salir del canal de voz',
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

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send(InstanceSession session) {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    session.sendText(text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<InstanceSession>();
    final channel = session.selectedChannel;
    if (channel == null) {
      return const Center(child: Text('Elegí un canal de texto'));
    }
    final messages = session.messagesFor(channel.id);

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(child: Text('Este es el inicio de #${channel.name}'))
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
                  decoration: InputDecoration(
                    hintText: 'Enviar mensaje a #${channel.name}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(session),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
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
            : 'vos')
        : _shortId(message.userId);
    final time = TimeOfDay.fromDateTime(message.createdAt).format(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            child: Text(author.substring(0, 2).toUpperCase(),
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
