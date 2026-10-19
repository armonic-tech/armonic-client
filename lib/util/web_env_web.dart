import 'package:web/web.dart' as web;

bool get isSecureContext => web.window.isSecureContext;

/// Drops the query from the address bar without reloading, so a reload does
/// not redeem the same single-use invite a second time.
void clearPageQuery() {
  final uri = Uri.base;
  if (!uri.hasQuery) return;
  final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
  web.window.history.replaceState(null, '', '${uri.path}$fragment');
}
