// Contract test: every ScrollAPI write operation against the REAL object
// server code (the local desk sandbox, tool/desk_sandbox.sh). Skipped unless
// configured, so a normal `flutter test` never needs a server:
//
//   tool/desk_sandbox.sh start
//   tool/sandbox_contract.sh
//
// Plain `test()` (no widget binding) so real HTTP is allowed. Everything it
// creates is throwaway sandbox data and is cleaned up.

import 'package:dbbasic_scroll/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _url = String.fromEnvironment(
  'SANDBOX_URL',
  defaultValue: 'http://127.0.0.1:18101/',
);
const _apiKey = String.fromEnvironment('SANDBOX_API_KEY');
const _adminToken = String.fromEnvironment('SANDBOX_ADMIN_TOKEN');
const _password = String.fromEnvironment('SANDBOX_PASSWORD');
final _configured = _apiKey.isNotEmpty && _adminToken.isNotEmpty;

final api = ScrollAPI();

void log(String op, Map<String, dynamic> r) {
  final body = r['body'];
  final keys = body is Map ? body.keys.take(8).join(',') : body.runtimeType;
  // ignore: avoid_print
  print('CONTRACT ${op.padRight(34)} -> ${r['status'] ?? r['error']}  {$keys}');
}

int status(Map<String, dynamic> r) => r['status'] is int ? r['status'] : -1;

bool ok(Map<String, dynamic> r) => status(r) >= 200 && status(r) < 300;

/// The id of a created record, wherever the server puts it.
String? recordId(Map<String, dynamic> r) {
  final body = r['body'];
  if (body is! Map) return null;
  final rec = body['record'] is Map ? body['record'] as Map : body;
  return (rec['id'] ?? body['id'])?.toString();
}

Future<void> connectAs(String token) async {
  SharedPreferences.setMockInitialValues({});
  await api.disconnect();
  await api.setSessionUser(null);
  expect(
    await api.connect(objectServerUrl: _url, token: token),
    isTrue,
    reason: 'sandbox reachable at $_url',
  );
}

