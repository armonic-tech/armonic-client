import 'app_strings_es.dart';

abstract interface class AppStrings {
  // App shell / home.
  String get appTitle;
  String get addServer;
  String get noInstancesYet;
  String get addArmonicInstance;
  String get offline;
  String get removeFromList;
  String get instanceNeedsLogin;
  String membersCount(int count);

  // Add-instance screen.
  String get addInstanceTitle;
  String get addInstanceIntro;
  String get urlLabel;
  String get urlHint;
  String get invalidUrl;
  String get connect;
  String couldNotContactInstance(Object error);

  // Onboarding: claim / login / invite.
  String get claimInstanceTitle;
  String get claimIntro;
  String get instancePasswordLabel;
  String get verify;
  String get claimCredentialsIntro;
  String get createAdminAccount;
  String get wrongPassword;
  String get instanceAlreadyClaimed;
  String get ticketExpired;
  String get usernameTaken;

  String get loginTitle;
  String get loginIntro;
  String get login;
  String get wrongCredentials;

  String get inviteJoinTitle;
  String get createAccountAndJoin;
  String get inviteNoLongerValid;
  String get inviteInvalid;
  String get instanceNotClaimedYet;
  String inviteValidIntro(String instanceName, DateTime? expiresAt);
  String couldNotValidateInvite(Object? error);

  // Credentials form.
  String get usernameLabel;
  String get passwordLabel;
  String get enterUsername;
  String get passwordTooShort;

  // Server screen: sidebar, chat, voice.
  String get disconnectedFromInstance;
  String get reconnect;
  String get noServersForAccount;
  String get textHeader;
  String get voiceHeader;
  String get createInvite;
  String get ownerOnly;
  String get inviteCreated;
  String get copyAndClose;
  String get onlyOwnerCanInvite;
  String get pickTextChannel;
  String get you;
  String get mute;
  String get unmute;
  String get deafen;
  String get undeafen;
  String get leaveVoiceTooltip;
  String get messageInvalid;
  String get couldNotSaveMessage;

  // Moderation (owner-only) + join-with-invite.
  String get kickFromVoice;
  String get kickFromServer;
  String get kickFromServerConfirmTitle;
  String kickFromServerConfirmBody(String memberName);
  String get cancel;
  String get kick;
  String get notAllowed;
  String get userKickedFromServer;
  String get youWereKickedFromVoice;
  String get joinWithInvite;
  String get inviteLinkLabel;
  String get join;
  String get joinedServer;
  String couldNotJoinServer(Object error);
  String inviteDetails(String url);
  String couldNotCreateInvite(Object error);
  String couldNotAccessMic(Object error);
  String voiceLabel(String channelName);
  String channelStart(String channelName);
  String sendMessageTo(String channelName);

  // Session-level connection errors (no BuildContext available at the source).
  String get instanceUnreachable;
  String get instanceUnreachableHint;
  String get connectionLost;
  String get connectionLostHint;
  String get connectionClosed;
  String get authTimeout;
  String get sessionInvalid;
  String get unknownError;
  String couldNotLoadServers(Object error);
  String couldNotLoadChannels(Object error);
  String couldNotLoadMessages(Object error);
}

/// The active language. Spanish by default; reassign to switch languages.
AppStrings strings = const AppStringsEs();