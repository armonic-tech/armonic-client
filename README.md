<div align="center">

# Armonic Client

**The cross-platform Flutter app for Armonic - a self-hosted, real-time messaging platform with text and voice channels.**

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![WebRTC](https://img.shields.io/badge/WebRTC-flutter__webrtc-333333?logo=webrtc&logoColor=white)](https://pub.dev/packages/flutter_webrtc)
[![Platforms](https://img.shields.io/badge/Platforms-Android_-_Linux_-_Web-success)](#)

**Frontend** - [Backend →](https://github.com/armonic-tech/armonic-backend)

</div>

---

## What is Armonic?

Armonic is an open-source, self-hostable alternative to Discord-style community servers - text channels over WebSocket and voice channels over WebRTC, running entirely on infrastructure you control.

This repository is the **client**: a single Flutter app that connects to any Armonic instance from Android, Linux, or the web. The **[Go backend lives here](https://github.com/armonic-tech/armonic-backend)**.

## Features

- 🌐 **Multi-instance** - save and switch between multiple Armonic servers, each with its own persisted session.
- 💬 **Text channels** in real time over WebSocket, with message history.
- 🎙️ **Voice channels** over WebRTC, with renegotiable peer connections.
- 🔐 **Full onboarding flow** - claim a fresh instance, log in, or join through an invite link.
- 🗝️ **Secure storage** - JWTs kept in the platform keystore via `flutter_secure_storage`.

## Tech stack

| Concern | Technology |
| --- | --- |
| Framework | Flutter / Dart |
| State management | `provider` |
| REST | `http` |
| Real-time | `web_socket_channel` |
| Voice | `flutter_webrtc` |
| Secure storage | `flutter_secure_storage` |

## Getting started

You'll need a running [Armonic backend](https://github.com/armonic-tech/armonic-backend) to connect to.

```bash
flutter pub get
flutter run              # or: flutter run -d chrome / -d linux / -d <android-device>
```

On first launch, add your instance by its base URL, then claim it (with the instance password) or redeem an invite link to create your account.

## Project structure

```
lib/
  api/        http_api.dart (REST), ws_client.dart (JSON framing over the WS)
  models/     Data shapes mirroring the backend's JSON tags
  state/      instance_store.dart (persisted instances + JWTs),
              session.dart (live session: auth, channels, messages, voice),
              settings_store.dart (client-side appearance + audio prefs)
  voice/      voice_session.dart (RTCPeerConnection, renegotiable offers)
  screens/    app_shell (instance rail + selected instance), add_instance,
              onboarding (claim/login/invite), server, settings
  theme/      armonic_colors.dart (palette tokens), armonic_theme.dart
              (Material mapping + ambient glow), theme_file_io/web.dart
  widgets/    instance_rail.dart (the vertical rail of saved instances),
              member_card.dart (the popover a member row opens),
              toast.dart (in-app notifications)
```

## Settings and theming

Open **the server name → Configuración** for the in-app settings. Everything there is client-side — it never reaches the instance, so two clients signed into the same account can look and sound completely different. It persists in the platform keystore, next to the saved instances.

- **Apariencia** — font scale, chat avatar size, ambient glow strength, and every color token as a swatch (preset palette + hex field).
- **Audio** — input (microphone) and output (speakers) device, and playback volume. Changes reach a call already in progress, not just the next one. Device routing is best-effort: some platforms do not implement output selection, in which case the choice is remembered but the OS default keeps playing.

For a palette an operator wants to ship pre-set (a branded build, a shared machine), [theme.example.json](theme.example.json) still works as the **seed**: copy it, edit any subset of the keys, and save it as one of

1. the path in the `ARMONIC_THEME` environment variable,
2. `theme.json` in the app's working directory (portable installs),
3. `~/.config/armonic/theme.json` (or `$XDG_CONFIG_HOME/armonic/theme.json`).

It decides the defaults a fresh install starts from; anything the user then changes in Settings wins over it. Missing or invalid keys silently keep their default, so a partial file (say, just `"accent"`) is fine. `glowOpacity` (0–1) controls the ambient corner glow; `0` turns it off. The web build always uses the built-in defaults as its seed — there is no filesystem to read from.

## Contributing

Issues and pull requests are welcome. Please run `flutter analyze` and `flutter test` before opening a PR.

## License

The Armonic client is licensed under the **GNU Affero General Public License v3.0** - see [LICENSE](LICENSE).
