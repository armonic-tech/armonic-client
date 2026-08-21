import 'app_strings.dart';

class AppStringsEs implements AppStrings {
  const AppStringsEs();

  // App shell / home.
  @override
  String get appTitle => 'Armonic';
  @override
  String get addServer => 'Agregar instancia';
  @override
  String get noInstancesYet => 'Sin instancias conectadas todavía';
  @override
  String get addArmonicInstance => 'Agregar una instancia de Armonic';
  @override
  String get offline => 'sin conexión';
  @override
  String get removeFromList => 'Quitar de la lista';
  @override
  String get instanceNeedsLogin =>
      'Guardaste esta instancia pero no iniciaste sesión.';
  @override
  String membersCount(int count) => '$count miembros';

  // Add-instance screen.
  @override
  String get addInstanceTitle => 'Agregar instancia';
  @override
  String get addInstanceIntro =>
      'URL de la instancia de Armonic, o un link de invitación '
      'que te hayan compartido.';
  @override
  String get urlLabel => 'URL';
  @override
  String get urlHint => 'http://mi-servidor:4000  -  …?invite=abc123';
  @override
  String get invalidUrl => 'Ingresá una URL válida (ej. http://host:4000)';
  @override
  String get connect => 'Conectar';
  @override
  String couldNotContactInstance(Object error) =>
      'No se pudo conectar la instancia';

  // Onboarding: claim / login / invite.
  @override
  String get claimInstanceTitle => 'Reclamar instancia';
  @override
  String get claimIntro =>
      'Esta instancia todavía no tiene dueño. Ingresá la '
      'contraseña de la instancia (definida en el config.json '
      'del servidor) para reclamarla y volverte admin.';
  @override
  String get instancePasswordLabel => 'Contraseña de la instancia';
  @override
  String get verify => 'Verificar';
  @override
  String get claimCredentialsIntro =>
      'Contraseña correcta. Creá tu cuenta de administrador '
      '(el ticket vence en ~10 minutos).';
  @override
  String get createAdminAccount => 'Crear cuenta de admin';
  @override
  String get wrongPassword => 'Contraseña incorrecta';
  @override
  String get instanceAlreadyClaimed =>
      'Esta instancia ya fue reclamada por otra persona';
  @override
  String get ticketExpired => 'El ticket venció — ingresá la contraseña de nuevo';
  @override
  String get usernameTaken => 'Ese nombre de usuario ya existe';

  @override
  String get loginTitle => 'Iniciar sesión';
  @override
  String get loginIntro =>
      '¿No tenés cuenta? Pedile un link de invitación al admin de '
      'la instancia — no hay registro público.';
  @override
  String get login => 'Entrar';
  @override
  String get wrongCredentials => 'Usuario o contraseña incorrectos';

  @override
  String get inviteJoinTitle => 'Unirse con invitación';
  @override
  String get createAccountAndJoin => 'Crear cuenta y unirme';
  @override
  String get inviteNoLongerValid =>
      'Esta invitación ya no es válida (vencida o ya usada).';
  @override
  String get inviteInvalid => 'Esta invitación ya no es válida';
  @override
  String get instanceNotClaimedYet =>
      'La instancia todavía no fue reclamada por un admin';
  @override
  String inviteValidIntro(String instanceName, DateTime? expiresAt) =>
      'Invitación válida para "$instanceName"'
      '${expiresAt != null ? ' — vence el $expiresAt' : ''}. '
      'Creá tu cuenta para unirte.';
  @override
  String couldNotValidateInvite(Object? error) =>
      'No se pudo validar la invitación: $error';

  // Credentials form.
  @override
  String get usernameLabel => 'Usuario';
  @override
  String get passwordLabel => 'Contraseña';
  @override
  String get enterUsername => 'Ingresá un nombre de usuario';
  @override
  String get passwordTooShort => 'La contraseña debe tener al menos 8 caracteres';

