import 'package:flutter/material.dart';

import '../api/http_api.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/instance_store.dart';
import '../util/text.dart';

/// One instance's logo as the app's live state knows it, which is not the
/// same question as "what did GET /info say": see [InstanceRail.logoOf].
class LiveLogo {
  /// Whether a live session answered at all.
  final bool known;

  /// Path of the logo thumbnail on that instance, or null for "none".
  final String? path;

  const LiveLogo({required this.known, this.path});
}

/// Discord-style vertical rail: one rounded square per instance saved in
/// [InstanceStore], plus a trailing "+" square to add another one.
///
/// The rail is pure local state — the list comes from what the user stored,
/// never from a backend (each backend *is* one instance). The only network
/// call is a one-shot GET /info per tile, used for the tooltip and the
/// offline dot; a failure there is cosmetic and never hides the instance.
class InstanceRail extends StatelessWidget {
  static const double width = 80;

  final List<StoredInstance> instances;
  final String? selectedUrl;

  /// Instance holding the live call, if any — marked so the user can see
  /// where they're talking while reading somewhere else.
  final String? voiceUrl;
  final ValueChanged<StoredInstance> onSelect;
  final ValueChanged<StoredInstance> onRemove;
  final VoidCallback onAdd;

  /// Injectable for tests; defaults to a real GET /info per instance.
  final Future<InstanceInfo> Function(String baseUrl)? fetchInfo;

  /// Membership per instance, probed once at launch by [InstanceStore]. The
  /// rail only paints it — it never asks the network about membership itself.
  final Membership Function(String baseUrl)? membershipOf;

  /// Whether the signed-in user administers that instance, which is what puts
  /// "create invite" in its context menu. Asked at menu time, not at build
  /// time: ownership is only known once that instance's session has loaded.
  final bool Function(String baseUrl)? canInvite;
  final ValueChanged<StoredInstance>? onCreateInvite;

  /// Owner-only too, gated on the same [canInvite] probe: on a phone the
  /// rail's context menu is the only server menu there is.
  final ValueChanged<StoredInstance>? onChangeLogo;

  /// Offered only when [logoOf] says that instance currently has a logo:
  /// "remove" on a server that has none would be a no-op entry.
  final ValueChanged<StoredInstance>? onRemoveLogo;

  /// What the live session of that instance knows about its logo.
  ///
  /// `known: false` means there is no session to ask (an instance still
  /// needing sign-in), and then the tile's own GET /info decides. When there
  /// *is* a session its answer wins, including `path: null` for "this server
  /// has no logo" — that is what makes a removal repaint. Letting /info win
  /// there would keep painting the logo it was fetched with, which is
  /// exactly how the first version of this got the removal wrong.
  final LiveLogo Function(String baseUrl)? logoOf;

