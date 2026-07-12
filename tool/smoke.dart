// End-to-end smoke test of the client's protocol code (HTTP + WS layers,
// no Flutter/UI) against a LIVE Armonic backend. Run it against a throwaway
// instance with a fresh DB — it claims the instance:
//
//   dart run tool/smoke.dart http://localhost:8090 change-me
//
// Exercises: /info, claim flow, /auth/login, WS auth handshake, get-servers,
// get-channels, get-messages (history order), text-message broadcast to a
// second account created via create-invite + /invite/signup, and single-use
// invite enforcement (410 on reuse). Voice/WebRTC is NOT covered (needs
// flutter_webrtc on a real device).
import 'dart:async';
import 'dart:io';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/api/ws_client.dart';

int _checks = 0;

void check(bool cond, String what) {
  _checks++;
  if (cond) {
    stdout.writeln('  ok: $what');
  } else {
    stderr.writeln('  FAIL: $what');
    exit(1);
  }
}

Future<Map<String, dynamic>> expectMessage(
    StreamIterator<Map<String, dynamic>> it, String type) async {
  while (await it.moveNext().timeout(const Duration(seconds: 5))) {
    if (it.current['type'] == type) return it.current;
    stdout.writeln('  (skipping ${it.current['type']})');
  }
  throw StateError('socket closed while waiting for "$type"');
}

Future<void> main(List<String> args) async {
  final baseUrl = normalizeBaseUrl(args.isNotEmpty ? args[0] : 'http://localhost:8090');
  final claimPassword = args.length > 1 ? args[1] : 'change-me';
  final suffix = DateTime.now().millisecondsSinceEpoch;
  final api = ArmonicHttpApi(baseUrl);

  stdout.writeln('1. GET /info');
  var info = await api.info();
  check(info.name.isNotEmpty || info.host.isNotEmpty, 'info responds');
  check(!info.claimed, 'instance starts unclaimed (needs a fresh DB)');

  stdout.writeln('2. Claim flow');
  try {
    await api.claimPassword('wrong-password');
    check(false, 'bad claim password rejected');
  } on ApiException catch (e) {
    check(e.statusCode == 401, 'bad claim password -> 401');
  }
  final ticket = await api.claimPassword(claimPassword);
  check(ticket.ticket.isNotEmpty, 'claim password -> ticket');
  final adminToken =
      await api.claimRegister(ticket.ticket, 'admin$suffix', 'password123');
  check(adminToken.isNotEmpty, 'claim register -> admin JWT');
  info = await api.info();
  check(info.claimed, '/info now reports claimed');

  stdout.writeln('3. Login');
  final loginToken = await api.login('admin$suffix', 'password123');
  check(loginToken.isNotEmpty, 'login with admin credentials');
  try {
    await api.login('admin$suffix', 'not-the-password');
    check(false, 'bad login rejected');
  } on ApiException catch (e) {
    check(e.statusCode == 401, 'bad login -> 401');
  }

  stdout.writeln('4. WS auth + servers + channels');
  final adminWs = await ArmonicSocket.connect(wsUrlFor(baseUrl));
  final adminMsgs = StreamIterator(adminWs.messages);
  adminWs.send({'type': 'auth', 'token': adminToken, 'name': 'Admin Smoke'});
  final authOk = await expectMessage(adminMsgs, 'auth-ok');
  final adminId = authOk['userId'] as String;
  check(adminId.isNotEmpty, 'auth-ok carries userId');
  check(authOk['displayName'] == 'Admin Smoke', 'display name persisted');

  adminWs.send({'type': 'get-servers'});
  final servers = await expectMessage(adminMsgs, 'servers');
  final serverList = servers['servers'] as List;
  check(serverList.length == 1, 'admin belongs to exactly one server');
  final serverId = (serverList.first as Map)['id'] as String;

  adminWs.send({'type': 'get-channels', 'serverId': serverId});
  final channels = await expectMessage(adminMsgs, 'channels');
  final channelList = (channels['channels'] as List).cast<Map>();
  final textChannel =
      channelList.firstWhere((c) => c['type'] == 'text')['id'] as String;
  check(channelList.any((c) => c['type'] == 'voice'),
      'default voice channel exists');

  stdout.writeln('5. Invite -> second account');
  adminWs.send({'type': 'create-invite', 'serverId': serverId});
  final invite = await expectMessage(adminMsgs, 'invite-created');
  final inviteToken = invite['inviteToken'] as String;
  check(inviteToken.isNotEmpty, 'invite created (owner check passed)');
  check((invite['url'] as String).contains('invite='), 'shareable URL shape');

  final status = await api.inviteStatus(inviteToken);
  check(status.serverId == serverId, 'invite status points at the server');
  final memberToken =
      await api.inviteSignup(inviteToken, 'member$suffix', 'password123');
  check(memberToken.isNotEmpty, 'invite signup -> member JWT');
  try {
    await api.inviteStatus(inviteToken);
    check(false, 'used invite rejected');
  } on ApiException catch (e) {
    check(e.statusCode == 410, 'used invite -> 410 Gone');
  }

  stdout.writeln('6. Text message broadcast (no echo to sender)');
  final memberWs = await ArmonicSocket.connect(wsUrlFor(baseUrl));
  final memberMsgs = StreamIterator(memberWs.messages);
  memberWs.send({'type': 'auth', 'token': memberToken});
  await expectMessage(memberMsgs, 'auth-ok');

  final content = 'hola desde el smoke test $suffix';
  adminWs.send({
    'type': 'text-message',
    'serverId': serverId,
    'channelId': textChannel,
    'content': content,
  });
  final pushed = await expectMessage(memberMsgs, 'text-message');
  check(pushed['content'] == content && pushed['channelId'] == textChannel,
      'member received the broadcast');
  check(pushed['userId'] == adminId, 'broadcast carries sender userId');

  adminWs.send({
    'type': 'get-messages',
    'serverId': serverId,
    'channelId': textChannel,
  });
  final history = await expectMessage(adminMsgs, 'messages');
  final historyList = (history['messages'] as List).cast<Map>();
  check(historyList.isNotEmpty && historyList.first['content'] == content,
      'history returns most-recent-first (client must reverse)');

  stdout.writeln('7. Oversized message rejected');
  adminWs.send({
    'type': 'text-message',
    'serverId': serverId,
    'channelId': textChannel,
    'content': 'x' * 5000,
  });
  final err = await expectMessage(adminMsgs, 'error');
  check(err['message'] == 'message content invalid',
      'server-side validation error surfaced');

  await adminWs.close();
  await memberWs.close();
  stdout.writeln('\nPASS — $_checks checks against $baseUrl');
  exit(0);
}
