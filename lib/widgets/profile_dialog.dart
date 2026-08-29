import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../state/session.dart';
import '../util/pick_image.dart';
import 'attachment_image.dart';
import 'toast.dart';

/// Lets the signed-in user look at and replace their avatar.
///
/// The picture goes through the same upload pipeline as a chat image, so it is
/// re-encoded and stripped of metadata before anyone else can fetch it.
Future<void> showProfileDialog(
  BuildContext context,
  InstanceSession session, {
  ImagePicker pickImage = pickImageFile,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ProfileDialog(session: session, pickImage: pickImage),
  );
}

class ProfileDialog extends StatefulWidget {
  final InstanceSession session;
  final ImagePicker pickImage;

  const ProfileDialog({
    super.key,
    required this.session,
    this.pickImage = pickImageFile,
  });

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _change() async {
    final picked = await widget.pickImage();
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.setAvatar(picked.bytes, picked.name);
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, strings.avatarUpdated);
    } on UploadFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final name = session.displayName?.isNotEmpty == true
        ? session.displayName!
        : strings.you;

    return AlertDialog(
      title: Text(strings.profileTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            cache: session.attachments,
            avatarPath: session.myAvatarPath,
            label: name,
            radius: 40,
          ),
          const SizedBox(height: 12),
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.closeImage),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _change,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_camera_outlined, size: 18),
          label: Text(strings.changeAvatar),
        ),
      ],
    );
  }
}
