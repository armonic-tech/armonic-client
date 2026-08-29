import 'package:flutter/material.dart';

import '../theme/armonic_theme.dart';

/// In-app notifications, replacing [SnackBar] everywhere.
///
/// Differences are deliberate: it drops in from the **top** (the bottom is
/// where the composer lives), it is quicker (~2s total instead of the
/// snackbar's 4), the entry/exit are animated as one slide+fade, and it is
/// color-coded — pink for errors, the accent panel for confirmations — using
/// theme tokens so `theme.json` recolors it too. Purely informational, so it
/// never intercepts pointer events.
void showToast(BuildContext context, String message, {bool error = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _current?.dismiss();
  final handle = _ToastHandle();
  handle.entry = OverlayEntry(
    builder: (_) => _Toast(message: message, error: error, handle: handle),
  );
  _current = handle;
  overlay.insert(handle.entry);
}

_ToastHandle? _current;

/// Guards [OverlayEntry.remove] so the entry is removed exactly once, whether
/// the animation finished, a newer toast replaced it, or the tree tore the
/// overlay down first (widget tests).
class _ToastHandle {
  late final OverlayEntry entry;
  bool _removed = false;

  void dismiss() {
    if (_removed) return;
    _removed = true;
    entry.remove();
  }

  /// The overlay died with the entry still in it; nothing left to remove.
  void expire() => _removed = true;
}

class _Toast extends StatefulWidget {
  final String message;
  final bool error;
  final _ToastHandle handle;

  const _Toast({
    required this.message,
    required this.error,
    required this.handle,
  });

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  // One controller drives the whole lifecycle — slide in, hold, slide out —
  // so there is no dart:async timer to outlive a widget test.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  late final Animation<double> _visible = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 9,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 75),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeInCubic)),
      weight: 16,
    ),
  ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.handle.dismiss();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    widget.handle.expire();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    final background = widget.error ? c.mention : c.chip;
    final foreground = widget.error ? c.onMention : c.accentPale;
    final border = widget.error
        ? Colors.transparent
        : c.accent.withValues(alpha: 0.4);

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 16,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _visible,
          builder: (context, child) => Opacity(
            opacity: _visible.value,
            child: Transform.translate(
              offset: Offset(0, -28 * (1 - _visible.value)),
              child: child,
            ),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.error
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: 16,
                      color: foreground,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
