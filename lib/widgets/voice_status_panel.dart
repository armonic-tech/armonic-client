import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/armonic_theme.dart';

/// "You are in a call" panel, pinned at the foot of the channel sidebar.
///
/// It reports the call wherever it is running, not the instance whose sidebar
/// it sits in: a call survives switching instances in the rail, so the panel
/// has to name *where* it is and keep its controls reachable from anywhere.
///
/// Deliberately takes plain values instead of an `InstanceSession`: the screen
/// maps the session onto it, and the panel stays renderable without WebRTC.
class VoiceStatusPanel extends StatelessWidget {
  final String channelName;

  /// Name of the instance (rail entry) hosting the call, and of the server
  /// inside it. They're usually the same one-server instance, in which case
  /// only one is shown.
  final String instanceLabel;
  final String serverName;

  final List<String> memberLabels;
  final bool muted;
  final bool deafened;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleDeafen;
  final VoidCallback onLeave;

  /// Jump the rail back to the instance hosting the call. Null while it's
  /// already the one on screen.
  final VoidCallback? onOpen;

  const VoiceStatusPanel({
    super.key,
    required this.channelName,
    required this.instanceLabel,
    required this.serverName,
    required this.memberLabels,
    required this.muted,
    required this.deafened,
    required this.onToggleMute,
    required this.onToggleDeafen,
    required this.onLeave,
    this.onOpen,
  });

  String get _location => serverName.isEmpty || serverName == instanceLabel
      ? instanceLabel
      : strings.voiceLocation(instanceLabel, serverName);

  @override
  Widget build(BuildContext context) {
    final t = context.armonic;
    final c = t.colors;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 3), child: _LiveBars()),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.voiceLabel(channelName),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _location,
                style: t.mono(size: 10, weight: FontWeight.w400),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (onOpen != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 2),
            child: Icon(Icons.open_in_new, size: 13, color: c.accentSoft),
          ),
      ],
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(11),
        // A faint accent edge is what marks the panel as live, rather than a
        // heavier fill that would compete with the channel list above it.
        border: Border.all(color: c.accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onOpen == null)
            header
          else
            InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(7),
              child: Tooltip(message: strings.goToVoiceServer, child: header),
            ),
          if (memberLabels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.group, size: 13, color: c.textFaint),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    memberLabels.join(', '),
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _CallButton(
                tooltip: muted ? strings.unmute : strings.mute,
                icon: muted ? Icons.mic_off : Icons.mic,
                hoverIcon: muted ? Icons.mic : Icons.mic_off,
                active: muted,
                onPressed: onToggleMute,
              ),
              const SizedBox(width: 8),
              _CallButton(
                tooltip: deafened ? strings.undeafen : strings.deafen,
                icon: deafened ? Icons.headset_off : Icons.headset,
                hoverIcon: deafened ? Icons.headset : Icons.headset_off,
                active: deafened,
                onPressed: onToggleDeafen,
              ),
              const Spacer(),
              _CallButton(
                tooltip: strings.leaveVoiceTooltip,
                icon: Icons.call_end,
                danger: true,
                onPressed: onLeave,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The static equalizer glyph that reads as "audio is flowing".
///
/// Deliberately not animated: an endlessly repeating animation never lets
/// `pumpAndSettle` finish, so every widget test that happens to render a call
/// would hang on it.
class _LiveBars extends StatelessWidget {
  const _LiveBars();

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    const heights = [5.0, 9.0, 12.0, 7.0];
    return SizedBox(
      height: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, height) in heights.indexed) ...[
            if (i > 0) const SizedBox(width: 2),
            Container(
              width: 2.5,
              height: height,
              decoration: BoxDecoration(
                color: c.accentSoft.withValues(alpha: height / 12),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One control in the call's button row.
///
/// Hover never recolors the button. Where the icon has a struck-through twin
/// it swaps to it instead — which doubles as a preview of what the click
/// does, since these are toggles: hovering an open mic shows it crossed out.
/// The hang-up has no such twin, so it just darkens.
class _CallButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;

  /// Shown while hovered. Null for buttons with no struck-through variant,
  /// which darken instead.
  final IconData? hoverIcon;
  final bool active;
  final bool danger;
  final VoidCallback onPressed;

  const _CallButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.hoverIcon,
    this.active = false,
    this.danger = false,
  });

  @override
  State<_CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<_CallButton> {
  bool _hovered = false;

  static const _fade = Duration(milliseconds: 140);

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    final (Color background, Color foreground) = widget.danger
        ? (c.mention, c.onMention)
        : widget.active
        ? (c.mention.withValues(alpha: 0.16), c.mention)
        : (c.chip, c.textSecondary);

    // Only the button with nothing to swap to reacts with a shade; the rest
    // keep exactly the color they had.
    final showDarker = _hovered && widget.hoverIcon == null;
    final icon = _hovered ? (widget.hoverIcon ?? widget.icon) : widget.icon;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: _fade,
            width: 38,
            height: 34,
            decoration: BoxDecoration(
              color: showDarker
                  ? Color.lerp(background, Colors.black, 0.22)!
                  : background,
              borderRadius: BorderRadius.circular(9),
            ),
            child: AnimatedSwitcher(
              duration: _fade,
              // Keyed by the glyph, so swapping mic <-> mic_off cross-fades
              // rather than snapping.
              child: Icon(
                icon,
                key: ValueKey(icon.codePoint),
                size: 17,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
