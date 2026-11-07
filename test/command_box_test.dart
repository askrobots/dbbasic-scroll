import 'package:dbbasic_scroll/command_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain text is not a command', () {
    final i = parseBoxInput('  open invoices ');
    expect(i.isCommand, isFalse);
    expect(i.arg, 'open invoices');
  });

  test('"/" alone lists every command', () {
    final i = parseBoxInput('/');
    expect(i.isCommand, isTrue);
    expect(i.token, '');
    expect(matchBoxCommands(i.token), boxCommands);
  });

  test('a partial word matches by prefix first, then contains', () {
    expect(matchBoxCommands('no').map((c) => c.name), ['note']);
    expect(matchBoxCommands('t').first.name, 'task');
    expect(matchBoxCommands('ind').map((c) => c.name), ['find']);
    expect(matchBoxCommands('zzz'), isEmpty);
  });

  test('command word + argument', () {
    final i = parseBoxInput('/Note  buy milk today ');
    expect(i.command?.name, 'note');
    expect(i.hasArgPart, isTrue);
    expect(i.arg, 'buy milk today');
    final bare = parseBoxInput('/note');
    expect(bare.command?.name, 'note');
    expect(bare.hasArgPart, isFalse);
  });

  test('create payloads match what the web shell sends', () {
    BoxCommand c(String n) => boxCommands.firstWhere((x) => x.name == n);
    expect(boxCreatePayload(c('note'), 'hi'), {
      'content': 'hi',
      'is_public': 'false',
    });
    expect(boxCreatePayload(c('task'), 'do it'), {'title': 'do it'});
    expect(boxCreatePayload(c('project'), 'Alpha'), {'name': 'Alpha'});
    expect(boxCreatePayload(c('link'), 'https://a.example'), {
      'url': 'https://a.example',
      'title': 'https://a.example',
    });
    expect(boxCreatePayload(c('link'), 'https://a.example  A site'), {
      'url': 'https://a.example',
      'title': 'A site',
    });
  });

  test('no payload carries an owner: the server stamps it', () {
    for (final c in boxCommands.where((c) => c.collection != null)) {
      expect(boxCreatePayload(c, 'x').containsKey('owner_id'), isFalse);
    }
  });
}