void main() {
  group('admin token', () {
    setUpAll(() async {
      if (_configured) await connectAs(_adminToken);
    });

    test('collection record create → update → read → delete', () async {
      if (!_configured) return markTestSkipped('sandbox not configured');
      final created = await api.createAdminCollectionRecord('notes', {
        'content': 'scroll contract test',
      });
      log('createAdminCollectionRecord', created);
      expect(ok(created), isTrue, reason: '${created['body']}');
      final id = recordId(created);
      expect(
        id,
        isNotNull,
        reason: 'Scroll needs the new id: ${created['body']}',
      );

      final updated = await api.updateAdminCollectionRecord('notes', id!, {
        'content': 'scroll contract test (edited)',
      });
      log('updateAdminCollectionRecord', updated);
      expect(ok(updated), isTrue, reason: '${updated['body']}');

      final read = await api.getAdminCollectionRecord('notes', id);
      final rec = read?['record'] is Map ? read!['record'] as Map : read;
      expect(rec?['content'], 'scroll contract test (edited)');
      expect(rec?['created_at'], isNotNull, reason: 'server stamps created_at');

      final deleted = await api.deleteAdminCollectionRecord('notes', id);
      log('deleteAdminCollectionRecord', deleted);
      expect(ok(deleted), isTrue, reason: '${deleted['body']}');
      expect(await api.getAdminCollectionRecord('notes', id), isNull);
    });

    test('schema edit → edit → rollback to the first edit → restore', () async {
      if (!_configured) return markTestSkipped('sandbox not configured');
      final original = await api.getAdminSchema('notes');
      expect(original, isNotNull);
      Future<Map<String, dynamic>> put(String description) {
        final edited = Map<String, dynamic>.from(original!)
          ..['description'] = description;
        return api.updateAdminSchema(
          'notes',
          schema: edited,
          author: 'scroll-contract',
          message: description,
        );
      }

      final a = await put('contract edit A');
      log('updateAdminSchema (A)', a);
      expect(ok(a), isTrue, reason: '${a['body']}');
      final b = await put('contract edit B');
      log('updateAdminSchema (B)', b);
      expect(ok(b), isTrue, reason: '${b['body']}');

      // Real shape: {version_id, timestamp, author, message, hash}. Each
      // version holds the schema AFTER that edit; the package-installed
      // original is never a version (restore it via the package instead).
      final versions = await api.getAdminSchemaVersions('notes');
      final byMessage = {
        for (final v in versions.whereType<Map>())
          v['message']: (v['version_id'] as num).toInt(),
      };
      expect(
        byMessage.keys,
        containsAll(['contract edit A', 'contract edit B']),
      );

      final rb = await api.rollbackAdminSchema(
        'notes',
        byMessage['contract edit A']!,
      );
      log('rollbackAdminSchema(to A)', rb);
      expect(ok(rb), isTrue, reason: '${rb['body']}');
      expect(
        (await api.getAdminSchema('notes'))?['description'],
        'contract edit A',
      );

      // Put the original back explicitly (rollback cannot reach it).
      final restore = await api.updateAdminSchema(
        'notes',
        schema: original!,
        author: 'scroll-contract',
        message: 'restore original',
      );
      expect(ok(restore), isTrue);
      expect(
        (await api.getAdminSchema('notes'))?['description'],
        original['description'],
      );
    });

    test('object file writes are refused cleanly (file_writes is off, as on '
        'the desk)', () async {
      if (!_configured) return markTestSkipped('sandbox not configured');
      final r = await api.createAdminFile(
        'site_home',
        name: 'scroll_contract.txt',
        content: 'x',
      );
      log('createAdminFile (disabled)', r);
      expect(status(r), inInclusiveRange(400, 499), reason: '${r['body']}');
      // ignore: avoid_print
      print('CONTRACT   Scroll would show: ${httpFailure(status(r))}');
    });

    test('package re-install (upgrade path) succeeds', () async {
      if (!_configured) return markTestSkipped('sandbox not configured');
      final r = await api.installPackage('app-notes');
      log('installPackage(app-notes)', r);
      expect(ok(r), isTrue, reason: '${r['body']}');
      final pkg = await api.getPackage('app-notes');
      expect(pkg, isNotNull);
    });

    test('backup create: success or a clean refusal, never a 5xx', () async {
      if (!_configured) return markTestSkipped('sandbox not configured');
      final r = await api.createBackup();
      log('createBackup', r);
      expect(status(r), lessThan(500), reason: '${r['body']}');
      final list = await api.listBackups();
      log('listBackups', list);
      expect(status(list), lessThan(500));
    });

    test('theme switch to the active theme (no-op) succeeds', () async {
      if (!_configured) return markTestSkipped('sandbox not configured');
      final info = await api.getStyleInfo();
      final active = info?['active']?.toString();
      expect(active, isNotNull, reason: '$info');
      final r = await api.setStyleTheme(active!);
      log('setStyleTheme($active)', r);
      expect(ok(r), isTrue, reason: '${r['body']}');
    });

    test('service key set → list shows names only → remove', () async {
      if (!_configured) return markTestSkipped('sandbox not configured');
      const secret = 'sk-contract-test-not-a-real-key';
      final set = await api.setServiceKey(
        'dan',
        service: 'openai',
        key: secret,
      );
      log('setServiceKey(dan, openai)', set);
      expect(ok(set), isTrue, reason: '${set['body']}');
      final list = await api.listServiceKeys('dan');
      log('listServiceKeys(dan)', list);
      expect(ok(list), isTrue);
      expect(
        '${list['body']}',
        isNot(contains(secret)),
        reason: 'the server must never return key material',
      );
      expect('${list['body']}', contains('openai'));
      final rm = await api.removeServiceKey('dan', 'openai');
      log('removeServiceKey(dan, openai)', rm);
      expect(ok(rm), isTrue, reason: '${rm['body']}');
    });

    test('admin set password (same value) keeps sign-in working', () async {
      if (!_configured || _password.isEmpty) {
        return markTestSkipped('sandbox not configured');
      }
      final r = await api.setAdminUserPassword('dan', _password);
      log('setAdminUserPassword(dan)', r);
      expect(ok(r), isTrue, reason: '${r['body']}');
      final login = await api.loginWithPassword(
        objectServerUrl: _url,
        userId: 'dan',
        password: _password,
      );
      expect(login['status'], inInclusiveRange(200, 299));
      expect(api.sessionTokenFromLogin(login), isNotNull);
      expect(api.sessionUserIdFromLogin(login), 'dan');
    });
  });

  group('API key (what Scroll on the desk uses)', () {
    setUpAll(() async {
      if (_configured) await connectAs(_apiKey);
    });

    test('user-level record create → put; admin routes refuse it', () async {
      if (!_configured) return markTestSkipped('sandbox not configured');
      expect(api.credentialKind, CredentialKind.apiKey);
      final created = await api.createUserCollectionRecord('notes', {
        'content': 'scroll contract test via API key',
      });
      log('createUserCollectionRecord', created);
      expect(ok(created), isTrue, reason: '${created['body']}');
      final id = recordId(created)!;
      final put = await api.putUserCollectionRecord('notes', id, {
        'content': 'edited via API key',
      });
      log('putUserCollectionRecord', put);
      expect(ok(put), isTrue, reason: '${put['body']}');

      // Real server: /admin/collections reads need the admin TOKEN (401 for
      // any key), but writes go through the permission policy, so an
      // admin-ROLE user's key may write (a non-admin user's key gets 403).
      final adminRead = await api.rawRequest(
        'GET',
        '${_url}admin/collections/notes/records?limit=1',
      );
      log('GET admin/collections/.. (key)', adminRead);
      expect(status(adminRead), 401);
      final adminWrite = await api.createAdminCollectionRecord('notes', {
        'content': 'admin-route write with an admin-role key',
      });
      log('POST admin/collections/.. (key)', adminWrite);
      expect(status(adminWrite), lessThan(500));
      expect(
        api.authRejected.value,
        isFalse,
        reason: 'neither a 401 nor a 403 here means the key is dead',
      );
      final adminWriteId = ok(adminWrite) ? recordId(adminWrite) : null;

      await connectAs(_adminToken); // clean up as admin
      final del = await api.deleteAdminCollectionRecord('notes', id);
      expect(ok(del), isTrue);
      if (adminWriteId != null) {
        await api.deleteAdminCollectionRecord('notes', adminWriteId);
      }
    });
  });
}
