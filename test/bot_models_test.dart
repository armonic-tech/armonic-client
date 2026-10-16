import 'package:armonic_client/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isBot is read from the roster and voice presence', () {
    expect(Member.fromJson({'id': 'b', 'isBot': true}).isBot, isTrue);
    expect(VoiceMember.fromJson({'id': 'b', 'isBot': true}).isBot, isTrue);
  });

  test('an older backend that sends no isBot means not a bot', () {
    expect(Member.fromJson({'id': 'u'}).isBot, isFalse);
    final v = VoiceMember.fromJson({'id': 'u'});
    expect(v.isBot, isFalse);
  });

  test('copyWith keeps the bot flag', () {
    final v = VoiceMember.fromJson({'id': 'b', 'isBot': true});
    expect(v.copyWith(muted: true).isBot, isTrue);
  });
}
