import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/instance_store.dart';
import '../widgets/instance_rail.dart';
import 'add_instance_screen.dart';
import 'server_screen.dart';

/// Root navigation: the instance rail on the left, the selected instance's
/// [ServerScreen] filling the rest. Replaces the old list-of-cards home —
/// switching instances is one click, not a push/pop.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Null until the user picks one; the shell then defaults to the first
  /// stored instance, so removing the selected one falls back on its own.
  String? _selectedUrl;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<InstanceStore>();

    if (!store.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (store.instances.isEmpty) {
      return Scaffold(body: _EmptyState(onAdd: () => _addInstance(context)));
    }

    final instances = store.instances;
    final selected =
        instances.where((i) => i.baseUrl == _selectedUrl).firstOrNull ??
            instances.first;

    return Scaffold(
      body: Row(
        children: [
          InstanceRail(
            instances: instances,
            selectedUrl: selected.baseUrl,
            onSelect: (instance) => _select(context, instance),
            onRemove: (instance) => store.remove(instance.baseUrl),
            onAdd: () => _addInstance(context),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selected.token == null
                ? _NeedsLoginPane(
                    instance: selected,
                    onSignIn: () => _addInstance(context, selected.baseUrl),
                  )
                // Keyed by URL so switching instances tears the old session
                // down (socket closed, voice left) instead of reusing it.
                : ServerScreen(
                    key: ValueKey(selected.baseUrl), instance: selected),
          ),
        ],
      ),
    );
  }

  void _select(BuildContext context, StoredInstance instance) {
    if (instance.token == null) {
      _addInstance(context, instance.baseUrl);
      return;
    }
    setState(() => _selectedUrl = instance.baseUrl);
  }

  Future<void> _addInstance(BuildContext context, [String? initialUrl]) async {
    final instance = await Navigator.of(context).push<StoredInstance>(
      MaterialPageRoute(
        builder: (_) => AddInstanceScreen(initialUrl: initialUrl),
      ),
    );
    if (instance != null && mounted) {
      setState(() => _selectedUrl = instance.baseUrl);
    }
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
          const Icon(Icons.dns_outlined, size: 64),
          const SizedBox(height: 16),
          Text(strings.noInstancesYet),
          const SizedBox(height: 8),
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
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: 12),
          Text(instance.name.isNotEmpty ? instance.name : instance.baseUrl,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(strings.instanceNeedsLogin),
          const SizedBox(height: 12),
          FilledButton(onPressed: onSignIn, child: Text(strings.connect)),
        ],
      ),
    );
  }
}
