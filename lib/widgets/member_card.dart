import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../state/attachment_cache.dart';
import '../theme/armonic_theme.dart';
import 'attachment_image.dart';

/// What the card shows. Built from either a roster [Member] or a
/// [VoiceMember], which carry different halves of the same person — the
/// roster knows presence and ownership, the voice list knows mic state — so
/// the card takes the union rather than one of the two models.
class MemberCardData {
  final String id;
  final String label;
  final String? avatarPath;
  final bool isOwner;
  final bool isSelf;

  /// Null when unknown (a voice tile with no roster entry loaded yet).
  final bool? online;

  /// Name of the voice channel they are in, if any.
  final String? voiceChannelName;
  final bool muted;
  final bool deafened;

  const MemberCardData({
    required this.id,
    required this.label,
    this.avatarPath,
    this.isOwner = false,
    this.isSelf = false,
    this.online,
    this.voiceChannelName,
    this.muted = false,
    this.deafened = false,
  });
}

/// Opens the member card beside [anchor] (the tapped tile's global rect).
///
/// A dialog rather than a popup menu: it is a read surface with its own
/// layout, and anchoring it to the tile is what makes it read as "this
/// person" instead of a modal about nobody in particular.
Future<void> showMemberCard(
  BuildContext context, {
  required Rect anchor,
  required MemberCardData member,
  AttachmentCache? attachments,
  VoidCallback? onKickVoice,
  VoidCallback? onKickServer,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black26,
    builder: (dialogContext) => _AnchoredMemberCard(
      anchor: anchor,
      member: member,
      attachments: attachments,
      onKickVoice: onKickVoice,
      onKickServer: onKickServer,
    ),
  );
}

const _cardWidth = 300.0;

/// Places the card next to the tile, preferring its left (the tiles that open
/// it live in the right-hand roster and the sidebar) and flipping to the other
/// side when there is no room, so it never lands off-screen or on top of what
/// was clicked.
class _AnchoredMemberCard extends StatelessWidget {
  final Rect anchor;
  final MemberCardData member;
  final AttachmentCache? attachments;
  final VoidCallback? onKickVoice;
  final VoidCallback? onKickServer;

  const _AnchoredMemberCard({
    required this.anchor,
    required this.member,
    this.attachments,
    this.onKickVoice,
    this.onKickServer,
  });

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    const gap = 10.0;
    const margin = 12.0;

    var left = anchor.left - _cardWidth - gap;
    if (left < margin) {
      final right = anchor.right + gap;
      left = right + _cardWidth + margin <= screen.width
          ? right
          : (screen.width - _cardWidth) / 2;
    }

    // Top-aligned with the tile, then pulled back inside the viewport — the
    // card is much taller than the row that opened it.
    const estimatedHeight = 330.0;
    var top = anchor.top - 8;
    if (top + estimatedHeight + margin > screen.height) {
      top = screen.height - estimatedHeight - margin;
    }
    if (top < margin) top = margin;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: _cardWidth,
          child: _MemberCard(
            member: member,
            attachments: attachments,
            onKickVoice: onKickVoice,
            onKickServer: onKickServer,
          ),
        ),
      ],
    );
  }
}

class _MemberCard extends StatelessWidget {
  final MemberCardData member;
  final AttachmentCache? attachments;
  final VoidCallback? onKickVoice;
  final VoidCallback? onKickServer;

  const _MemberCard({
    required this.member,
    this.attachments,
    this.onKickVoice,
    this.onKickServer,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.armonic;
    final c = t.colors;
    final canModerate = onKickVoice != null || onKickServer != null;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.accentSoft.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 44,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner, per the design canvas: a gradient strip the avatar
            // overlaps from below.
            Container(
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.accentDeep, c.accent.withValues(alpha: 0.55)],
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -30),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: c.panel, width: 4),
                      ),
                      child: UserAvatar(
                        cache: attachments,
                        avatarPath: member.avatarPath,
                        label: member.label,
                        radius: 32,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      member.label,
                      style: TextStyle(
                        fontFamily: kUiFont,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: c.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        member.id.length <= 8
                            ? member.id
                            : member.id.substring(0, 8),
                        if (member.isOwner) strings.ownerBadge.toUpperCase(),
                        if (member.isSelf) strings.you.toUpperCase(),
                      ].join(' · '),
                      style: t.mono(size: 11, weight: FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: c.border),
                    const SizedBox(height: 14),
                    Text(
                      strings.memberStatusLabel,
                      style: t.mono(
                        size: 9,
                        letterSpacing: 1.6,
                        color: c.accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StatusRow(member: member),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
            if (canModerate)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onKickVoice != null)
                      _CardAction(
                        icon: Icons.logout,
                        label: strings.kickFromVoice,
                        onPressed: () {
                          Navigator.of(context).pop();
                          onKickVoice!();
                        },
                      ),
                    if (onKickServer != null) ...[
                      const SizedBox(height: 8),
                      _CardAction(
                        icon: Icons.person_remove,
                        label: strings.kickFromServer,
                        danger: true,
                        onPressed: () {
                          Navigator.of(context).pop();
                          onKickServer!();
                        },
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final MemberCardData member;
  const _StatusRow({required this.member});

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;

    final (IconData icon, String label, Color color) = switch (member) {
      MemberCardData(voiceChannelName: final channel?) => (
        Icons.graphic_eq,
        strings.inVoiceStatus(channel),
        c.accentSoft,
      ),
      MemberCardData(online: true) => (
        Icons.circle,
        strings.onlineLabel,
        c.accent,
      ),
      MemberCardData(online: false) => (
        Icons.circle_outlined,
        strings.offlineLabel,
        c.textFaint,
      ),
      _ => (Icons.circle_outlined, strings.unknownStatus, c.textFaint),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: c.textBody),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (member.muted || member.deafened) ...[
          const SizedBox(height: 7),
          Row(
            children: [
              Icon(
                member.deafened ? Icons.headset_off : Icons.mic_off,
                size: 13,
                color: c.textFaint,
              ),
              const SizedBox(width: 9),
              Text(
                member.deafened ? strings.deafenedStatus : strings.mutedStatus,
                style: TextStyle(fontSize: 13, color: c.textMuted),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onPressed;

  const _CardAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    final color = danger ? c.mention : c.textBody;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: danger ? c.mention.withValues(alpha: 0.5) : c.border,
          ),
        ),
      ),
    );
  }
}

/// The global rect of the widget behind [context], which is what
/// [showMemberCard] anchors to. Null if it is not laid out (never, from a tap
/// handler, but the caller shouldn't have to assume that).
Rect? globalRectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
