import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/instance_store.dart';
import '../state/session.dart';
import '../state/session_manager.dart';
import '../theme/armonic_theme.dart';
import '../util/pick_image.dart';
import '../util/text.dart';
import '../widgets/attachment_image.dart';
import '../widgets/toast.dart';
import 'server_screen.dart';
import 'settings_screen.dart';

/// The phone's profile page: who you are on this instance, the instance
/// itself, and the doors out of it (settings, invites, sign out).
///
/// A route rather than the wide layout's [ProfileDialog]: on a phone the
/// same content wants the whole screen, and the actions grouped under it
/// have nowhere else to live once the server-name menu is gone.
class ProfileScreen extends StatefulWidget {
  final InstanceSession session;
  final ImagePicker pickImage;

  const ProfileScreen({
    super.key,
    required this.session,
    this.pickImage = pickImageFile,
  });

  static Future<void> open(BuildContext context, InstanceSession session) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileScreen(session: session)),
      );

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;

  InstanceSession get _session => widget.session;

  Future<void> _changeAvatar() async {
    final picked = await widget.pickImage();
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _session.setAvatar(picked.bytes, picked.name);
      if (!mounted) return;
      showToast(context, strings.avatarUpdated);
    } on UploadFailure catch (e) {
      if (!mounted) return;
      showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.logOutConfirmTitle),
        content: Text(strings.logOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.logOut),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final url = _session.instance.baseUrl;
    final sessions = context.read<SessionManager>();
    final store = context.read<InstanceStore>();
    Navigator.of(context).pop();
    // Same order as removing an instance from the rail: the live session goes
    // first, then the credential — the shell swaps to the sign-in pane once
    // the store notifies.
    sessions.release(url);
    await store.clearToken(url);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final t = context.armonic;
        final c = t.colors;
        final session = _session;
        final instance = session.instance;
        final name = session.displayName?.isNotEmpty == true
            ? session.displayName!
            : strings.you;
        final connected = session.status == SessionStatus.connected;
        final instanceLabel = instance.name.isNotEmpty
            ? instance.name
            : instance.baseUrl;

        return Scaffold(
          appBar: AppBar(title: Text(strings.profileTitle)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      UserAvatar(
                        cache: session.attachments,
                        avatarPath: session.myAvatarPath,
                        label: name,
                        radius: 36,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: connected ? onlineGreen : c.textFaint,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.background, width: 3),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: c.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            '@$name',
                            if (session.isOwner) strings.ownerBadge,
                          ].join(' · '),
                          style: t.mono(
                            size: 12,
                            weight: FontWeight.w400,
                            color: c.accentSoft,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.accentSoft,
                      side: BorderSide(color: c.accent.withValues(alpha: 0.5)),
                      shape: const StadiumBorder(),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    onPressed: _busy ? null : _changeAvatar,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(strings.edit),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                strings.instanceSection,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 10),
              _Card(
                children: [
                  _InstanceRow(
                    label: instanceLabel,
                    host: hostOf(instance.baseUrl),
                    connected: connected,
                  ),
                  _ActionRow(
                    icon: Icons.tune,
                    label: strings.settingsTitle,
                    onTap: () => showSettingsDialog(context),
                  ),
                  if (session.isOwner)
                    _ActionRow(
                      icon: Icons.person_add_outlined,
                      label: strings.createInvite,
                      onTap: () => showCreateInviteDialog(context, session),
                    ),
                  _ActionRow(
                    icon: Icons.link,
                    label: strings.joinWithInvite,
                    onTap: () => showJoinWithInviteDialog(context, session),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.mention,
                  side: BorderSide(color: c.mention.withValues(alpha: 0.5)),
                  minimumSize: const Size(0, 52),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onPressed: _logOut,
                child: Text(strings.logOut),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  strings.appTitle.toLowerCase(),
                  style: t.mono(size: 11, weight: FontWeight.w400),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The rounded group the instance rows sit in, hairlines between them.
class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.panel.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) Divider(height: 1, color: c.border),
            child,
          ],
        ],
      ),
    );
  }
}

class _InstanceRow extends StatelessWidget {
  final String label;
  final String host;
  final bool connected;

  const _InstanceRow({
    required this.label,
    required this.host,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.armonic;
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.accentDeep,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              initialsOf(label),
              style: t.mono(
                size: 13,
                weight: FontWeight.w600,
                color: c.accentPale,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  host,
                  style: t.mono(size: 11.5, weight: FontWeight.w400),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (connected ? onlineGreen : c.mention).withValues(
                alpha: 0.16,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              connected ? strings.statusOk : strings.offline,
              style: t.mono(
                size: 10,
                weight: FontWeight.w600,
                letterSpacing: 1,
                color: connected ? onlineGreen : c.mention,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 16, color: c.textBody),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: c.textFaint),
          ],
        ),
      ),
    );
  }
}
