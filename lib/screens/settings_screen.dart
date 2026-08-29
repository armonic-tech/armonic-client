import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/session_manager.dart';
import '../state/settings_store.dart';
import '../theme/armonic_colors.dart';
import '../theme/armonic_theme.dart';

/// Client-side settings: palette, sizes and audio devices.
///
/// A dialog rather than a route so it can be opened from the server menu
/// without unmounting the screen behind it (and the call panel with it).
Future<void> showSettingsDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const SettingsDialog());

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

enum _Section { appearance, audio }

class _SettingsDialogState extends State<SettingsDialog> {
  _Section _section = _Section.appearance;

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    final narrow = MediaQuery.sizeOf(context).width < 720;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 620),
        child: Row(
          children: [
            // The left nav collapses on narrow windows: two sections do not
            // justify eating half a phone's width.
            if (!narrow)
              Container(
                width: 220,
                decoration: BoxDecoration(
                  color: c.backgroundRail,
                  border: Border(right: BorderSide(color: c.border)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      child: Text(
                        strings.settingsTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    for (final section in _Section.values)
                      _NavItem(
                        label: _labelOf(section),
                        selected: _section == section,
                        onTap: () => setState(() => _section = section),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  if (narrow)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                      child: Row(
                        children: [
                          for (final section in _Section.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _NavItem(
                                label: _labelOf(section),
                                selected: _section == section,
                                onTap: () => setState(() => _section = section),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: switch (_section) {
                      _Section.appearance => const _AppearancePane(),
                      _Section.audio => const _AudioPane(),
                    },
                  ),
                  Divider(height: 1, color: c.border),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: () =>
                              context.read<SettingsStore>().reset(),
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: Text(strings.resetSettings),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(strings.close),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _labelOf(_Section section) => switch (section) {
    _Section.appearance => strings.appearanceSection,
    _Section.audio => strings.audioSection,
  };
}

class _NavItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    return Material(
      color: selected ? c.selection : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? c.textPrimary : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A mono, letterspaced eyebrow over each block — the canvas's section label.
class _PaneSection extends StatelessWidget {
  final String label;
  final Widget child;

  const _PaneSection({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = context.armonic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: t.mono(size: 9, letterSpacing: 1.8, color: t.colors.accent),
        ),
        const SizedBox(height: 12),
        child,
        const SizedBox(height: 26),
      ],
    );
  }
}

class _AppearancePane extends StatelessWidget {
  const _AppearancePane();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SettingsStore>();
    final settings = store.settings;

    return ListView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 8),
      children: [
        _PaneSection(
          label: strings.fontSizeLabel,
          child: _Slider(
            value: settings.fontScale,
            min: ArmonicSettings.minFontScale,
            max: ArmonicSettings.maxFontScale,
            format: (v) => '${(v * 100).round()}%',
            onChanged: store.setFontScale,
          ),
        ),
        _PaneSection(
          label: strings.chatAvatarSizeLabel,
          child: _Slider(
            value: settings.chatAvatarRadius,
            min: ArmonicSettings.minAvatarRadius,
            max: ArmonicSettings.maxAvatarRadius,
            format: (v) => '${(v * 2).round()} px',
            onChanged: store.setChatAvatarRadius,
          ),
        ),
        _PaneSection(
          label: strings.glowLabel,
          child: _Slider(
            value: settings.colors.glowOpacity,
            min: 0,
            max: 0.6,
            format: (v) => '${(v * 100).round()}%',
            onChanged: store.setGlow,
          ),
        ),
        _PaneSection(
          label: strings.colorsLabel,
          child: Column(
            children: [
              for (final entry in settings.colors.tokens.entries)
                _ColorRow(
                  token: entry.key,
                  color: entry.value,
                  onPick: (color) => store.setColor(entry.key, color),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _Slider({
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.armonic;
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            format(value),
            textAlign: TextAlign.right,
            style: t.mono(size: 12, color: t.colors.textBody),
          ),
        ),
      ],
    );
  }
}

/// One editable palette entry: a swatch that opens a small picker, plus the
/// hex the user can type directly (which is also what `theme.json` takes, so
/// what is seen here can be pasted into a file and shared).
class _ColorRow extends StatelessWidget {
  final String token;
  final Color color;
  final ValueChanged<Color> onPick;

  const _ColorRow({
    required this.token,
    required this.color,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.armonic;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              token,
              style: TextStyle(fontSize: 13, color: t.colors.textBody),
            ),
          ),
          Text(
            _hexOf(color),
            style: t.mono(size: 11, color: t.colors.textFaint),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () async {
              final picked = await showDialog<Color>(
                context: context,
                builder: (_) => _ColorPickerDialog(initial: color),
              );
              if (picked != null) onPick(picked);
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 34,
              height: 26,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.colors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _hexOf(Color c) {
  int channel(double v) => (v * 255).round().clamp(0, 255);
  final rgb = [
    c.r,
    c.g,
    c.b,
  ].map((v) => channel(v).toRadixString(16).padLeft(2, '0')).join();
  return '#$rgb'.toUpperCase();
}

/// A palette of ready-made swatches plus a hex field.
///
/// Deliberately not a full HSV wheel: no color-picker package is a dependency
/// here, and hex covers everything the swatches do not — it is also the format
/// `theme.json` already speaks.
class _ColorPickerDialog extends StatefulWidget {
  final Color initial;

  const _ColorPickerDialog({required this.initial});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  static const _swatches = [
    Color(0xFF4C86F6),
    Color(0xFF8AB4FF),
    Color(0xFF24406F),
    Color(0xFF10B981),
    Color(0xFF34D399),
    Color(0xFFF2B04A),
    Color(0xFFFF5A8A),
    Color(0xFFE05252),
    Color(0xFFA855F7),
    Color(0xFF0B0D1A),
    Color(0xFF11142A),
    Color(0xFF182347),
    Color(0xFF6C7596),
    Color(0xFFCCD3E8),
    Color(0xFFFFFFFF),
  ];

  late final TextEditingController _hex = TextEditingController(
    text: _hexOf(widget.initial),
  );
  late Color _color = widget.initial;
  String? _error;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _onHexChanged(String value) {
    final parsed = ArmonicColors.parseHex(value);
    setState(() {
      _error = parsed == null ? strings.invalidColor : null;
      if (parsed != null) _color = parsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(strings.colorsLabel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final swatch in _swatches)
                InkWell(
                  onTap: () {
                    setState(() {
                      _color = swatch;
                      _error = null;
                      _hex.text = _hexOf(swatch);
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: swatch,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: swatch == _color
                            ? context.armonic.colors.accentPale
                            : context.armonic.colors.border,
                        width: swatch == _color ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hex,
            decoration: InputDecoration(
              labelText: strings.colorHexLabel,
              errorText: _error,
            ),
            onChanged: _onHexChanged,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                strings.previewLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: context.armonic.colors.border),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _error != null
              ? null
              : () => Navigator.of(context).pop(_color),
          child: Text(strings.create),
        ),
      ],
    );
  }
}

class _AudioPane extends StatefulWidget {
  const _AudioPane();

  @override
  State<_AudioPane> createState() => _AudioPaneState();
}

class _AudioPaneState extends State<_AudioPane> {
  List<MediaDeviceInfo>? _inputs;
  List<MediaDeviceInfo>? _outputs;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _enumerate();
  }

  /// Device labels are only filled in once microphone permission has been
  /// granted; before that the browser/OS returns blank names, which is why an
  /// unnamed device falls back to a truncated id rather than an empty row.
  Future<void> _enumerate() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      if (!mounted) return;
      setState(() {
        _inputs = devices.where((d) => d.kind == 'audioinput').toList();
        _outputs = devices.where((d) => d.kind == 'audiooutput').toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  /// Settings must reach a call that is already running, not just the next one.
  void _apply(AudioPrefs prefs) {
    context.read<SettingsStore>().setAudio(prefs);
    context.read<SessionManager>().applyAudio(prefs);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SettingsStore>();
    final audio = store.settings.audio;

    return ListView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 8),
      children: [
        if (_failed)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              strings.audioDeviceUnavailable,
              style: TextStyle(color: context.armonic.colors.mention),
            ),
          ),
        _PaneSection(
          label: strings.inputDeviceLabel,
          child: _DeviceDropdown(
            devices: _inputs,
            selected: audio.inputDeviceId,
            onChanged: (id) => _apply(audio.copyWith(inputDeviceId: id)),
          ),
        ),
        _PaneSection(
          label: strings.outputDeviceLabel,
          child: _DeviceDropdown(
            devices: _outputs,
            selected: audio.outputDeviceId,
            onChanged: (id) => _apply(audio.copyWith(outputDeviceId: id)),
          ),
        ),
        _PaneSection(
          label: strings.volumeLabel,
          child: _Slider(
            value: audio.volume,
            min: 0,
            max: 1,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) => _apply(audio.copyWith(volume: v)),
          ),
        ),
      ],
    );
  }
}

class _DeviceDropdown extends StatelessWidget {
  final List<MediaDeviceInfo>? devices;
  final String selected;
  final ValueChanged<String> onChanged;

  const _DeviceDropdown({
    required this.devices,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final list = devices;
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    // A remembered device that is no longer plugged in must not leave the
    // dropdown on a value it cannot show: fall back to "system default".
    final ids = {'', for (final d in list) d.deviceId};
    return DropdownButtonFormField<String>(
      initialValue: ids.contains(selected) ? selected : '',
      isExpanded: true,
      items: [
        DropdownMenuItem(value: '', child: Text(strings.systemDefaultDevice)),
        for (final device in list)
          DropdownMenuItem(
            value: device.deviceId,
            child: Text(
              device.label.isNotEmpty
                  ? device.label
                  : device.deviceId.characters.take(12).toString(),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) => onChanged(value ?? ''),
    );
  }
}
