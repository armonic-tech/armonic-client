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
  String get notAMember => 'ya no sos miembro';
  @override
  String get noLongerMember => 'Ya no sos miembro de esta instancia';
  @override
  String get noLongerMemberHint =>
      'Un administrador te eliminó. Necesitás una invitación nueva para volver '
      'a entrar.';
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
  String get ticketExpired =>
      'El ticket venció — ingresá la contraseña de nuevo';
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
  String get passwordTooShort =>
      'La contraseña debe tener al menos 8 caracteres';

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
  String get serverOptions => 'Opciones del servidor';
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
  String get newTextChannel => 'Nuevo canal de texto';
  @override
  String get newVoiceChannel => 'Nuevo canal de voz';
  @override
  String get channelNameLabel => 'Nombre del canal';
  @override
  String get create => 'Crear';
  @override
  String get deleteChannel => 'Eliminar canal';
  @override
  String get deleteChannelConfirmTitle => '¿Eliminar el canal?';
  @override
  String deleteTextChannelConfirmBody(String channelName) =>
      '"$channelName" deja de verse para todos y su historial de mensajes '
      'queda inaccesible. No se puede deshacer desde la app.';
  @override
  String deleteVoiceChannelConfirmBody(String channelName) =>
      '"$channelName" deja de verse para todos y quien esté hablando ahí se '
      'desconecta. No se puede deshacer desde la app.';
  @override
  String get channelNameInvalid =>
      'Nombre inválido (vacío o de más de 64 caracteres)';
  @override
  String get couldNotCreateChannel =>
      'No se pudo crear el canal — probá de nuevo';
  @override
  String get couldNotDeleteChannel =>
      'No se pudo eliminar el canal — probá de nuevo';
  @override
  String get channelNotFound => 'El canal ya no existe';
  @override
  String get deleteMessage => 'Eliminar mensaje';
  @override
  String get deleteMessageConfirmTitle => '¿Eliminar el mensaje?';
  @override
  String get deleteMessageConfirmBody =>
      'El mensaje deja de verse para todos. No se puede deshacer desde la app.';
  @override
  String get delete => 'Eliminar';
  @override
  String get couldNotDeleteMessage =>
      'No se pudo eliminar el mensaje — probá de nuevo';
  @override
  String get messageNotFound => 'El mensaje ya no existe';
  @override
  String get notAllowed => 'No tenés permisos para hacer eso';
  @override
  String get userKickedFromServer => 'Usuario expulsado del servidor';
  @override
  String get youWereKickedFromVoice => 'Te expulsaron del canal de voz';
  @override
  String get channelNameTaken => 'Ya existe un canal con ese nombre';
  @override
  String get channelNameEmpty => 'Poné un nombre';
  @override
  String get channelNameTooLong => 'Máximo 64 caracteres';
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
  String voiceLocation(String instanceName, String serverName) =>
      '$instanceName · $serverName';
  @override
  String get goToVoiceServer => 'Ir al servidor de la llamada';
  @override
  String get inVoiceHere => 'Estás en un canal de voz acá';
  @override
  String channelStart(String channelName) =>
      'Este es el inicio de #$channelName';
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

  // Image attachments and avatars.
  @override
  String get imageUnavailable => 'No se pudo cargar la imagen';
  @override
  String get attachImage => 'Adjuntar imagen';
  @override
  String get removeAttachment => 'Quitar imagen';
  @override
  String get uploadingImage => 'Subiendo imagen…';
  @override
  String get imageTooLarge => 'La imagen supera el tamaño máximo permitido';
  @override
  String get imageUnsupported =>
      'Formato no soportado. Se aceptan PNG, JPEG, GIF y WebP.';
  @override
  String get imageDimensionsTooBig =>
      'La imagen excede las dimensiones permitidas';
  @override
  String get imageCorrupt => 'La imagen está dañada o no es una imagen válida';
  @override
  String get imageOnlyMessageHint => 'Escribí algo o mandá solo la imagen';
  @override
  String uploadRateLimited(int? seconds) => seconds == null
      ? 'Estás subiendo imágenes muy rápido, esperá un momento'
      : 'Estás subiendo imágenes muy rápido, probá en ${seconds}s';
  @override
  String couldNotUploadImage(Object error) => 'No se pudo subir la imagen';
  @override
  String get openImage => 'Ver imagen';
  @override
  String get closeImage => 'Cerrar';

  @override
  String get profileTitle => 'Tu perfil';
  @override
  String get changeAvatar => 'Cambiar foto';
  @override
  String get avatarUpdated => 'Foto actualizada';
  @override
  String couldNotUpdateAvatar(Object error) => 'No se pudo cambiar la foto';

  // Server members roster.
  @override
  String get membersTitle => 'Miembros';
  @override
  String get showMembers => 'Mostrar miembros';
  @override
  String get hideMembers => 'Ocultar miembros';
  @override
  String get ownerBadge => 'admin';
  @override
  String get onlineLabel => 'En línea';
  @override
  String get offlineLabel => 'Desconectados';
  @override
  String get noMembers => 'Sin miembros';
  @override
  String couldNotLoadMembers(Object error) =>
      'No se pudieron cargar los miembros';

  // Proof of work on the public forms.
  @override
  String get memberStatusLabel => 'ESTADO';
  @override
  String get unknownStatus => 'Sin información';
  @override
  String get mutedStatus => 'Micrófono silenciado';
  @override
  String get deafenedStatus => 'Audio desactivado';
  @override
  String inVoiceStatus(String channelName) => 'En voz · $channelName';

  @override
  String get mentionPickerTitle => 'MENCIONAR A';
  @override
  String get mentionPickerEnterHint => 'ENTER';
  @override
  String mentionPickerMore(int count) => '+$count más';

  @override
  String get settingsTitle => 'Configuración';
  @override
  String get appearanceSection => 'Apariencia';
  @override
  String get audioSection => 'Audio y micrófono';
  @override
  String get colorsLabel => 'Colores';
  @override
  String get fontSizeLabel => 'Tamaño de fuente';
  @override
  String get chatAvatarSizeLabel => 'Tamaño de avatar en el chat';
  @override
  String get glowLabel => 'Resplandor de fondo';
  @override
  String get inputDeviceLabel => 'Micrófono (entrada)';
  @override
  String get outputDeviceLabel => 'Altavoces (salida)';
  @override
  String get volumeLabel => 'Volumen';
  @override
  String get systemDefaultDevice => 'Predeterminado del sistema';
  @override
  String get resetSettings => 'Restablecer';
  @override
  String get resetSettingsHint => 'Vuelve a los colores y tamaños originales.';
  @override
  String get close => 'Cerrar';
  @override
  String get colorHexLabel => 'Color (#RRGGBB)';
  @override
  String get invalidColor => 'Color inválido';
  @override
  String get audioDeviceUnavailable =>
      'No se pudieron leer los dispositivos de audio.';
  @override
  String get previewLabel => 'Vista previa';

  @override
  String get verifying => 'Verificando…';
  @override
  String get powFailed =>
      'No se pudo completar la verificación. Probá de nuevo.';
  @override
  String get powExpired => 'La verificación venció. Probá de nuevo.';
  @override
  String tooManyAttempts(int? seconds) => seconds == null
      ? 'Demasiados intentos, esperá un momento'
      : 'Demasiados intentos, probá en ${seconds}s';
}
