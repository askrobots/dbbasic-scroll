// The top bar's command box. Same behaviour as the server's own web pages,
// in the AskRobots box layout:
//   * ⌘K / Ctrl-K focuses it from anywhere (the web /nav bar, app-theme
//     nav.py).
//   * Typing searches everything live over /api/search, results grouped
//     by collection (nav.py runSearch); a hit opens its page.
//   * "/" lists commands: Tab completes, ↑↓ pick, Enter runs, Esc closes.
//     The capture commands are the web shell's (app-shell shell.py: $ note,
//     . task, ^ link, ~ search), spelled as "/" commands.
//   * Enter with plain text asks the AI (the same shell conversation);
//     ⌘Enter is Find.
//
// Every command is an ordinary server request made with the signed-in
// user's credentials (record writes go through the server's permissions and
// owner stamping). Nothing is changed locally.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'server_ui.dart';
import 'view_renderer.dart';

enum BoxCommandKind { ask, find, create, open, help }

class BoxCommand {
  /// Without the slash.
  final String name;

  /// Argument placeholder shown after the name; '' = takes none.
  final String arg;
  final String help;
  final BoxCommandKind kind;

  /// create: the collection it writes to.
  final String? collection;

  /// open: the server path it opens.
  final String? path;

  const BoxCommand(
    this.name,
    this.arg,
    this.help,
    this.kind, {
    this.collection,
    this.path,
  });

  bool get takesArg => arg.isNotEmpty;
}

const boxCommands = <BoxCommand>[
  BoxCommand('ask', '<question>', 'ask the AI', BoxCommandKind.ask),
  BoxCommand('find', '<words>', 'search everything', BoxCommandKind.find),
  BoxCommand(
    'note',
    '<text>',
    'save a private note',
    BoxCommandKind.create,
    collection: 'notes',
  ),
  BoxCommand(
    'task',
    '<title>',
    'create a task',
    BoxCommandKind.create,
    collection: 'tasks',
  ),
  BoxCommand(
    'project',
    '<name>',
    'create a project',
    BoxCommandKind.create,
    collection: 'projects',
  ),
  BoxCommand(
    'link',
    '<url> [title]',
    'save a link',
    BoxCommandKind.create,
    collection: 'links',
  ),
  BoxCommand(
    'shell',
    '',
    'open the shell',
    BoxCommandKind.open,
    path: '/shell',
  ),
  BoxCommand('help', '', 'list every command', BoxCommandKind.help),
];

/// What's typed, read as a command (or not).
class BoxInput {
  final bool isCommand;

  /// The word after "/" (lowercased), '' when only "/" is typed.
  final String token;

  /// Exact match for [token], if any.
  final BoxCommand? command;

  /// Text after the command word (trimmed), or the whole text for plain
  /// input.
  final String arg;

  /// A space follows the command word (so the user is typing its argument).
  final bool hasArgPart;

  const BoxInput({
    required this.isCommand,
    required this.token,
    required this.command,
    required this.arg,
    required this.hasArgPart,
  });
}

BoxInput parseBoxInput(String text) {
  final t = text.trimLeft();
  if (!t.startsWith('/')) {
    return BoxInput(
      isCommand: false,
      token: '',
      command: null,
      arg: text.trim(),
      hasArgPart: false,
    );
  }
  final body = t.substring(1);
  final space = body.indexOf(RegExp(r'\s'));
  final word = (space < 0 ? body : body.substring(0, space)).toLowerCase();
  final rest = space < 0 ? '' : body.substring(space + 1).trim();
  BoxCommand? exact;
  for (final c in boxCommands) {
    if (c.name == word) exact = c;
  }
  return BoxInput(
    isCommand: true,
    token: word,
    command: exact,
    arg: rest,
    hasArgPart: space >= 0,
  );
}

