import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum _AuthMode { none, objectServer, platform }

/// Scroll connects to two services:
/// 1. Object Server (required) — Python objects, execution, state, clustering
/// 2. Platform API (optional) — askrobots.com collections (contacts, tasks, etc.)
class ScrollAPI {
  String? _objectServerUrl; // e.g. https://object.example.com
  String? _platformUrl; // e.g. https://askrobots.com
  String? _token;
  final http.Client _client = http.Client();

  static final ScrollAPI _instance = ScrollAPI._();
  factory ScrollAPI() => _instance;
  ScrollAPI._();

  String? get objectServerUrl => _objectServerUrl;
  String? get platformUrl => _platformUrl;
  bool get isConnected => _objectServerUrl != null && _token != null;
  bool get hasPlatform => _platformUrl != null;

  /// Token for WebView JS injection only (dev helper — don't expose elsewhere)
  String get tokenForWebView => _token ?? '';

  /// Websocket endpoint for realtime push (/ws), or null when not
  /// connected. http(s) → ws(s), trailing slash trimmed.
  String? get realtimeUrl {
    final base = _objectServerUrl;
    if (base == null || _token == null) return null;
    final trimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '${trimmed.replaceFirst(RegExp(r'^http'), 'ws')}/ws';
  }

  /// Auth headers for the realtime websocket handshake.
  Map<String, dynamic> get realtimeHeaders =>
      _token == null ? const {} : {'Authorization': 'Bearer $_token'};

  /// Fires (once per connection) when the object server rejects the stored
  /// credential with a 401 — typically an expired session token. The shell
  /// listens and prompts the operator to sign in again.
  final ValueNotifier<bool> authRejected = ValueNotifier(false);

  void _noteAuthResult(int statusCode, _AuthMode authMode) {
    if (statusCode == 401 &&
        authMode == _AuthMode.objectServer &&
        isConnected) {
      authRejected.value = true;
    }
  }

  // --- Connection ---

  Future<void> loadSavedConnection() async {
    final prefs = await SharedPreferences.getInstance();
    _objectServerUrl = prefs.getString('object_server_url');
    _platformUrl = prefs.getString('platform_url');
    _token = prefs.getString('server_token');
    _sessionUserId = prefs.getString('session_user_id');
  }

  Future<bool> connect({
    required String objectServerUrl,
    required String token,
    String? platformUrl,
  }) async {
    final objUrl = objectServerUrl.endsWith('/')
        ? objectServerUrl
        : '$objectServerUrl/';
    try {
      // Test object server connection via /health (public, no auth needed)
      final health = await _getRaw('${objUrl}health');
      if (health == null) return false;

      _objectServerUrl = objUrl;
      _token = token;
      authRejected.value = false;

      // Test platform connection if provided
      if (platformUrl != null && platformUrl.isNotEmpty) {
        final platUrl = platformUrl.endsWith('/')
            ? platformUrl
            : '$platformUrl/';
        final platTest = await _getRaw(
          '${platUrl}api/projects/',
          token: token,
          authMode: _AuthMode.platform,
        );
        if (platTest != null) {
          _platformUrl = platUrl;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('object_server_url', _objectServerUrl!);
      await prefs.setString('server_token', _token!);
      if (_platformUrl != null) {
        await prefs.setString('platform_url', _platformUrl!);
      }
      return true;
    } catch (_) {}
    return false;
  }

  // --- OpenAI key (user-provided, optional) ---

  Future<String?> getOpenAIKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('openai_api_key');
  }

  Future<void> setOpenAIKey(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == null || key.isEmpty) {
      await prefs.remove('openai_api_key');
    } else {
      await prefs.setString('openai_api_key', key);
    }
  }

