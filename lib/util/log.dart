import 'package:flutter/foundation.dart';

/// One line per event, `<time> <level> [<tag>] <message>`, so a console or
/// logcat dump reads the same on every platform. Debug lines are dropped in
/// release builds; everything else is kept, because a release build is
/// exactly where a user hits the bug nobody reproduced.
enum LogLevel { debug, info, warn, error }

abstract final class Log {
  static LogLevel minLevel = kReleaseMode ? LogLevel.info : LogLevel.debug;

  static void d(String tag, String message) =>
      _write(LogLevel.debug, tag, message);

  static void i(String tag, String message) =>
      _write(LogLevel.info, tag, message);

  static void w(
    String tag,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) => _write(LogLevel.warn, tag, message, error, stack);

  static void e(
    String tag,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) => _write(LogLevel.error, tag, message, error, stack);

  static const _labels = {
    LogLevel.debug: 'D',
    LogLevel.info: 'I',
    LogLevel.warn: 'W',
    LogLevel.error: 'E',
  };

  static void _write(
    LogLevel level,
    String tag,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    if (level.index < minLevel.index) return;
    final buf = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write(' ')
      ..write(_labels[level])
      ..write(' [')
      ..write(tag)
      ..write('] ')
      ..write(message);
    if (error != null) buf.write(': $error');
    if (stack != null) buf.write('\n$stack');
    debugPrint(buf.toString());
  }
}
