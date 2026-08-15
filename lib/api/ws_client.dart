import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// What the session layer needs from the WS transport; ArmonicSocket is the
/// real implementation, tests provide fakes.
abstract interface class SignalingSocket {
  Stream<Map<String, dynamic>> get messages;
  bool get isClosed;
  void send(Map<String, dynamic> message);
  Future<void> close();
}

class ArmonicSocket implements SignalingSocket {
  final WebSocketChannel _channel;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  bool _closed = false;

  ArmonicSocket._(this._channel) {
    _channel.stream.listen(
      (data) {
        final decoded = jsonDecode(data as String);
        if (decoded is Map<String, dynamic>) {
          _messages.add(decoded);
        }
      },
      onError: (Object e) {
        if (!_closed) _messages.addError(e);
      },
      onDone: () {
        _closed = true;
        _messages.close();
      },
    );
  }

  static Future<ArmonicSocket> connect(String wsUrl) async {
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    await channel.ready;
    return ArmonicSocket._(channel);
  }

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  bool get isClosed => _closed;

  @override
  void send(Map<String, dynamic> message) {
    if (_closed) return;
    _channel.sink.add(jsonEncode(message));
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _channel.sink.close();
  }
}
