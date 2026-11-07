import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbbasic_scroll/server_profiles.dart';

ServerProfile _profile(String url, {String name = 'p', String token = 't'}) =>
    ServerProfile(
      id: ServerProfile.idForUrl(url),
      name: name,
      objectServerUrl: ServerProfile.normaliseUrl(url),
      token: token,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('empty store lists nothing', () async {
    expect(await ServerProfileStore().list(), isEmpty);
    expect(await ServerProfileStore().activeId(), isNull);
  });

  test(
    'upsert adds, then replaces the same server instead of duplicating',
    () async {
      final store = ServerProfileStore();
      await store.upsert(_profile('https://object.dbbasic.com', name: 'Prod'));
      await store.upsert(
        _profile(
          'https://object.dbbasic.com/',
          name: 'Production',
          token: 'new',
        ),
      );
      final list = await store.list();
      expect(list, hasLength(1));
      expect(list.single.name, 'Production');
      expect(list.single.token, 'new');
    },
  );

  test('two servers coexist and the last upserted is active', () async {
    final store = ServerProfileStore();
    final prod = _profile('https://object.dbbasic.com', name: 'Prod');
    final vm = _profile('http://127.0.0.1:18001', name: 'nc VM');
    await store.upsert(prod);
    await store.upsert(vm);
    expect((await store.list()).map((p) => p.name), ['Prod', 'nc VM']);
    expect(await store.activeId(), vm.id);
  });

  test('remove drops the profile and clears active if it was active', () async {
    final store = ServerProfileStore();
    final vm = _profile('http://127.0.0.1:18001');
    await store.upsert(vm);
    await store.remove(vm.id);
    expect(await store.list(), isEmpty);
    expect(await store.activeId(), isNull);
  });

  test('corrupt stored data yields an empty list, not an exception', () async {
    SharedPreferences.setMockInitialValues({'server_profiles': '{not json'});
    expect(await ServerProfileStore().list(), isEmpty);
  });

  test('toString never includes the token', () {
    expect(
      _profile('https://x.example', token: 'SECRET').toString(),
      isNot(contains('SECRET')),
    );
  });
}
