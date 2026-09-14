import 'package:flutter/material.dart';

import '../theme/armonic_colors.dart';
import '../theme/armonic_theme.dart';

/// A miniature of the main window painted with [colors]: rail, channel
/// sidebar, a few chat messages and the member list, plus the ambient glow.
///
/// Laid out at a fixed design size and scaled to whatever width it is given,
/// so the same widget serves both the large preview and the preset cards.
/// Entirely fake content — it never touches session state.
class ThemePreview extends StatelessWidget {
  final ArmonicColors colors;

  const ThemePreview({super.key, required this.colors});

  static const _width = 360.0;
  static const _height = 216.0;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _width / _height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: _width,
            height: _height,
            child: Stack(
              children: [
                ColoredBox(
                  color: colors.background,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Rail(colors),
                      _Sidebar(colors),
                      Expanded(child: _Chat(colors)),
                      _Members(colors),
                    ],
                  ),
                ),
                if (colors.glowOpacity > 0)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0, 0.26, 0.58, 1],
                          colors: [
                            colors.accent.withValues(alpha: colors.glowOpacity),
                            colors.accent.withValues(
                              alpha: colors.glowOpacity * 0.42,
                            ),
                            colors.accent.withValues(alpha: 0),
                            Colors.black.withValues(
                              alpha: colors.glowOpacity * 0.8,
                            ),
                          ],
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _ui(
  Color color, {
  double size = 7,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: kUiFont,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: 1.2,
);

TextStyle _mono(Color color, {double size = 5.5}) => TextStyle(
  fontFamily: kMonoFont,
  fontSize: size,
  fontWeight: FontWeight.w500,
  letterSpacing: 1,
  color: color,
  height: 1.2,
);

class _Rail extends StatelessWidget {
  final ArmonicColors c;
  const _Rail(this.c);

  @override
  Widget build(BuildContext context) {
    Widget tile({bool selected = false, bool warn = false}) => Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: selected ? c.accentDeep : c.panelHigh,
            borderRadius: BorderRadius.circular(6),
            border: selected ? Border.all(color: c.accent, width: 1) : null,
          ),
        ),
        if (warn)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: c.warning,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
    return Container(
      width: 32,
      color: c.backgroundRail,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          tile(selected: true),
          const SizedBox(height: 6),
          tile(),
          const SizedBox(height: 6),
          tile(warn: true),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final ArmonicColors c;
  const _Sidebar(this.c);

  @override
  Widget build(BuildContext context) {
    Widget channel(String name, {bool selected = false, bool voice = false}) =>
        Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? c.selection : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Text(
                voice ? '♪' : '#',
                style: _ui(selected ? c.accentSoft : c.textFaint, size: 7.5),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: _ui(selected ? c.textPrimary : c.textSecondary),
                ),
              ),
            ],
          ),
        );
    return Container(
      width: 84,
      decoration: BoxDecoration(
        color: c.backgroundSidebar,
        border: Border(right: BorderSide(color: c.border, width: 0.5)),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Armonic',
            style: _ui(c.textPrimary, size: 8, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text('TEXTO', style: _mono(c.textFaint)),
          const SizedBox(height: 3),
          channel('general', selected: true),
          channel('proyectos'),
          channel('random'),
          const SizedBox(height: 6),
          Text('VOZ', style: _mono(c.textFaint)),
          const SizedBox(height: 3),
          channel('General', voice: true),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: c.border, width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'En llamada',
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: _ui(c.accentSoft, size: 6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chat extends StatelessWidget {
  final ArmonicColors c;
  const _Chat(this.c);

  @override
  Widget build(BuildContext context) {
    Widget avatar(String initial) => Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.accentDeep, shape: BoxShape.circle),
      child: Text(
        initial,
        style: _ui(c.accentPale, size: 6, weight: FontWeight.w600),
      ),
    );
    Widget message(
      String initial,
      String name,
      String time,
      Widget body, {
      bool hover = false,
    }) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: hover ? c.surfaceHover : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar(initial),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: _ui(c.textPrimary, weight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        time,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: _mono(c.textFaint, size: 5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                body,
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Text('#', style: _ui(c.accentSoft, size: 8)),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  'general',
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: _ui(c.textPrimary, size: 8, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Center(child: Text('HOY', style: _mono(c.textMuted))),
        const SizedBox(height: 3),
        message(
          'A',
          'Ana',
          '10:24',
          Text('¿Vieron el diseño nuevo?', style: _ui(c.textBody)),
        ),
        message(
          'M',
          'Martín',
          '10:26',
          Container(
            width: 56,
            height: 26,
            decoration: BoxDecoration(
              color: c.panelHigh,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        message(
          'L',
          'Lucía',
          '10:31',
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 3,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: c.mention,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '@Ana',
                  style: _ui(c.onMention, size: 6.5, weight: FontWeight.w600),
                ),
              ),
              Text('me encanta', style: _ui(c.textBody)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: c.chip,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('❤ 2', style: _ui(c.textSecondary, size: 6)),
              ),
            ],
          ),
          hover: true,
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 7),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: c.backgroundSidebar,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: c.border, width: 0.5),
                  ),
                  child: Text(
                    'Escribí un mensaje…',
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: _ui(c.textFaint, size: 6.5),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 28,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'Enviar',
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: _ui(c.onAccent, size: 6, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Members extends StatelessWidget {
  final ArmonicColors c;
  const _Members(this.c);

  @override
  Widget build(BuildContext context) {
    Widget member(String initial, String name, {bool owner = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Container(
            width: 11,
            height: 11,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.accentDeep,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: _ui(c.accentPale, size: 5, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              name,
              style: _ui(c.textSecondary, size: 6.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (owner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
              decoration: BoxDecoration(
                color: c.accentDeep,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'ADMIN',
                overflow: TextOverflow.clip,
                softWrap: false,
                style: _mono(c.accentPale, size: 4),
              ),
            ),
        ],
      ),
    );
    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: c.backgroundSidebar,
        border: Border(left: BorderSide(color: c.border, width: 0.5)),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EN LÍNEA — 3', style: _mono(c.textFaint)),
          const SizedBox(height: 5),
          member('A', 'Ana', owner: true),
          member('M', 'Martín'),
          member('L', 'Lucía'),
        ],
      ),
    );
  }
}
