import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../state/session.dart';
import '../theme/armonic_theme.dart';
import 'member_card.dart';
import 'toast.dart';

/// Marks a bot account wherever a name is shown, so nobody mistakes the
/// voice they hear for a person's.
class BotBadge extends StatelessWidget {
  const BotBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.armonic;
    final c = t.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c.accentSoft.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        strings.botBadge.toUpperCase(),
        style: t.mono(
          size: 9,
          weight: FontWeight.w600,
          letterSpacing: 1,
          color: c.accentSoft,
        ),
      ),
    );
  }
}

/// The card action that summons [member] into the owner's current call, or
/// null when it does not apply: only the owner summons, only an online bot
/// that is not already in a call, and only into a call the owner is in —
/// the bot talks to whoever summoned it, so it never sits in an empty room.
MemberCardAction? botSummonAction(
  BuildContext context,
  InstanceSession session,
  Member member,
) {
  final call = session.voiceChannel;
  if (!session.isOwner ||
      !member.isBot ||
      !member.online ||
      call == null ||
      session.voiceChannelOf(member.id) != null) {
    return null;
  }
  return (
    label: strings.summonBotTo(call.name),
    onPressed: () {
      session.summonBot(call.id, member.id);
      showToast(context, strings.summoningBot);
    },
  );
}