  // Server screen: sidebar, chat, voice.
  @override
  String get disconnectedFromInstance => 'Desconectado de la instancia';
  @override
  String get reconnect => 'Reconectar';
  @override
  String get noServersForAccount => 'Sin servidores para esta cuenta';
  @override
  String get textHeader => 'TEXTO';
  @override
  String get voiceHeader => 'VOZ';
  @override
  String get createInvite => 'Crear invitación';
  @override
  String get ownerOnly => 'solo dueño';
  @override
  String get inviteCreated => 'Invitación creada';
  @override
  String get copyAndClose => 'Copiar y cerrar';
  @override
  String get onlyOwnerCanInvite =>
      'Solo el dueño de la instancia puede crear invitaciones';
  @override
  String get pickTextChannel => 'Elegí un canal de texto';
  @override
  String get you => 'vos';
  @override
  String get mute => 'Silenciar';
  @override
  String get unmute => 'Activar micrófono';
  @override
  String get deafen => 'Ensordecer';
  @override
  String get undeafen => 'Dejar de ensordecer';
  @override
  String get leaveVoiceTooltip => 'Salir del canal de voz';
  @override
  String get messageInvalid => 'Mensaje inválido (vacío o demasiado largo)';
  @override
  String get couldNotSaveMessage =>
      'No se pudo guardar el mensaje — probá de nuevo';

  // Moderation (owner-only) + join-with-invite.
  @override
  String get kickFromVoice => 'Expulsar del canal de voz';
  @override
  String get kickFromServer => 'Expulsar del servidor';
  @override
  String get kickFromServerConfirmTitle => '¿Expulsar del servidor?';
  @override
  String kickFromServerConfirmBody(String memberName) =>
      '$memberName va a perder el acceso al servidor y a todos sus canales. '
      'Puede volver solo con una nueva invitación.';
  @override
  String get cancel => 'Cancelar';
  @override
  String get kick => 'Expulsar';
  @override
  String get notAllowed => 'No tenés permisos para hacer eso';
  @override
  String get userKickedFromServer => 'Usuario expulsado del servidor';
  @override
  String get youWereKickedFromVoice => 'Te expulsaron del canal de voz';
  @override
  String get joinWithInvite => 'Unirse con invitación';
  @override
  String get inviteLinkLabel => 'Link o código de invitación';
  @override
  String get join => 'Unirme';
  @override
  String get joinedServer => 'Te uniste al servidor';
  @override
  String couldNotJoinServer(Object error) =>
      'No se pudo usar la invitación: $error';
  @override
  String inviteDetails(String url) =>
      '$url\n\nEs de un solo uso y vence en 24 horas.';
  @override
  String couldNotCreateInvite(Object error) =>
      'No se pudo crear la invitación: $error';
  @override
  String couldNotAccessMic(Object error) =>
      'No se pudo acceder al micrófono: $error';
  @override
  String voiceLabel(String channelName) => 'Voz: $channelName';
  @override
  String channelStart(String channelName) => 'Este es el inicio de #$channelName';
  @override
  String sendMessageTo(String channelName) => 'Enviar mensaje a #$channelName';

  // Session-level connection errors.
  @override
  String get instanceUnreachable => 'No pudimos conectarnos con la instancia';
  @override
  String get instanceUnreachableHint =>
      'Puede estar apagada, reiniciándose o fuera de alcance desde esta red. '
      'Revisá que el servidor esté andando y probá de nuevo.';
  @override
  String get connectionLost => 'Se cortó la conexión con la instancia';
  @override
  String get connectionLostHint =>
      'Puede haber sido un corte de red o un reinicio del servidor.';
  @override
  String get connectionClosed => 'La conexión se cerró';
  @override
  String get authTimeout => 'La instancia tardó demasiado en responder';
  @override
  String get sessionInvalid =>
      'Sesión inválida o vencida — volvé a iniciar sesión';
  @override
  String get unknownError => 'error desconocido';
  @override
  String couldNotLoadServers(Object error) =>
      'No se pudieron cargar los servidores';
  @override
  String couldNotLoadChannels(Object error) =>
      'No se pudieron cargar los canales';
  @override
  String couldNotLoadMessages(Object error) =>
      'No se pudieron cargar los mensajes';
}