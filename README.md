# armonic_client

Cliente Flutter multi-instancia para [Armonic](../armonic) — un backend tipo
Discord self-hosted (texto por WebSocket, voz por WebRTC).

Al estilo de un cliente Matrix/Element con varios homeservers: la app maneja
**N instancias de Armonic** (cada una con su base URL y su JWT propio en
almacenamiento seguro), no N guilds dentro de una instancia.

## Flujos implementados

- **Home**: lista de instancias conectadas (nombre/descripción/miembros vía
  `GET /info`) + agregar por URL.
- **Onboarding** según `claimed` de `/info`:
  - sin dueño → flujo de claim (`/claim/password` → `/claim/register`, con
    vuelta al paso de contraseña si el ticket vence);
  - reclamada → login (`/auth/login`). No hay pantalla de registro genérica —
    el backend no tiene signup público.
- **Invitaciones**: pegar un link `{baseUrl}?invite=<token>` en "Agregar
  instancia" valida con `GET /invite/status` y da de alta vía
  `POST /invite/signup` (410 = "esta invitación ya no es válida").
- **Vista de servidor**: WS a `/ws` (primer mensaje `auth`, espera `auth-ok`),
  canales de texto con historial (invertido: el backend manda
  más-reciente-primero) y push en vivo (`text-message` llega para todos los
  canales del server — se filtra/cachea por canal del lado del cliente; el
  emisor no recibe eco, se agrega optimista).
- **Voz** (`flutter_webrtc`): `join-voice` → el **backend** manda el `offer`;
  el cliente responde `answer` con su track de audio ya agregado e intercambia
  `candidate`s. Los `offer` se repiten durante toda la sesión (el SFU
  renegocia cuando alguien entra/sale) y siempre se responden de nuevo.
- **Moderación mínima**: `create-invite` (solo dueño) desde el sidebar.

Nota: el backend no tiene mensaje "leave-voice" — salir de voz cierra la
peer connection localmente; el server lo detecta al fallar la lectura RTP.

## Correr

```bash
flutter pub get
flutter run          # o: flutter run -d chrome / -d linux
```

## Smoke test contra un backend vivo

`tool/smoke.dart` ejercita las capas HTTP+WS del cliente (sin UI) contra una
instancia real **con DB fresca** (la reclama):

```bash
# en ../armonic, con un Postgres vacío corriendo:
PORT=8090 go run .

dart run tool/smoke.dart http://localhost:8090 change-me
```

Cubre claim, login, auth por WS, servers/channels, invitación de un solo uso,
broadcast de texto y validación de largo máximo. No cubre la voz (necesita
`flutter_webrtc` en un dispositivo real).

## Estructura

```
lib/
  api/        http_api.dart (REST), ws_client.dart (framing JSON del WS)
  models/     shapes espejados de los json tags del backend
  state/      instance_store.dart (instancias+JWT persistidos),
              session.dart (sesión viva: auth, canales, mensajes, voz)
  voice/      voice_session.dart (RTCPeerConnection, offers renegociables)
  screens/    home, add_instance, onboarding (claim/login/invite), server
```
