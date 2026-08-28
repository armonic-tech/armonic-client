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
  String get notAMember;
  String get noLongerMember;
  String get noLongerMemberHint;
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
  String get serverOptions;
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
  String get newTextChannel;
  String get newVoiceChannel;
  String get channelNameLabel;
  String get create;
  String get deleteChannel;
  String get deleteChannelConfirmTitle;
  String deleteTextChannelConfirmBody(String channelName);
  String deleteVoiceChannelConfirmBody(String channelName);
  String get channelNameInvalid;
  String get couldNotCreateChannel;
  String get couldNotDeleteChannel;
  String get channelNotFound;
  String get deleteMessage;
  String get deleteMessageConfirmTitle;
  String get deleteMessageConfirmBody;
  String get delete;
  String get couldNotDeleteMessage;
  String get messageNotFound;
  String get notAllowed;
  String get userKickedFromServer;
  String get youWereKickedFromVoice;
  String get channelNameTaken;
  String get channelNameEmpty;
  String get channelNameTooLong;
  String get joinWithInvite;
  String get inviteLinkLabel;
  String get join;
  String get joinedServer;
  String couldNotJoinServer(Object error);
  String inviteDetails(String url);
  String couldNotCreateInvite(Object error);
  String couldNotAccessMic(Object error);
  String voiceLabel(String channelName);
  String voiceLocation(String instanceName, String serverName);
  String get goToVoiceServer;
  String get inVoiceHere;
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

  // Image attachments and avatars.
  String get imageUnavailable;
  String get attachImage;
  String get removeAttachment;
  String get uploadingImage;
  String get imageTooLarge;
  String get imageUnsupported;
  String get imageDimensionsTooBig;
  String get imageCorrupt;
  String get imageOnlyMessageHint;
  String uploadRateLimited(int? seconds);
  String couldNotUploadImage(Object error);
  String get openImage;
  String get closeImage;

  String get profileTitle;
  String get changeAvatar;
  String get avatarUpdated;
  String couldNotUpdateAvatar(Object error);

  // Server members roster.
  String get membersTitle;
  String get showMembers;
  String get hideMembers;
  String get ownerBadge;
  String get onlineLabel;
  String get offlineLabel;
  String get noMembers;
  String couldNotLoadMembers(Object error);

  // Proof of work on the public forms.
  String get verifying;
  String get powFailed;
  String get powExpired;
  String tooManyAttempts(int? seconds);
}

/// The active language. Spanish by default; reassign to switch languages.
AppStrings strings = const AppStringsEs();