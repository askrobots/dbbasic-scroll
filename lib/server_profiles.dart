import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved object-server connection (e.g. "Production", "nc VM via tunnel").
///
/// Foundation for talking to several servers and, later, managing clusters.
/// Credentials are stored the same way the single saved connection already
/// is (SharedPreferences). Moving them to the macOS keychain is a follow-up.
class ServerProfile {
  final String id;
  final String name;
  final String objectServerUrl; // always normalised with a trailing slash
  final String? platformUrl;
  final String token;
  final String? sessionUserId;

  const ServerProfile({
    required this.id,
    required this.name,
    required this.objectServerUrl,
    required this.token,
    this.platformUrl,
    this.sessionUserId,
  });

  /// Stable id derived from the URL so reconnecting to the same server
  /// updates its profile instead of duplicating it.
  static String idForUrl(String url) => normaliseUrl(url).toLowerCase();

  static String normaliseUrl(String url) {
    final trimmed = url.trim();
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }

  ServerProfile copyWith({
    String? name,
    String? token,
    String? platformUrl,
    String? sessionUserId,
  }) => ServerProfile(
    id: id,
    name: name ?? this.name,
    objectServerUrl: objectServerUrl,
    platformUrl: platformUrl ?? this.platformUrl,
    token: token ?? this.token,
    sessionUserId: sessionUserId ?? this.sessionUserId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'object_server_url': objectServerUrl,
    if (platformUrl != null) 'platform_url': platformUrl,
    'token': token,
    if (sessionUserId != null) 'session_user_id': sessionUserId,
  };

  static ServerProfile? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final url = json['object_server_url'];
    final token = json['token'];
    if (id is! String ||
        name is! String ||
        url is! String ||
        token is! String) {
      return null;
    }
    return ServerProfile(
      id: id,
      name: name,
      objectServerUrl: url,
      token: token,
      platformUrl: json['platform_url'] as String?,
      sessionUserId: json['session_user_id'] as String?,
    );
  }

  @override
  String toString() => 'ServerProfile($name, $objectServerUrl)'; // never the token
}

class ServerProfileStore {
  static const _profilesKey = 'server_profiles';
  static const _activeKey = 'active_server_profile_id';

  Future<List<ServerProfile>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(ServerProfile.fromJson)
          .whereType<ServerProfile>()
          .toList();
    } catch (_) {
      return []; // corrupt data must not block the Connect screen
    }
  }

  Future<String?> activeId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  Future<void> _write(List<ServerProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  /// Insert or replace (matched by id) and mark it active.
  Future<void> upsert(ServerProfile profile, {bool makeActive = true}) async {
    final profiles = await list();
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await _write(profiles);
    if (makeActive) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeKey, profile.id);
    }
  }

  Future<void> remove(String id) async {
    final profiles = await list()
      ..removeWhere((p) => p.id == id);
    await _write(profiles);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_activeKey) == id) await prefs.remove(_activeKey);
  }

  Future<void> clearActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeKey);
  }
}
