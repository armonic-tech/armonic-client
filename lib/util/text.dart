String initialsOf(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return '?';
  final end = trimmed.length >= 2 ? 2 : 1;
  return trimmed.substring(0, end).toUpperCase();
}
