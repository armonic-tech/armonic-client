// End-to-end smoke test of the client's protocol code (HTTP + WS layers,
// no Flutter/UI) against a LIVE Armonic backend. Run it against a throwaway
// instance with a fresh DB — it claims the instance:
//
//   dart run tool/smoke.dart http://localhost:8090 change-me
//
// Exercises: /info, claim flow, /auth/login, WS auth handshake, the
// authenticated reads (GET /server, GET /server/{id}, GET /channel/{id},
// GET /channel/{id}/messages — history order), POST /server/{id}/invite
// (owner-only, 403 for members), text-message broadcast to a second account
// created via /invite/signup, and single-use invite enforcement (410 on
// reuse). Voice/WebRTC is NOT covered (needs flutter_webrtc on a real
// device).
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

  stdout.writeln('4. WS auth + HTTP reads (servers, channels)');
  final adminWs = await ArmonicSocket.connect(wsUrlFor(baseUrl));
  final adminMsgs = StreamIterator(adminWs.messages);
  adminWs.send({'type': 'auth', 'token': adminToken, 'name': 'Admin Smoke'});
  final authOk = await expectMessage(adminMsgs, 'auth-ok');
  final adminId = authOk['userId'] as String;
  check(adminId.isNotEmpty, 'auth-ok carries userId');
  check(authOk['displayName'] == 'Admin Smoke', 'display name persisted');

  try {
    await api.myServers('not-a-token');
    check(false, 'GET /server without valid JWT rejected');
  } on ApiException catch (e) {
    check(e.statusCode == 401, 'GET /server with bad token -> 401');
  }
  final servers = await api.myServers(adminToken);
  check(servers.length == 1, 'admin belongs to exactly one server');
  final serverId = servers.first.id;

  final channels = await api.serverChannels(adminToken, serverId);
  final textChannel = channels.firstWhere((c) => c.isText).id;
  final voiceChannel = channels.firstWhere((c) => c.isVoice).id;
  check(voiceChannel.isNotEmpty, 'default voice channel exists');

  final voiceDetail = await api.channelDetail(adminToken, voiceChannel);
  check(voiceDetail.channel.isVoice, 'GET /channel/{id} returns the channel');
  check(voiceDetail.connected.isEmpty && voiceDetail.connectedCount == 0,
      'voice channel starts with nobody connected');

  stdout.writeln('5. Invite (HTTP, owner-only) -> second account');
  final invite = await api.createInvite(adminToken, serverId);
  check(invite.inviteToken.isNotEmpty, 'invite created (owner check passed)');
  check(invite.url.contains('invite='), 'shareable URL shape');

  final status = await api.inviteStatus(invite.inviteToken);
  check(status.serverId == serverId, 'invite status points at the server');
  final memberToken = await api.inviteSignup(
      invite.inviteToken, 'member$suffix', 'password123');
  check(memberToken.isNotEmpty, 'invite signup -> member JWT');
  try {
    await api.inviteStatus(invite.inviteToken);
    check(false, 'used invite rejected');
  } on ApiException catch (e) {
    check(e.statusCode == 410, 'used invite -> 410 Gone');
  }
  try {
    await api.createInvite(memberToken, serverId);
    check(false, 'non-owner invite rejected');
  } on ApiException catch (e) {
    check(e.statusCode == 403, 'member creating invite -> 403');
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

  final history = await api.channelMessages(memberToken, textChannel);
  check(history.isNotEmpty && history.first.content == content,
      'history returns most-recent-first (client must reverse), member can read');

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
