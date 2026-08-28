import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final where = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.volume_up, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                strings.voiceLabel(channelName),
                style: theme.textTheme.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onOpen != null)
              Icon(Icons.open_in_new, size: 12, color: scheme.outline),
          ],
        ),
        Text(
          _location,
          style:
              theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onOpen == null)
              where
            else
              InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(6),
                child: Tooltip(message: strings.goToVoiceServer, child: where),
              ),
            if (memberLabels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child:
                          Icon(Icons.group, size: 12, color: scheme.outline),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        memberLabels.join(', '),
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: muted ? strings.unmute : strings.mute,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(muted ? Icons.mic_off : Icons.mic),
                  onPressed: onToggleMute,
                ),
                IconButton(
                  tooltip: deafened ? strings.undeafen : strings.deafen,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(deafened ? Icons.headset_off : Icons.headset),
                  onPressed: onToggleDeafen,
                ),
                const Spacer(),
                IconButton(
                  tooltip: strings.leaveVoiceTooltip,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.call_end, color: Colors.redAccent),
                  onPressed: onLeave,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
