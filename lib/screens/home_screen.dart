import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/http_api.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/instance_store.dart';
import '../util/text.dart';
import 'add_instance_screen.dart';
import 'server_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<InstanceStore>();

    return Scaffold(
      appBar: AppBar(title: Text(strings.appTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addInstance(context),
        icon: const Icon(Icons.add),
        label: Text(strings.addServer),
      ),
      body: !store.loaded
          ? const Center(child: CircularProgressIndicator())
          : store.instances.isEmpty
              ? _EmptyState(onAdd: () => _addInstance(context))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(strings.myServersHeader,
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 8),
                    for (final instance in store.instances)
                      _InstanceCard(instance: instance),
                  ],
                ),
    );
  }

  Future<void> _addInstance(BuildContext context) async {
    final instance = await Navigator.of(context).push<StoredInstance>(
      MaterialPageRoute(builder: (_) => const AddInstanceScreen()),
    );
    if (instance != null && context.mounted) {
      _open(context, instance);
    }
  }

  static void _open(BuildContext context, StoredInstance instance) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ServerScreen(instance: instance)),
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

class _InstanceCard extends StatefulWidget {
  final StoredInstance instance;
  const _InstanceCard({required this.instance});

  @override
  State<_InstanceCard> createState() => _InstanceCardState();
}

class _InstanceCardState extends State<_InstanceCard> {
  late Future<InstanceInfo> _info;

  @override
  void initState() {
    super.initState();
    _info = ArmonicHttpApi(widget.instance.baseUrl).info();
  }

  @override
  Widget build(BuildContext context) {
    final instance = widget.instance;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            initialsOf(instance.name.isNotEmpty
                ? instance.name
                : instance.baseUrl),
          ),
        ),
        title: Text(instance.name.isNotEmpty ? instance.name : instance.baseUrl),
        subtitle: FutureBuilder<InstanceInfo>(
          future: _info,
          builder: (context, snap) {
            final parts = <String>[
              instance.baseUrl,
              if (instance.description.isNotEmpty) instance.description,
              if (snap.hasData) strings.membersCount(snap.data!.memberCount),
              if (snap.hasError) strings.offline,
            ];
            return Text(parts.join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis);
          },
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'remove') {
              context.read<InstanceStore>().remove(instance.baseUrl);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'remove', child: Text(strings.removeFromList)),
          ],
        ),
        onTap: () async {
          if (instance.token != null) {
            HomeScreen._open(context, instance);
          } else {
            // Stored without a token (e.g. aborted onboarding): redo it.
            final done = await Navigator.of(context).push<StoredInstance>(
              MaterialPageRoute(
                builder: (_) =>
                    AddInstanceScreen(initialUrl: instance.baseUrl),
              ),
            );
            if (done != null && context.mounted) {
              HomeScreen._open(context, done);
            }
          }
        },
      ),
    );
  }
}
