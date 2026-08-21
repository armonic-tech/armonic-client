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
              session.dart (live session: auth, channels, messages, voice)
  voice/      voice_session.dart (RTCPeerConnection, renegotiable offers)
  screens/    app_shell (instance rail + selected instance), add_instance,
              onboarding (claim/login/invite), server
  widgets/    instance_rail.dart (the vertical rail of saved instances)
```

## Contributing

Issues and pull requests are welcome. Please run `flutter analyze` and `flutter test` before opening a PR.

## License

The Armonic client is licensed under the **GNU Affero General Public License v3.0** - see [LICENSE](LICENSE).