/// Commands for a partly typed word: prefix matches first, then the rest
/// that contain it.
List<BoxCommand> matchBoxCommands(String token) {
  final t = token.toLowerCase();
  if (t.isEmpty) return boxCommands;
  return [
    ...boxCommands.where((c) => c.name.startsWith(t)),
    ...boxCommands.where((c) => !c.name.startsWith(t) && c.name.contains(t)),
  ];
}

/// The record a create command sends; the same fields the web shell sends.
/// The server stamps owner_id itself.
Map<String, dynamic> boxCreatePayload(BoxCommand c, String arg) {
  switch (c.collection) {
    case 'notes':
      return {'content': arg, 'is_public': 'false'};
    case 'links':
      final parts = arg.split(RegExp(r'\s+'));
      final url = parts.first;
      final title = parts.skip(1).join(' ').trim();
      return {'url': url, 'title': title.isEmpty ? url : title};
    case 'projects':
      return {'name': arg};
    default:
      return {'title': arg};
  }
}

// ---------------------------------------------------------------------------

class _Row {
  final IconData icon;
  final String title;
  final String? arg;
  final String? sub;
  final String? keyHint;
  final bool enabled;

  /// Text Tab puts in the box.
  final String? complete;
  final Future<void> Function()? run;
  final String? group;

  const _Row({
    required this.icon,
    required this.title,
    this.arg,
    this.sub,
    this.keyHint,
    this.enabled = true,
    this.complete,
    this.run,
    this.group,
  });
}

class CommandBox extends StatefulWidget {
  final void Function(String question) onAsk;
  final void Function(String words) onFind;
  final ServerUiNav nav;

  const CommandBox({
    super.key,
    required this.onAsk,
    required this.onFind,
    required this.nav,
  });

  @override
  State<CommandBox> createState() => _CommandBoxState();
}

class _CommandBoxState extends State<CommandBox> {
  final _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  Timer? _debounce;
  int _selected = 0;
  String _searchedFor = '';
  bool _searching = false;
  Map<String, List<Map<String, dynamic>>> _hits = const {};