  const InstanceRail({
    super.key,
    required this.instances,
    required this.selectedUrl,
    this.voiceUrl,
    required this.onSelect,
    required this.onRemove,
    required this.onAdd,
    this.fetchInfo,
    this.membershipOf,
    this.canInvite,
    this.onCreateInvite,
    this.onChangeLogo,
    this.onRemoveLogo,
    this.logoOf,
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
                    inVoice: instance.baseUrl == voiceUrl,
                    onTap: () => onSelect(instance),
                    onRemove: () => onRemove(instance),
                    onCreateInvite: onCreateInvite == null
                        ? null
                        : () => onCreateInvite!(instance),
                    onChangeLogo: onChangeLogo == null
                        ? null
                        : () => onChangeLogo!(instance),
                    // No logo, nothing to remove. An instance with no
                    // session is not offered it either: the menu would be
                    // guessing, and the backend would answer 403 anyway.
                    onRemoveLogo:
                        onRemoveLogo == null ||
                            logoOf?.call(instance.baseUrl).path == null
                        ? null
                        : () => onRemoveLogo!(instance),
                    logo:
                        logoOf?.call(instance.baseUrl) ??
                        const LiveLogo(known: false),
                    canInvite: () => canInvite?.call(instance.baseUrl) ?? false,
                    fetchInfo: fetchInfo ?? _defaultFetchInfo,
                    membership:
                        membershipOf?.call(instance.baseUrl) ??
                        Membership.unknown,
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
              child: Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.primary,
              ),
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
  final bool inVoice;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onCreateInvite;
  final VoidCallback? onChangeLogo;
  final VoidCallback? onRemoveLogo;
  final LiveLogo logo;
  final bool Function() canInvite;
  final Future<InstanceInfo> Function(String baseUrl) fetchInfo;
  final Membership membership;

  const _InstanceTile({
    super.key,
    required this.instance,
    required this.selected,
    required this.inVoice,
    required this.onTap,
    required this.onRemove,
    required this.canInvite,
    required this.fetchInfo,
    required this.membership,
    required this.logo,
    this.onCreateInvite,
    this.onChangeLogo,
    this.onRemoveLogo,
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
    final owner = widget.canInvite();
    final invite = widget.onCreateInvite != null && owner;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (invite)
          PopupMenuItem(
            value: widget.onCreateInvite,
            child: Row(
              children: [
                const Icon(Icons.person_add, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    strings.createInvite,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (widget.onChangeLogo != null && owner)
          PopupMenuItem(
            value: widget.onChangeLogo,
            child: Row(
              children: [
                const Icon(Icons.image_outlined, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    strings.changeServerLogo,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (widget.onRemoveLogo != null && owner)
          PopupMenuItem(
            value: widget.onRemoveLogo,
            child: Row(
              children: [
                const Icon(Icons.hide_image_outlined, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    strings.removeServerLogo,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          value: widget.onRemove,
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
                  strings.removeFromList,
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

  Widget _initials(ColorScheme scheme) => Text(
    initialsOf(_label),
    style: TextStyle(
      fontWeight: FontWeight.w600,
      color: widget.selected
          ? scheme.onPrimaryContainer
          : scheme.onSurfaceVariant,
    ),
  );

  /// The logo square, or null when the instance has none.
  ///
  /// Served without a token, like the name beside it, so no header plumbing
  /// is needed here; a broken image falls back to initials rather than
  /// leaving a blank tile.
  Widget? _logo(InstanceInfo? info) {
    final path = widget.logo.known
        ? widget.logo.path ?? ''
        : info?.logoThumbPath ?? '';
    if (path.isEmpty) return null;
    return Builder(
      builder: (context) => Image.network(
        '${widget.instance.baseUrl}$path',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stack) =>
            Center(child: _initials(Theme.of(context).colorScheme)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<InstanceInfo>(
      future: _info,
      builder: (context, snap) {
        final notMember = widget.membership == Membership.notMember;
        final details = <String>[
          _label,
          widget.instance.baseUrl,
          if (snap.hasData) strings.membersCount(snap.data!.memberCount),
          if (snap.hasError) strings.offline,
          if (widget.instance.token == null) strings.instanceNeedsLogin,
          if (notMember) strings.notAMember,
          if (widget.inVoice) strings.inVoiceHere,
        ];
        // Three distinct dots on purpose: a red "unreachable right now" must
        // never be read as a grey "you were removed", and vice versa.
        final Color? badge = snap.hasError
            ? scheme.error
            : widget.instance.token == null
            ? scheme.tertiary
            : notMember
            ? scheme.outline
            : null;
        return Row(
          children: [
            // Selection indicator, Discord-style: a pill hugging the left edge.
            Container(
              width: 4,
              height: widget.selected ? 36 : 0,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(4),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
                onLongPressStart: (d) => _showMenu(context, d.globalPosition),
                child: Opacity(
                  opacity: notMember ? 0.45 : 1,
                  child: _RailSquare(
                    tooltip: details.join('\n'),
                    onTap: widget.onTap,
                    background: widget.selected
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    badge: badge,
                    inVoice: widget.inVoice,
                    child: _logo(snap.data) ?? _initials(scheme),
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
  final bool inVoice;
  final Widget child;

  const _RailSquare({
    required this.tooltip,
    required this.onTap,
    required this.background,
    required this.child,
    this.badge,
    this.inVoice = false,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(15));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: SizedBox(
            width: 54,
            height: 54,
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
                // Top corner, so it never fights the status dot below it:
                // "there's a call here" and "this instance is unreachable /
                // needs login" are separate facts and can be true together.
                if (inVoice)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLowest,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.volume_up,
                        size: 10,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
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
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLowest,
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
