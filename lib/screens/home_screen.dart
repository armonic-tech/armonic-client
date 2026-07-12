import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/http_api.dart';
import '../models/models.dart';
import '../state/instance_store.dart';
import 'add_instance_screen.dart';
import 'server_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<InstanceStore>();

    return Scaffold(
      appBar: AppBar(title: const Text('Armonic')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addInstance(context),
        icon: const Icon(Icons.add),
        label: const Text('Agregar servidor'),
      ),
      body: !store.loaded
          ? const Center(child: CircularProgressIndicator())
          : store.instances.isEmpty
              ? _EmptyState(onAdd: () => _addInstance(context))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('MIS SERVIDORES',
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
          const Text('Sin instancias conectadas todavía'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Agregar una instancia de Armonic'),
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
            (instance.name.isNotEmpty ? instance.name : instance.baseUrl)
                .substring(0, 2)
                .toUpperCase(),
          ),
        ),
        title: Text(instance.name.isNotEmpty ? instance.name : instance.baseUrl),
        subtitle: FutureBuilder<InstanceInfo>(
          future: _info,
          builder: (context, snap) {
            final parts = <String>[
              instance.baseUrl,
              if (instance.description.isNotEmpty) instance.description,
              if (snap.hasData) '${snap.data!.memberCount} miembros',
              if (snap.hasError) 'sin conexión',
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
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'remove', child: Text('Quitar de la lista')),
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