  /// Which create commands this server has (collection readable), per URL.
  static final Map<String, Map<String, bool>> _availability = {};

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_globalKey);
    _focus.addListener(_focusChanged);
    _controller.addListener(_textChanged);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKey);
    _debounce?.cancel();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool _globalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final kb = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyK &&
        (kb.isMetaPressed || kb.isControlPressed) &&
        mounted) {
      _focus.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
      return true;
    }
    return false;
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      _portal.show();
      _checkAvailability();
      setState(() {});
    } else {
      // Let a tap on a row finish first.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_focus.hasFocus) _portal.hide();
      });
    }
  }

  void _textChanged() {
    _selected = 0;
    final input = parseBoxInput(_controller.text);
    _debounce?.cancel();
    if (!input.isCommand && input.arg.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 200), _runSearch);
    } else {
      _hits = const {};
      _searchedFor = '';
    }
    if (_focus.hasFocus && !_portal.isShowing) _portal.show();
    setState(() {});
  }

  Future<void> _checkAvailability() async {
    final url = ScrollAPI().objectServerUrl ?? '';
    if (_availability.containsKey(url)) return;
    final found = <String, bool>{};
    _availability[url] = found;
    for (final c in boxCommands) {
      final col = c.collection;
      if (col == null) continue;
      found[col] = await collectionReadable(col);
    }
    if (mounted) setState(() {});
  }

  bool _available(BoxCommand c) {
    final col = c.collection;
    if (col == null) return true;
    final known = _availability[ScrollAPI().objectServerUrl ?? ''];
    return known?[col] ?? true;
  }

  Future<void> _runSearch() async {
    final q = parseBoxInput(_controller.text).arg;
    if (q.isEmpty) return;
    setState(() => _searching = true);
    final res = await ScrollAPI().globalSearch(q, limit: 6);
    if (!mounted || parseBoxInput(_controller.text).arg != q) return;
    final out = <String, List<Map<String, dynamic>>>{};
    final raw = res?['results'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final rows = [
          for (final r in (e.value is List ? e.value as List : const []))
            if (r is Map) Map<String, dynamic>.from(r),
        ];
        if (rows.isNotEmpty) out['${e.key}'] = rows;
      }
    }
    setState(() {
      _hits = out;
      _searchedFor = q;
      _searching = false;
    });
  }

  void _close({bool clear = true}) {
    if (clear) _controller.clear();
    _focus.unfocus();
    _portal.hide();
  }

  void _snack(String text, {bool error = false, SnackBarAction? action}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade800 : null,
        action: action,
      ),
    );
  }

  Future<void> _runCommand(BoxCommand c, String arg) async {
    switch (c.kind) {
      case BoxCommandKind.help:
        _controller.value = const TextEditingValue(
          text: '/',
          selection: TextSelection.collapsed(offset: 1),
        );
        return;
      case BoxCommandKind.ask:
        if (arg.isEmpty) return _completeTo(c);
        _close();
        widget.onAsk(arg);
        return;
      case BoxCommandKind.find:
        if (arg.isEmpty) return _completeTo(c);
        _close();
        widget.onFind(arg);
        return;
      case BoxCommandKind.open:
        _close();
        await widget.nav.open(context, c.path!, title: titleCaseName(c.name));
        return;
      case BoxCommandKind.create:
        if (arg.isEmpty) return _completeTo(c);
        if (!_available(c)) {
          _snack(
            '${titleCaseName(c.collection!)} isn\'t installed on this '
            'server.',
            error: true,
          );
          return;
        }
        _close();
        final res = await ScrollAPI().createUserCollectionRecord(
          c.collection!,
          boxCreatePayload(c, arg),
        );
        if (!mounted) return;
        final status = res['status'];
        final body = res['body'];
        final ok = status is int && status >= 200 && status < 300;
        if (!ok) {
          final err = body is Map ? body['error'] : null;
          _snack(
            'Couldn\'t save the ${singular(c.collection!).toLowerCase()}: '
            '${err ?? 'HTTP $status'}',
            error: true,
          );
          return;
        }
        final record = body is Map && body['record'] is Map
            ? body['record'] as Map
            : null;
        final id = record?['id'];
        final label = '${singular(c.collection!)} saved';
        _snack(
          label,
          action: id == null
              ? null
              : SnackBarAction(
                  label: 'Open',
                  onPressed: () =>
                      widget.nav.open(context, '/${c.collection}/$id'),
                ),
        );
        return;
    }
  }

  void _completeTo(BoxCommand c) {
    final text = '/${c.name}${c.takesArg ? ' ' : ''}';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  String _hitPath(String collection, Map<String, dynamic> hit) {
    if (collection == 'nav_entries' && '${hit['path'] ?? ''}'.isNotEmpty) {
      return '${hit['path']}';
    }
    return '/$collection/${hit['id']}';
  }

  String _hitLabel(String collection, Map<String, dynamic> hit) {
    final text = rowLabel(hit);
    return text == '(untitled)' ? singular(collection) : text;
  }

  List<_Row> _rows() {
    final input = parseBoxInput(_controller.text);
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return [
        _Row(
          icon: Icons.terminal,
          title: '/',
          sub: 'all ${boxCommands.length} commands',
          complete: '/',
          group: 'QUICK START',
          run: () async => _runCommand(boxCommands.last, ''),
        ),
        for (final name in const ['note', 'task', 'find'])
          _commandRow(
            boxCommands.firstWhere((c) => c.name == name),
            'QUICK START',
          ),
      ];
    }
    if (input.isCommand) {
      final exact = input.command;
      if (exact != null && input.hasArgPart) {
        final row = _commandRow(exact, 'COMMAND');
        return [
          _Row(
            icon: row.icon,
            title: '/${exact.name}',
            arg: input.arg.isEmpty ? exact.arg : input.arg,
            sub: input.arg.isEmpty ? exact.help : _runLabel(exact),
            keyHint: input.arg.isEmpty && exact.takesArg ? null : 'Enter',
            enabled: row.enabled,
            group: 'COMMAND',
            run: () => _runCommand(exact, input.arg),
          ),
        ];
      }
      final matches = matchBoxCommands(input.token);
      if (matches.isEmpty) {
        return [
          const _Row(
            icon: Icons.help_outline,
            title: 'No such command',
            sub: 'type / to see them all',
            enabled: false,
            group: 'COMMANDS',
          ),
        ];
      }
      return [for (final c in matches) _commandRow(c, 'COMMANDS')];
    }
    return [
      _Row(
        icon: Icons.auto_awesome,
        title: 'Ask AI',
        arg: text,
        keyHint: 'Enter',
        group: 'DO',
        run: () async {
          _close();
          widget.onAsk(text);
        },
      ),
      _Row(
        icon: Icons.search,
        title: 'Find',
        arg: text,
        keyHint: '⌘↵',
        group: 'DO',
        run: () async {
          _close();
          widget.onFind(text);
        },
      ),
      for (final e in _hits.entries)
        for (final hit in e.value)
          _Row(
            icon: iconForCollection(e.key),
            title: _hitLabel(e.key, hit),
            group: titleCaseName(e.key).toUpperCase(),
            run: () async {
              _close();
              await widget.nav.open(
                context,
                _hitPath(e.key, hit),
                title: _hitLabel(e.key, hit),
              );
            },
          ),
    ];
  }

  String _runLabel(BoxCommand c) => switch (c.kind) {
    BoxCommandKind.create => 'saves to ${titleCaseName(c.collection!)}',
    BoxCommandKind.ask => 'asks the AI',
    BoxCommandKind.find => 'searches everything',
    _ => c.help,
  };

  _Row _commandRow(BoxCommand c, String group) {
    final ok = _available(c);
    return _Row(
      icon: switch (c.kind) {
        BoxCommandKind.ask => Icons.auto_awesome,
        BoxCommandKind.find => Icons.search,
        BoxCommandKind.open => Icons.open_in_new,
        BoxCommandKind.help => Icons.list,
        BoxCommandKind.create => iconForCollection(c.collection!),
      },
      title: '/${c.name}',
      arg: c.arg.isEmpty ? null : c.arg,
      sub: ok ? c.help : '${c.help} · not installed on this server',
      enabled: ok,
      complete: '/${c.name}${c.takesArg ? ' ' : ''}',
      group: group,
      run: () async {
        if (c.takesArg) {
          _completeTo(c);
        } else {
          await _runCommand(c, '');
        }
      },
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final rows = _rows();
    if (key == LogicalKeyboardKey.escape) {
      _close(clear: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && rows.isNotEmpty) {
      setState(() => _selected = (_selected + 1) % rows.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && rows.isNotEmpty) {
      setState(() => _selected = (_selected - 1 + rows.length) % rows.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      final i = _selected.clamp(0, rows.isEmpty ? 0 : rows.length - 1);
      final c = rows.isEmpty ? null : rows[i].complete;
      if (c != null) {
        _controller.value = TextEditingValue(
          text: c,
          selection: TextSelection.collapsed(offset: c.length),
        );
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final kb = HardwareKeyboard.instance;
      final text = _controller.text.trim();
      if (kb.isMetaPressed || kb.isControlPressed) {
        final input = parseBoxInput(text);
        final words = input.isCommand ? input.arg : text;
        if (words.isNotEmpty) {
          _close();
          widget.onFind(words);
        }
        return KeyEventResult.handled;
      }
      final input = parseBoxInput(text);
      if (input.isCommand && input.command != null && input.hasArgPart) {
        _runCommand(input.command!, input.arg);
        return KeyEventResult.handled;
      }
      if (rows.isNotEmpty) {
        final row = rows[_selected.clamp(0, rows.length - 1)];
        if (row.enabled && row.run != null) row.run!();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _dropdown(context),
        child: SizedBox(
          height: 36,
          child: TextField(
            key: const Key('command-box'),
            controller: _controller,
            focusNode: _focus,
            decoration: InputDecoration(
              hintText: 'Ask AI, find, or / for commands',
              hintStyle: const TextStyle(fontSize: 12, color: Colors.white24),
              prefixIcon: const Icon(
                Icons.search,
                size: 16,
                color: Colors.amber,
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _kbd('⌘K'),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.mic_outlined,
                      size: 16,
                      color: Colors.white24,
                    ),
                  ],
                ),
              ),
              suffixIconConstraints: const BoxConstraints(minHeight: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: scheme.primary),
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _kbd(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white24),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 10, color: Colors.white54),
    ),
  );

  Widget _dropdown(BuildContext context) {
    final rows = _rows();
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(280.0, 560.0);
    final input = parseBoxInput(_controller.text);
    final searchingNow =
        !input.isCommand && input.arg.isNotEmpty && _searchedFor != input.arg;
    String? lastGroup;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r.group != null && r.group != lastGroup) {
        lastGroup = r.group;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              r.group!,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: Colors.white38,
              ),
            ),
          ),
        );
      }
      children.add(_rowTile(r, i == _selected));
    }
    if (searchingNow || _searching) {
      children.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Searching…',
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ),
      );
    } else if (!input.isCommand &&
        input.arg.isNotEmpty &&
        _hits.isEmpty &&
        _searchedFor == input.arg) {
      children.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'No matches in your records',
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ),
      );
    }
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.bottomRight,
      followerAnchor: Alignment.topRight,
      offset: const Offset(0, 6),
      child: Align(
        alignment: Alignment.topRight,
        child: TextFieldTapRegion(
          child: Material(
            key: const Key('command-box-dropdown'),
            elevation: 12,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 6),
                        children: children,
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          _keyLegend('Tab', 'completes'),
                          _keyLegend('↑ ↓', 'pick'),
                          _keyLegend('Enter', 'Ask AI'),
                          _keyLegend('⌘↵', 'Find'),
                          _keyLegend('Esc', 'closes'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyLegend(String key, String what) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _kbd(key),
      const SizedBox(width: 5),
      Text(what, style: const TextStyle(fontSize: 11, color: Colors.white38)),
    ],
  );

  Widget _rowTile(_Row r, bool selected) {
    final dim = !r.enabled;
    return InkWell(
      canRequestFocus: false,
      onTap: r.enabled && r.run != null ? () => r.run!() : null,
      child: Container(
        color: selected ? Colors.white.withValues(alpha: 0.06) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            Icon(
              r.icon,
              size: 16,
              color: dim ? Colors.white24 : Colors.white54,
            ),
            const SizedBox(width: 12),
            Text(
              r.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: r.title.startsWith('/') ? 'monospace' : null,
                color: dim ? Colors.white38 : null,
              ),
            ),
            if (r.arg != null) ...[
              const SizedBox(width: 6),
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    r.arg!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: r.arg!.startsWith('<') ? 'monospace' : null,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ],
            if (r.sub != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: dim ? Colors.white24 : Colors.white38,
                  ),
                ),
              ),
            ] else
              const Spacer(),
            if (r.keyHint != null) _kbd(r.keyHint!),
          ],
        ),
      ),
    );
  }
}

IconData iconForCollection(String c) => switch (c) {
  'notes' => Icons.sticky_note_2_outlined,
  'tasks' => Icons.check_circle_outline,
  'projects' => Icons.folder_outlined,
  'links' => Icons.link,
  'files' => Icons.insert_drive_file_outlined,
  'contacts' => Icons.people_outline,
  'views' => Icons.web_asset_outlined,
  'nav_entries' => Icons.apps,
  'notifications' => Icons.notifications_none,
  _ => Icons.description_outlined,
};
