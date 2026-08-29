/// Web build: there is no filesystem to read a theme file from, so the
/// defaults always apply. (Serving a theme per instance would be a backend
/// feature, not a client file.)
String? readUserThemeFile() => null;
