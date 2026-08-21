import 'package:flutter/material.dart';

import '../api/http_api.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../util/text.dart';

/// Discord-style vertical rail: one rounded square per instance saved in
/// [InstanceStore], plus a trailing "+" square to add another one.
///
/// The rail is pure local state — the list comes from what the user stored,
/// never from a backend (each backend *is* one instance). The only network
/// call is a one-shot GET /info per tile, used for the tooltip and the
/// offline dot; a failure there is cosmetic and never hides the instance.
class InstanceRail extends StatelessWidget {
  static const double width = 72;

  final List<StoredInstance> instances;
  final String? selectedUrl;
  final ValueChanged<StoredInstance> onSelect;
  final ValueChanged<StoredInstance> onRemove;
  final VoidCallback onAdd;

  /// Injectable for tests; defaults to a real GET /info per instance.
  final Future<InstanceInfo> Function(String baseUrl)? fetchInfo;

  const InstanceRail({
    super.key,
    required this.instances,
    required this.selectedUrl,
    required this.onSelect,
    required this.onRemove,
    required this.onAdd,
    this.fetchInfo,
  });

  static Future<InstanceInfo> _defaultFetchInfo(String baseUrl) =>
      ArmonicHttpApi(baseUrl).info();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final instance in instances)
                  _InstanceTile(
                    key: ValueKey(instance.baseUrl),
                    instance: instance,
                    selected: instance.baseUrl == selectedUrl,
                    onTap: () => onSelect(instance),
                    onRemove: () => onRemove(instance),
                    fetchInfo: fetchInfo ?? _defaultFetchInfo,
                  ),
              ],
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RailSquare(
              tooltip: strings.addServer,
              onTap: onAdd,
              background: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(Icons.add,
                  color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstanceTile extends StatefulWidget {
  final StoredInstance instance;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final Future<InstanceInfo> Function(String baseUrl) fetchInfo;

  const _InstanceTile({
    super.key,
    required this.instance,
    required this.selected,
    required this.onTap,
    required this.onRemove,
    required this.fetchInfo,
  });

  @override
  State<_InstanceTile> createState() => _InstanceTileState();
}

class _InstanceTileState extends State<_InstanceTile> {
  late Future<InstanceInfo> _info;

  @override
  void initState() {
    super.initState();
    _info = widget.fetchInfo(widget.instance.baseUrl);
  }

  String get _label => widget.instance.name.isNotEmpty
      ? widget.instance.name
      : widget.instance.baseUrl;

  Future<void> _showMenu(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final remove = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: true, child: Text(strings.removeFromList)),
      ],
    );
    if (remove == true) widget.onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<InstanceInfo>(
      future: _info,
      builder: (context, snap) {
        final details = <String>[
          _label,
          widget.instance.baseUrl,
          if (snap.hasData) strings.membersCount(snap.data!.memberCount),
          if (snap.hasError) strings.offline,
          if (widget.instance.token == null) strings.instanceNeedsLogin,
        ];
        return Row(
          children: [
            // Selection indicator, Discord-style: a pill hugging the left edge.
            Container(
              width: 4,
              height: widget.selected ? 32 : 0,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(4)),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
                onLongPressStart: (d) => _showMenu(context, d.globalPosition),
                child: _RailSquare(
                  tooltip: details.join('\n'),
                  onTap: widget.onTap,
                  background: widget.selected
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  badge: snap.hasError
                      ? scheme.error
                      : widget.instance.token == null
                          ? scheme.tertiary
                          : null,
                  child: Text(
                    initialsOf(_label),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: widget.selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The rounded square itself — shared by instance tiles and the "+" button so
/// they stay the same size/shape.
class _RailSquare extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  final Color background;
  final Color? badge;
  final Widget child;

  const _RailSquare({
    required this.tooltip,
    required this.onTap,
    required this.background,
    required this.child,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(16));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Material(
                  color: background,
                  borderRadius: radius,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTap,
                    child: Center(child: child),
                  ),
                ),
                if (badge != null)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: badge,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLowest,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
