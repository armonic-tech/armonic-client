import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../screens/voice_screen.dart';
import '../state/session_manager.dart';
import '../theme/armonic_theme.dart';
import 'voice_status_panel.dart';

/// The phone's "you are in a call" strip, pinned above the composer.
///
/// Like [VoiceStatusPanel] it follows [SessionManager.voiceSession] rather
/// than the session on screen, so the call stays reachable from any instance.
/// Tapping it opens the full [VoiceScreen]; mute and hang-up are one tap away
/// without leaving the chat.
class CallBar extends StatelessWidget {
  const CallBar({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionManager>();
    final call = sessions.voiceSession;
    if (call == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: call,
      builder: (context, _) {
        final voice = call.voice;
        final channel = call.voiceChannel;
        if (voice == null || channel == null) return const SizedBox.shrink();
        final t = context.armonic;
        final c = t.colors;
        final instance = call.instance;
        final where = instance.name.isNotEmpty
            ? instance.name
            : instance.baseUrl;

        return Material(
          color: c.panel,
          child: InkWell(
            onTap: () => VoiceScreen.open(context),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: c.accent.withValues(alpha: 0.28)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  const LiveBars(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          channel.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${strings.voiceMembersCount(call.voiceMembers.length)}'
                          ' · $where',
                          style: t.mono(size: 10, weight: FontWeight.w400),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: voice.muted ? strings.unmute : strings.mute,
                    icon: Icon(
                      voice.muted ? Icons.mic_off : Icons.mic,
                      size: 20,
                      color: voice.muted ? c.mention : c.textSecondary,
                    ),
                    onPressed: call.toggleMute,
                  ),
                  IconButton(
                    tooltip: strings.leaveVoiceTooltip,
                    style: IconButton.styleFrom(
                      backgroundColor: c.mention,
                      foregroundColor: c.onMention,
                    ),
                    icon: const Icon(Icons.call_end, size: 20),
                    onPressed: call.leaveVoice,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
