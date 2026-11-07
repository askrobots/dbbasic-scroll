import 'dart:convert';
import 'dart:io';

/// A tiny in-process stand-in for a DBBASIC object server, for hermetic UI
/// tests. It reproduces the behaviours Scroll has to cope with:
///
/// * `/health` is public; `/health?metrics=true` is admin-gated like /admin.
/// * User-level routes (`/collections/...`, `/identity/...`) accept any valid
///   credential — unless [credentialExpired] (then 401 = "your session died").
/// * Admin-gated routes (`/admin`, `/daemon`, `/permissions`) answer **401**
///   (not 403) to a valid-but-not-admin credential, exactly like the real
///   server (verified against object.dbbasic.com and the nc desk).
///
/// Never touches the network beyond loopback and never sees a real token.
class FakeObjectServer {
  FakeObjectServer({this.credentialExpired = false, this.adminGated = true});

  /// User-level routes reject the credential (expired session / revoked key).
  bool credentialExpired;

  /// Admin routes reject a non-admin credential with 401.
  bool adminGated;

  /// Rows served for /collections/ai_usage/records (null = collection absent → 404).
  List<Map<String, dynamic>>? aiUsageRows;

  /// "METHOD /path?query" for every request received, in order.
  final List<String> requests = [];

  /// Authorization header values seen on user-level requests.
  final List<String> authHeaders = [];

  late HttpServer _server;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  bool requested(String pathPrefix) =>
      requests.any((r) => r.split(' ')[1].startsWith(pathPrefix));

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path.replaceFirst(RegExp(r'^/'), '');
    requests.add('${request.method} ${request.uri}');
    final first = path.split('/').first;
    final auth = request.headers.value('authorization');

    if (first == 'health') {
      if (request.uri.queryParameters['metrics'] == 'true' && adminGated) {
        return _json(request, 401, {'error': 'Unauthorized'});
      }
      return _json(request, 200, {'status': 'ok'});
    }
    if (first == 'collections' || first == 'identity') {
      if (auth != null) authHeaders.add(auth);
      if (credentialExpired || auth == null) {
        return _json(request, 401, {'error': 'Unauthorized'});
      }
      if (path.startsWith('collections/ai_usage/records')) {
        final rows = aiUsageRows;
        if (rows == null) return _json(request, 404, {'error': 'Not found'});
        return _json(request, 200, {
          'status': 'ok',
          'records': rows,
          'total': rows.length,
        });
      }
      return _json(request, 200, {'status': 'ok', 'records': <dynamic>[]});
    }
    if (const {'admin', 'daemon', 'permissions'}.contains(first)) {
      if (adminGated) return _json(request, 401, {'error': 'Unauthorized'});
      return _json(request, 200, {'status': 'ok'});
    }
    if (first == 'objects') {
      return _json(request, 200, {'objects': <dynamic>[]});
    }
    return _json(request, 404, {'error': 'Not found'});
  }

  void _json(HttpRequest request, int status, Object body) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    request.response.close();
  }
}
