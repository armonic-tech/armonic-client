import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../state/attachment_cache.dart';
import '../util/text.dart';

/// An image served from the instance behind the Bearer JWT.
///
/// Bytes come from [AttachmentCache] rather than a URL because the endpoint is
/// membership-gated; a cached entry paints on the first frame with no spinner.
class AttachmentImage extends StatefulWidget {
  final AttachmentCache cache;
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  const AttachmentImage({
    super.key,
    required this.cache,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  Future<Uint8List>? _pending;
  Uint8List? _bytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.cache != widget.cache) {
      _bytes = null;
      _error = null;
      _start();
    }
  }

  void _start() {
    final ready = widget.cache.peek(widget.path);
    if (ready != null) {
      _bytes = ready;
      return;
    }
    final pending = widget.cache.load(widget.path);
    _pending = pending;
    pending.then((bytes) {
      // The tile may have been recycled onto another attachment meanwhile.
      if (!mounted || !identical(_pending, pending)) return;
      setState(() => _bytes = bytes);
    }).catchError((Object e) {
      if (!mounted || !identical(_pending, pending)) return;
      setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, _, _) => _Fallback(
          width: widget.width,
          height: widget.height,
          icon: Icons.broken_image_outlined,
          tooltip: strings.imageUnavailable,
        ),
      );
    }
    if (_error != null) {
      return _Fallback(
        width: widget.width,
        height: widget.height,
        icon: Icons.broken_image_outlined,
        tooltip: strings.imageUnavailable,
      );
    }
    return _Fallback(
      width: widget.width,
      height: widget.height,
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  final double? width;
  final double? height;
  final IconData? icon;
  final String? tooltip;
  final Widget? child;

  const _Fallback({
    this.width,
    this.height,
    this.icon,
    this.tooltip,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final box = Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: child ??
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
    );
    return tooltip == null ? box : Tooltip(message: tooltip!, child: box);
  }
}

/// A user's avatar, falling back to their initials when they have not set one.
class UserAvatar extends StatelessWidget {
  final AttachmentCache? cache;
  final String? avatarPath;
  final String label;
  final double radius;

  const UserAvatar({
    super.key,
    required this.cache,
    required this.avatarPath,
    required this.label,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final path = avatarPath;
    final initials = Text(
      initialsOf(label),
      style: TextStyle(fontSize: radius * 0.78),
    );
    if (path == null || cache == null) {
      return CircleAvatar(radius: radius, child: initials);
    }
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: AttachmentImage(
          cache: cache!,
          path: path,
          width: radius * 2,
          height: radius * 2,
        ),
      ),
    );
  }
}
