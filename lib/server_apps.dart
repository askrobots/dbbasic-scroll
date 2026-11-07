// Home's icon launcher: the server's own app switchboard (app-nav home.py:
// apps grouped as tiles, a "Needs you" band only when something is
// waiting) plus the shared icon tile that Home's VIEWS grid uses too.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'mockup.dart';
import 'server_ui.dart';
import 'view_renderer.dart';

class NavMenuCache {
  static Future<NavMenu?>? _pending;
  static String? _forUrl;

  static Future<NavMenu?> load({bool refresh = false}) {
    final url = ScrollAPI().objectServerUrl;
    if (refresh || _pending == null || _forUrl != url) {
      _forUrl = url;
      _pending = fetchNavMenu();
    }
    return _pending!;
  }
}

/// Grid (icons) or list (rows) for Home's tiles; remembered per viewer.
class HomeTileMode {
  static final ValueNotifier<bool> grid = ValueNotifier(true);
  static const _key = 'home_tiles_grid';
  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      grid.value = prefs.getBool(_key) ?? true;
    } catch (_) {}
  }

  static Future<void> set(bool value) async {
    grid.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }
}

/// Tells tiles below it whether Home is in grid mode.
class TileModeScope extends InheritedWidget {
  final bool grid;
  const TileModeScope({super.key, required this.grid, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TileModeScope>()?.grid ??
      false;

  @override
  bool updateShouldNotify(TileModeScope old) => old.grid != grid;
}

IconData iconForApp(String path, [String label = '']) {
  final key = path.split('/').where((s) => s.isNotEmpty).firstOrNull ?? '';
  return switch (key) {
    'shell' => Icons.terminal,
    'talk' => Icons.mic_none,
    'notes' => Icons.sticky_note_2_outlined,
    'tasks' => Icons.check_circle_outline,
    'projects' => Icons.folder_outlined,
    'files' => Icons.insert_drive_file_outlined,
    'contacts' => Icons.people_outline,
    'links' => Icons.link,
    'calendar' => Icons.event_outlined,
    'templates' => Icons.description_outlined,
    'inbox' => Icons.inbox_outlined,
    'activity' => Icons.timeline,
    'articles' => Icons.article_outlined,
    'forum' => Icons.forum_outlined,
    'profile' => Icons.person_outline,
    'invoices' => Icons.receipt_long_outlined,
    'journals' => Icons.account_balance_outlined,
    'products' => Icons.inventory_2_outlined,
    'orders' => Icons.shopping_cart_outlined,
    'stock' => Icons.warehouse_outlined,
    'dashboard' => Icons.dashboard_outlined,
    'appearance' => Icons.palette_outlined,
    'flow' => Icons.account_tree_outlined,
    'urls' => Icons.public,
    'notifications' => Icons.notifications_none,
    'feed_posts' => Icons.dynamic_feed_outlined,
    'ai_usage' => Icons.paid_outlined,
    _ => Icons.apps,
  };
}

Color colorForApp(String key) {
  const palette = <Color>[
    Color(0xFF60A5FA),
    Color(0xFF34D399),
    Color(0xFFFBBF24),
    Color(0xFFA78BFA),
    Color(0xFF2DD4BF),
    Color(0xFFF87171),
    Color(0xFF818CF8),
    Color(0xFFFB923C),
  ];
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// One app/view as an icon tile. [mockup] = pink planned design;
/// [unavailable] = grey (exists, not on this connection).
class IconTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final String? tooltip;
  final String? badge;
  final bool badgeAlert;
  final VoidCallback? onTap;
  final bool mockup;
  final bool unavailable;
  final Color? color;

  const IconTile({
    super.key,
    required this.icon,
    required this.label,
    this.sub,
    this.tooltip,
    this.badge,
    this.badgeAlert = false,
    this.onTap,
    this.mockup = false,
    this.unavailable = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = unavailable ? Colors.white38 : (color ?? colorForApp(label));
    Widget tile = SizedBox(
      width: 124,
      height: 112,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: c, size: 26),
                    ),
                    if (badge != null && badge!.isNotEmpty)
                      Positioned(
                        top: -6,
                        right: -10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: badgeAlert
                                ? Colors.red
                                : const Color(0xFF3F3F4A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: unavailable ? Colors.white54 : null,
                  ),
                ),
                if (sub != null && sub!.isNotEmpty)
                  Text(
                    sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mockup) tile = MockupOutline(radius: 14, tagLeft: true, child: tile);
    final tip = tooltip ?? (unavailable ? sub : null);
    return tip == null || tip.isEmpty
        ? tile
        : Tooltip(
            message: tip,
            waitDuration: const Duration(milliseconds: 400),
            child: tile,
          );
  }
}

Widget _sectionLabel(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: Colors.white38,
      letterSpacing: 1,
    ),
  ),
);

/// NEEDS YOU (only when something is waiting) + the server's apps as icons.
class ServerAppsSection extends StatelessWidget {
  final ServerUiNav nav;
  const ServerAppsSection({super.key, required this.nav});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NavMenu?>(
      future: NavMenuCache.load(),
      builder: (context, snap) {
        final menu = snap.data;
        if (menu == null || menu.isEmpty) return const SizedBox.shrink();
        final groups = [
          for (final g in menu.groups)
            NavGroup(
              g.group,
              // "/" is the switchboard itself: Scroll's Home already is.
              g.entries.where((e) => e.path != '/').toList(),
            ),
        ].where((g) => g.entries.isNotEmpty).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (menu.attention.isNotEmpty) ...[
              _sectionLabel('NEEDS YOU'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final a in menu.attention)
                    IconTile(
                      icon: iconForApp(a.path, a.label),
                      label: a.label,
                      sub: a.detail,
                      badge: '${a.count}',
                      badgeAlert: a.severity == 'urgent',
                      onTap: () => nav.open(context, a.path, title: a.label),
                    ),
                ],
              ),
              const SizedBox(height: 28),
            ],
            _sectionLabel('APPS'),
            for (final g in groups) ...[
              if (groups.length > 1 && g.group.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    g.group,
                    style: const TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final e in g.entries)
                    IconTile(
                      icon: iconForApp(e.path, e.label),
                      label: e.label,
                      tooltip: e.blurb,
                      badge: (e.count ?? 0) > 0 ? '${e.count}' : null,
                      badgeAlert: e.severity == 'urgent',
                      onTap: () => nav.open(context, e.path, title: e.label),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}