  /// Call OpenAI directly (user's key) to extract structured data from text.
  /// Returns parsed JSON map or null on failure.
  Future<Map<String, dynamic>?> aiExtract({
    required String prompt,
    required String userText,
  }) async {
    final key = await getOpenAIKey();
    if (key == null || key.isEmpty) return null;
    try {
      final response = await _client.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You extract structured data. Output ONLY valid JSON, no markdown, no explanations.',
            },
            {'role': 'user', 'content': '$prompt\n\nInput text:\n$userText'},
          ],
          'response_format': {'type': 'json_object'},
        }),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final content = body['choices']?[0]?['message']?['content'];
        if (content is String) {
          return jsonDecode(content) as Map<String, dynamic>;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Generate Python object code from a natural language description.
  /// Returns {name: suggested_object_name, code: python_source} or null.
  Future<Map<String, String>?> aiGenerateObject({
    required String description,
    required String objectType, // 'view', 'data', 'object', 'trigger'
  }) async {
    final key = await getOpenAIKey();
    if (key == null || key.isEmpty) return null;

    final typeGuide = switch (objectType) {
      'view' =>
        'This is a VIEW object — GET(request) should return {"content_type": "text/html; charset=utf-8", "body": "<full html document>"} for interactive UI, or a plain dict for JSON API. HTML can include forms that POST to the same object.',
      'data' =>
        'This is a DATA STORE object — GET(request) returns stored data as JSON, POST(request) accepts data to add/update. Use _state_manager.get("items", []) and _state_manager.set("items", new_list).',
      'trigger' =>
        'This is a TRIGGER object — GET(request) runs the scheduled work, returns status dict. Called by the cron runner periodically.',
      _ => 'Generic object — define GET(request) and POST(request) as needed.',
    };

    final systemPrompt =
        '''You are generating Python code for the dbbasic Object Server (a live Python runtime).

OBJECT CONVENTIONS:
- Every object is a single Python file defining uppercase HTTP verb functions at module top level: GET(request), POST(request), PUT(request), DELETE(request). Only define the ones needed.
- request is a dict carrying the query params / request payload. request["_identity"] is server-controlled: {"user_id", "account_id", "roles", "subscriptions", "auth_method"} — user_id is None for anonymous visitors. Use it for per-user content; it cannot be spoofed.
- Persistent state: _state_manager.get(key, default) to read, _state_manager.set(key, value) to write. It is an injected global — no import needed. No database needed.
- Logging: _logger.info("message", key=value) — also an injected global.
- Return a Python dict. Plain dict → returned as JSON. For an HTML page return {"content_type": "text/html; charset=utf-8", "body": "<!doctype html>..."}.
- For HTML views, include full <html>...</html> with <style>. Use dark theme (bg #0a0a0a, fg #e0e0e0). Make it functional and clean.
- Forms POST to the same object URL — no separate routes. Use <form method="POST"> with onsubmit fetch to stay on the page.

$typeGuide

OUTPUT: JSON object with two keys:
- "name": short snake_case object name (e.g. "expense_tracker", "deals_kanban"). No u_{id}_ prefix - server adds it.
- "code": complete Python source as a string, starting with GET or POST.

No markdown, no backticks, no explanations. Only JSON.''';

    try {
      final response = await _client.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-4o',
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': description},
          ],
          'response_format': {'type': 'json_object'},
          'temperature': 0.7,
        }),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final content = body['choices']?[0]?['message']?['content'];
        if (content is String) {
          final parsed = jsonDecode(content) as Map<String, dynamic>;
          final name = parsed['name']?.toString() ?? '';
          final code = parsed['code']?.toString() ?? '';
          if (name.isNotEmpty && code.isNotEmpty) {
            return {'name': name, 'code': code};
          }
        }
      } else {
        lastError = 'OpenAI HTTP ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      lastError = 'AI error: $e';
    }
    return null;
  }

  /// Password login — POST /identity/session with no Authorization header.
  /// Returns {status, body} (or {error}) so callers can show the raw result.
  Future<Map<String, dynamic>> loginWithPassword({
    required String objectServerUrl,
    String? email,
    String? userId,
    required String password,
    String? label,
    int? ttlSeconds,
  }) async {
    final base = objectServerUrl.endsWith('/')
        ? objectServerUrl
        : '$objectServerUrl/';
    try {
      final response = await _client.post(
        Uri.parse('${base}identity/session'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          if (userId != null && userId.trim().isNotEmpty)
            'user_id': userId.trim(),
          'password': password,
          if (label != null && label.trim().isNotEmpty) 'label': label,
          if (ttlSeconds != null) 'ttl_seconds': ttlSeconds,
        }),
      );
      return {
        'status': response.statusCode,
        'body': _decodeResponseBody(response.body),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Extract the session bearer token from a loginWithPassword result.
  String? sessionTokenFromLogin(Map<String, dynamic> result) {
    dynamic body = result['body'];
    for (var depth = 0; depth < 2 && body is Map; depth++) {
      for (final key in const [
        'token',
        'session_token',
        'access_token',
        'bearer_token',
      ]) {
        final value = body[key];
        if (value is String && value.isNotEmpty) return value;
      }
      body = body['session'];
    }
    return null;
  }

  /// Extract the user id from a loginWithPassword result.
  String? sessionUserIdFromLogin(Map<String, dynamic> result) {
    dynamic body = result['body'];
    for (var depth = 0; depth < 2 && body is Map; depth++) {
      final value = body['user_id'];
      if (value is String && value.isNotEmpty) return value;
      body = body['session'];
    }
    return null;
  }

  String? _sessionUserId;

  /// The user id behind the current session token, when known (password
  /// logins set it; deployment-token connections have none). Used to
  /// prefill owner_id on record creates for owner-scoped app collections.
  String? get sessionUserId => _sessionUserId;

  Future<void> setSessionUser(String? userId) async {
    _sessionUserId = (userId == null || userId.isEmpty) ? null : userId;
    final prefs = await SharedPreferences.getInstance();
    if (_sessionUserId == null) {
      await prefs.remove('session_user_id');
    } else {
      await prefs.setString('session_user_id', _sessionUserId!);
    }
  }

  // --- AI provider service keys (write-only) + AI chat ---

  /// Store an AI provider key for a user (self-service with the user's own
  /// session). The server never returns key material — GET lists which
  /// services have keys, nothing more.
  Future<Map<String, dynamic>> setServiceKey(
    String userId, {
    required String service,
    required String key,
  }) {
    return rawRequest(
      'PUT',
      _objUrl('identity/users/${_pathSegment(userId)}/service-keys'),
      data: {'service': service, 'key': key},
    );
  }

  Future<Map<String, dynamic>> listServiceKeys(String userId) {
    return rawRequest(
      'GET',
      _objUrl('identity/users/${_pathSegment(userId)}/service-keys'),
    );
  }

  Future<Map<String, dynamic>> removeServiceKey(String userId, String service) {
    return rawRequest(
      'DELETE',
      _objUrl(
        'identity/users/${_pathSegment(userId)}/service-keys/'
        '${_pathSegment(service)}',
      ),
    );
  }

  /// One AI conversation turn using the caller's stored provider key.
  /// Tool calls dispatch with the caller's credentials — the AI can do
  /// exactly what the session could, permission-checked and audited.
  /// [history] is prior turns as [{role, content}] (server caps at 40).
  Future<Map<String, dynamic>> aiChat({
    required String message,
    String? model,
    List<String>? tools,
    int? maxRounds,
    List<Map<String, String>>? history,
  }) {
    return rawRequest(
      'POST',
      _objUrl('api/ai/chat'),
      data: {
        'message': message,
        if (model != null && model.isNotEmpty) 'model': model,
        if (tools != null) 'tools': tools,
        if (maxRounds != null) 'max_rounds': maxRounds,
        if (history != null && history.isNotEmpty) 'history': history,
      },
    );
  }

  /// Ops event stream: object execution failures + auth activity.
  /// kind: execution_error | auth; event: e.g. login_failed.
  Future<Map<String, dynamic>> listAdminOpsEvents({
    String? kind,
    String? event,
    String? identifier,
    int limit = 200,
  }) {
    var query = 'limit=$limit';
    if (kind != null && kind.isNotEmpty) {
      query += '&kind=${Uri.encodeQueryComponent(kind)}';
    }
    if (event != null && event.isNotEmpty) {
      query += '&event=${Uri.encodeQueryComponent(event)}';
    }
    if (identifier != null && identifier.isNotEmpty) {
      query += '&identifier=${Uri.encodeQueryComponent(identifier)}';
    }
    return rawRequest('GET', _objUrl('admin/ops?$query'));
  }

  // --- Caller-scoped record routes (/collections/*) ---
  // Unlike the admin routes these run inside the permission engine: rows
  // arrive pre-filtered for the session's user, which is what shell
  // history/preferences want.

  Future<Map<String, dynamic>> listUserCollectionRecords(
    String collection, {
    int limit = 100,
  }) {
    return rawRequest(
      'GET',
      _objUrl('collections/${_pathSegment(collection)}/records?limit=$limit'),
    );
  }

  Future<Map<String, dynamic>> getUserCollectionRecord(
    String collection,
    String recordId,
  ) {
    return rawRequest(
      'GET',
      _objUrl(
        'collections/${_pathSegment(collection)}/records/'
        '${_pathSegment(recordId)}',
      ),
    );
  }

  Future<Map<String, dynamic>> putUserCollectionRecord(
    String collection,
    String recordId,
    Map<String, dynamic> changes,
  ) {
    return rawRequest(
      'PUT',
      _objUrl(
        'collections/${_pathSegment(collection)}/records/'
        '${_pathSegment(recordId)}',
      ),
      data: changes,
    );
  }

  Future<Map<String, dynamic>> createUserCollectionRecord(
    String collection,
    Map<String, dynamic> record,
  ) {
    return rawRequest(
      'POST',
      _objUrl('collections/${_pathSegment(collection)}/records'),
      data: record,
    );
  }

  Future<void> disconnect() async {
    _objectServerUrl = null;
    _platformUrl = null;
    _token = null;
    _sessionUserId = null;
    authRejected.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('object_server_url');
    await prefs.remove('platform_url');
    await prefs.remove('server_token');
    await prefs.remove('session_user_id');
  }

  // --- HTTP helpers ---

  Map<String, String> _headers({
    String? token,
    _AuthMode authMode = _AuthMode.objectServer,
  }) {
    final headers = {'Content-Type': 'application/json'};
    final resolvedToken = token ?? _token;
    if (resolvedToken == null ||
        resolvedToken.isEmpty ||
        authMode == _AuthMode.none) {
      return headers;
    }
    final prefix = authMode == _AuthMode.platform ? 'Token' : 'Bearer';
    headers['Authorization'] = '$prefix $resolvedToken';
    return headers;
  }

  // Public raw request helpers for API Explorer
  Future<dynamic> rawGet(String url, {bool platformAuth = false}) => _getRaw(
    url,
    authMode: platformAuth ? _AuthMode.platform : _AuthMode.objectServer,
  );

  Future<Map<String, dynamic>> rawRequest(
    String method,
    String url, {
    Map<String, dynamic>? data,
    bool platformAuth = false,
  }) async {
    final authMode = platformAuth ? _AuthMode.platform : _AuthMode.objectServer;
    try {
      final uri = Uri.parse(url);
      final headers = _headers(authMode: authMode);
      final response = switch (method.toUpperCase()) {
        'POST' => await _client.post(
          uri,
          headers: headers,
          body: jsonEncode(data ?? {}),
        ),
        'PUT' => await _client.put(
          uri,
          headers: headers,
          body: jsonEncode(data ?? {}),
        ),
        'PATCH' => await _client.patch(
          uri,
          headers: headers,
          body: jsonEncode(data ?? {}),
        ),
        'DELETE' => await _client.delete(uri, headers: headers),
        _ => await _client.get(uri, headers: headers),
      };
      _noteAuthResult(response.statusCode, authMode);
      return {
        'status': response.statusCode,
        'body': _decodeResponseBody(response.body),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  dynamic _decodeResponseBody(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  Future<dynamic> _getRaw(
    String url, {
    String? token,
    _AuthMode authMode = _AuthMode.objectServer,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: _headers(token: token, authMode: authMode),
      );
      if (response.statusCode == 200) {
        lastError = null;
        return _decodeResponseBody(response.body);
      }
      _noteAuthResult(response.statusCode, authMode);
      lastError = 'HTTP ${response.statusCode}: ${response.body}';
    } catch (e) {
      lastError = 'Error: $e';
    }
    return null;
  }

  // Last error from a POST/PUT/PATCH, for debugging
  String? lastError;

  Future<dynamic> _postRaw(
    String url,
    Map<String, dynamic> data, {
    _AuthMode authMode = _AuthMode.objectServer,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse(url),
        headers: _headers(authMode: authMode),
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        lastError = null;
        return _decodeResponseBody(response.body);
      }
      _noteAuthResult(response.statusCode, authMode);
      lastError = 'HTTP ${response.statusCode}: ${response.body}';
    } catch (e) {
      lastError = 'Error: $e';
    }
    return null;
  }

  Future<dynamic> _putRaw(
    String url,
    Map<String, dynamic> data, {
    _AuthMode authMode = _AuthMode.objectServer,
  }) async {
    try {
      final response = await _client.put(
        Uri.parse(url),
        headers: _headers(authMode: authMode),
        body: jsonEncode(data),
      );
      if (response.statusCode == 200) {
        return _decodeResponseBody(response.body);
      }
      _noteAuthResult(response.statusCode, authMode);
    } catch (_) {}
    return null;
  }

  Future<bool> _deleteRaw(
    String url, {
    _AuthMode authMode = _AuthMode.objectServer,
  }) async {
    try {
      final response = await _client.delete(
        Uri.parse(url),
        headers: _headers(authMode: authMode),
      );
      _noteAuthResult(response.statusCode, authMode);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {}
    return false;
  }

  String _objUrl(String path) => '${_objectServerUrl}$path';
  String _platUrl(String path) => '${_platformUrl}api/$path';

  // =====================================================================
  // OBJECT SERVER API (core)
  // =====================================================================

  // --- Health & Cluster ---

  /// Get health from a specific station URL (for station detail view)
  Future<Map<String, dynamic>?> getStationHealth(
    String stationUrl, {
    bool metrics = false,
  }) async {
    final baseUrl = stationUrl.endsWith('/') ? stationUrl : '$stationUrl/';
    final url = metrics
        ? '${baseUrl}health?metrics=true&format=json'
        : '${baseUrl}health?format=json';
    final result = await _getRaw(url);
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> getHealth({
    bool metrics = false,
    bool history = false,
    int historyLimit = 360,
  }) async {
    var url = metrics
        ? 'health?metrics=true&format=json'
        : 'health?format=json';
    if (history) url += '&history=true&history_limit=$historyLimit';
    final result = await _getRaw(_objUrl(url));
    return result is Map<String, dynamic> ? result : null;
  }

  // --- Theme / design system (/style is a themeable object) ---

  /// GET /style?info=true (public) → {active, available, previews, tokens}.
  /// `previews` maps each theme to a small swatch (bg/panel/accent/text).
  Future<Map<String, dynamic>?> getStyleInfo() async {
    final result = await _getRaw(_objUrl('style?info=true'));
    return result is Map<String, dynamic> ? result : null;
  }

  /// POST /style {theme} — switch the whole instance's theme live.
  /// Admin-gated server-side (the object self-gates on identity; non-admin
  /// sessions get 403).
  Future<Map<String, dynamic>> setStyleTheme(String theme) {
    return rawRequest('POST', _objUrl('style'), data: {'theme': theme});
  }

  Future<Map<String, dynamic>?> getAdminStatus() async {
    final result = await _getRaw(_objUrl('admin/status'));
    return result is Map<String, dynamic> ? result : null;
  }

  /// GET /packages/{id} (admin-gated) → {status, package, provenance}.
  /// The provenance block reports install-once baseline state: whether the
  /// package is installed, at what version, and per-artifact pristine/
  /// customized/removed vs the shipped baseline.
  Future<Map<String, dynamic>?> getPackage(String id) async {
    final result = await _getRaw(_objUrl('packages/${_pathSegment(id)}'));
    return result is Map<String, dynamic> ? result : null;
  }

  /// In-place package upgrade: POST /packages/{id}/install {allow_replace:true}.
  /// Objects/schema/permissions update, records preserved, conflicts parked
  /// as pending-reconcile records rather than overwritten.
  Future<Map<String, dynamic>> installPackage(
    String id, {
    bool allowReplace = true,
  }) {
    return rawRequest(
      'POST',
      _objUrl('packages/${_pathSegment(id)}/install'),
      data: {'allow_replace': allowReplace},
    );
  }

  // --- Reconcile inbox (parked upgrade conflicts) ---

  /// GET /admin/reconciles → {status, count, reconciles:[...]}.
  Future<Map<String, dynamic>> listReconciles({
    String? status,
    String? package,
  }) {
    final params = <String>[
      if (status != null && status.isNotEmpty)
        'status=${Uri.encodeQueryComponent(status)}',
      if (package != null && package.isNotEmpty)
        'package=${Uri.encodeQueryComponent(package)}',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    return rawRequest('GET', _objUrl('admin/reconciles$query'));
  }

  /// POST /admin/reconciles/{id}/resolve {choice: keep_mine|take_theirs}.
  Future<Map<String, dynamic>> resolveReconcile(String id, String choice) {
    return rawRequest(
      'POST',
      _objUrl('admin/reconciles/${_pathSegment(id)}/resolve'),
      data: {'choice': choice},
    );
  }

  // --- Backups (admin-gated; a backup contains ALL data, never public) ---

  /// GET /admin/backups → {backups: [{id, created_at, size, kind, scope}],
  /// count, schedule} newest-first.
  Future<Map<String, dynamic>> listBackups() {
    return rawRequest('GET', _objUrl('admin/backups'));
  }

  /// POST /admin/backups → 201 {backup: {...}} — creates a full-runtime
  /// backup now. Synchronous; returns the finished record.
  Future<Map<String, dynamic>> createBackup() {
    return rawRequest('POST', _objUrl('admin/backups'));
  }

  /// GET /admin/backups/{id}/download → the archive bytes. Returns the raw
  /// bytes plus the server-suggested filename, or null on failure.
  Future<({List<int> bytes, String filename})?> downloadBackup(
    String id,
  ) async {
    final uri = Uri.parse(
      _objUrl('admin/backups/${_pathSegment(id)}/download'),
    );
    try {
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 90));
      _noteAuthResult(response.statusCode, _AuthMode.objectServer);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        var filename = 'backup-$id.tar.gz';
        final disposition = response.headers['content-disposition'];
        if (disposition != null) {
          final match = RegExp(
            'filename\\*?=(?:"([^"]+)"|([^;]+))',
          ).firstMatch(disposition);
          final captured = (match?.group(1) ?? match?.group(2))?.trim();
          if (captured != null && captured.isNotEmpty) filename = captured;
        }
        return (bytes: response.bodyBytes, filename: filename);
      }
      lastError = 'HTTP ${response.statusCode}';
    } catch (e) {
      lastError = 'Error: $e';
    }
    return null;
  }

  Future<Map<String, dynamic>?> getDaemonStatus() async {
    final result = await _getRaw(_objUrl('daemon/status'));
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> getDaemonSchedulerTasks() async {
    final result = await _getRaw(_objUrl('daemon/scheduler/tasks'));
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> getDaemonQueueMessages() async {
    final result = await _getRaw(_objUrl('daemon/queue/messages'));
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> getEventDeliveries({int limit = 100}) async {
    final result = await _getRaw(_objUrl('events/deliveries?limit=$limit'));
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> getPermissionsStatus() async {
    final result = await _getRaw(_objUrl('permissions/status'));
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> getPermissionsPolicy() async {
    final result = await _getRaw(_objUrl('permissions/policy'));
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> listAdminChanges({
    int limit = 100,
    int offset = 0,
    String? kind,
    String? objectId,
    String? collection,
    String? recordId,
    String? packageId,
    String? file,
  }) async {
    final params = <String, String>{'limit': '$limit', 'offset': '$offset'};
    void addParam(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) params[key] = trimmed;
    }

    addParam('kind', kind);
    addParam('object_id', objectId);
    addParam('collection', collection);
    addParam('record_id', recordId);
    addParam('package_id', packageId);
    addParam('file', file);

    final query = Uri(queryParameters: params).query;
    final result = await _getRaw(_objUrl('admin/changes?$query'));
    return _asStringMap(result);
  }

  Future<List<dynamic>> listAdminIdentityAccounts() async {
    final result = await _getRaw(_objUrl('admin/identity/accounts'));
    return _listFromObjectInspection(result, const [
      'accounts',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<Map<String, dynamic>?> getAdminIdentityAccount(
    String accountId,
  ) async {
    final id = _pathSegment(accountId);
    final result = await _getRaw(_objUrl('admin/identity/accounts/$id'));
    return _mapFromObjectInspection(
      result,
      nestedKeys: const ['account', 'identity', 'detail'],
    );
  }

  Future<List<dynamic>> listAdminIdentityUsers({String? accountId}) async {
    final query = accountId == null || accountId.isEmpty
        ? ''
        : '?account_id=${Uri.encodeQueryComponent(accountId)}';
    final result = await _getRaw(_objUrl('admin/identity/users$query'));
    return _listFromObjectInspection(result, const [
      'users',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<Map<String, dynamic>?> getAdminIdentityUser(String userId) async {
    final id = _pathSegment(userId);
    final result = await _getRaw(_objUrl('admin/identity/users/$id'));
    return _mapFromObjectInspection(
      result,
      nestedKeys: const ['user', 'identity', 'detail'],
    );
  }

  Future<Map<String, dynamic>> setAdminUserPassword(
    String userId,
    String password,
  ) {
    final id = _pathSegment(userId);
    return rawRequest(
      'POST',
      _objUrl('admin/identity/users/$id/password'),
      data: {'password': password},
    );
  }

  Future<Map<String, dynamic>> removeAdminUserPassword(String userId) {
    final id = _pathSegment(userId);
    return rawRequest('DELETE', _objUrl('admin/identity/users/$id/password'));
  }

  Future<List<dynamic>> listAdminIdentitySessions() async {
    final result = await _getRaw(_objUrl('admin/identity/sessions'));
    return _listFromObjectInspection(result, const [
      'sessions',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<Map<String, dynamic>?> getAdminIdentitySession(
    String sessionId,
  ) async {
    final id = _pathSegment(sessionId);
    final result = await _getRaw(_objUrl('admin/identity/sessions/$id'));
    return _mapFromObjectInspection(
      result,
      nestedKeys: const ['session', 'identity', 'detail'],
    );
  }

  Future<Map<String, dynamic>?> getClusterInfo() async {
    final result = await _getRaw(_objUrl('cluster/info'));
    return result is Map<String, dynamic> ? result : null;
  }

  Future<dynamic> getClusterStations() async {
    return _getRaw(_objUrl('cluster/stations?format=json'));
  }

  // --- Objects ---

  Future<dynamic> _getFirstObjectInspection(List<String> paths) async {
    for (final path in paths) {
      final result = await _getRaw(_objUrl(path));
      if (result != null) return result;
    }
    return null;
  }

  String _pathSegment(String value) => Uri.encodeComponent(value);

  Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return null;
  }

  List<dynamic> _listFromObjectInspection(dynamic result, List<String> keys) {
    if (result is List) return result;
    final map = _asStringMap(result);
    if (map == null) return const [];
    for (final key in keys) {
      final value = map[key];
      if (value is List) return value;
    }
    return const [];
  }

  Map<String, dynamic>? _mapFromObjectInspection(
    dynamic result, {
    List<String> nestedKeys = const [],
  }) {
    final map = _asStringMap(result);
    if (map == null) return null;
    for (final key in nestedKeys) {
      final nested = _asStringMap(map[key]);
      if (nested != null) return nested;
    }
    return map;
  }

  String? _sourceFromObjectInspection(dynamic result) {
    if (result is String) return result;
    final map = _asStringMap(result);
    if (map == null) return null;
    for (final key in const ['source', 'code', 'content', 'text']) {
      final value = map[key];
      if (value is String) return value;
    }
    final object = _asStringMap(map['object']);
    if (object != null) {
      for (final key in const ['source', 'code', 'content', 'text']) {
        final value = object[key];
        if (value is String) return value;
      }
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  Future<List<dynamic>> listAdminObjects() async {
    final result = await _getFirstObjectInspection([
      'admin/objects',
      'admin/objects?format=json',
    ]);
    return _listFromObjectInspection(result, const [
      'objects',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<Map<String, dynamic>?> getAdminObjectMetadata(String objectId) async {
    final id = _pathSegment(objectId);
    final result = await _getFirstObjectInspection([
      'admin/objects/$id',
      'admin/objects/$id?metadata=true',
    ]);
    return _mapFromObjectInspection(
      result,
      nestedKeys: const ['object', 'metadata', 'status', 'detail'],
    );
  }

  Future<String?> getAdminObjectSource(String objectId) async {
    final id = _pathSegment(objectId);
    final result = await _getRaw(
      _objUrl('admin/objects/$id?source=true&format=json'),
    );
    return _sourceFromObjectInspection(result);
  }

  Future<Map<String, dynamic>?> getAdminObjectState(String objectId) async {
    final id = _pathSegment(objectId);
    final result = await _getRaw(_objUrl('admin/objects/$id?state=true'));
    return _mapFromObjectInspection(
      result,
      nestedKeys: const ['state', 'data'],
    );
  }

  Future<List<dynamic>> getAdminObjectLogs(
    String objectId, {
    int limit = 100,
  }) async {
    final id = _pathSegment(objectId);
    final result = await _getRaw(
      _objUrl('admin/objects/$id?logs=true&limit=$limit'),
    );
    return _listFromObjectInspection(result, const [
      'logs',
      'events',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<List<dynamic>> getAdminObjectVersions(
    String objectId, {
    int limit = 10,
  }) async {
    final id = _pathSegment(objectId);
    final result = await _getRaw(
      _objUrl('admin/objects/$id?versions=true&limit=$limit'),
    );
    return _listFromObjectInspection(result, const [
      'versions',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<dynamic> getAdminObjectVersion(String objectId, int version) async {
    final id = _pathSegment(objectId);
    return _getRaw(_objUrl('admin/objects/$id?version=$version'));
  }

  Future<List<dynamic>> getAdminObjectSourceChanges(
    String objectId, {
    int limit = 100,
  }) async {
    final id = _pathSegment(objectId);
    final result = await _getRaw(
      _objUrl('admin/objects/$id?source_changes=true&limit=$limit'),
    );
    return _listFromObjectInspection(result, const [
      'source_changes',
      'changes',
      'events',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<List<dynamic>> getAdminObjectChanges(
    String objectId, {
    int limit = 100,
  }) async {
    final id = _pathSegment(objectId);
    final result = await _getRaw(
      _objUrl('admin/objects/$id?changes=true&limit=$limit'),
    );
    return _listFromObjectInspection(result, const [
      'changes',
      'source_changes',
      'events',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<List<dynamic>> getAdminObjectFiles(String objectId) async {
    final id = _pathSegment(objectId);
    final result = await _getRaw(_objUrl('admin/objects/$id?files=true'));
    return _listFromObjectInspection(result, const [
      'files',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<Map<String, dynamic>> getAdminObjectFileContent(
    String objectId,
    String fileName,
  ) {
    final id = _pathSegment(objectId);
    final file = Uri.encodeQueryComponent(fileName);
    return rawRequest('GET', _objUrl('admin/objects/$id?file=$file'));
  }

  Future<List<dynamic>> listAdminCollections() async {
    final result = await _getRaw(_objUrl('admin/collections'));
    return _listFromObjectInspection(result, const [
      'collections',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<Map<String, dynamic>?> getAdminCollection(String collection) async {
    final name = _pathSegment(collection);
    final result = await _getRaw(_objUrl('admin/collections/$name'));
    return _mapFromObjectInspection(
      result,
      nestedKeys: const ['collection', 'metadata', 'detail'],
    );
  }

  Future<List<dynamic>> listAdminCollectionRecords(
    String collection, {
    int limit = 100,
  }) async {
    final name = _pathSegment(collection);
    final result = await _getRaw(
      _objUrl('admin/collections/$name/records?limit=$limit'),
    );
    return _listFromObjectInspection(result, const [
      'records',
      'items',
      'results',
      'rows',
    ]);
  }

  /// Global search across searchable collections (schemas with a `search`
  /// key opt in). Permission-aware server-side: denied collections are
  /// skipped, row filters and field redaction apply before matching.
  /// Returns {status, query, limit, results: {collection: [records]},
  /// total_count, warnings?} or null on failure.
  Future<Map<String, dynamic>?> globalSearch(
    String query, {
    int limit = 10,
    List<String>? collections,
  }) async {
    var url = 'api/search?q=${Uri.encodeQueryComponent(query)}&limit=$limit';
    if (collections != null && collections.isNotEmpty) {
      url += '&collections=${Uri.encodeQueryComponent(collections.join(","))}';
    }
    final result = await _getRaw(_objUrl(url));
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> getAdminCollectionRecord(
    String collection,
    String recordId,
  ) async {
    final name = _pathSegment(collection);
    final id = _pathSegment(recordId);
    final result = await _getRaw(
      _objUrl('admin/collections/$name/records/$id'),
    );
    return _mapFromObjectInspection(
      result,
      nestedKeys: const ['record', 'item', 'data', 'detail'],
    );
  }

  Future<List<dynamic>> listAdminCollectionChanges(
    String collection, {
    int limit = 100,
  }) async {
    final name = _pathSegment(collection);
    final result = await _getRaw(
      _objUrl('admin/collections/$name/changes?limit=$limit'),
    );
    return _listFromObjectInspection(result, const [
      'changes',
      'events',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<List<dynamic>> listAdminCollectionRecordChanges(
    String collection,
    String recordId, {
    int limit = 100,
  }) async {
    final name = _pathSegment(collection);
    final id = _pathSegment(recordId);
    final result = await _getRaw(
      _objUrl('admin/collections/$name/records/$id/changes?limit=$limit'),
    );
    return _listFromObjectInspection(result, const [
      'changes',
      'events',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<Map<String, dynamic>> createAdminCollectionRecord(
    String collection,
    Map<String, dynamic> record,
  ) {
    final name = _pathSegment(collection);
    return rawRequest(
      'POST',
      _objUrl('admin/collections/$name/records'),
      data: record,
    );
  }

  Future<Map<String, dynamic>> updateAdminCollectionRecord(
    String collection,
    String recordId,
    Map<String, dynamic> record,
  ) {
    final name = _pathSegment(collection);
    final id = _pathSegment(recordId);
    return rawRequest(
      'PUT',
      _objUrl('admin/collections/$name/records/$id'),
      data: record,
    );
  }

  Future<Map<String, dynamic>> deleteAdminCollectionRecord(
    String collection,
    String recordId,
  ) {
    final name = _pathSegment(collection);
    final id = _pathSegment(recordId);
    return rawRequest('DELETE', _objUrl('admin/collections/$name/records/$id'));
  }

  Future<List<dynamic>> listAdminSchemas() async {
    final result = await _getRaw(_objUrl('admin/schemas'));
    return _listFromObjectInspection(result, const [
      'schemas',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<Map<String, dynamic>?> getAdminSchema(String collection) async {
    final name = _pathSegment(collection);
    final result = await _getRaw(_objUrl('admin/schemas/$name'));
    return _mapFromObjectInspection(
      result,
      nestedKeys: const ['schema', 'metadata', 'detail'],
    );
  }

  Future<List<dynamic>> getAdminSchemaVersions(
    String collection, {
    int limit = 10,
  }) async {
    final name = _pathSegment(collection);
    final result = await _getRaw(
      _objUrl('admin/schemas/$name?versions=true&limit=$limit'),
    );
    return _listFromObjectInspection(result, const [
      'versions',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<dynamic> getAdminSchemaVersion(String collection, int version) async {
    final name = _pathSegment(collection);
    return _getRaw(_objUrl('admin/schemas/$name?version=$version'));
  }

  Future<Map<String, dynamic>> updateAdminSchema(
    String collection, {
    required Map<String, dynamic> schema,
    String? author,
    String? message,
  }) {
    final name = _pathSegment(collection);
    return rawRequest(
      'PUT',
      _objUrl('admin/schemas/$name'),
      data: {
        'schema': schema,
        if (author != null && author.trim().isNotEmpty) 'author': author,
        if (message != null && message.trim().isNotEmpty) 'message': message,
      },
    );
  }

  Future<Map<String, dynamic>> rollbackAdminSchema(
    String collection,
    int versionId,
  ) {
    final name = _pathSegment(collection);
    return rawRequest(
      'POST',
      _objUrl('admin/schemas/$name'),
      data: {'action': 'rollback', 'version_id': versionId},
    );
  }

  Future<Map<String, dynamic>?> listAdminFiles({
    int limit = 100,
    int offset = 0,
    String? objectId,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (objectId != null && objectId.isNotEmpty) 'object_id': objectId,
    };
    final query = Uri(queryParameters: params).query;
    final result = await _getRaw(_objUrl('admin/files?$query'));
    return result is Map<String, dynamic> ? result : _asStringMap(result);
  }

  Future<List<dynamic>> listAdminFilesForObject(String objectId) async {
    final id = _pathSegment(objectId);
    final result = await _getRaw(_objUrl('admin/files/$id'));
    return _listFromObjectInspection(result, const [
      'files',
      'items',
      'results',
      'records',
      'rows',
    ]);
  }

  Future<Map<String, dynamic>> getAdminFileContent(
    String objectId,
    String fileName,
  ) {
    final id = _pathSegment(objectId);
    final file = Uri.encodeQueryComponent(fileName);
    return rawRequest('GET', _objUrl('admin/files/$id?file=$file'));
  }

  Future<Map<String, dynamic>> createAdminFile(
    String objectId, {
    required String name,
    required String content,
  }) {
    final id = _pathSegment(objectId);
    return rawRequest(
      'POST',
      _objUrl('admin/files/$id'),
      data: {
        'name': name,
        'content_base64': base64Encode(utf8.encode(content)),
      },
    );
  }

  Future<Map<String, dynamic>> overwriteAdminFile(
    String objectId, {
    required String name,
    required String content,
  }) {
    final id = _pathSegment(objectId);
    return rawRequest(
      'PUT',
      _objUrl('admin/files/$id'),
      data: {
        'name': name,
        'content_base64': base64Encode(utf8.encode(content)),
      },
    );
  }

  Future<Map<String, dynamic>> deleteAdminFile(
    String objectId,
    String fileName,
  ) {
    final id = _pathSegment(objectId);
    final file = Uri.encodeQueryComponent(fileName);
    return rawRequest('DELETE', _objUrl('admin/files/$id?file=$file'));
  }

  Future<List<dynamic>> listObjects() async {
    final result = await _getRaw(_objUrl('objects?format=json'));
    if (result is Map && result.containsKey('objects'))
      return result['objects'] as List;
    if (result is List) return result;
    return [];
  }

  Future<dynamic> executeObject(
    String objectId, {
    String method = 'GET',
    Map<String, dynamic>? data,
  }) async {
    if (method == 'GET') {
      final result = await _getRaw(_objUrl('objects/$objectId?format=json'));
      // If the object returns HTML, format=json will error with raw_response containing the HTML
      if (result is Map &&
          result['error'] == 'Invalid JSON response from remote station' &&
          result.containsKey('raw_response')) {
        return {'_html': result['raw_response'], '_type': 'html'};
      }
      return result;
    }
    return _postRaw(_objUrl('objects/$objectId?format=json'), data ?? {});
  }

  Future<Map<String, dynamic>> executeAdminObject(
    String objectId, {
    String method = 'GET',
    Map<String, dynamic>? payload,
  }) {
    final id = _pathSegment(objectId);
    return rawRequest(
      'POST',
      _objUrl('admin/objects/$id/execute'),
      data: {'method': method, 'payload': payload ?? {}},
    );
  }

  /// Fetch raw HTML for an HTML-returning object (used for WebView rendering)
  Future<String?> getObjectHTML(String objectId) async {
    try {
      final response = await _client.get(
        Uri.parse(_objUrl('objects/$objectId')),
        headers: _headers(),
      );
      if (response.statusCode == 200) {
        final body = response.body;
        // If it looks like HTML, return it. If JSON, skip.
        if (body.trimLeft().startsWith('<')) return body;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getObjectSource(String objectId) async {
    final result = await _getRaw(
      _objUrl('objects/$objectId?source=true&format=json'),
    );
    if (result is Map<String, dynamic>) {
      return result['source'] as String? ?? result.toString();
    }
    if (result is String) return result;
    return null;
  }

  Future<Map<String, dynamic>?> getObjectState(String objectId) async {
    final result = await _getRaw(
      _objUrl('objects/$objectId?state=true&format=json'),
    );
    return result is Map<String, dynamic> ? result : null;
  }

  Future<List<dynamic>> getObjectLogs(String objectId, {int limit = 50}) async {
    final result = await _getRaw(
      _objUrl('objects/$objectId?logs=true&limit=$limit&format=json'),
    );
    if (result is List) return result;
    if (result is Map && result.containsKey('logs'))
      return result['logs'] as List;
    return [];
  }

  Future<Map<String, dynamic>?> getObjectMetadata(String objectId) async {
    final result = await _getRaw(
      _objUrl('objects/$objectId?metadata=true&format=json'),
    );
    return result is Map<String, dynamic> ? result : null;
  }

  Future<List<dynamic>> getObjectVersions(String objectId) async {
    final result = await _getRaw(
      _objUrl('objects/$objectId?versions=true&format=json'),
    );
    if (result is List) return result;
    if (result is Map && result.containsKey('versions'))
      return result['versions'] as List;
    return [];
  }

  Future<dynamic> getObjectVersion(String objectId, int version) async {
    return _getRaw(_objUrl('objects/$objectId?version=$version&format=json'));
  }

  Future<List<dynamic>> getObjectFiles(String objectId) async {
    final result = await _getRaw(
      _objUrl('objects/$objectId?files=true&format=json'),
    );
    if (result is List) return result;
    if (result is Map && result.containsKey('files'))
      return result['files'] as List;
    return [];
  }

  Future<dynamic> createObject(
    String name,
    String code, {
    String? description,
  }) async {
    return _postRaw(_objUrl('admin/objects'), {
      'name': name,
      'code': code,
      if (description != null) 'description': description,
    });
  }

  Future<dynamic> updateObjectSource(String objectId, String code) async {
    final id = _pathSegment(objectId);
    return _putRaw(_objUrl('admin/objects/$id?source=true'), {'code': code});
  }

  Future<bool> deleteObject(String objectId) async {
    return _deleteRaw(_objUrl('objects/$objectId'));
  }

  Future<dynamic> rollbackObject(String objectId, int toVersion) async {
    return _postRaw(_objUrl('objects/$objectId'), {
      'action': 'rollback',
      'to': toVersion,
    });
  }

  // --- New OSS object-server dogfood routes ---

  Future<Map<String, dynamic>?> getSession() async {
    final result = await _getRaw(_objUrl('identity/session'));
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> getSchema(String collection) async {
    final result = await _getRaw(_objUrl('schemas/$collection'));
    return result is Map<String, dynamic> ? result : null;
  }

  Future<List<dynamic>> listProbeRecords() async {
    final result = await _getRaw(_objUrl('collections/dbbasic_probe/records'));
    return _listFromResult(result, preferredKey: 'records');
  }

  Future<Map<String, dynamic>?> createProbeRecord(
    Map<String, dynamic> data,
  ) async {
    final result = await _postRaw(
      _objUrl('collections/dbbasic_probe/records'),
      data,
    );
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> updateProbeRecord(
    String id,
    Map<String, dynamic> data,
  ) async {
    final result = await _putRaw(
      _objUrl('collections/dbbasic_probe/records/${Uri.encodeComponent(id)}'),
      data,
    );
    return result is Map<String, dynamic> ? result : null;
  }

  Future<bool> deleteProbeRecord(String id) async {
    return _deleteRaw(
      _objUrl('collections/dbbasic_probe/records/${Uri.encodeComponent(id)}'),
    );
  }

  Future<List<dynamic>> listProbeChanges() async {
    final result = await _getRaw(_objUrl('collections/dbbasic_probe/changes'));
    return _listFromResult(result, preferredKey: 'changes');
  }

  Future<List<dynamic>> listProbeRecordChanges(String id) async {
    final result = await _getRaw(
      _objUrl(
        'collections/dbbasic_probe/records/${Uri.encodeComponent(id)}/changes',
      ),
    );
    return _listFromResult(result, preferredKey: 'changes');
  }

  List<dynamic> _listFromResult(
    dynamic result, {
    required String preferredKey,
  }) {
    if (result is List) return result;
    if (result is Map) {
      final preferred = result[preferredKey];
      if (preferred is List) return preferred;
      final results = result['results'];
      if (results is List) return results;
      final items = result['items'];
      if (items is List) return items;
    }
    return [];
  }

  // =====================================================================
  // PLATFORM API (optional — askrobots.com collections)
  // =====================================================================

  Future<List<dynamic>> _platformList(
    String collection, {
    int limit = 50,
  }) async {
    if (!hasPlatform) return [];
    final result = await _getRaw(
      _platUrl('$collection/?limit=$limit'),
      authMode: _AuthMode.platform,
    );
    if (result is Map && result.containsKey('results'))
      return result['results'] as List;
    if (result is List) return result;
    return [];
  }

  Future<Map<String, dynamic>?> _platformGet(
    String collection,
    String id,
  ) async {
    if (!hasPlatform) return null;
    final result = await _getRaw(
      _platUrl('$collection/$id/'),
      authMode: _AuthMode.platform,
    );
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> _platformCreate(
    String collection,
    Map<String, dynamic> data,
  ) async {
    if (!hasPlatform) return null;
    final result = await _postRaw(
      _platUrl('$collection/'),
      data,
      authMode: _AuthMode.platform,
    );
    return result is Map<String, dynamic> ? result : null;
  }

  // Public create for any collection
  Future<Map<String, dynamic>?> create(
    String collection,
    Map<String, dynamic> data,
  ) async {
    return _platformCreate(collection, data);
  }

  // Update (PATCH) an existing record
  Future<Map<String, dynamic>?> update(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (!hasPlatform) return null;
    try {
      final response = await _client.patch(
        Uri.parse(_platUrl('$collection/$id/')),
        headers: _headers(authMode: _AuthMode.platform),
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        lastError = null;
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      lastError = 'HTTP ${response.statusCode}: ${response.body}';
    } catch (e) {
      lastError = 'Error: $e';
    }
    return null;
  }

  // Delete a record
  Future<bool> delete(String collection, String id) async {
    if (!hasPlatform) return false;
    return _deleteRaw(
      _platUrl('$collection/$id/'),
      authMode: _AuthMode.platform,
    );
  }

  // Count (fetches 1 record just to get the count)
  Future<int> platformCount(String collection) async {
    if (!hasPlatform) return 0;
    final result = await _getRaw(
      _platUrl('$collection/?limit=1'),
      authMode: _AuthMode.platform,
    );
    if (result is Map && result.containsKey('count'))
      return result['count'] as int? ?? 0;
    return 0;
  }

  // Collections
  Future<List<dynamic>> listContacts({int limit = 50}) =>
      _platformList('contacts', limit: limit);
  Future<List<dynamic>> listProjects({int limit = 50}) =>
      _platformList('projects', limit: limit);
  Future<List<dynamic>> listTasks({int limit = 50}) =>
      _platformList('tasks', limit: limit);
  Future<List<dynamic>> listInvoices({int limit = 50}) =>
      _platformList('invoices', limit: limit);
  Future<List<dynamic>> listOrders({int limit = 50}) =>
      _platformList('orders', limit: limit);
  Future<List<dynamic>> listProducts({int limit = 50}) =>
      _platformList('products', limit: limit);
  Future<List<dynamic>> listArticles({int limit = 50}) =>
      _platformList('articles', limit: limit);
  Future<List<dynamic>> listFiles({int limit = 50}) =>
      _platformList('files', limit: limit);

  Future<Map<String, dynamic>?> getContact(String id) =>
      _platformGet('contacts', id);
  Future<Map<String, dynamic>?> getProject(String id) =>
      _platformGet('projects', id);
  Future<Map<String, dynamic>?> getTask(String id) => _platformGet('tasks', id);

  // Search
  Future<Map<String, dynamic>?> search(String query) async {
    if (!hasPlatform) return null;
    final result = await _getRaw(
      _platUrl('search/?q=${Uri.encodeComponent(query)}'),
      authMode: _AuthMode.platform,
    );
    return result is Map<String, dynamic> ? result : null;
  }
}
