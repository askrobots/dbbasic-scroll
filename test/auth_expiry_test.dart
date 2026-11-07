import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbbasic_scroll/api.dart';

void main() {
  group('httpFailure', () {
    test('401 reads as locked, not as a bare status code', () {
      final text = httpFailure(401);
      expect(text, contains('Locked'));
      expect(text, contains('admin token'));
    });

    test('403 explains disabled/not permitted', () {
      expect(httpFailure(403), contains('Not enabled or not permitted'));
    });

    test('other statuses and transport errors stay plain', () {
      expect(httpFailure(500), 'HTTP 500');
      expect(httpFailure(null, 'SocketException'), 'HTTP SocketException');
      expect(httpFailure(null), 'HTTP ?');
    });
  });

  // Expectations mirror what the real object server did (desk commit
  // 6707021, permission enforcement on), measured in the local sandbox.
  group('classifyAuthFailure', () {
    const base = 'http://127.0.0.1:18001';
    AuthSignal c(int status, String path, CredentialKind kind) =>
        classifyAuthFailure(status, '$base/$path', kind);

    test('successes and other errors are never auth signals', () {
      for (final kind in CredentialKind.values) {
        expect(c(200, 'admin/status', kind), AuthSignal.none);
        expect(c(404, 'collections/x/records', kind), AuthSignal.none);
        expect(c(500, 'daemon/status', kind), AuthSignal.none);
      }
    });

    test('API key: admin-gate 401 is "locked", never "expired"', () {
      const k = CredentialKind.apiKey;
      expect(c(401, 'admin/status', k), AuthSignal.locked);
      expect(c(401, 'daemon/status', k), AuthSignal.locked);
      // /identity/session is 401 for every API key, valid or not.
      expect(c(401, 'identity/session', k), AuthSignal.locked);
      expect(c(403, 'collections/notes/records', k), AuthSignal.none);
    });

    test(
      'admin token: a 401 anywhere but /identity/session means it is dead',
      () {
        const k = CredentialKind.adminToken;
        expect(c(401, 'admin/status', k), AuthSignal.expired);
        expect(c(401, 'collections/x/records', k), AuthSignal.expired);
        expect(c(401, 'identity/session', k), AuthSignal.none);
        expect(c(403, 'packages/x/install', k), AuthSignal.none); // feature off
      },
    );

    test('session: expiry shows as 403 on collections, so ask the server', () {
      const k = CredentialKind.session;
      expect(
        c(403, 'collections/notifications/records?limit=1', k),
        AuthSignal.probeSession,
      );
      expect(c(401, 'admin/status', k), AuthSignal.probeSession);
      expect(c(401, 'identity/session', k), AuthSignal.expired);
      expect(c(403, 'identity/session', k), AuthSignal.none);
    });
  });

  group('saved connections from before credential_kind existed', () {
    test('inferCredentialKind', () {
      expect(inferCredentialKind(token: 'dbk_abc'), CredentialKind.apiKey);
      expect(
        inferCredentialKind(token: 'xyz', sessionUserId: 'dan'),
        CredentialKind.session,
      );
      expect(inferCredentialKind(token: 'xyz'), CredentialKind.adminToken);
      expect(
        inferCredentialKind(stored: 'session', token: 'dbk_abc'),
        CredentialKind.session,
      );
      expect(
        inferCredentialKind(stored: 'bogus', token: 'dbk_abc'),
        CredentialKind.apiKey,
      );
    });

    test(
      'relaunch with an old saved API-key connection loads as apiKey',
      () async {
        SharedPreferences.setMockInitialValues({
          'object_server_url': 'http://127.0.0.1:18001/',
          'server_token': 'dbk_saved-before-the-upgrade',
        });
        await ScrollAPI().loadSavedConnection();
        expect(ScrollAPI().credentialKind, CredentialKind.apiKey);
        SharedPreferences.setMockInitialValues({});
        await ScrollAPI().disconnect();
      },
    );
  });
}
