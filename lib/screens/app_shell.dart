import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/instance_store.dart';
import '../state/session.dart';
import '../state/session_manager.dart';
import '../theme/armonic_theme.dart';
import '../widgets/instance_rail.dart';
import 'add_instance_screen.dart';
import 'server_screen.dart';

/// Root navigation: the instance rail on the left, the selected instance's
/// [ServerScreen] filling the rest. Replaces the old list-of-cards home —
/// switching instances is one click, not a push/pop.
///
/// Which instance is on screen is [SessionManager]'s, not this widget's: the
/// call panel at the foot of the sidebar can send the user back to the
/// instance hosting the call, from deep inside the screen it would replace.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<InstanceStore>();
    final sessions = context.watch<SessionManager>();

    if (!store.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (store.instances.isEmpty) {
      return Scaffold(body: _EmptyState(onAdd: () => _addInstance(context)));
    }

    final instances = store.instances;
    // Falls back to the first stored instance, so removing the selected one
    // recovers on its own.
    final selected =
        instances.where((i) => i.baseUrl == sessions.selectedUrl).firstOrNull ??
        instances.first;
    final inCall = sessions.voiceSession;

    return Scaffold(
      // The ambient glow paints over everything — rail included — as one
      // diagonal wash, per the redesign canvas (option 2a); the panels
      // underneath stay flat.
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    InstanceRail(
                      instances: instances,
                      selectedUrl: selected.baseUrl,
                      voiceUrl: inCall?.instance.baseUrl,
                      onSelect: (instance) => _select(context, instance),
                      onRemove: (instance) {
                        sessions.release(instance.baseUrl);
                        store.remove(instance.baseUrl);
                      },
                      onAdd: () => _addInstance(context),
                      membershipOf: store.membershipOf,
                      // Admin-only entry, and only for instances already opened:
                      // ownership is a fact of a live session, and the rail must
                      // not connect to an instance just to draw a menu.
                      canInvite: (baseUrl) =>
                          sessions.peek(baseUrl)?.isOwner ?? false,
                      onCreateInvite: (instance) {
                        final session = sessions.peek(instance.baseUrl);
                        if (session != null) {
                          showCreateInviteDialog(context, session);
                        }
                      },
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: selected.token == null
                          ? _NeedsLoginPane(
                              instance: selected,
                              onSignIn: () =>
                                  _addInstance(context, selected.baseUrl),
                            )
                          // Keyed by URL so the screen state (subscriptions, chat
                          // scroll) belongs to one instance; the session behind it
                          // is the manager's and survives the swap.
                          : ServerScreen(
                              key: ValueKey(selected.baseUrl),
                              session: sessions.sessionFor(selected),
                            ),
                    ),
                  ],
                ),
              ),
              if (inCall != null) _CallAudio(session: inCall),
            ],
          ),
          const Positioned.fill(child: AmbientGlow()),
        ],
      ),
    );
  }

  void _select(BuildContext context, StoredInstance instance) {
    if (instance.token == null) {
      _addInstance(context, instance.baseUrl);
      return;
    }
    context.read<SessionManager>().select(instance.baseUrl);
  }

  Future<void> _addInstance(BuildContext context, [String? initialUrl]) async {
    final sessions = context.read<SessionManager>();
    final instance = await Navigator.of(context).push<StoredInstance>(
      MaterialPageRoute(
        builder: (_) => AddInstanceScreen(initialUrl: initialUrl),
      ),
    );
    if (instance != null) sessions.select(instance.baseUrl);
  }
}

/// The zero-sized renderers that actually play the remote voice audio.
///
/// They live in the shell, not in the server screen, because unmounting an
/// [RTCVideoView] detaches the stream from the element playing it — switching
/// instances mid-call would cut the sound even though the renderer survives.
class _CallAudio extends StatelessWidget {
  final InstanceSession session;
  const _CallAudio({required this.session});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => SizedBox(
        height: 1,
        child: Row(
          children: [
            for (final renderer in session.voice?.remoteRenderers ?? const [])
              SizedBox(width: 1, height: 1, child: RTCVideoView(renderer)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 72,
            color: context.armonic.colors.textFaint,
          ),
          const SizedBox(height: 20),
          Text(
            strings.noInstancesYet,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(strings.addArmonicInstance),
          ),
        ],
      ),
    );
  }
}

/// Stored without a token (e.g. aborted onboarding): the rail still shows it,
/// but there's no session to open until the user finishes signing in.
class _NeedsLoginPane extends StatelessWidget {
  final StoredInstance instance;
  final VoidCallback onSignIn;
  const _NeedsLoginPane({required this.instance, required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 52,
            color: context.armonic.colors.textFaint,
          ),
          const SizedBox(height: 14),
          Text(
            instance.name.isNotEmpty ? instance.name : instance.baseUrl,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(strings.instanceNeedsLogin),
          const SizedBox(height: 18),
          FilledButton(onPressed: onSignIn, child: Text(strings.connect)),
        ],
      ),
    );
  }
}
