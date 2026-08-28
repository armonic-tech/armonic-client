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
// created via /invite/signup, single-use invite enforcement (410 on reuse),
// the members roster, image upload + fetch + attachment on a message, and
// avatars. Proof of work is exercised automatically when the instance has it
// on (POW_ENABLED=true). Voice/WebRTC is NOT covered (needs flutter_webrtc on
// a real device).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/api/pow_gate.dart';
import 'package:armonic_client/api/pow_solver.dart';
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

/// A tiny but real 1x1 PNG, so the backend's magic-number sniff, decode and
/// re-encode all have something valid to chew on.
final onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

Future<void> main(List<String> args) async {
  final baseUrl = normalizeBaseUrl(args.isNotEmpty ? args[0] : 'http://localhost:8090');
  final claimPassword = args.length > 1 ? args[1] : 'change-me';
  final suffix = DateTime.now().millisecondsSinceEpoch;
  final api = ArmonicHttpApi(baseUrl);

  stdout.writeln('1. GET /info');
  var info = await api.info();
  check(info.name.isNotEmpty || info.host.isNotEmpty, 'info responds');
  check(!info.claimed, 'instance starts unclaimed (needs a fresh DB)');

  final powOn = await api.powChallenge() != null;
  stdout.writeln(powOn
      ? '   (proof of work is ON for this instance)'
      : '   (proof of work is off)');

  stdout.writeln('2. Claim flow');
  try {
    await withProofOfWork(
        api, (altcha) => api.claimPassword('wrong-password', altcha: altcha));
    check(false, 'bad claim password rejected');
  } on ApiException catch (e) {
    check(e.statusCode == 401, 'bad claim password -> 401');
  }
  final ticket = await withProofOfWork(
      api, (altcha) => api.claimPassword(claimPassword, altcha: altcha));
  check(ticket.ticket.isNotEmpty, 'claim password -> ticket');
  final adminToken =
      await api.claimRegister(ticket.ticket, 'admin$suffix', 'password123');
  check(adminToken.isNotEmpty, 'claim register -> admin JWT');
  info = await api.info();
  check(info.claimed, '/info now reports claimed');

  stdout.writeln('3. Login');
  final loginToken = await withProofOfWork(
      api, (altcha) => api.login('admin$suffix', 'password123', altcha: altcha));
  check(loginToken.isNotEmpty, 'login with admin credentials');
  try {
    await withProofOfWork(api,
        (altcha) => api.login('admin$suffix', 'not-the-password', altcha: altcha));
    check(false, 'bad login rejected');
  } on ApiException catch (e) {
    check(e.statusCode == 401, 'bad login -> 401');
  }
  if (powOn) {
    // A solution is single-use: replaying one must be refused, or the work
    // factor would cost an attacker nothing after the first solve.
    final challenge = (await api.powChallenge())!;
    final payload = await PowSolver.solve(challenge);
    await api.login('admin$suffix', 'password123', altcha: payload);
    try {
      await api.login('admin$suffix', 'password123', altcha: payload);
      check(false, 'replayed proof of work rejected');
    } on ApiException catch (e) {
      check(e.statusCode == 409, 'replayed proof of work -> 409');
    }
    try {
      await api.login('admin$suffix', 'password123', altcha: 'not-a-solution');
      check(false, 'garbage proof of work rejected');
    } on ApiException catch (e) {
      check(e.statusCode == 400, 'garbage proof of work -> 400');
    }
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
  final memberToken = await withProofOfWork(
      api,
      (altcha) => api.inviteSignup(
          invite.inviteToken, 'member$suffix', 'password123', altcha: altcha));
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

  stdout.writeln('8. Members roster');
  final roster = await api.serverMembers(adminToken, serverId);
  check(roster.length == 2, 'roster lists both accounts');
  final adminEntry = roster.firstWhere((m) => m.id == adminId);
  check(adminEntry.isOwner, 'the claimer is flagged as owner');
  check(adminEntry.displayName == 'Admin Smoke', 'roster carries display name');
  check(roster.every((m) => m.online), 'both have a live socket right now');
  try {
    await api.serverMembers('not-a-token', serverId);
    check(false, 'roster without a valid JWT rejected');
  } on ApiException catch (e) {
    check(e.statusCode == 401, 'GET /server/{id}/members with bad token -> 401');
  }

  stdout.writeln('9. Image upload, fetch and attachment on a message');
  final attachment =
      await api.uploadImage(adminToken, serverId, onePixelPng, 'pixel.png');
  check(attachment.id.isNotEmpty, 'upload -> attachment id');
  check(attachment.mime == 'image/png', 'stored as PNG');
  check(attachment.width == 1 && attachment.height == 1, 'dimensions reported');
  check(attachment.url == '/attachment/${attachment.id}', 'url shape');

  final fullBytes = await api.attachmentBytes(adminToken, attachment.url);
  check(fullBytes.isNotEmpty, 'attachment bytes fetched with the JWT');
  check(fullBytes.length >= 8 && fullBytes[1] == 0x50 && fullBytes[2] == 0x4E,
      'served bytes are a PNG');
  final thumbBytes = await api.attachmentBytes(adminToken, attachment.thumbUrl);
  check(thumbBytes.isNotEmpty, 'thumbnail bytes fetched');
  try {
    await api.attachmentBytes('not-a-token', attachment.url);
    check(false, 'attachment without a valid JWT rejected');
  } on ApiException catch (e) {
    check(e.statusCode == 401, 'attachment with bad token -> 401');
  }

  // A non-image must be refused by the magic-number sniff, whatever it claims.
  try {
    await api.uploadImage(adminToken, serverId,
        Uint8List.fromList('#!/bin/sh\nrm -rf /'.codeUnits), 'innocent.png');
    check(false, 'non-image upload rejected');
  } on ApiException catch (e) {
    check(e.statusCode == 415, 'a script named .png -> 415');
  }

  adminWs.send({
    'type': 'text-message',
    'serverId': serverId,
    'channelId': textChannel,
    'content': '',
    'attachmentId': attachment.id,
  });
  final withImage = await expectMessage(memberMsgs, 'text-message');
  check(withImage['attachmentId'] == attachment.id,
      'image-only message broadcast with its attachmentId');
  check(withImage['content'] == '', 'empty content is allowed with an image');

  final historyWithImage = await api.channelMessages(memberToken, textChannel);
  // Deliberately not asserting on position: messages.created_at has one-second
  // resolution and the query has no tiebreaker, so two messages sent in the
  // same second come back in an arbitrary order.
  check(historyWithImage.any((m) => m.attachmentId == attachment.id),
      'history carries attachmentId');
  check(historyWithImage.any((m) => m.attachmentId == null),
      'text-only messages still carry no attachmentId');

  // The member did not upload it, so attributing it to themselves must fail.
  memberWs.send({
    'type': 'text-message',
    'serverId': serverId,
    'channelId': textChannel,
    'content': 'robando',
    'attachmentId': attachment.id,
  });
  final stealErr = await expectMessage(memberMsgs, 'error');
  check(stealErr['message'] == 'invalid attachment',
      'a member cannot attach someone else\'s upload');

  stdout.writeln('10. Avatars');
  var me = await api.me(adminToken);
  check(me.id == adminId, 'GET /me identifies the caller');
  check(me.avatarId == null, 'no avatar set yet');
  final avatar = await api.uploadAvatar(adminToken, onePixelPng, 'me.png');
  me = await api.me(adminToken);
  check(me.avatarId == avatar.id, 'avatar set through POST /me/avatar');
  final rosterWithAvatar = await api.serverMembers(memberToken, serverId);
  check(rosterWithAvatar.firstWhere((m) => m.id == adminId).avatarId ==
      avatar.id, 'the roster exposes the avatar to other members');

  await adminWs.close();
  await memberWs.close();
  stdout.writeln('\nPASS — $_checks checks against $baseUrl');
  exit(0);
}
