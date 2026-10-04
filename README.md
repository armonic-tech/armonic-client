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
              settings_store.dart (client-side appearance, audio, privacy)
  mls/        End-to-end encryption: tree.dart (TreeKEM ratchet tree),
              group.dart (commits, welcomes, message AEAD), client.dart
              (device identity, key packages, sync with the server's
              delivery service), store.dart (keystore persistence)
  media/      image_pipeline.dart (sanitize/thumbnail before encrypting),
              attachment_crypto.dart (per-attachment keys)
  voice/      voice_session.dart (RTCPeerConnection, renegotiable offers)
  screens/    app_shell (instance rail + selected instance), add_instance,
              onboarding (claim/login/invite), server, settings
  theme/      armonic_colors.dart (palette tokens), armonic_theme.dart
              (Material mapping + ambient glow), theme_presets.dart
              (built-in palettes), theme_file_io/web.dart
  widgets/    instance_rail.dart (the vertical rail of saved instances),
              theme_preview.dart (the settings' miniature of the window),
              member_card.dart (the popover a member row opens),
              toast.dart (in-app notifications)
```

## Settings and theming

Open **the server name → Configuración** for the in-app settings. Everything there is client-side — it never reaches the instance, so two clients signed into the same account can look and sound completely different. It persists in the platform keystore, next to the saved instances.

- **Apariencia** — font scale and chat avatar size apply live. The palette is edited as a **draft**: a miniature of the window previews it, a row of built-in presets (`lib/theme/theme_presets.dart` — Armonic, Medianoche, Bosque, Brasa, Uva, Día) fills it in one tap, the glow slider and the per-token swatches (under *Personalizar colores*, hex field included) tweak it, and nothing reaches the app until **Aplicar**; **Descartar** drops the draft. A draft that matches a preset exactly is labelled with its name, anything else is *Personalizado*. Brightness is derived from the background color, so a light preset gets Material's light defaults for whatever the tokens don't cover.
- **Audio** — input (microphone) and output (speakers) device, and playback volume. Changes reach a call already in progress, not just the next one. Device routing is best-effort: some platforms do not implement output selection, in which case the choice is remembered but the OS default keeps playing.
- **Privacidad y datos** — *Descargar imágenes automáticamente*. On (the default), an image in the chat is fetched as soon as its message appears. Off, the tile is a download button showing the size, and nothing is fetched until it is tapped — for metered links, and so a picture from someone you do not know never renders unasked.

## End-to-end encryption

Messages and images on a server are encrypted between members with an MLS-style TreeKEM group (`lib/mls/`); the instance stores and relays ciphertext it cannot open. There is nothing to switch on: the first member online creates the group, and every device that logs in afterwards publishes key packages and is added by whichever member the server nominates. Until that happens the composer says *Esperando claves de cifrado…* rather than sending in the clear. Messages from before the group existed stay readable and carry an open padlock; a message from an epoch this device never had shows as locked.

Images are sanitized **on the sending device** (`lib/media/image_pipeline.dart`: magic-number sniff, header-first dimension and frame budget, decode, EXIF dropped by re-encoding from pixels, animated GIFs kept, thumbnail — animated too) and encrypted under a per-image key that travels inside the message. The recipient does not trust that: it checks the ciphertext digest, decrypts, and re-checks the header before rendering anything.

All key material lives in the platform keystore next to the instance list; every epoch secret since the device joined is kept so history stays readable after a restart. Wiping the app therefore loses every message this device could read. Voice is encrypted to the server, not end to end. The protocol and its limits are documented in the backend's `docs/ai/e2ee.md`.

For a palette an operator wants to ship pre-set (a branded build, a shared machine), [theme.example.json](theme.example.json) still works as the **seed**: copy it, edit any subset of the keys, and save it as one of

1. the path in the `ARMONIC_THEME` environment variable,
2. `theme.json` in the app's working directory (portable installs),
3. `~/.config/armonic/theme.json` (or `$XDG_CONFIG_HOME/armonic/theme.json`).

It decides the defaults a fresh install starts from; anything the user then changes in Settings wins over it. Missing or invalid keys silently keep their default, so a partial file (say, just `"accent"`) is fine. `glowOpacity` (0–1) controls the ambient corner glow; `0` turns it off. The web build always uses the built-in defaults as its seed — there is no filesystem to read from.

## Contributing

Issues and pull requests are welcome. Please run `flutter analyze` and `flutter test` before opening a PR.

## License

The Armonic client is licensed under the **GNU Affero General Public License v3.0** - see [LICENSE](LICENSE).
