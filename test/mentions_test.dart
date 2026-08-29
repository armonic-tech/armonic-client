import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/util/mentions.dart';

void main() {
  group('mentionQueryAt', () {
    test('finds the token being typed at the caret', () {
      final m = mentionQueryAt('hola @bo', 8);
      expect(m, isNotNull);
      expect(m!.start, 5);
      expect(m.query, 'bo');
    });

    test('an @ on its own opens the picker with everything', () {
      final m = mentionQueryAt('@', 1);
      expect(m!.query, '');
      expect(m.start, 0);
    });

    test('the query is lowercased so matching is case-insensitive', () {
      expect(mentionQueryAt('@Bo', 3)!.query, 'bo');
    });

    test('a space ends the token', () {
      expect(mentionQueryAt('@bob ya', 7), isNull);
    });

    test('only counts at a word boundary, so emails are left alone', () {
      expect(mentionQueryAt('leo@casa', 8), isNull);
    });

    test('reads at the caret, not at the end of the line', () {
      // Caret sits right after "@bo", with more text to its right.
      expect(mentionQueryAt('@bob dijo algo', 3)!.query, 'bo');
    });

    test('plain text is not a mention', () {
      expect(mentionQueryAt('hola', 4), isNull);
      expect(mentionQueryAt('', 0), isNull);
    });
  });

  group('rankMentionCandidates', () {
    test('prefix matches come before substring matches', () {
      final ranked = rankMentionCandidates(['Robot', 'Bob', 'Abobo'], 'bo');
      expect(ranked, ['Bob', 'Robot', 'Abobo']);
    });

    test('an empty query keeps everyone, in roster order', () {
      expect(rankMentionCandidates(['Ana', 'Bob'], ''), ['Ana', 'Bob']);
    });

    test('no match yields nothing', () {
      expect(rankMentionCandidates(['Ana', 'Bob'], 'zz'), isEmpty);
    });
  });

  group('applyMention', () {
    test('replaces the token and leaves the caret past a trailing space', () {
      const text = 'hola @bo';
      final mention = mentionQueryAt(text, 8)!;
      final result = applyMention(text, mention, 'Bob', 8);

      expect(result.text, 'hola @Bob ');
      expect(result.caret, 10);
    });

    test('keeps whatever followed the caret', () {
      const text = '@bo dijo algo';
      final mention = mentionQueryAt(text, 3)!;
      final result = applyMention(text, mention, 'Bob', 3);

      expect(result.text, '@Bob  dijo algo');
      expect(result.caret, 5);
    });
  });

  group('findMentions', () {
    test('resolves a name against the roster', () {
      final found = findMentions('hola @Bob que tal', ['Bob', 'Ana']);
      expect(found, hasLength(1));
      expect(found.single.label, 'Bob');
      expect(found.single.start, 5);
      expect(found.single.end, 9);
    });

    test('matches names containing spaces', () {
      final found = findMentions('@Juan Perez vino', ['Juan Perez', 'Juan']);
      expect(found.single.label, 'Juan Perez');
      expect(found.single.end, 11);
    });

    test('prefers the longest name when one is a prefix of another', () {
      final found = findMentions('@Ana Maria', ['Ana', 'Ana Maria']);
      expect(found.single.label, 'Ana Maria');
    });

    test('does not light up inside a longer word', () {
      expect(findMentions('@Anabel', ['Ana']), isEmpty);
    });

    test('leaves an unknown @word alone', () {
      expect(findMentions('@nadie', ['Bob']), isEmpty);
    });

    test('needs a word boundary, so emails stay text', () {
      expect(findMentions('leo@Bob', ['Bob']), isEmpty);
    });

    test('trailing punctuation still ends the name', () {
      final found = findMentions('gracias @Bob!', ['Bob']);
      expect(found.single.label, 'Bob');
    });

    test('finds several in one message', () {
      final found = findMentions('@Ana y @Bob', ['Ana', 'Bob']);
      expect(found.map((m) => m.label), ['Ana', 'Bob']);
    });

    test('is case-insensitive but reports the roster casing', () {
      expect(findMentions('@bob', ['Bob']).single.label, 'Bob');
    });
  });

  group('mentionsLabel', () {
    test('true only when the message names that person', () {
      expect(mentionsLabel('hola @Bob', 'Bob'), isTrue);
      expect(mentionsLabel('hola @Ana', 'Bob'), isFalse);
      expect(mentionsLabel('hola Bob', 'Bob'), isFalse);
    });

    test('an empty label never matches', () {
      expect(mentionsLabel('hola @', ''), isFalse);
    });
  });
}
