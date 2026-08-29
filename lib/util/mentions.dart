/// An `@…` being typed at the caret: where it starts and what has been typed
/// after the `@`.
class MentionQuery {
  /// Index of the `@` itself.
  final int start;

  /// What follows it, lowercased — the empty string right after typing `@`.
  final String query;

  const MentionQuery({required this.start, required this.query});

  @override
  bool operator ==(Object other) =>
      other is MentionQuery && other.start == start && other.query == query;

  @override
  int get hashCode => Object.hash(start, query);
}

/// The mention being typed at [caret], or null when the caret is not inside
/// one.
///
/// The `@` only counts at a word boundary, so an email address or a `a@b`
/// never opens the picker. A space ends the token: mentions are matched
/// against a single display name, and letting the query run past a space
/// would make every following word widen the search instead of filtering it.
MentionQuery? mentionQueryAt(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;
  for (var i = caret - 1; i >= 0; i--) {
    final char = text[i];
    if (char == '@') {
      final before = i == 0 ? ' ' : text[i - 1];
      if (before != ' ' && before != '\n' && before != '\t') return null;
      return MentionQuery(
        start: i,
        query: text.substring(i + 1, caret).toLowerCase(),
      );
    }
    if (char == ' ' || char == '\n' || char == '\t') return null;
  }
  return null;
}

/// [labels] that match [query], prefix matches first.
///
/// Ranked rather than filtered to prefix only: typing the middle of a name is
/// a normal way to reach it, but someone typing the start expects that person
/// first — and the first entry is what Enter picks.
List<String> rankMentionCandidates(Iterable<String> labels, String query) {
  if (query.isEmpty) return labels.toList();
  final prefix = <String>[];
  final contains = <String>[];
  for (final label in labels) {
    final lower = label.toLowerCase();
    if (lower.startsWith(query)) {
      prefix.add(label);
    } else if (lower.contains(query)) {
      contains.add(label);
    }
  }
  return [...prefix, ...contains];
}

/// The text and caret after completing the mention at [mention] with [label].
///
/// A trailing space is added so the next word is not swallowed into the
/// mention the moment the user keeps typing.
({String text, int caret}) applyMention(
  String text,
  MentionQuery mention,
  String label,
  int caret,
) {
  final replacement = '@$label ';
  final updated = text.replaceRange(mention.start, caret, replacement);
  return (text: updated, caret: mention.start + replacement.length);
}

/// One `@name` found inside a message, matched against real display names.
class FoundMention {
  /// Index of the `@`.
  final int start;

  /// Index just past the name.
  final int end;

  /// The roster label it resolved to, in the roster's own casing.
  final String label;

  const FoundMention({
    required this.start,
    required this.end,
    required this.label,
  });
}

/// Every `@name` in [text] that resolves to one of [labels].
///
/// Matched against the roster rather than by tokenizing on whitespace,
/// because display names may contain spaces ("Juan Perez") — the composer
/// inserts those verbatim, so a whitespace-delimited token would only ever
/// see half of one. Longest label first, so "@Ana Maria" is not swallowed by
/// an "Ana" who also exists.
///
/// An unknown `@word` is left alone: it is ordinary text, and painting it as
/// a mention would promise a link to a person who does not exist.
List<FoundMention> findMentions(String text, Iterable<String> labels) {
  final sorted = labels.where((l) => l.isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final lower = text.toLowerCase();
  final found = <FoundMention>[];

  for (var i = 0; i < text.length; i++) {
    if (text[i] != '@') continue;
    if (i > 0 && !_isBoundary(text[i - 1])) continue;
    for (final label in sorted) {
      final end = i + 1 + label.length;
      if (end > text.length) continue;
      if (lower.substring(i + 1, end) != label.toLowerCase()) continue;
      // The name has to end where the word ends, or "@Ana" would light up
      // inside "@Anabel".
      if (end < text.length && !_isBoundary(text[end])) continue;
      found.add(FoundMention(start: i, end: end, label: label));
      i = end - 1;
      break;
    }
  }
  return found;
}

/// Whether [text] mentions [label] — what decides if a message is highlighted
/// for the reader.
bool mentionsLabel(String text, String label) =>
    label.isNotEmpty && findMentions(text, [label]).isNotEmpty;

/// A character that may sit next to a mention without being part of the name:
/// whitespace and the punctuation a sentence normally ends on.
bool _isBoundary(String char) =>
    !RegExp(r'[\w@]', unicode: true).hasMatch(char);
