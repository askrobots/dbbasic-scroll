import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'data.dart';
import 'realtime.dart';
import 'schema_form.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScrollApp());
}

class ScrollApp extends StatelessWidget {
  const ScrollApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DBBasic Scroll',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
      ),
      home: const ConnectScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin state — shared via InheritedWidget
// ---------------------------------------------------------------------------

class AdminState extends InheritedWidget {
  final bool adminMode;
  final VoidCallback onToggle;
  const AdminState({
    super.key,
    required this.adminMode,
    required this.onToggle,
    required super.child,
  });

  static AdminState? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AdminState>();
  }

  static bool isAdmin(BuildContext context) {
    return of(context)?.adminMode ?? false;
  }

  @override
  bool updateShouldNotify(AdminState oldWidget) =>
      adminMode != oldWidget.adminMode;
}

// ---------------------------------------------------------------------------
// AdminFieldOverlay — wraps any field to make it editable in admin mode
// ---------------------------------------------------------------------------

class AdminFieldOverlay extends StatefulWidget {
  final Widget child;
  final String fieldName;
  final String fieldType;
  final Map<String, String> rolePermissions; // role -> 'edit'|'read'|'hidden'
  final bool required;

  const AdminFieldOverlay({
    super.key,
    required this.child,
    required this.fieldName,
    this.fieldType = 'text',
    this.rolePermissions = const {},
    this.required = false,
  });

  @override
  State<AdminFieldOverlay> createState() => _AdminFieldOverlayState();
}

class _AdminFieldOverlayState extends State<AdminFieldOverlay> {
  bool _hovered = false;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin = AdminState.isAdmin(context);
    if (!isAdmin) return widget.child;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () => setState(() => _editing = !_editing),
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _editing
                          ? Colors.amber
                          : (_hovered
                                ? Colors.amber.withOpacity(0.7)
                                : Colors.amber.withOpacity(0.4)),
                      width: _editing ? 2 : 1.5,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    color: _hovered ? Colors.amber.withOpacity(0.03) : null,
                  ),
                  child: IgnorePointer(ignoring: true, child: widget.child),
                ),
                // Edit badge
                Positioned(
                  top: -8,
                  right: -4,
                  child: AnimatedOpacity(
                    opacity: _hovered || _editing ? 1.0 : 0.7,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit, size: 10, color: Colors.black87),
                          const SizedBox(width: 2),
                          Text(
                            widget.fieldName,
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Inline config panel
        if (_editing) _buildConfigPanel(context),
      ],
    );
  }

  Widget _buildConfigPanel(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings, size: 14, color: Colors.amber),
              const SizedBox(width: 6),
              Text(
                'FIELD CONFIG',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _editing = false),
                child: Icon(Icons.close, size: 16, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Field name
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: TextEditingController(text: widget.fieldName),
                    decoration: const InputDecoration(
                      labelText: 'Field Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Type
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: DropdownButtonFormField<String>(
                    value: widget.fieldType,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    style: const TextStyle(fontSize: 12),
                    items:
                        [
                              'text',
                              'number',
                              'currency',
                              'date',
                              'email',
                              'phone',
                              'dropdown',
                              'relation',
                              'computed',
                              'textarea',
                              'checkbox',
                              'file',
                            ]
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                  t,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (_) {},
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Required
              Row(
                children: [
                  Checkbox(
                    value: widget.required,
                    onChanged: (_) {},
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    'Required',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Role permissions
          Text(
            'ROLE PERMISSIONS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white38,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          _rolePermRow('admin', 'edit'),
          _rolePermRow('manager', 'edit'),
          _rolePermRow('sales', widget.rolePermissions['sales'] ?? 'edit'),
          _rolePermRow('viewer', 'read'),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () => setState(() => _editing = false),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Apply', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _editing = false),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {},
                icon: Icon(
                  Icons.delete_outline,
                  size: 14,
                  color: Colors.red[300],
                ),
                label: Text(
                  'Remove Field',
                  style: TextStyle(fontSize: 12, color: Colors.red[300]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rolePermRow(String role, String perm) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              role,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 8),
          _permRadio('edit', perm),
          _permRadio('read', perm),
          _permRadio('hidden', perm),
        ],
      ),
    );
  }

  Widget _permRadio(String value, String current) {
    final selected = value == current;
    final color = switch (value) {
      'edit' => Colors.green,
      'read' => Colors.orange,
      'hidden' => Colors.red,
      _ => Colors.grey,
    };
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () {},
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? color : Colors.white24,
                  width: 2,
                ),
                color: selected ? color.withOpacity(0.3) : Colors.transparent,
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: selected ? color : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connect Screen
// ---------------------------------------------------------------------------

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _objUrlController = TextEditingController();
  final _platUrlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _usePasswordLogin = false;
  bool _connecting = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _tryAutoConnect();
  }

  Future<void> _tryAutoConnect() async {
    final api = ScrollAPI();
    await api.loadSavedConnection();
    if (api.isConnected && mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
      return;
    }
    // Dev mode: load connection defaults from .env (see .env.example)
    try {
      final envFile = File('.env');
      if (await envFile.exists()) {
        final lines = await envFile.readAsLines();
        for (final line in lines) {
          if (line.startsWith('OBJECT_SERVER_URL=')) {
            final url = line.substring('OBJECT_SERVER_URL='.length).trim();
            if (url.isNotEmpty) _objUrlController.text = url;
          } else if (line.startsWith('PLATFORM_URL=')) {
            final url = line.substring('PLATFORM_URL='.length).trim();
            if (url.isNotEmpty) _platUrlController.text = url;
          } else if (line.startsWith('DBBASIC_ADMIN_TOKEN=')) {
            final token = line.substring('DBBASIC_ADMIN_TOKEN='.length).trim();
            if (token.isNotEmpty) _tokenController.text = token;
          } else if (line.startsWith('ASKROBOTS_TOKEN=')) {
            final token = line.substring('ASKROBOTS_TOKEN='.length).trim();
            if (token.isNotEmpty) _tokenController.text = token;
          }
          // Dev convenience: auto-import OpenAI key from .env if user hasn't set one yet
          if (line.startsWith('OPENAI_API_KEY=')) {
            final existing = await ScrollAPI().getOpenAIKey();
            if (existing == null || existing.isEmpty) {
              final key = line.substring('OPENAI_API_KEY='.length).trim();
              if (key.isNotEmpty) await ScrollAPI().setOpenAIKey(key);
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
      _status = _usePasswordLogin
          ? 'Signing in...'
          : 'Testing object server...';
    });
    var token = _tokenController.text.trim();
    if (_usePasswordLogin) {
      final api = ScrollAPI();
      final login = await api.loginWithPassword(
        objectServerUrl: _objUrlController.text.trim(),
        email: _emailController.text,
        password: _passwordController.text,
        label: 'scroll login',
      );
      if (!mounted) return;
      final status = login['status'];
      final sessionToken = api.sessionTokenFromLogin(login);
      if (status is! int || status < 200 || status >= 300) {
        final body = login['body'];
        final detail = body is Map && body['error'] != null
            ? body['error'].toString()
            : (login['error']?.toString() ?? 'HTTP $status');
        setState(() {
          _connecting = false;
          // 429 is the login lockout — the server message says it all.
          _error = status == 429 ? detail : 'Sign-in failed: $detail';
          _status = null;
        });
        return;
      }
      if (sessionToken == null) {
        setState(() {
          _connecting = false;
          _error = 'Sign-in succeeded but no session token was returned.';
          _status = null;
        });
        return;
      }
      token = sessionToken;
      await api.setSessionUser(api.sessionUserIdFromLogin(login));
      setState(() => _status = 'Signed in — connecting session...');
    } else {
      // Deployment-token connection: no user identity behind the token.
      await ScrollAPI().setSessionUser(null);
    }
    final success = await ScrollAPI().connect(
      objectServerUrl: _objUrlController.text.trim(),
      token: token,
      platformUrl: _platUrlController.text.trim().isEmpty
          ? null
          : _platUrlController.text.trim(),
    );
    if (!mounted) return;
    if (success) {
      final api = ScrollAPI();
      setState(() {
        _status =
            'Connected! Object server${api.hasPlatform ? " + platform" : ""}';
      });
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
    } else {
      setState(() {
        _connecting = false;
        _error = 'Could not connect. Check object server URL.';
        _status = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_stories,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'DBBasic Scroll',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Connect to your object server',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white54),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _objUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Object Server URL (required)',
                    prefixIcon: Icon(Icons.dns_outlined),
                    border: OutlineInputBorder(),
                    hintText: 'https://object.example.com',
                  ),
                  enabled: !_connecting,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _platUrlController,
                  decoration: InputDecoration(
                    labelText: 'Platform URL (optional)',
                    prefixIcon: Icon(Icons.cloud_outlined),
                    border: OutlineInputBorder(),
                    hintText: 'https://askrobots.com',
                    helperText:
                        'Adds collections: contacts, tasks, invoices, etc.',
                    helperStyle: TextStyle(fontSize: 11, color: Colors.white24),
                  ),
                  enabled: !_connecting,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Admin Token'),
                        icon: Icon(Icons.key_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Email + Password'),
                        icon: Icon(Icons.person_outline, size: 16),
                      ),
                    ],
                    selected: {_usePasswordLogin},
                    onSelectionChanged: _connecting
                        ? null
                        : (selection) => setState(
                            () => _usePasswordLogin = selection.first,
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_usePasswordLogin) ...[
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.alternate_email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    enabled: !_connecting,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.password_outlined),
                      border: const OutlineInputBorder(),
                      helperText:
                          'Signs in through POST /identity/session and uses the returned session token. Admin screens stay locked unless the server enables session admin gates.',
                      helperMaxLines: 3,
                      helperStyle: TextStyle(
                        fontSize: 11,
                        color: Colors.white24,
                      ),
                    ),
                    enabled: !_connecting,
                    onSubmitted: (_) => _connect(),
                  ),
                ] else
                  TextField(
                    controller: _tokenController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Bearer Token',
                      prefixIcon: const Icon(Icons.key_outlined),
                      border: const OutlineInputBorder(),
                      helperText:
                          'Use an admin token on staging; admin-role session tokens are only accepted when the server enables session admin gates.',
                      helperStyle: TextStyle(
                        fontSize: 11,
                        color: Colors.white24,
                      ),
                    ),
                    enabled: !_connecting,
                    onSubmitted: (_) => _connect(),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Colors.red[300], fontSize: 13),
                  ),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _status!,
                    style: TextStyle(color: Colors.green, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _connecting ? null : _connect,
                    icon: _connecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login),
                    label: Text(
                      _connecting
                          ? 'Connecting...'
                          : _usePasswordLogin
                          ? 'Sign In'
                          : 'Connect',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {},
                  child: const Text('Saved Connections'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main Shell
// ---------------------------------------------------------------------------

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final List<_Screen> _history = [];
  late _Screen _current;
  bool _adminMode = false;
  int _adminNav = -1; // -1 = no admin nav selected (show user content)

  final _adminNavItems = [
    _NavItem('Home', Icons.home_outlined),
    _NavItem('Search', Icons.search_outlined),
    _NavItem('Chat', Icons.forum_outlined),
    _NavItem('Collections', Icons.storage_outlined),
    _NavItem('Objects', Icons.code_outlined),
    _NavItem('Stations', Icons.dns_outlined),
    _NavItem('Users', Icons.manage_accounts_outlined),
    _NavItem('Permissions', Icons.security_outlined),
    _NavItem('API', Icons.api_outlined),
    _NavItem('SQL', Icons.terminal_outlined),
    _NavItem('Daemon', Icons.hub_outlined),
    _NavItem('Changes', Icons.manage_history_outlined),
    _NavItem('Ops', Icons.monitor_heart_outlined),
    _NavItem('Files', Icons.folder_outlined),
    _NavItem('Schema', Icons.schema_outlined),
    _NavItem('Diagram', Icons.account_tree_outlined),
    _NavItem('Packages', Icons.extension_outlined),
    _NavItem('Backup', Icons.backup_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _current = _Screen('Home', const SwitchboardView(), Icons.home);
    ScrollAPI().authRejected.addListener(_onAuthRejected);
    _loadData();
  }

  @override
  void dispose() {
    ScrollAPI().authRejected.removeListener(_onAuthRejected);
    super.dispose();
  }

  bool _authDialogShowing = false;

  void _onAuthRejected() {
    if (!mounted || !ScrollAPI().authRejected.value || _authDialogShowing) {
      return;
    }
    _authDialogShowing = true;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Session expired'),
          content: const Text(
            'The server rejected the saved credential (HTTP 401). '
            'Session tokens expire after their TTL — sign in again to '
            'continue. Screens will show stale or missing data until then.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Not Now'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                ScrollRealtime().shutdown();
                await ScrollAPI().disconnect();
                ScrollData().clear();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const ConnectScreen()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.login, size: 16),
              label: const Text('Sign In Again'),
            ),
          ],
        );
      },
    ).then((_) => _authDialogShowing = false);
  }

  Future<void> _loadData() async {
    await ScrollData().loadAll();
    if (mounted) setState(() {});
  }

  void _navigate(
    String title,
    Widget view, [
    IconData icon = Icons.arrow_forward,
  ]) {
    setState(() {
      _history.add(_current);
      _current = _Screen(title, view, icon);
      _adminNav = -1;
    });
  }

  void _goBack() {
    if (_history.isNotEmpty) {
      setState(() {
        _current = _history.removeLast();
        _adminNav = -1;
      });
    }
  }

  void _goHome() {
    setState(() {
      _history.clear();
      _current = _Screen('Home', const SwitchboardView(), Icons.home);
      _adminNav = -1;
    });
  }

  void _selectAdminNav(int index) {
    setState(() => _adminNav = index);
  }

  Widget _getAdminView() {
    return switch (_adminNav) {
      0 => SwitchboardView(onNavigate: _navigate),
      1 => const GlobalSearchView(),
      2 => const AIChatView(),
      3 => const CollectionBrowser(),
      4 => ObjectWorkspace(onNavigate: _navigate),
      5 => StationMonitor(onNavigate: _navigate),
      6 => const IdentityRegistryView(),
      7 => const PermissionsView(),
      8 => const APIExplorerView(),
      9 => const SQLQueryView(),
      10 => const DaemonStatusView(),
      11 => const ChangesView(),
      12 => const OpsEventsView(),
      13 => const FileManagerView(),
      14 => const SchemaEditorView(),
      15 => const DiagramView(),
      16 => const PackageManagerView(),
      17 => const BackupView(),
      _ => SwitchboardView(onNavigate: _navigate),
    };
  }

  @override
  Widget build(BuildContext context) {
    Widget currentView = _current.view;
    if (currentView is SwitchboardView) {
      currentView = SwitchboardView(onNavigate: _navigate);
    }

    // When admin nav is active, show that view instead
    final showAdminNav = _adminMode && _adminNav >= 0;
    final displayView = showAdminNav ? _getAdminView() : currentView;
    final displayTitle = showAdminNav
        ? _adminNavItems[_adminNav].label
        : _current.title;

    return AdminState(
      adminMode: _adminMode,
      onToggle: () => setState(() {
        _adminMode = !_adminMode;
        if (!_adminMode) _adminNav = -1;
      }),
      child: Scaffold(
        body: Column(
          children: [
            _AppBar(
              title: displayTitle,
              canGoBack: _history.isNotEmpty && !showAdminNav,
              adminMode: _adminMode,
              onBack: _goBack,
              onHome: _goHome,
              onAdminToggle: () => setState(() {
                _adminMode = !_adminMode;
                if (!_adminMode) _adminNav = -1;
              }),
              onNavigate: _navigate,
            ),
            // Admin editing banner when viewing user content in admin mode
            if (_adminMode && _adminNav < 0 && _current.title != 'Home')
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: Colors.amber.withOpacity(0.08),
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 14, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      'Admin Edit Mode — click any field to configure it',
                      style: TextStyle(fontSize: 12, color: Colors.amber),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {},
                      icon: Icon(Icons.add, size: 14),
                      label: Text('Add Field', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.amber,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {},
                      icon: Icon(Icons.save, size: 14),
                      label: Text(
                        'Save Layout',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.amber,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  if (_adminMode) _buildAdminNavRail(context),
                  if (_adminMode) Container(width: 1, color: Colors.white10),
                  Expanded(child: displayView),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _StatusBar(adminMode: _adminMode),
      ),
    );
  }

  Widget _buildAdminNavRail(BuildContext context) {
    return Container(
      width: 76,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: List.generate(_adminNavItems.length, (i) {
                final item = _adminNavItems[i];
                final selected = _adminNav == i;
                return InkWell(
                  onTap: () => _selectAdminNav(i),
                  child: Container(
                    width: 76,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(
                              context,
                            ).colorScheme.primaryContainer.withOpacity(0.3)
                          : null,
                      border: selected
                          ? Border(
                              left: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3,
                              ),
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          size: 18,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white38,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white54,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const Divider(indent: 12, endIndent: 12, height: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Colors.amber,
                ),
                tooltip: 'AI Assistant',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                onPressed: () =>
                    _navigate('Settings', const SettingsView(), Icons.settings),
                icon: const Icon(
                  Icons.settings_outlined,
                  size: 16,
                  color: Colors.white38,
                ),
                tooltip: 'Settings',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  _NavItem(this.label, this.icon);
}

class _Screen {
  final String title;
  final Widget view;
  final IconData icon;
  _Screen(this.title, this.view, this.icon);
}

// ---------------------------------------------------------------------------
// App Bar
// ---------------------------------------------------------------------------

class _AppBar extends StatelessWidget {
  final String title;
  final bool canGoBack;
  final bool adminMode;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final VoidCallback onAdminToggle;
  final void Function(String, Widget, [IconData]) onNavigate;

  const _AppBar({
    required this.title,
    required this.canGoBack,
    required this.adminMode,
    required this.onBack,
    required this.onHome,
    required this.onAdminToggle,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          if (canGoBack)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 20),
              tooltip: 'Back',
            ),
          if (canGoBack) const SizedBox(width: 4),
          InkWell(
            onTap: onHome,
            borderRadius: BorderRadius.circular(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_stories,
                  color: Theme.of(context).colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  title == 'Home' ? 'DBBasic Scroll' : title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const Spacer(),
          // AI bar
          SizedBox(
            width: 340,
            height: 36,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search... "deals" "invoices" "contact name"',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.white24),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 16,
                  color: Colors.amber,
                ),
                suffixIcon: const Icon(
                  Icons.mic_outlined,
                  size: 16,
                  color: Colors.white24,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.white12),
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onSubmitted: (query) {
                if (query.trim().isNotEmpty) {
                  onNavigate(
                    'Search: $query',
                    SearchResultsView(query: query, onNavigate: onNavigate),
                    Icons.search,
                  );
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          // Notification bell — mirrors the web app-shell bell over the
          // notifications collection.
          const _NotificationBell(),
          const SizedBox(width: 8),
          // Admin toggle
          _AdminToggle(active: adminMode, onTap: onAdminToggle),
        ],
      ),
    );
  }
}

/// App-bar notification bell reading the caller's `notifications` collection
/// (per-user rows with is_read). Polls on a timer today; when the server
/// ships websocket push it subscribes to the same stream instead.
class _NotificationBell extends StatefulWidget {
  const _NotificationBell();

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  List<Map<String, dynamic>> _notifications = [];
  Timer? _poll;
  VoidCallback? _rtDispose;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Live push when the websocket is up; a slow poll covers reconnect gaps.
    _rtDispose = ScrollRealtime().bind('notifications', _load);
    _poll = Timer.periodic(const Duration(seconds: 120), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _rtDispose?.call();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !ScrollAPI().isConnected) return;
    _loading = true;
    final result = await ScrollAPI().listUserCollectionRecords(
      'notifications',
      limit: 50,
    );
    _loading = false;
    if (!mounted) return;
    final body = result['body'];
    final rows = body is Map && body['records'] is List
        ? body['records'] as List
        : const [];
    final parsed = [
      for (final row in rows)
        if (row is Map)
          Map<String, dynamic>.from(
            row.map((k, v) => MapEntry(k.toString(), v)),
          ),
    ]..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    setState(() => _notifications = parsed);
  }

  int get _unread =>
      _notifications.where((n) => !schemaBoolIsTrue(n['is_read'])).length;

  String _text(Map<String, dynamic> n) {
    for (final key in const ['message', 'title', 'body', 'text', 'summary']) {
      final value = n[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return n['id']?.toString() ?? 'notification';
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    final id = n['id']?.toString();
    if (id == null || id.isEmpty || schemaBoolIsTrue(n['is_read'])) return;
    setState(() => n['is_read'] = 'true');
    await ScrollAPI().putUserCollectionRecord('notifications', id, {
      'is_read': 'true',
    });
  }

  Future<void> _markAllRead() async {
    final unread = _notifications
        .where((n) => !schemaBoolIsTrue(n['is_read']))
        .toList();
    setState(() {
      for (final n in unread) {
        n['is_read'] = 'true';
      }
    });
    for (final n in unread) {
      final id = n['id']?.toString();
      if (id != null && id.isNotEmpty) {
        await ScrollAPI().putUserCollectionRecord('notifications', id, {
          'is_read': 'true',
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _unread;
    return PopupMenuButton<void>(
      tooltip: 'Notifications',
      offset: const Offset(0, 44),
      constraints: const BoxConstraints(minWidth: 320, maxWidth: 380),
      onOpened: _load,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            unread > 0
                ? Icons.notifications
                : Icons.notifications_none_outlined,
            size: 20,
            color: unread > 0 ? Colors.amber : Colors.white54,
          ),
          if (unread > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      itemBuilder: (context) {
        if (_notifications.isEmpty) {
          return [
            const PopupMenuItem<void>(
              enabled: false,
              child: Text(
                'No notifications',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ),
          ];
        }
        return [
          PopupMenuItem<void>(
            enabled: false,
            height: 32,
            child: Row(
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white54,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                if (unread > 0)
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      _markAllRead();
                    },
                    child: Text(
                      'Mark all read',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final n in _notifications.take(15))
            PopupMenuItem<void>(
              onTap: () => _markRead(n),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 5, right: 8),
                    decoration: BoxDecoration(
                      color: schemaBoolIsTrue(n['is_read'])
                          ? Colors.transparent
                          : Colors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _text(n),
                      style: TextStyle(
                        fontSize: 12,
                        color: schemaBoolIsTrue(n['is_read'])
                            ? Colors.white54
                            : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
    );
  }
}

class _AdminToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _AdminToggle({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? 'Hide Admin Tools' : 'Show Admin Tools',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? Colors.amber.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? Colors.amber.withOpacity(0.4) : Colors.white12,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.admin_panel_settings,
                size: 16,
                color: active ? Colors.amber : Colors.white38,
              ),
              const SizedBox(width: 4),
              Text(
                'Admin',
                style: TextStyle(
                  fontSize: 12,
                  color: active ? Colors.amber : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// (Admin nav rail is now built into MainShell)

// ---------------------------------------------------------------------------
// Status Bar
// ---------------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  final bool adminMode;
  const _StatusBar({required this.adminMode});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Builder(
        builder: (context) {
          final d = ScrollData();
          final api = ScrollAPI();
          final authDead = api.authRejected.value;
          return Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: authDead ? Colors.amber : Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                authDead ? 'Session expired — sign in again' : 'Connected',
                style: TextStyle(
                  fontSize: 11,
                  color: authDead ? Colors.amber : Colors.white54,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                api.objectServerUrl ?? '',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
              if (api.hasPlatform) ...[
                const SizedBox(width: 8),
                Text(
                  '+ platform',
                  style: TextStyle(fontSize: 11, color: Colors.white24),
                ),
              ],
              const SizedBox(width: 12),
              Text(
                d.stationSummary,
                style: TextStyle(fontSize: 11, color: Colors.green),
              ),
              const Spacer(),
              if (adminMode)
                const Text(
                  'Admin Mode',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.amber,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (adminMode) const SizedBox(width: 12),
              if (d.hasAdminStatus) ...[
                Text(
                  '${d.inventoryCount('objects') ?? d.objectCount} objects',
                  style: TextStyle(fontSize: 11, color: Colors.white24),
                ),
                const SizedBox(width: 12),
                Text(
                  d.packageSummary,
                  style: TextStyle(fontSize: 11, color: Colors.white24),
                ),
              ] else ...[
                Text(
                  '${d.requestSummary} requests',
                  style: TextStyle(fontSize: 11, color: Colors.white24),
                ),
                const SizedBox(width: 12),
                Text(
                  '${d.errors} errors',
                  style: TextStyle(fontSize: 11, color: Colors.white24),
                ),
              ],
              const SizedBox(width: 12),
              ValueListenableBuilder<bool>(
                valueListenable: ScrollRealtime().connected,
                builder: (context, live, _) => Row(
                  children: [
                    Icon(
                      live ? Icons.bolt : Icons.bolt_outlined,
                      size: 12,
                      color: live ? Colors.green : Colors.white24,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      live ? 'Live' : 'Polling',
                      style: TextStyle(
                        fontSize: 11,
                        color: live ? Colors.green : Colors.white24,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                d.version.isNotEmpty ? d.version : 'v0.1.0',
                style: TextStyle(fontSize: 11, color: Colors.white24),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Switchboard — HOME
// ---------------------------------------------------------------------------

class SwitchboardView extends StatelessWidget {
  final void Function(String, Widget, [IconData])? onNavigate;
  const SwitchboardView({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final d = ScrollData();
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 17 ? 'Good afternoon' : 'Good evening');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(greeting, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'What would you like to do?',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 24),
          _OperatorStatusPanel(data: d, onNavigate: onNavigate),
          const SizedBox(height: 32),

          // Quick actions
          _sectionLabel('QUICK ACTIONS'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ActionCard(
                icon: Icons.person_add,
                label: 'New Contact',
                color: Colors.blue,
                onTap: () {
                  onNavigate?.call(
                    'New Contact',
                    FormView(
                      title: 'New Contact',
                      collection: 'contacts',
                      fields: const [
                        'First Name',
                        'Last Name',
                        'Email',
                        'Phone',
                        'Organization',
                        'Job Title',
                        'Notes',
                      ],
                      onNavigate: onNavigate,
                    ),
                    Icons.person_add,
                  );
                },
              ),
              _ActionCard(
                icon: Icons.add_task,
                label: 'New Task',
                color: Colors.green,
                onTap: () {
                  onNavigate?.call(
                    'New Task',
                    FormView(
                      title: 'New Task',
                      collection: 'tasks',
                      fields: const [
                        'Title',
                        'Description',
                        'Project',
                        'Urgency',
                        'Due Date',
                        'Assigned To',
                      ],
                      onNavigate: onNavigate,
                    ),
                    Icons.add_task,
                  );
                },
              ),
              _ActionCard(
                icon: Icons.shopping_cart,
                label: 'New Order',
                color: Colors.orange,
                onTap: () {
                  onNavigate?.call(
                    'New Order',
                    FormView(
                      title: 'New Order',
                      collection: 'orders',
                      fields: const [
                        'Customer',
                        'Product',
                        'Quantity',
                        'Unit Price',
                        'Shipping Address',
                        'Notes',
                      ],
                      onNavigate: onNavigate,
                    ),
                    Icons.shopping_cart,
                  );
                },
              ),
              _ActionCard(
                icon: Icons.receipt_long,
                label: 'New Invoice',
                color: Colors.purple,
                onTap: () {
                  onNavigate?.call(
                    'New Invoice',
                    const InvoiceFormView(),
                    Icons.receipt_long,
                  );
                },
              ),
              _ActionCard(
                icon: Icons.upload_file,
                label: 'Import Data',
                color: Colors.teal,
                onTap: () {},
              ),
              _ActionCard(
                icon: Icons.auto_awesome,
                label: 'Ask AI',
                color: Colors.amber,
                onTap: () {
                  onNavigate?.call(
                    'AI Create',
                    const AICreateView(),
                    Icons.auto_awesome,
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 36),

          // Views
          _sectionLabel('VIEWS'),
          const SizedBox(height: 12),
          _ViewTile(
            icon: Icons.people,
            title: 'Contacts',
            sub: '${d.contactCount} contacts',
            count: '${d.contactCount}',
            onTap: () {
              onNavigate?.call(
                'Contacts',
                LiveListView(
                  title: 'Contacts',
                  collection: 'contacts',
                  columns: const [
                    'Name',
                    'Email',
                    'Organization',
                    'Phone',
                    'Status',
                  ],
                  fields: const [
                    'full_name',
                    'email',
                    'organization',
                    'phone_numbers.0.number',
                    'lead_status',
                  ],
                  onNavigate: onNavigate,
                ),
                Icons.people,
              );
            },
          ),
          _ViewTile(
            icon: Icons.check_circle_outline,
            title: 'My Tasks',
            sub: '${d.taskCount} tasks',
            count: '${d.taskCount}',
            onTap: () {
              onNavigate?.call(
                'My Tasks',
                LiveListView(
                  title: 'My Tasks',
                  collection: 'tasks',
                  columns: const ['Title', 'Status', 'Urgency', 'Created'],
                  fields: const ['title', 'status', 'urgency', 'created_at'],
                  onNavigate: onNavigate,
                ),
                Icons.check_circle_outline,
              );
            },
          ),
          _ViewTile(
            icon: Icons.shopping_cart,
            title: 'Recent Orders',
            sub: '341 total, 18 this week',
            count: '341',
            onTap: () {
              onNavigate?.call(
                'Recent Orders',
                ListView2(
                  title: 'Orders',
                  columns: const [
                    'Order #',
                    'Customer',
                    'Items',
                    'Total',
                    'Status',
                  ],
                  rows: List.generate(
                    8,
                    (i) => [
                      'ORD-${2041 + i}',
                      [
                        'Acme Corp',
                        'TechStart',
                        'DataFlow',
                        'CloudNine',
                        'NetWorks',
                        'ByteSize',
                        'MidTech',
                        'CoreData',
                      ][i],
                      '${(i % 4) + 1} items',
                      '\$${((i + 1) * 299).toStringAsFixed(2)}',
                      i < 2 ? 'shipped' : (i < 5 ? 'processing' : 'pending'),
                    ],
                  ),
                  onNavigate: onNavigate,
                ),
                Icons.shopping_cart,
              );
            },
          ),
          _ViewTile(
            icon: Icons.receipt_long,
            title: 'Invoices',
            sub: '5 unpaid, 2 overdue',
            count: '5',
            alert: true,
            onTap: () {
              onNavigate?.call(
                'Invoices',
                ListView2(
                  title: 'Invoices',
                  columns: const [
                    'Invoice #',
                    'Customer',
                    'Amount',
                    'Due',
                    'Status',
                  ],
                  rows: [
                    [
                      'INV-1043',
                      'Acme Corp',
                      '\$2,118.45',
                      '2026-05-08',
                      'draft',
                    ],
                    [
                      'INV-1042',
                      'TechStart',
                      '\$890.00',
                      '2026-04-15',
                      'overdue',
                    ],
                    [
                      'INV-1041',
                      'DataFlow',
                      '\$3,450.00',
                      '2026-04-10',
                      'overdue',
                    ],
                    [
                      'INV-1040',
                      'CloudNine',
                      '\$1,200.00',
                      '2026-04-20',
                      'sent',
                    ],
                    ['INV-1039', 'NetWorks', '\$675.00', '2026-04-25', 'sent'],
                  ],
                  onNavigate: onNavigate,
                ),
                Icons.receipt_long,
              );
            },
          ),
          _ViewTile(
            icon: Icons.inventory_2,
            title: 'Products',
            sub: '89 active products',
            count: '89',
            onTap: () {
              onNavigate?.call(
                'Products',
                ListView2(
                  title: 'Products',
                  columns: const ['Name', 'SKU', 'Price', 'Stock', 'Category'],
                  rows: List.generate(
                    8,
                    (i) => [
                      [
                        'Web Hosting',
                        'SSL Certificate',
                        'Support Hours',
                        'Domain Name',
                        'Email Plan',
                        'CDN Service',
                        'Backup Plan',
                        'API Access',
                      ][i],
                      'SKU-${1001 + i}',
                      '\$${[299, 79, 150, 15, 49, 89, 39, 199][i]}.00',
                      '${[999, 245, 500, 999, 350, 180, 420, 275][i]}',
                      [
                        'hosting',
                        'security',
                        'support',
                        'domains',
                        'email',
                        'performance',
                        'backup',
                        'api',
                      ][i],
                    ],
                  ),
                  onNavigate: onNavigate,
                ),
                Icons.inventory_2,
              );
            },
          ),
          _ViewTile(
            icon: Icons.folder,
            title: 'Projects',
            sub: '${d.projectCount} projects',
            count: '${d.projectCount}',
            onTap: () {
              onNavigate?.call(
                'Projects',
                LiveListView(
                  title: 'Projects',
                  collection: 'projects',
                  columns: const ['Name', 'Status', 'Created'],
                  fields: const ['name', 'status', 'created_at'],
                  onNavigate: onNavigate,
                ),
                Icons.folder,
              );
            },
          ),

          const SizedBox(height: 36),

          // Reports
          _sectionLabel('REPORTS'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ReportCard(
                icon: Icons.trending_up,
                title: 'Monthly Sales',
                sub: 'By region, subtotaled',
                onTap: () {
                  onNavigate?.call(
                    'Monthly Sales Report',
                    const ReportView(),
                    Icons.assessment,
                  );
                },
              ),
              _ReportCard(
                icon: Icons.people_outline,
                title: 'Customer List',
                sub: 'With contact info',
                onTap: () {},
              ),
              _ReportCard(
                icon: Icons.warning_amber,
                title: 'Overdue Invoices',
                sub: 'Grouped by customer',
                onTap: () {},
              ),
              _ReportCard(
                icon: Icons.inventory,
                title: 'Inventory Report',
                sub: 'Stock levels & reorder',
                onTap: () {},
              ),
              _ReportCard(
                icon: Icons.label_outline,
                title: 'Shipping Labels',
                sub: 'Avery 5160 format',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.white38,
        letterSpacing: 1,
      ),
    );
  }
}

class _OperatorStatusPanel extends StatelessWidget {
  final ScrollData data;
  final void Function(String, Widget, [IconData])? onNavigate;

  const _OperatorStatusPanel({required this.data, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final status = data.adminHealthStatus;
    final healthy = status == 'ok';
    final inventory = data.inventoryEntries.take(6).toList();
    final packages = data.adminPackages.take(4).toList();
    final capabilities = data.capabilityEntries.take(5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.monitor_heart_outlined,
                size: 20,
                color: healthy ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                'Operator Status',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 10),
              _statusChip(
                data.hasAdminStatus ? status.toUpperCase() : 'PUBLIC HEALTH',
                healthy ? Colors.green : Colors.orange,
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  onNavigate?.call(
                    'API',
                    const APIExplorerView(),
                    Icons.api_outlined,
                  );
                },
                icon: const Icon(Icons.api_outlined, size: 16),
                label: const Text('API'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric(
                Icons.inventory_2_outlined,
                'Objects',
                _countText(data.inventoryCount('objects') ?? data.objectCount),
                Colors.blue,
              ),
              _metric(
                Icons.storage_outlined,
                'Collections',
                _countText(data.inventoryCount('collections')),
                Colors.teal,
              ),
              _metric(
                Icons.schema_outlined,
                'Schemas',
                _countText(data.inventoryCount('schemas')),
                Colors.purple,
              ),
              _metric(
                Icons.extension_outlined,
                'Packages',
                _countText(data.inventoryCount('packages')),
                Colors.amber,
              ),
              _metric(
                Icons.check_circle_outline,
                'Package State',
                data.packageSummary,
                Colors.green,
                wide: true,
              ),
            ],
          ),
          if (inventory.isNotEmpty ||
              packages.isNotEmpty ||
              capabilities.isNotEmpty) ...[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 900;
                final columns = [
                  _summaryColumn(
                    context,
                    'Inventory',
                    inventory.map((entry) {
                      return _labelValue(entry.key, entry.value.toString());
                    }).toList(),
                  ),
                  _summaryColumn(
                    context,
                    'Packages',
                    packages.map(_packageLine).toList(),
                  ),
                  _summaryColumn(
                    context,
                    'Capabilities',
                    capabilities.map(_capabilityLine).toList(),
                  ),
                ];
                if (narrow) {
                  return Column(
                    children: [
                      for (final column in columns) ...[
                        column,
                        if (column != columns.last) const SizedBox(height: 10),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final column in columns) ...[
                      Expanded(child: column),
                      if (column != columns.last) const SizedBox(width: 12),
                    ],
                  ],
                );
              },
            ),
          ],
          if (!data.hasAdminStatus) ...[
            const SizedBox(height: 12),
            Text(
              'Admin status is unavailable; showing the public health summary.',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(
    IconData icon,
    String label,
    String value,
    Color color, {
    bool wide = false,
  }) {
    return Container(
      width: wide ? 220 : 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryColumn(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          if (children.isEmpty)
            Text(
              'Not reported',
              style: TextStyle(fontSize: 12, color: Colors.white30),
            )
          else
            ...children,
        ],
      ),
    );
  }

  Widget _packageLine(Map<String, dynamic> package) {
    final name =
        package['name']?.toString() ??
        package['id']?.toString() ??
        package['package']?.toString() ??
        'package';
    final status =
        package['status']?.toString() ??
        package['state']?.toString() ??
        package['value']?.toString() ??
        (package['installed'] == true ? 'installed' : 'available');
    return _labelValue(name, status);
  }

  Widget _capabilityLine(MapEntry<String, dynamic> entry) {
    final value = entry.value;
    String status;
    String detail = '';
    if (value is Map) {
      final enabled = value['enabled'];
      if (enabled is bool) {
        status = enabled ? 'on' : 'off';
      } else {
        status = _valueLabel(enabled ?? value['status'] ?? value['value']);
      }
      final env = value['env']?.toString();
      if (env != null && env.isNotEmpty) detail = env;
    } else {
      status = _valueLabel(value);
    }
    return _labelValue(
      entry.key,
      detail.isEmpty ? status : '$status · $detail',
    );
  }

  Widget _labelValue(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              _titleCase(label),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: _valueColor(value),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _countText(int? value) => value == null ? '?' : value.toString();

  String _valueLabel(dynamic value) {
    if (value is bool) return value ? 'on' : 'off';
    if (value == null) return '?';
    return value.toString();
  }

  String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Color _valueColor(String value) {
    final normalized = value.toLowerCase();
    if (normalized == 'installed' ||
        normalized == 'on' ||
        normalized == 'true' ||
        normalized == 'ok') {
      return Colors.green;
    }
    if (normalized == 'off' ||
        normalized == 'false' ||
        normalized == 'disabled') {
      return Colors.orange;
    }
    return Colors.white70;
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 140,
        height: 90,
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 13, color: color)),
          ],
        ),
      ),
    );
  }
}

class _ViewTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final String count;
  final bool alert;
  final VoidCallback onTap;
  const _ViewTile({
    required this.icon,
    required this.title,
    required this.sub,
    required this.count,
    this.alert = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(icon, color: alert ? Colors.red[300] : Colors.white54),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          sub,
          style: TextStyle(fontSize: 12, color: Colors.white38),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: alert
                ? Colors.red.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: alert ? Colors.red[300] : Colors.white54,
            ),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _ReportCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Colors.white38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form View — single record editing (the dBASE EDIT mode)
// ---------------------------------------------------------------------------

class FormView extends StatefulWidget {
  final String title;
  final List<String> fields;
  final String? collection; // API collection name for saving
  final void Function(String, Widget, [IconData])? onNavigate;
  const FormView({
    super.key,
    required this.title,
    required this.fields,
    this.collection,
    this.onNavigate,
  });

  @override
  State<FormView> createState() => _FormViewState();
}

class _FormViewState extends State<FormView> {
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;
  String? _saveResult;

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      _controllers[field] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Map display field name -> API field name
  String _apiFieldName(String displayName) {
    return displayName.toLowerCase().replaceAll(' ', '_');
  }

  Future<void> _save() async {
    if (widget.collection == null) {
      setState(() => _saveResult = 'No collection configured');
      return;
    }
    setState(() {
      _saving = true;
      _saveResult = null;
    });
    final data = <String, dynamic>{};
    for (final entry in _controllers.entries) {
      final val = entry.value.text.trim();
      if (val.isEmpty) continue;

      final field = entry.key;
      final apiField = _apiFieldName(field);

      // Special handling for phone fields on contacts
      // Valid phone_type values: mobile, home, work, fax (not "primary")
      if (widget.collection == 'contacts' && field == 'Phone') {
        // Normalize unicode dashes to ASCII hyphen
        final cleaned = val.replaceAll(RegExp(r'[\u2010-\u2015\u2212]'), '-');
        data['phone_numbers'] = [
          {'phone_type': 'mobile', 'number': cleaned},
        ];
      } else {
        data[apiField] = val;
      }
    }
    final result = await ScrollAPI().create(widget.collection!, data);
    if (mounted) {
      setState(() {
        _saving = false;
        if (result != null) {
          _saveResult = 'Saved!';
        } else {
          final err = ScrollAPI().lastError ?? 'Unknown error';
          _saveResult = err.length > 80
              ? 'Failed: ${err.substring(0, 80)}...'
              : 'Failed: $err';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final fields = widget.fields;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Form header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Fill in the details below',
                          style: TextStyle(fontSize: 13, color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                  // Record navigation
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.chevron_left, size: 20),
                        tooltip: 'Previous Record',
                        visualDensity: VisualDensity.compact,
                      ),
                      const Text(
                        'New',
                        style: TextStyle(fontSize: 12, color: Colors.white38),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.chevron_right, size: 20),
                        tooltip: 'Next Record',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Form fields
              ...fields.map(
                (field) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildField(context, field),
                ),
              ),

              const SizedBox(height: 8),

              // Ownership info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 16, color: Colors.white38),
                    const SizedBox(width: 8),
                    Text(
                      'Owner: you',
                      style: TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                    const Spacer(),
                    Text(
                      'Access: REGISTERED',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save, size: 18),
                    label: Text(_saving ? 'Saving...' : 'Save'),
                  ),
                  if (_saveResult != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      _saveResult!,
                      style: TextStyle(
                        color: _saveResult == 'Saved!'
                            ? Colors.green
                            : Colors.red[300],
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _saving ? null : _aiFill,
                    icon: const Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: Colors.amber,
                    ),
                    label: const Text(
                      'AI Fill',
                      style: TextStyle(color: Colors.amber),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _aiFill() async {
    final key = await ScrollAPI().getOpenAIKey();
    if (key == null || key.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add your OpenAI API key in Settings first'),
        ),
      );
      return;
    }

    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI Fill'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Paste email, scanned text, business card, or any text and AI will extract the fields.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 8,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Paste text here...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Extract'),
          ),
        ],
      ),
    );

    if (text == null || text.trim().isEmpty) return;

    if (mounted)
      setState(() {
        _saving = true;
        _saveResult = 'Extracting...';
      });

    final fieldsList = widget.fields.join(', ');
    final result = await ScrollAPI().aiExtract(
      prompt:
          'Extract these fields from the input text into a JSON object. '
          'Field names should match exactly (lowercase with underscores): '
          '${widget.fields.map(_apiFieldName).join(', ')}. '
          'Original field labels: $fieldsList. '
          'Return JSON with these keys, using empty string for missing fields.',
      userText: text,
    );

    if (!mounted) return;
    if (result == null) {
      setState(() {
        _saving = false;
        _saveResult = 'AI extraction failed';
      });
      return;
    }

    // Fill controllers with extracted values
    for (final field in widget.fields) {
      final apiKey = _apiFieldName(field);
      final val = result[apiKey];
      if (val != null && val.toString().isNotEmpty) {
        _controllers[field]?.text = val.toString();
      }
    }
    setState(() {
      _saving = false;
      _saveResult = 'AI filled ${result.length} fields';
    });
  }

  Widget _buildField(BuildContext context, String label) {
    final controller = _controllers[label];
    if (label == 'Notes' || label == 'Description') {
      return TextField(
        controller: controller,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      );
    }
    if (label == 'Urgency') {
      return DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          'low',
          'normal',
          'high',
          'critical',
        ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) {
          if (v != null) controller?.text = v;
        },
      );
    }
    if (label.contains('Date')) {
      return TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
      );
    }
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List View — data grid accessed from switchboard
// ---------------------------------------------------------------------------

class ListView2 extends StatefulWidget {
  final String title;
  final List<String> columns;
  final List<List<String>> rows;
  final void Function(String, Widget, [IconData])? onNavigate;
  const ListView2({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    this.onNavigate,
  });

  @override
  State<ListView2> createState() => _ListView2State();
}

class _ListView2State extends State<ListView2> {
  int? _selectedRow;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Text(
                '${widget.rows.length} records',
                style: TextStyle(fontSize: 13, color: Colors.white38),
              ),
              const Spacer(),
              SizedBox(
                width: 200,
                height: 32,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search ${widget.title.toLowerCase()}...',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.filter_list, size: 18),
                tooltip: 'Filter',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.sort, size: 18),
                tooltip: 'Sort',
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'grid',
                    icon: Icon(Icons.view_list, size: 16),
                  ),
                  ButtonSegment(
                    value: 'form',
                    icon: Icon(Icons.dynamic_form, size: 16),
                  ),
                ],
                selected: const {'grid'},
                onSelectionChanged: (_) {},
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        // Grid
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 36,
                columnSpacing: 32,
                headingTextStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white54,
                ),
                dataTextStyle: const TextStyle(fontSize: 13),
                columns: widget.columns
                    .map((c) => DataColumn(label: Text(c)))
                    .toList(),
                rows: widget.rows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final row = entry.value;
                  return DataRow(
                    selected: _selectedRow == i,
                    onSelectChanged: (_) {
                      if (_selectedRow == i && widget.onNavigate != null) {
                        // Double-click / re-click opens detail
                        final record = Map.fromIterables(widget.columns, row);
                        widget.onNavigate!(
                          '${row[0]}',
                          RecordDetailView(
                            title: row.length > 1 ? row[0] : 'Record',
                            collection: widget.title,
                            fields: record,
                            onNavigate: widget.onNavigate,
                          ),
                          Icons.article,
                        );
                      }
                      setState(() => _selectedRow = i);
                    },
                    cells: row.map((cell) {
                      if ([
                        'hot',
                        'warm',
                        'cold',
                        'customer',
                        'high',
                        'critical',
                        'low',
                        'normal',
                        'open',
                        'in_progress',
                        'active',
                        'draft',
                      ].contains(cell)) {
                        return DataCell(_chip(cell));
                      }
                      if (cell == 'today') {
                        return DataCell(
                          Text(
                            cell,
                            style: TextStyle(
                              color: Colors.red[300],
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }
                      return DataCell(Text(cell));
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        // Pagination
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Text(
                'Page 1 of 1',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
              const Spacer(),
              Text(
                'Showing 1-${widget.rows.length} of ${widget.rows.length}',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String value) {
    final color = switch (value) {
      'hot' || 'critical' || 'overdue' => Colors.red,
      'warm' || 'high' || 'in_progress' => Colors.orange,
      'customer' || 'active' => Colors.green,
      'cold' || 'low' || 'draft' => Colors.grey,
      'open' || 'normal' => Colors.blue,
      _ => Colors.white54,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(value, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

// ---------------------------------------------------------------------------
// Report View
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Record Detail View — click a row to see full record
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// LiveListView — loads real data from API
// ---------------------------------------------------------------------------

class LiveListView extends StatefulWidget {
  final String title;
  final String collection; // API collection name
  final List<String> columns; // display column headers
  final List<String> fields; // API field names matching columns
  final void Function(String, Widget, [IconData])? onNavigate;

  const LiveListView({
    super.key,
    required this.title,
    required this.collection,
    required this.columns,
    required this.fields,
    this.onNavigate,
  });

  @override
  State<LiveListView> createState() => _LiveListViewState();
}

class _LiveListViewState extends State<LiveListView> {
  List<List<String>> _rows = [];
  List<Map<String, dynamic>> _rawData = [];
  bool _loading = true;
  int? _selectedRow;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final api = ScrollAPI();
    List<dynamic> results;
    switch (widget.collection) {
      case 'contacts':
        results = await api.listContacts(limit: 100);
        break;
      case 'tasks':
        results = await api.listTasks(limit: 100);
        break;
      case 'projects':
        results = await api.listProjects(limit: 100);
        break;
      case 'files':
        results = await api.listFiles(limit: 100);
        break;
      case 'articles':
        results = await api.listArticles(limit: 100);
        break;
      default:
        results = [];
    }
    _rawData = results.cast<Map<String, dynamic>>();
    _rows = _rawData.map((record) {
      return widget.fields.map((field) {
        if (field.contains('.')) {
          // Nested field like phone_numbers.0.number
          final parts = field.split('.');
          dynamic val = record;
          for (final p in parts) {
            if (val is Map)
              val = val[p];
            else if (val is List)
              val = val.isNotEmpty ? val[int.tryParse(p) ?? 0] : null;
            else
              break;
          }
          return val?.toString() ?? '';
        }
        final val = record[field];
        if (val is List) return val.isNotEmpty ? val.first.toString() : '';
        return val?.toString() ?? '';
      }).toList();
    }).toList();
    if (mounted) setState(() => _loading = false);
  }

  void _openDetail(int index) {
    if (index >= _rawData.length || widget.onNavigate == null) return;
    final record = _rawData[index];
    final title =
        (record['full_name'] ??
                record['title'] ??
                record['name'] ??
                record['id'] ??
                'Record')
            .toString();
    final stringFields = <String, String>{};
    record.forEach((k, v) {
      if (v == null) return;
      if (v is List || v is Map) {
        stringFields[k] = const JsonEncoder.withIndent('  ').convert(v);
      } else {
        stringFields[k] = v.toString();
      }
    });
    widget.onNavigate!(
      title,
      RecordDetailView(
        title: title,
        collection: widget.collection,
        fields: stringFields,
        onNavigate: widget.onNavigate,
      ),
      Icons.article,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              'No ${widget.collection} yet',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }
    return ListView2Plus(
      title: widget.title,
      columns: widget.columns,
      rows: _rows,
      onRowTap: _openDetail,
      onRefresh: _loadData,
    );
  }
}

// ---------------------------------------------------------------------------
// ListView2Plus — grid view with row-tap callback (passes index, not just record)
// ---------------------------------------------------------------------------

class ListView2Plus extends StatefulWidget {
  final String title;
  final List<String> columns;
  final List<List<String>> rows;
  final void Function(int) onRowTap;
  final VoidCallback? onRefresh;
  const ListView2Plus({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    required this.onRowTap,
    this.onRefresh,
  });

  @override
  State<ListView2Plus> createState() => _ListView2PlusState();
}

class _ListView2PlusState extends State<ListView2Plus> {
  int? _selectedRow;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? widget.rows
        : widget.rows
              .where(
                (r) => r.any(
                  (c) => c.toLowerCase().contains(_search.toLowerCase()),
                ),
              )
              .toList();

    return Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Text(
                '${filtered.length} records',
                style: TextStyle(fontSize: 13, color: Colors.white38),
              ),
              const SizedBox(width: 8),
              if (widget.onRefresh != null)
                IconButton(
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                ),
              const Spacer(),
              SizedBox(
                width: 240,
                height: 32,
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Filter ${widget.title.toLowerCase()}...',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 36,
                columnSpacing: 32,
                headingTextStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white54,
                ),
                dataTextStyle: const TextStyle(fontSize: 13),
                columns: widget.columns
                    .map((c) => DataColumn(label: Text(c)))
                    .toList(),
                rows: filtered.asMap().entries.map((entry) {
                  final i = entry.key;
                  final row = entry.value;
                  return DataRow(
                    selected: _selectedRow == i,
                    onSelectChanged: (_) {
                      final realIndex = widget.rows.indexOf(row);
                      if (_selectedRow == i) {
                        widget.onRowTap(realIndex);
                      }
                      setState(() => _selectedRow = i);
                    },
                    cells: row.map((cell) {
                      if ([
                        'hot',
                        'warm',
                        'cold',
                        'customer',
                        'high',
                        'critical',
                        'low',
                        'normal',
                        'open',
                        'in_progress',
                        'active',
                        'draft',
                        'completed',
                        'closed',
                      ].contains(cell)) {
                        return DataCell(_chip(cell));
                      }
                      return DataCell(
                        Text(
                          cell.length > 50
                              ? '${cell.substring(0, 50)}...'
                              : cell,
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String value) {
    final color = switch (value) {
      'hot' || 'critical' || 'overdue' => Colors.red,
      'warm' || 'high' || 'in_progress' => Colors.orange,
      'customer' || 'active' || 'completed' => Colors.green,
      'cold' || 'low' || 'draft' || 'closed' => Colors.grey,
      'open' || 'normal' => Colors.blue,
      _ => Colors.white54,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(value, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

// ---------------------------------------------------------------------------
// Record Detail View
// ---------------------------------------------------------------------------

class RecordDetailView extends StatefulWidget {
  final String title;
  final String collection;
  final Map<String, String> fields;
  final void Function(String, Widget, [IconData])? onNavigate;

  const RecordDetailView({
    super.key,
    required this.title,
    required this.collection,
    required this.fields,
    this.onNavigate,
  });

  @override
  State<RecordDetailView> createState() => _RecordDetailViewState();
}

class _RecordDetailViewState extends State<RecordDetailView> {
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _modified = {};
  bool _saving = false;
  bool _deleting = false;
  String? _message;

  // Fields that shouldn't be edited
  static const _readonlyFields = {
    'id',
    'created_at',
    'updated_at',
    'user',
    'full_name',
  };

  @override
  void initState() {
    super.initState();
    for (final entry in widget.fields.entries) {
      final controller = TextEditingController(text: entry.value);
      controller.addListener(() => _modified.add(entry.key));
      _controllers[entry.key] = controller;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _recordId => widget.fields['id'] ?? '';

  Future<void> _save() async {
    if (_recordId.isEmpty) {
      setState(() => _message = 'No record ID to update');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    final data = <String, dynamic>{};
    for (final key in _modified) {
      if (_readonlyFields.contains(key)) continue;
      final val = _controllers[key]?.text ?? '';

      // Special handling for complex fields
      if (key == 'phone_numbers' && widget.collection == 'contacts') {
        // Handle as list — try to parse as JSON, fall back to single phone string
        if (val.trim().isEmpty) {
          data[key] = [];
        } else if (val.trim().startsWith('[')) {
          // Looks like JSON, try to parse
          try {
            data[key] = jsonDecode(val);
          } catch (_) {
            // Fall back to single phone
            data[key] = [
              {'phone_type': 'mobile', 'number': val.trim()},
            ];
          }
        } else {
          // Plain phone string — wrap it
          data[key] = [
            {'phone_type': 'mobile', 'number': val.trim()},
          ];
        }
      } else if (key == 'tags' || key.endsWith('_ids')) {
        // List fields — try JSON parse
        try {
          data[key] = jsonDecode(val);
        } catch (_) {
          data[key] = [];
        }
      } else {
        data[key] = val;
      }
    }
    if (data.isEmpty) {
      setState(() {
        _saving = false;
        _message = 'No changes to save';
      });
      return;
    }
    final result = await ScrollAPI().update(widget.collection, _recordId, data);
    if (mounted) {
      setState(() {
        _saving = false;
        _message = result != null ? 'Saved!' : 'Failed to save';
        if (result != null) _modified.clear();
      });
    }
  }

  Future<void> _delete() async {
    if (_recordId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text('This cannot be undone. Delete ${widget.title}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _deleting = true;
      _message = null;
    });
    final success = await ScrollAPI().delete(widget.collection, _recordId);
    if (mounted) {
      if (success) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _deleting = false;
          _message = 'Failed to delete';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final collection = widget.collection;
    final fields = widget.fields;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          collection,
                          style: TextStyle(fontSize: 13, color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.chevron_left, size: 20),
                    tooltip: 'Previous',
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.chevron_right, size: 20),
                    tooltip: 'Next',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Record fields
              ...fields.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AdminFieldOverlay(
                    fieldName: entry.key,
                    fieldType: _guessType(entry.key, entry.value),
                    child: _buildFieldDisplay(context, entry.key, entry.value),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Related data
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RELATED DATA',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white38,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (collection == 'Contacts') ...[
                      _relatedTile(
                        Icons.receipt_long,
                        'Invoices',
                        '3 invoices (\$4,200 total)',
                      ),
                      _relatedTile(
                        Icons.shopping_cart,
                        'Orders',
                        '7 orders this year',
                      ),
                      _relatedTile(Icons.note, 'Notes', '2 notes'),
                      _relatedTile(Icons.attach_file, 'Files', '1 attachment'),
                    ] else if (collection == 'Orders') ...[
                      _relatedTile(
                        Icons.person,
                        'Customer',
                        'Acme Corp — Alice Chen',
                      ),
                      _relatedTile(Icons.inventory_2, 'Items', '3 line items'),
                      _relatedTile(
                        Icons.receipt_long,
                        'Invoice',
                        'INV-1043 (draft)',
                      ),
                    ] else ...[
                      _relatedTile(
                        Icons.link,
                        'Related Records',
                        'Click to load related data',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Ownership
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 16, color: Colors.white38),
                    const SizedBox(width: 8),
                    Text(
                      'Owner: admin',
                      style: TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Created: 2026-04-05',
                      style: TextStyle(fontSize: 12, color: Colors.white24),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Modified: 2026-04-08',
                      style: TextStyle(fontSize: 12, color: Colors.white24),
                    ),
                    const Spacer(),
                    Text(
                      'ROLE-BASED',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Actions
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: (_saving || _deleting) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save, size: 16),
                    label: Text(_saving ? 'Saving...' : 'Save'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      _message!,
                      style: TextStyle(
                        color: _message == 'Saved!'
                            ? Colors.green
                            : Colors.red[300],
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const Spacer(),
                  TextButton.icon(
                    onPressed: (_saving || _deleting) ? null : _delete,
                    icon: _deleting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.red,
                            ),
                          )
                        : Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: Colors.red[300],
                          ),
                    label: Text(
                      _deleting ? 'Deleting...' : 'Delete',
                      style: TextStyle(color: Colors.red[300]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldDisplay(BuildContext context, String label, String value) {
    final isStatus = [
      'hot',
      'warm',
      'cold',
      'customer',
      'active',
      'draft',
      'open',
      'in_progress',
      'shipped',
      'processing',
      'pending',
      'sent',
      'paid',
      'overdue',
      'cancelled',
    ].contains(value);

    if (isStatus) {
      final color = switch (value) {
        'hot' || 'overdue' || 'cancelled' => Colors.red,
        'warm' || 'processing' || 'in_progress' => Colors.orange,
        'customer' || 'active' || 'paid' || 'shipped' => Colors.green,
        'cold' || 'draft' || 'pending' => Colors.grey,
        'open' || 'sent' => Colors.blue,
        _ => Colors.white54,
      };
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(value, style: TextStyle(fontSize: 13, color: color)),
        ),
      );
    }

    final isReadonly = _readonlyFields.contains(label);
    final isMulti =
        value.length > 80 || label == 'notes' || label == 'description';

    return TextField(
      controller: _controllers[label],
      readOnly: isReadonly,
      maxLines: isMulti ? null : 1,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: isReadonly
            ? Icon(Icons.lock, size: 14, color: Colors.white24)
            : null,
        filled: isReadonly,
        fillColor: isReadonly ? Colors.white.withOpacity(0.02) : null,
      ),
    );
  }

  String _guessType(String key, String value) {
    if (key.contains('email')) return 'email';
    if (key.contains('phone')) return 'phone';
    if (key.contains('date') ||
        key.contains('Date') ||
        key.contains('Updated') ||
        key.contains('Created'))
      return 'date';
    if (key.contains('price') ||
        key.contains('Total') ||
        key.contains('Amount') ||
        value.startsWith('\$'))
      return 'currency';
    if (key.contains('status') || key.contains('Status')) return 'enum';
    return 'text';
  }

  Widget _relatedTile(IconData icon, String label, String detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: Colors.white38),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 8),
              Text(
                detail,
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, size: 16, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report View
// ---------------------------------------------------------------------------

class ReportView extends StatelessWidget {
  const ReportView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Report header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly Sales Report',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          'April 2026 — Grouped by Region',
                          style: TextStyle(fontSize: 13, color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('Export PDF'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Print'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Report groups
              _reportGroup(context, 'West Region', [
                ['Acme Corp', '42', '\$12,600'],
                ['TechStart', '28', '\$8,400'],
                ['CloudNine', '15', '\$4,500'],
              ], '\$25,500'),

              _reportGroup(context, 'East Region', [
                ['DataFlow', '38', '\$11,400'],
                ['NetWorks', '22', '\$6,600'],
                ['ByteSize', '19', '\$5,700'],
              ], '\$23,700'),

              _reportGroup(context, 'Central Region', [
                ['MidTech', '31', '\$9,300'],
                ['CoreData', '17', '\$5,100'],
              ], '\$14,400'),

              const SizedBox(height: 8),
              const Divider(thickness: 2),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'GRAND TOTAL',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '\$63,600',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[300],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportGroup(
    BuildContext context,
    String region,
    List<List<String>> rows,
    String subtotal,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            region,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        const SizedBox(height: 4),
        ...rows.map(
          (row) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(row[0], style: const TextStyle(fontSize: 13)),
                ),
                Expanded(
                  child: Text(
                    '${row[1]} units',
                    style: TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    row[2],
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              const Spacer(),
              Text(
                'Subtotal: $subtotal',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Station Monitor (admin)
// ---------------------------------------------------------------------------

/// Polyline sparklines for the Stations trend tiles. All series in one
/// paint share a vertical scale so p50/p95 (or cpu/mem) compare honestly.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.series});

  final List<(List<double>, Color)> series;

  @override
  void paint(Canvas canvas, Size size) {
    var min = double.infinity;
    var max = double.negativeInfinity;
    for (final (values, _) in series) {
      for (final value in values) {
        if (value < min) min = value;
        if (value > max) max = value;
      }
    }
    if (!min.isFinite || !max.isFinite) return;
    final span = (max - min) == 0 ? 1.0 : (max - min);

    for (final (values, color) in series) {
      if (values.length < 2) continue;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = i / (values.length - 1) * size.width;
        final y = size.height - ((values[i] - min) / span * size.height);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.series != series;
}

class StationMonitor extends StatefulWidget {
  final void Function(String, Widget, [IconData])? onNavigate;
  const StationMonitor({super.key, this.onNavigate});

  @override
  State<StationMonitor> createState() => _StationMonitorState();
}

class _StationMonitorState extends State<StationMonitor> {
  String? _selectedStation;
  bool _refreshing = false;
  String? _refreshError;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      await ScrollData().loadAll();
      // Metrics history snapshots (~1/min while traffic flows, survives
      // restarts) — feeds the trend sparklines.
      final health = await ScrollAPI().getHealth(metrics: true, history: true);
      final rows = health?['history'];
      _history = [
        if (rows is List)
          for (final row in rows)
            if (row is Map)
              Map<String, dynamic>.from(
                row.map((k, v) => MapEntry(k.toString(), v)),
              ),
      ];
    } catch (e) {
      _refreshError = e.toString();
    }
    if (mounted) {
      setState(() => _refreshing = false);
    }
  }

  List<double> _series(String key) => [
    for (final row in _history)
      if (row[key] is num) (row[key] as num).toDouble(),
  ];

  Widget _trendTile(
    BuildContext context,
    String title, {
    required Map<String, (List<double>, Color)> series,
  }) {
    final present = {
      for (final entry in series.entries)
        if (entry.value.$1.length >= 2) entry.key: entry.value,
    };
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ),
                for (final entry in present.entries)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '${entry.key} '
                      '${entry.value.$1.last.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: entry.value.$2,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              width: double.infinity,
              child: present.isEmpty
                  ? const Center(
                      child: Text('—', style: TextStyle(color: Colors.white24)),
                    )
                  : CustomPaint(
                      painter: _SparklinePainter(
                        series: [
                          for (final entry in present.values)
                            (entry.$1, entry.$2),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedStation != null) {
      return _buildStationDetail(context);
    }
    return _buildOverview(context);
  }

  Widget _buildOverview(BuildContext context) {
    final d = ScrollData();
    final h = d.health ?? {};
    final rt = d.responseTime ?? {};
    final status = h['status']?.toString() ?? '?';
    final requests = h.containsKey('requests') ? d.requestSummary : '?';
    final errorRate = h.containsKey('error_rate') ? '${d.errorRate}%' : '?';
    final threads = h['threads']?.toString() ?? '?';
    // Scale response times for bar height (max 40px)
    final rtAvg = (rt['avg'] as num?)?.toDouble() ?? 0;
    final rtP50 = (rt['p50'] as num?)?.toDouble() ?? 0;
    final rtP95 = (rt['p95'] as num?)?.toDouble() ?? 0;
    final rtP99 = (rt['p99'] as num?)?.toDouble() ?? 0;
    final rtMax = [
      rtAvg,
      rtP50,
      rtP95,
      rtP99,
      1.0,
    ].reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Server Health',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh health',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (_refreshError != null) ...[
            const SizedBox(height: 8),
            Text(
              'Refresh failed: $_refreshError',
              style: TextStyle(fontSize: 12, color: Colors.red[300]),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              _statBox(
                context,
                'Status',
                status,
                status == 'ok' ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 12),
              _statBox(
                context,
                'Uptime',
                d.uptime.isEmpty ? '?' : d.uptime,
                Colors.green,
              ),
              const SizedBox(width: 12),
              _statBox(context, 'Requests', requests, Colors.blue),
              const SizedBox(width: 12),
              _statBox(context, 'Threads', threads, Colors.white54),
              const SizedBox(width: 12),
              _statBox(
                context,
                'Error Rate',
                errorRate,
                errorRate == '0.0%' || errorRate == '0%'
                    ? Colors.green
                    : Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 24),

          Text(
            'Response Time (ms)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (rt.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                'Response-time metrics are not exposed by this /health response.',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            )
          else
            Container(
              height: 112,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _responseBar(
                    context,
                    'avg\n${rtAvg.toStringAsFixed(0)}ms',
                    (rtAvg / rtMax * 40).clamp(4, 40),
                    Colors.orange,
                  ),
                  _responseBar(
                    context,
                    'p50\n${rtP50.toStringAsFixed(0)}ms',
                    (rtP50 / rtMax * 40).clamp(4, 40),
                    Colors.red,
                  ),
                  _responseBar(
                    context,
                    'p95\n${rtP95.toStringAsFixed(0)}ms',
                    (rtP95 / rtMax * 40).clamp(4, 40),
                    Colors.red,
                  ),
                  _responseBar(
                    context,
                    'p99\n${rtP99.toStringAsFixed(0)}ms',
                    (rtP99 / rtMax * 40).clamp(4, 40),
                    Colors.red,
                  ),
                ],
              ),
            ),

          if (_history.length >= 2) ...[
            const SizedBox(height: 24),
            Text(
              'Trends (metrics history)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${_history.length} snapshots, ~1/min while traffic flows — '
              'survives restarts.',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _trendTile(
                  context,
                  'Response (ms)',
                  series: {
                    'p50': (_series('p50_ms'), Colors.orange),
                    'p95': (_series('p95_ms'), Colors.red),
                  },
                ),
                const SizedBox(width: 12),
                _trendTile(
                  context,
                  'Requests/sec',
                  series: {'rps': (_series('rps'), Colors.blue)},
                ),
                const SizedBox(width: 12),
                _trendTile(
                  context,
                  'CPU / Memory %',
                  series: {
                    'cpu': (_series('cpu_percent'), Colors.orange),
                    'mem': (_series('memory_used_percent'), Colors.purple),
                  },
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),
          Text(
            d.usingHealthFallback ? 'Server Node' : 'Cluster Stations (legacy)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            d.usingHealthFallback
                ? 'Cluster routes are not exposed by this object server. Showing the connected server from /health.'
                : 'Legacy cluster route data. This surface is optional for the OSS object server.',
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: d.stations.isEmpty
                ? [
                    Expanded(
                      child: Text(
                        'No station data',
                        style: TextStyle(color: Colors.white24),
                      ),
                    ),
                  ]
                : d.stations.map((s) {
                    final m = s['metrics'] as Map<String, dynamic>? ?? {};
                    final memTotal =
                        (m['memory_total_mb'] as num?)?.toDouble() ?? 0;
                    final diskUsed = (m['disk_used_gb'] as num?)?.toDouble();
                    final diskTotal = (m['disk_total_gb'] as num?)?.toDouble();
                    final objectCount = (m['object_count'] as num?)?.toInt();
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: s != d.stations.last ? 12 : 0,
                        ),
                        child: _stationCard(
                          context,
                          s['station_id']?.toString() ?? '?',
                          s['is_active'] == true,
                          cpu: (m['cpu_percent'] as num?)?.toInt() ?? -1,
                          mem: (m['memory_percent'] as num?)?.toInt() ?? -1,
                          disk: (m['disk_percent'] as num?)?.toInt() ?? -1,
                          cores: (m['cpu_count'] as num?)?.toInt() ?? 0,
                          ram: memTotal > 0
                              ? '${(memTotal / 1024).toStringAsFixed(1)}GB'
                              : '?',
                          diskInfo: diskTotal != null && diskTotal > 0
                              ? '${diskUsed?.toStringAsFixed(0) ?? '?'}/${diskTotal.toStringAsFixed(0)}GB'
                              : '?',
                          objects: objectCount?.toString() ?? '?',
                          version: s['version']?.toString() ?? '?',
                        ),
                      ),
                    );
                  }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStationDetail(BuildContext context) {
    final d = ScrollData();
    // Find the selected station's data
    final stationData = d.stations.firstWhere(
      (s) => s['station_id'] == _selectedStation,
      orElse: () => <String, dynamic>{},
    );
    final m = stationData['metrics'] as Map<String, dynamic>? ?? {};
    final h = d.health ?? {};
    final cpu = (m['cpu_percent'] as num?)?.toInt() ?? -1;
    final mem = (m['memory_percent'] as num?)?.toInt() ?? -1;
    final disk = (m['disk_percent'] as num?)?.toInt() ?? -1;
    final cores = (m['cpu_count'] as num?)?.toInt() ?? 0;
    final ramMb = (m['memory_total_mb'] as num?)?.toDouble() ?? 0;
    final objCount = (m['object_count'] as num?)?.toInt();
    final version = stationData['version']?.toString() ?? '?';
    final source = stationData['source']?.toString() ?? 'cluster';
    final ramLabel = ramMb > 0 ? '${(ramMb / 1024).toStringAsFixed(1)}GB' : '?';
    final coresLabel = cores > 0 ? '$cores' : '?';
    final objectLabel = objCount?.toString() ?? '?';

    return Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _selectedStation = null),
                icon: const Icon(Icons.arrow_back, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: stationData['is_active'] == true
                      ? Colors.green
                      : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _selectedStation!,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                version,
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
              const Spacer(),
              Text(
                '$coresLabel cores | $ramLabel RAM | $objectLabel objects',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RESOURCES',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white38,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _meter('CPU', cpu, cpu > 80 ? Colors.red : Colors.green),
                      const SizedBox(height: 12),
                      _meter('MEM', mem, mem > 80 ? Colors.red : Colors.blue),
                      const SizedBox(height: 12),
                      _meter(
                        'DISK',
                        disk,
                        disk > 80
                            ? Colors.red
                            : (disk > 70 ? Colors.orange : Colors.green),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'SERVER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white38,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _detailRow('Requests/sec', '${d.rps}'),
                      _detailRow('Total Requests', '${d.requests}'),
                      _detailRow('Errors', '${d.errors}'),
                      _detailRow('Error Rate', '${d.errorRate}%'),
                      _detailRow(
                        'Source',
                        source == 'health' ? '/health' : '/cluster/stations',
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'PROCESS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white38,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _detailRow('PID', '${h['pid'] ?? '?'}'),
                      _detailRow('Threads', '${h['threads'] ?? '?'}'),
                      _detailRow('Uptime', d.uptime),
                      _detailRow('Version', version),
                      _detailRow(
                        'Host',
                        stationData['host']?.toString() ?? '?',
                      ),
                      _detailRow('Port', '${stationData['port'] ?? '?'}'),
                    ],
                  ),
                ),
              ),
              Container(width: 1, color: Colors.white10),
              // Right: health payload
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.white10),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'HEALTH PAYLOAD',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white38,
                              letterSpacing: 1,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            source == 'health'
                                ? 'Cluster API unavailable'
                                : 'Cluster data',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white24,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: source == 'health'
                                  ? Colors.orange
                                  : Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.black26,
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          const JsonEncoder.withIndent(
                            '  ',
                          ).convert({'station': stationData, 'health': h}),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _responseBar(
    BuildContext context,
    String label,
    double pct,
    Color color,
  ) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 28,
            height: pct.clamp(4, 40),
            decoration: BoxDecoration(
              color: color.withOpacity(0.6),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _statBox(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.white38)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stationCard(
    BuildContext context,
    String name,
    bool healthy, {
    required int cpu,
    required int mem,
    required int disk,
    required int cores,
    required String ram,
    required String diskInfo,
    required String objects,
    required String version,
  }) {
    return InkWell(
      onTap: () => setState(() => _selectedStation = name),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: healthy ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Text(
                  version,
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _meter('CPU', cpu, Colors.green),
            const SizedBox(height: 8),
            _meter('MEM', mem, Colors.blue),
            const SizedBox(height: 8),
            _meter('DISK', disk, disk > 70 ? Colors.orange : Colors.green),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$cores cores | $ram RAM | $diskInfo disk | $objects objects',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: Colors.white24),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meter(String label, int percent, Color color) {
    // Negative percent means the server did not report this metric.
    final reported = percent >= 0;
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: reported ? percent / 100 : 0,
              backgroundColor: Colors.white10,
              color: color,
              minHeight: 8,
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            reported ? '$percent%' : '—',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daemon Status View (admin — jobs, queue, events)
// ---------------------------------------------------------------------------

class DaemonStatusView extends StatefulWidget {
  const DaemonStatusView({super.key});

  @override
  State<DaemonStatusView> createState() => _DaemonStatusViewState();
}

enum _DaemonListKind { scheduler, queue }

class _DaemonStatusViewState extends State<DaemonStatusView> {
  bool _refreshing = false;
  String _taskStatusFilter = 'all';
  String _messageStatusFilter = 'all';
  String _deliveryModeFilter = 'all';
  String _deliveryEventTypeFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final data = ScrollData();
    final status = data.daemonStatus;
    final healthy = data.daemonHealthStatus == 'ok';
    final scheduler = data.daemonSection('scheduler');
    final queue = data.daemonSection('queue');
    final events = data.daemonSection('events');
    final subscriptions = data.daemonSection('subscriptions');
    final retention = data.daemonSection('retention');
    final rateLimit = data.daemonSection('rate_limit');
    final schedulerTasks = data.daemonSchedulerTasks;
    final queueMessages = data.daemonQueueMessages;
    final eventDeliveries = data.eventDeliveries;
    final schedulerTaskCount =
        data.daemonSchedulerTaskCount ??
        _firstCount(scheduler, const ['task_count', 'tasks', 'total_tasks']);
    final queueMessageCount =
        data.daemonQueueMessageCount ??
        _firstCount(queue, const [
          'message_count',
          'messages',
          'total_messages',
        ]);
    final eventDeliveryCount =
        data.eventDeliveryCount ??
        _firstCount(subscriptions, const [
          'subscription_count',
          'subscriptions',
          'total_subscriptions',
          'count',
        ]);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.hub_outlined,
                color: healthy ? Colors.green : Colors.orange,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Daemon Status',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(width: 10),
              _statusChip(
                data.hasDaemonStatus
                    ? data.daemonHealthStatus.toUpperCase()
                    : 'AUTH REQUIRED',
                healthy ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 12),
              Text(
                'GET /daemon/status',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white38,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _refreshing ? null : _refreshDaemonStatus,
                icon: _refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh daemon status',
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (status == null)
            _emptyDaemonStatus(context)
          else ...[
            _lockedControlBar(context),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric(
                  Icons.schedule_outlined,
                  'Tasks',
                  _countText(schedulerTaskCount),
                  Colors.blue,
                ),
                _metric(
                  Icons.queue_outlined,
                  'Messages',
                  _countText(queueMessageCount),
                  Colors.teal,
                ),
                _metric(
                  Icons.event_outlined,
                  'Events',
                  _countText(
                    _firstCount(events, const [
                      'event_count',
                      'events',
                      'total_events',
                    ]),
                  ),
                  Colors.purple,
                ),
                _metric(
                  Icons.forward_to_inbox_outlined,
                  'Deliveries',
                  _countText(eventDeliveryCount),
                  Colors.indigo,
                ),
                _metric(
                  Icons.subscriptions_outlined,
                  'Subscriptions',
                  _countText(
                    _firstCount(subscriptions, const [
                      'subscription_count',
                      'subscriptions',
                      'total_subscriptions',
                      'count',
                    ]),
                  ),
                  Colors.amber,
                ),
                _metric(
                  Icons.pending_actions_outlined,
                  'Pending',
                  _countText(
                    _firstCount(subscriptions, const [
                      'pending_delivery_count',
                      'pending_deliveries',
                      'pending',
                    ]),
                  ),
                  Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 980;
                final cards = [
                  _daemonListCard(
                    context,
                    title: 'Scheduler Tasks',
                    route: 'GET /daemon/scheduler/tasks',
                    icon: Icons.schedule_outlined,
                    color: Colors.blue,
                    rows: schedulerTasks,
                    response: data.daemonSchedulerTasksResponse,
                    filter: _taskStatusFilter,
                    onFilterChanged: (value) {
                      setState(() => _taskStatusFilter = value);
                    },
                    kind: _DaemonListKind.scheduler,
                  ),
                  _daemonListCard(
                    context,
                    title: 'Queue Messages',
                    route: 'GET /daemon/queue/messages',
                    icon: Icons.queue_outlined,
                    color: Colors.teal,
                    rows: queueMessages,
                    response: data.daemonQueueMessagesResponse,
                    filter: _messageStatusFilter,
                    onFilterChanged: (value) {
                      setState(() => _messageStatusFilter = value);
                    },
                    kind: _DaemonListKind.queue,
                  ),
                ];
                if (!twoColumns) {
                  return Column(
                    children: [
                      for (final card in cards) ...[
                        card,
                        if (card != cards.last) const SizedBox(height: 12),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards.first),
                    const SizedBox(width: 12),
                    Expanded(child: cards.last),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _eventDeliveriesCard(
              context,
              rows: eventDeliveries,
              response: data.eventDeliveriesResponse,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 900;
                final cards = [
                  _sectionCard(
                    context,
                    'Scheduler',
                    Icons.schedule_outlined,
                    Colors.blue,
                    scheduler,
                    preferredKeys: const [
                      'trigger_source_present',
                      'task_count',
                      'due_count',
                      'future_count',
                      'missing_next_run_count',
                    ],
                  ),
                  _sectionCard(
                    context,
                    'Queue',
                    Icons.queue_outlined,
                    Colors.teal,
                    queue,
                    preferredKeys: const [
                      'trigger_source_present',
                      'message_count',
                      'visible_pending_count',
                      'delayed_pending_count',
                      'expired_pending_count',
                    ],
                  ),
                  _sectionCard(
                    context,
                    'Events',
                    Icons.event_outlined,
                    Colors.purple,
                    events,
                    preferredKeys: const [
                      'state_present',
                      'event_count',
                      'event_counts_by_type',
                      'latest_event',
                    ],
                  ),
                  _sectionCard(
                    context,
                    'Subscriptions',
                    Icons.subscriptions_outlined,
                    Colors.amber,
                    subscriptions,
                    preferredKeys: const [
                      'subscription_count',
                      'delivery_status',
                      'pending_delivery_count',
                    ],
                  ),
                  _sectionCard(
                    context,
                    'Retention',
                    Icons.history_toggle_off_outlined,
                    Colors.green,
                    retention,
                    preferredKeys: const ['keep_count', 'keep_seconds'],
                  ),
                  _sectionCard(
                    context,
                    'Rate Limit',
                    Icons.speed_outlined,
                    Colors.orange,
                    rateLimit,
                  ),
                ];
                if (!twoColumns) {
                  return Column(
                    children: [
                      for (final card in cards) ...[
                        card,
                        if (card != cards.last) const SizedBox(height: 12),
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards
                      .map(
                        (card) => SizedBox(
                          width: (constraints.maxWidth - 12) / 2,
                          child: card,
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            _rawStatusPanel(status),
          ],
        ],
      ),
    );
  }

  Future<void> _refreshDaemonStatus() async {
    setState(() => _refreshing = true);
    await ScrollData().loadAll();
    if (mounted) setState(() => _refreshing = false);
  }

  Widget _lockedControlBar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _lockedAction(
                Icons.add_alarm_outlined,
                'Schedule Task',
                'POST /daemon/scheduler/tasks',
              ),
              _lockedAction(
                Icons.playlist_add_outlined,
                'Enqueue Message',
                'POST /daemon/queue/messages',
              ),
              _lockedAction(
                Icons.replay_outlined,
                'Retry Failed',
                'PATCH /daemon/queue/messages/{message_id}',
              ),
              _lockedAction(
                Icons.delete_outline,
                'Cancel',
                'DELETE /daemon/scheduler/tasks/{task_id}',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Write controls staged, locked in Scroll',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _lockedAction(IconData icon, String label, String route) {
    return Tooltip(
      message: '$route requires an explicit confirmation flow before enabling',
      child: OutlinedButton.icon(
        onPressed: null,
        icon: Icon(icon, size: 15),
        label: Text(label),
      ),
    );
  }

  Widget _emptyDaemonStatus(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_outline, size: 36, color: Colors.white38),
          const SizedBox(height: 10),
          const Text(
            'Daemon status unavailable',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Connect with an admin Bearer token so Scroll can read scheduler, queue, event, subscription, retention, and rate-limit state.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventDeliveriesCard(
    BuildContext context, {
    required List<Map<String, dynamic>> rows,
    required Map<String, dynamic>? response,
  }) {
    final eventTypes = _deliveryEventTypes(rows);
    final activeEventType =
        _deliveryEventTypeFilter == 'all' ||
            eventTypes.contains(_deliveryEventTypeFilter)
        ? _deliveryEventTypeFilter
        : 'all';
    final orderedRows = [...rows]
      ..sort((a, b) => _deliveryPriority(a).compareTo(_deliveryPriority(b)));
    final visibleRows = orderedRows.where((row) {
      if (!_deliveryMatchesMode(row, _deliveryModeFilter)) return false;
      if (activeEventType == 'all') return true;
      return _normalizedStatus(_deliveryEventType(row)) == activeEventType;
    }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.forward_to_inbox_outlined,
                size: 18,
                color: Colors.indigo,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Event Deliveries',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'GET /events/deliveries',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(
                _listCountLabel(response, visibleRows.length, rows.length),
                Colors.indigo,
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _refreshing ? null : _refreshDaemonStatus,
                icon: const Icon(Icons.refresh, size: 16),
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filterChip(
                'All',
                'all',
                _deliveryModeFilter,
                (value) => setState(() => _deliveryModeFilter = value),
                Colors.indigo,
              ),
              _filterChip(
                'Failed',
                'failed',
                _deliveryModeFilter,
                (value) => setState(() => _deliveryModeFilter = value),
                Colors.red,
              ),
              _filterChip(
                'Pending',
                'pending',
                _deliveryModeFilter,
                (value) => setState(() => _deliveryModeFilter = value),
                Colors.orange,
              ),
              _eventTypeMenu(eventTypes, activeEventType),
            ],
          ),
          const SizedBox(height: 12),
          if (response == null)
            _daemonEmptyState(
              context,
              Icons.forward_to_inbox_outlined,
              'Event deliveries unavailable',
              'The endpoint did not return data for this session.',
            )
          else if (rows.isEmpty)
            _daemonEmptyState(
              context,
              Icons.forward_to_inbox_outlined,
              'No deliveries reported',
              'The object server returned an empty list.',
            )
          else if (visibleRows.isEmpty)
            _daemonEmptyState(
              context,
              Icons.filter_alt_off_outlined,
              'No deliveries match the filters',
              'No matching rows in the current response.',
            )
          else
            Column(
              children: [
                for (var i = 0; i < visibleRows.length; i++)
                  _deliveryRow(context, visibleRows[i], i),
              ],
            ),
          if (response != null) ...[
            const SizedBox(height: 8),
            _rawJsonPanel(
              'Raw Event Deliveries response',
              _redactedMap(response),
            ),
          ],
        ],
      ),
    );
  }

  Widget _eventTypeMenu(List<String> eventTypes, String activeEventType) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: activeEventType,
          isDense: true,
          icon: const Icon(Icons.expand_more, size: 16),
          style: const TextStyle(fontSize: 11, color: Colors.white70),
          dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          onChanged: (value) {
            if (value != null) {
              setState(() => _deliveryEventTypeFilter = value);
            }
          },
          items: [
            const DropdownMenuItem(
              value: 'all',
              child: Text('All event types'),
            ),
            for (final eventType in eventTypes)
              DropdownMenuItem(
                value: eventType,
                child: Text(_titleCase(eventType)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _deliveryRow(
    BuildContext context,
    Map<String, dynamic> row,
    int index,
  ) {
    final subscriber =
        _firstString(row, const ['subscriber_id', 'subscription_id', 'id']) ??
        'subscription ${index + 1}';
    final eventType = _deliveryEventType(row);
    final status = _deliveryStatus(row);
    final pendingCount = _deliveryPendingCount(row);
    final pending = _deliveryPending(row);
    final attemptLine = _deliveryAttemptLine(row);
    final eventLine = _deliveryEventLine(row);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 740;
        final statusChips = Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _statusChip(_titleCase(status), _statusTone(status)),
            _statusChip(
              pending ? 'PENDING ${pendingCount ?? ''}'.trim() : 'PENDING 0',
              pending ? Colors.orange : Colors.white38,
            ),
            _callbackChip(row),
          ],
        );
        final rowBody = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _daemonIdBlock(subscriber, 'Event: ${_titleCase(eventType)}'),
                  const SizedBox(height: 8),
                  statusChips,
                  if (attemptLine.isNotEmpty || eventLine.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      [
                        attemptLine,
                        eventLine,
                      ].where((part) => part.isNotEmpty).join(' | '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ],
              )
            : Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: _daemonIdBlock(
                      subscriber,
                      'Event: ${_titleCase(eventType)}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: statusChips),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Text(
                      [
                        attemptLine,
                        eventLine,
                      ].where((part) => part.isNotEmpty).join(' | '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ),
                ],
              );

        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: compact ? 10 : 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: rowBody,
        );
      },
    );
  }

  Widget _daemonListCard(
    BuildContext context, {
    required String title,
    required String route,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> rows,
    required Map<String, dynamic>? response,
    required String filter,
    required ValueChanged<String> onFilterChanged,
    required _DaemonListKind kind,
  }) {
    final statuses = _statusValues(rows);
    final activeFilter = filter == 'all' || statuses.contains(filter)
        ? filter
        : 'all';
    final visibleRows = activeFilter == 'all'
        ? rows
        : rows.where((row) {
            return _normalizedStatus(_rowStatus(row)) == activeFilter;
          }).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      route,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(
                _listCountLabel(response, visibleRows.length, rows.length),
                color,
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _refreshing ? null : _refreshDaemonStatus,
                icon: const Icon(Icons.refresh, size: 16),
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _filterChip('All', 'all', activeFilter, onFilterChanged, color),
              for (final status in statuses)
                _filterChip(
                  _titleCase(status),
                  status,
                  activeFilter,
                  onFilterChanged,
                  color,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (response == null)
            _daemonEmptyState(
              context,
              icon,
              '$title unavailable',
              'The endpoint did not return data for this session.',
            )
          else if (rows.isEmpty)
            _daemonEmptyState(
              context,
              icon,
              'No ${kind == _DaemonListKind.scheduler ? 'tasks' : 'messages'} reported',
              'The object server returned an empty list.',
            )
          else if (visibleRows.isEmpty)
            _daemonEmptyState(
              context,
              Icons.filter_alt_off_outlined,
              'No rows match ${_titleCase(activeFilter)}',
              'No matching rows in the current response.',
            )
          else
            Column(
              children: [
                for (var i = 0; i < visibleRows.length; i++)
                  _daemonRow(context, visibleRows[i], i, kind),
              ],
            ),
          if (response != null) ...[
            const SizedBox(height: 8),
            _rawJsonPanel('Raw $title response', response),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(
    String label,
    String value,
    String activeFilter,
    ValueChanged<String> onFilterChanged,
    Color color,
  ) {
    final selected = value == activeFilter;
    return FilterChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onFilterChanged(value),
      backgroundColor: Colors.white.withValues(alpha: 0.04),
      selectedColor: color.withValues(alpha: 0.16),
      side: BorderSide(
        color: selected ? color.withValues(alpha: 0.4) : Colors.white12,
      ),
      labelStyle: TextStyle(
        fontSize: 11,
        color: selected ? color : Colors.white54,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Widget _daemonEmptyState(
    BuildContext context,
    IconData icon,
    String title,
    String detail,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: Colors.white38),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _daemonRow(
    BuildContext context,
    Map<String, dynamic> row,
    int index,
    _DaemonListKind kind,
  ) {
    final id =
        _firstString(
          row,
          kind == _DaemonListKind.scheduler
              ? const ['task_id', 'id', 'name', 'key']
              : const ['message_id', 'id', 'key'],
        ) ??
        '${kind == _DaemonListKind.scheduler ? 'task' : 'message'} ${index + 1}';
    final status = _rowStatus(row);
    final detail = _daemonDetailLine(row, kind);
    final contextValue = _daemonContextValue(row, kind);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final rowBody = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _daemonIdBlock(id, detail)),
                      const SizedBox(width: 8),
                      _statusChip(_titleCase(status), _statusTone(status)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contextValue,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _payloadChip(row),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 5, child: _daemonIdBlock(id, detail)),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _statusChip(
                        _titleCase(status),
                        _statusTone(status),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Text(
                      contextValue,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(width: 92, child: Align(child: _payloadChip(row))),
                ],
              );

        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: compact ? 10 : 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: rowBody,
        );
      },
    );
  }

  Widget _daemonIdBlock(String id, String detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ],
    );
  }

  Widget _payloadChip(Map<String, dynamic> row) {
    final present = _payloadPresent(row);
    if (present == true) return _statusChip('PAYLOAD', Colors.amber);
    if (present == false) return _statusChip('NO PAYLOAD', Colors.white38);
    return _statusChip('PAYLOAD ?', Colors.white38);
  }

  Widget _callbackChip(Map<String, dynamic> row) {
    final present = _callbackPresent(row);
    if (present == true) return _statusChip('CALLBACK', Colors.indigo);
    if (present == false) return _statusChip('NO CALLBACK', Colors.white38);
    return _statusChip('CALLBACK ?', Colors.white38);
  }

  List<String> _deliveryEventTypes(List<Map<String, dynamic>> rows) {
    final values = <String>{};
    for (final row in rows) {
      final eventType = _normalizedStatus(_deliveryEventType(row));
      if (eventType.isNotEmpty && eventType != 'unknown') values.add(eventType);
    }
    final sorted = values.toList()..sort();
    return sorted;
  }

  String _deliveryEventType(Map<String, dynamic> row) {
    return _firstString(row, const ['event_type', 'eventType', 'type']) ??
        'unknown';
  }

  String _deliveryStatus(Map<String, dynamic> row) {
    final delivery = _mapValue(row['delivery']);
    return _firstString(delivery, const ['status', 'state']) ??
        _firstString(row, const [
          'delivery_status',
          'deliveryStatus',
          'status',
          'state',
        ]) ??
        'idle';
  }

  bool _deliveryMatchesMode(Map<String, dynamic> row, String mode) {
    return switch (mode) {
      'failed' => _normalizedStatus(_deliveryStatus(row)) == 'failed',
      'pending' => _deliveryPending(row),
      _ => true,
    };
  }

  int _deliveryPriority(Map<String, dynamic> row) {
    if (_normalizedStatus(_deliveryStatus(row)) == 'failed') return 0;
    if (_deliveryPending(row)) return 1;
    return 2;
  }

  bool _deliveryPending(Map<String, dynamic> row) {
    final pending = _boolFromValue(row['pending']);
    if (pending != null) return pending;
    return (_deliveryPendingCount(row) ?? 0) > 0;
  }

  int? _deliveryPendingCount(Map<String, dynamic> row) {
    return _intFromValue(row['pending_count'] ?? row['pendingCount']);
  }

  String _deliveryAttemptLine(Map<String, dynamic> row) {
    final delivery = _mapValue(row['delivery']);
    final values = {...row, ...delivery};
    final attempt = _firstString(values, const [
      'last_attempt_at',
      'lastAttemptAt',
      'last_attempt',
      'last_failure_at',
      'last_success_at',
    ]);
    final code = _firstString(values, const [
      'last_status_code',
      'lastStatusCode',
      'status_code',
      'http_status',
    ]);
    final error = _firstString(values, const [
      'last_error',
      'lastError',
      'error',
    ]);
    final parts = [
      if (attempt != null) 'Attempt: $attempt',
      if (code != null) 'Status: $code',
      if (error != null) 'Error: $error',
    ];
    return parts.take(3).join(' | ');
  }

  String _deliveryEventLine(Map<String, dynamic> row) {
    final next = _eventReference(
      row['next_pending_event'] ?? row['next_pending_event_id'],
    );
    final latest = _eventReference(
      row['latest_pending_event'] ?? row['latest_pending_event_id'],
    );
    final last = _eventReference(row['last_event_id'] ?? row['last_event']);
    final parts = [
      if (next != null) 'Next: $next',
      if (latest != null) 'Latest: $latest',
      if (last != null) 'Last: $last',
    ];
    return parts.take(3).join(' | ');
  }

  String? _eventReference(dynamic value) {
    if (value == null) return null;
    final map = _mapValue(value);
    if (map.isNotEmpty) {
      return _firstString(map, const ['event_id', 'id', 'key']) ??
          _valueLabel(map);
    }
    final text = _valueLabel(value).trim();
    return text.isEmpty || text == '?' ? null : text;
  }

  bool? _callbackPresent(Map<String, dynamic> row) {
    for (final key in const [
      'callback_url_present',
      'callbackUrlPresent',
      'has_callback_url',
    ]) {
      final parsed = _boolFromValue(row[key]);
      if (parsed != null) return parsed;
    }
    if (row.containsKey('callback_url')) return row['callback_url'] != null;
    return null;
  }

  Map<String, dynamic> _mapValue(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  int? _intFromValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool? _boolFromValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase();
      if (normalized == 'true' || normalized == 'yes' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == 'no' || normalized == '0') {
        return false;
      }
    }
    return null;
  }

  Map<String, dynamic> _redactedMap(Map<String, dynamic> source) {
    return source.map((key, value) {
      return MapEntry(key, _redactedValue(key, value));
    });
  }

  dynamic _redactedValue(String key, dynamic value) {
    final normalized = key.toLowerCase();
    if (normalized.contains('payload') ||
        normalized.contains('callback_url') ||
        normalized.contains('secret') ||
        normalized.contains('token') ||
        normalized == 'body' ||
        normalized == 'content') {
      return '[redacted]';
    }
    if (value is Map<String, dynamic>) return _redactedMap(value);
    if (value is Map) {
      return value.map((itemKey, itemValue) {
        final textKey = itemKey.toString();
        return MapEntry(textKey, _redactedValue(textKey, itemValue));
      });
    }
    if (value is List) {
      return value.map((item) {
        if (item is Map<String, dynamic>) return _redactedMap(item);
        if (item is Map) {
          return item.map((itemKey, itemValue) {
            final textKey = itemKey.toString();
            return MapEntry(textKey, _redactedValue(textKey, itemValue));
          });
        }
        return item;
      }).toList();
    }
    return value;
  }

  List<String> _statusValues(List<Map<String, dynamic>> rows) {
    final values = <String>{};
    for (final row in rows) {
      final status = _normalizedStatus(_rowStatus(row));
      if (status.isNotEmpty && status != 'unknown') values.add(status);
    }
    final sorted = values.toList()..sort();
    return sorted;
  }

  String _rowStatus(Map<String, dynamic> row) {
    return _firstString(row, const [
          'status',
          'state',
          'delivery_status',
          'run_status',
          'visibility',
        ]) ??
        'unknown';
  }

  String _daemonContextValue(Map<String, dynamic> row, _DaemonListKind kind) {
    if (kind == _DaemonListKind.queue) {
      final queue = _firstString(row, const ['queue_name', 'queue']);
      final priority = _firstString(row, const ['priority']);
      final visibleAt = _firstString(row, const [
        'visible_at',
        'available_at',
        'run_at',
      ]);
      final parts = [
        if (queue != null) queue,
        if (priority != null) 'p$priority',
        if (visibleAt != null) visibleAt,
      ];
      if (parts.isNotEmpty) return parts.join(' | ');
    }
    return _firstString(
          row,
          kind == _DaemonListKind.scheduler
              ? const [
                  'next_run_at',
                  'run_at',
                  'scheduled_for',
                  'cron',
                  'interval_seconds',
                  'created_at',
                ]
              : const ['created_at', 'updated_at', 'expires_at', 'attempts'],
        ) ??
        'No timing reported';
  }

  String _daemonDetailLine(Map<String, dynamic> row, _DaemonListKind kind) {
    final preferred = kind == _DaemonListKind.scheduler
        ? const [
            'task_type',
            'handler',
            'object_id',
            'method',
            'last_run_at',
            'updated_at',
          ]
        : const [
            'topic',
            'message_type',
            'handler',
            'attempts',
            'max_attempts',
            'updated_at',
          ];
    final pieces = <String>[];
    for (final key in preferred) {
      final value = row[key];
      if (_isDetailValue(value)) {
        pieces.add('${_titleCase(key)}: ${_valueLabel(value)}');
      }
    }
    if (pieces.isEmpty) {
      for (final entry in row.entries) {
        if (_skipDaemonDetailKey(entry.key)) continue;
        if (_isDetailValue(entry.value)) {
          pieces.add('${_titleCase(entry.key)}: ${_valueLabel(entry.value)}');
        }
        if (pieces.length >= 3) break;
      }
    }
    return pieces.take(3).join(' | ');
  }

  bool _isDetailValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  bool _skipDaemonDetailKey(String key) {
    final normalized = key.toLowerCase();
    if (normalized.contains('payload')) return true;
    if (normalized == 'body' ||
        normalized == 'content' ||
        normalized == 'data' ||
        normalized == 'status' ||
        normalized == 'state' ||
        normalized == 'id' ||
        normalized == 'task_id' ||
        normalized == 'message_id' ||
        normalized == 'key') {
      return true;
    }
    return false;
  }

  bool? _payloadPresent(Map<String, dynamic> row) {
    for (final key in const [
      'payload_present',
      'has_payload',
      'payloadPresent',
    ]) {
      final value = row[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.toLowerCase();
        if (normalized == 'true' || normalized == 'yes' || normalized == '1') {
          return true;
        }
        if (normalized == 'false' || normalized == 'no' || normalized == '0') {
          return false;
        }
      }
    }
    if (row.containsKey('payload')) return row['payload'] != null;
    return null;
  }

  String? _firstString(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      final text = _valueLabel(value).trim();
      if (text.isNotEmpty && text != '?') return text;
    }
    return null;
  }

  String _normalizedStatus(String status) {
    return status.trim().toLowerCase().replaceAll(' ', '_');
  }

  String _listCountLabel(
    Map<String, dynamic>? response,
    int visibleCount,
    int rowCount,
  ) {
    final count = _responseCount(response, const ['count', 'total']);
    if (count == null) return '$visibleCount rows';
    if (visibleCount != rowCount) return '$visibleCount/$count shown';
    return '$count rows';
  }

  int? _responseCount(Map<String, dynamic>? response, List<String> keys) {
    if (response == null) return null;
    for (final key in keys) {
      final value = response[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Color _statusTone(String status) {
    final normalized = _normalizedStatus(status);
    if (normalized == 'ok' ||
        normalized == 'ready' ||
        normalized == 'visible' ||
        normalized == 'running' ||
        normalized == 'active' ||
        normalized == 'complete' ||
        normalized == 'completed' ||
        normalized == 'sent') {
      return Colors.green;
    }
    if (normalized == 'failed' ||
        normalized == 'error' ||
        normalized == 'expired' ||
        normalized == 'dead' ||
        normalized == 'cancelled' ||
        normalized == 'canceled') {
      return Colors.red;
    }
    if (normalized == 'pending' ||
        normalized == 'delayed' ||
        normalized == 'scheduled' ||
        normalized == 'due' ||
        normalized == 'future' ||
        normalized == 'retry') {
      return Colors.orange;
    }
    return Colors.white54;
  }

  Widget _sectionCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    Map<String, dynamic> values, {
    List<String> preferredKeys = const [],
  }) {
    final rows = _orderedRows(values, preferredKeys);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _statusChip(rows.isEmpty ? 'EMPTY' : 'READ ONLY', color),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'Not reported',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            )
          else
            ...rows.map((entry) => _statusRow(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _statusRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              _titleCase(label),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              _valueLabel(value),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: _valueColor(value),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rawStatusPanel(Map<String, dynamic> status) {
    return _rawJsonPanel('Raw daemon response', status);
  }

  Widget _rawJsonPanel(String title, Map<String, dynamic> status) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: TextStyle(fontSize: 12, color: Colors.white54)),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(status),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<MapEntry<String, dynamic>> _orderedRows(
    Map<String, dynamic> values,
    List<String> preferredKeys,
  ) {
    final rows = <MapEntry<String, dynamic>>[];
    final used = <String>{};
    for (final key in preferredKeys) {
      if (values.containsKey(key)) {
        rows.add(MapEntry(key, values[key]));
        used.add(key);
      }
    }
    for (final entry in values.entries) {
      if (!used.contains(entry.key)) rows.add(entry);
    }
    return rows.take(8).toList();
  }

  int? _firstCount(Map<String, dynamic> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
      if (value is Map) {
        var total = 0;
        var found = false;
        for (final item in value.values) {
          if (item is num) {
            total += item.toInt();
            found = true;
          }
        }
        if (found) return total;
      }
    }
    return null;
  }

  String _countText(int? value) => value == null ? '?' : value.toString();

  String _valueLabel(dynamic value) {
    if (value == null) return '?';
    if (value is bool) return value ? 'yes' : 'no';
    if (value is num || value is String) return value.toString();
    if (value is List) return '${value.length} items';
    if (value is Map) {
      final entries = value.entries.take(4).map((entry) {
        return '${_titleCase(entry.key.toString())}: ${_valueLabel(entry.value)}';
      });
      return entries.join(', ');
    }
    return value.toString();
  }

  String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Color _valueColor(dynamic value) {
    if (value is bool) return value ? Colors.green : Colors.orange;
    final normalized = value?.toString().toLowerCase() ?? '';
    if (normalized == 'ok' ||
        normalized == 'ready' ||
        normalized == 'enabled' ||
        normalized == 'present') {
      return Colors.green;
    }
    if (normalized == 'missing' ||
        normalized == 'disabled' ||
        normalized == 'blocked') {
      return Colors.orange;
    }
    return Colors.white70;
  }
}

// ---------------------------------------------------------------------------
// Object Workspace (admin read-only object inspection)
// ---------------------------------------------------------------------------

class ObjectWorkspace extends StatefulWidget {
  final void Function(String, Widget, [IconData])? onNavigate;
  const ObjectWorkspace({super.key, this.onNavigate});

  @override
  State<ObjectWorkspace> createState() => _ObjectWorkspaceState();
}

class _ObjectWorkspaceState extends State<ObjectWorkspace> {
  String? _selectedObject;
  String _tab = 'Overview';
  Map<String, List<Map<String, dynamic>>> _objects = {};
  bool _loading = true;
  String? _loadError;

  // Cached data for selected object
  Map<String, dynamic>? _selectedObjectInfo;
  Map<String, dynamic>? _metadataData;
  String? _sourceCode;
  Map<String, dynamic>? _sourceSaveResponse;
  Map<String, dynamic>? _executeResponse;
  Map<String, dynamic>? _stateData;
  List<dynamic>? _logsData;
  List<dynamic>? _versionsData;
  List<dynamic>? _changesData;
  bool _tabLoading = false;
  bool _sourceSaving = false;
  bool _executing = false;

  @override
  void initState() {
    super.initState();
    _loadObjects();
  }

  Future<void> _loadObjects() async {
    setState(() => _loading = true);
    try {
      final list = await ScrollAPI().listAdminObjects();
      final Map<String, List<Map<String, dynamic>>> categorized = {};
      for (final obj in list) {
        final object = _mapFromDynamic(obj);
        final id = (object['object_id'] ?? object['id'] ?? object['name'] ?? '')
            .toString();
        if (id.isEmpty) continue;
        final owner = (object['owner'] ?? '').toString();
        final path = (object['path'] ?? object['file'] ?? '').toString();

        String category;
        if (owner == 'system' && id.startsWith('tools_')) {
          category = 'Tools';
        } else if (owner == 'system' && id.startsWith('views_')) {
          category = 'Views';
        } else if (owner == 'system' && id.startsWith('triggers_')) {
          category = 'Triggers';
        } else if (owner == 'system' && id.startsWith('basics_')) {
          category = 'Basics';
        } else if (owner == 'system' && id.startsWith('apps_')) {
          category = 'Apps';
        } else if (owner == 'system' && id.startsWith('tutorial_')) {
          category = 'Tutorials';
        } else if (owner == 'system' && id.startsWith('advanced_')) {
          category = 'Advanced';
        } else if (owner == 'system' &&
            (id.startsWith('config_') ||
                id.startsWith('layouts_') ||
                id.startsWith('pages_'))) {
          category = 'System';
        } else if (owner != 'system') {
          category = 'My Objects';
        } else {
          category = 'Other';
        }

        categorized.putIfAbsent(category, () => []);
        categorized[category]!.add({
          ...object,
          'id': id,
          'owner': owner,
          'path': path,
        });
      }
      // Sort: My Objects first, then alphabetical
      final sorted = Map.fromEntries(
        categorized.entries.toList()..sort((a, b) {
          if (a.key == 'My Objects') return -1;
          if (b.key == 'My Objects') return 1;
          return a.key.compareTo(b.key);
        }),
      );
      setState(() {
        _objects = sorted;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _loadTabData(String tab) async {
    if (_selectedObject == null) return;
    setState(() => _tabLoading = true);
    final api = ScrollAPI();
    try {
      switch (tab) {
        case 'Overview':
          _metadataData = await api.getAdminObjectMetadata(_selectedObject!);
          break;
        case 'Source':
          _sourceCode = await api.getAdminObjectSource(_selectedObject!);
          break;
        case 'State':
          _stateData = await api.getAdminObjectState(_selectedObject!);
          break;
        case 'Logs':
          _logsData = await api.getAdminObjectLogs(_selectedObject!);
          break;
        case 'Versions':
          _versionsData = await api.getAdminObjectVersions(_selectedObject!);
          break;
        case 'Activity':
          _changesData = await api.getAdminObjectChanges(_selectedObject!);
          break;
      }
    } catch (_) {}
    if (mounted) setState(() => _tabLoading = false);
  }

  void _selectObject(String id) {
    setState(() {
      _selectedObject = id;
      _selectedObjectInfo = _objectInfo(id);
      _tab = 'Overview';
      _metadataData = null;
      _sourceCode = null;
      _sourceSaveResponse = null;
      _executeResponse = null;
      _stateData = null;
      _logsData = null;
      _versionsData = null;
      _changesData = null;
    });
    _loadTabData('Overview');
  }

  void _selectTab(String tab) {
    setState(() => _tab = tab);
    _loadTabData(tab);
  }

  Future<void> _runSelectedObject() async {
    final objectId = _selectedObject;
    if (objectId == null || _executing) return;
    setState(() {
      _executing = true;
      _executeResponse = null;
      _tab = 'Overview';
    });
    final result = await ScrollAPI().executeAdminObject(objectId);
    if (!mounted) return;
    setState(() {
      _executing = false;
      _executeResponse = result;
    });
  }

  Future<void> _showSourceEditDialog() async {
    final objectId = _selectedObject;
    if (objectId == null || !ScrollData().sourceWritesEnabled) return;
    final source =
        _sourceCode ?? await ScrollAPI().getAdminObjectSource(objectId);
    if (!mounted) return;
    final controller = TextEditingController(text: source ?? '');
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Edit $objectId Source'),
          content: SizedBox(
            width: 760,
            height: 520,
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                labelText: 'Source code',
              ),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Save Source'),
            ),
          ],
        );
      },
    );
    if (submitted != true) {
      controller.dispose();
      return;
    }
    final updatedSource = controller.text;
    controller.dispose();
    setState(() {
      _sourceSaving = true;
      _sourceSaveResponse = null;
    });
    final result = await ScrollAPI().updateObjectSource(
      objectId,
      updatedSource,
    );
    final refreshedSource = await ScrollAPI().getAdminObjectSource(objectId);
    final refreshedMetadata = await ScrollAPI().getAdminObjectMetadata(
      objectId,
    );
    if (!mounted) return;
    final saveSucceeded = result != null;
    setState(() {
      _sourceSaving = false;
      _sourceCode =
          refreshedSource ?? (saveSucceeded ? updatedSource : _sourceCode);
      _metadataData = refreshedMetadata ?? _metadataData;
      _sourceSaveResponse = result is Map<String, dynamic>
          ? result
          : {
              if (result != null) 'response': result,
              if (result == null)
                'error': ScrollAPI().lastError ?? 'Source update failed',
            };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Object sidebar
        Container(
          width: 220,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Text(
                      'OBJECTS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white38,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_objects.values.fold<int>(0, (s, l) => s + l.length)}',
                      style: TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search objects...',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _loadError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red[300]),
                            const SizedBox(height: 8),
                            Text(
                              'Failed to load',
                              style: TextStyle(
                                color: Colors.red[300],
                                fontSize: 12,
                              ),
                            ),
                            TextButton(
                              onPressed: _loadObjects,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        children: _objects.entries.map((cat) {
                          final isUser = cat.key == 'My Objects';
                          return ExpansionTile(
                            dense: true,
                            initiallyExpanded: isUser,
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            leading: Icon(
                              isUser ? Icons.person : Icons.folder_outlined,
                              size: 16,
                              color: isUser
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white38,
                            ),
                            title: Text(
                              cat.key,
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Text(
                              '${cat.value.length}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white38,
                              ),
                            ),
                            children: cat.value.map((obj) {
                              final id = obj['id'] as String;
                              final selected = _selectedObject == id;
                              return ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                selected: selected,
                                selectedTileColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer.withOpacity(0.2),
                                contentPadding: const EdgeInsets.only(
                                  left: 40,
                                  right: 8,
                                ),
                                leading: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                title: Text(
                                  id,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                onTap: () => _selectObject(id),
                              );
                            }).toList(),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
        Container(width: 1, color: Colors.white10),
        // Object detail
        Expanded(
          child: _selectedObject == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.code, size: 48, color: Colors.white12),
                      const SizedBox(height: 12),
                      Text(
                        'Select an object',
                        style: TextStyle(color: Colors.white24),
                      ),
                    ],
                  ),
                )
              : _buildObjectDetail(context),
        ),
      ],
    );
  }

  Widget _buildObjectDetail(BuildContext context) {
    final info = _selectedObjectInfo ?? const <String, dynamic>{};
    final isView =
        _selectedObject!.startsWith('view_') ||
        _selectedObject == 'counter_dashboard' ||
        _selectedObject == 'server_status';
    final typeLabel = _objectTypeLabel(info, isView);
    final typeColor = isView ? Colors.blue : Colors.green;
    final versionLabel = _objectVersionLabel(info);

    return Column(
      children: [
        // Object header with tabs
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _selectedObject!,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              // Object type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(fontSize: 10, color: typeColor),
                ),
              ),
              if (versionLabel != null) ...[
                const SizedBox(width: 4),
                Text(
                  versionLabel,
                  style: TextStyle(fontSize: 10, color: Colors.white24),
                ),
              ],
              const SizedBox(width: 16),
              ..._tabBtn('Overview', _selectTab),
              ..._tabBtn('Source', _selectTab),
              ..._tabBtn('Activity', _selectTab),
              ..._tabBtn('State', _selectTab),
              ..._tabBtn('Logs', _selectTab),
              ..._tabBtn('Versions', _selectTab),
              const Spacer(),
              if (isView)
                Tooltip(
                  message:
                      'Public view routes stay separate from admin execution',
                  child: TextButton.icon(
                    onPressed: null,
                    icon: Icon(Icons.open_in_new, size: 14),
                    label: Text(
                      '/v/${_selectedObject!.replaceFirst('view_', '')}/',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(foregroundColor: Colors.blue),
                  ),
                ),
              Tooltip(
                message: 'Run through POST /admin/objects/{object_id}/execute',
                child: FilledButton.icon(
                  onPressed: _executing ? null : _runSelectedObject,
                  icon: _executing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow, size: 16),
                  label: Text(_executing ? 'Running...' : 'Run'),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Object deletes are disabled on staging',
                child: IconButton(
                  onPressed: null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Delete disabled',
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        // Tab content
        Expanded(child: _buildTabContent()),
      ],
    );
  }

  List<Widget> _tabBtn(String label, void Function(String) onSelect) {
    final active = _tab == label;
    return [
      InkWell(
        onTap: () => onSelect(label),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white38,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
      const SizedBox(width: 2),
    ];
  }

  Widget _buildTabContent() {
    if (_tabLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return switch (_tab) {
      'Overview' => _buildOverviewTab(),
      'Source' => _buildCodeTab(),
      'Activity' => _buildActivityTab(),
      'State' => _buildStateTab(),
      'Logs' => _buildLogsTab(),
      'Versions' => _buildVersionsTab(),
      _ => const SizedBox(),
    };
  }

  Map<String, dynamic>? _objectInfo(String id) {
    for (final group in _objects.values) {
      for (final object in group) {
        if (object['id']?.toString() == id) return object;
      }
    }
    return null;
  }

  Map<String, dynamic> _mapFromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  Widget _objectMetric(IconData icon, String label, String value, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _objectInfoCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    List<MapEntry<String, dynamic>> rows,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _objectChip(rows.isEmpty ? 'EMPTY' : 'READ ONLY', color),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'Not reported',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            )
          else
            ...rows.map((entry) => _objectInfoRow(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _objectInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              _titleCase(label),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              _valueText(value),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _objectChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _rawObjectPanel(String title, Map<String, dynamic> value) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: TextStyle(fontSize: 12, color: Colors.white54)),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(value),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  List<MapEntry<String, dynamic>> _orderedObjectRows(
    Map<String, dynamic> values,
  ) {
    final preferred = [
      'id',
      'object_id',
      'name',
      'owner',
      'type',
      'path',
      'version',
      'created_at',
      'updated_at',
      'description',
    ];
    final rows = <MapEntry<String, dynamic>>[];
    final used = <String>{};
    for (final key in preferred) {
      final value = values[key];
      if (_hasValue(value)) {
        rows.add(MapEntry(key, value));
        used.add(key);
      }
    }
    for (final entry in values.entries) {
      if (used.contains(entry.key) || !_hasValue(entry.value)) continue;
      rows.add(entry);
    }
    return rows.take(10).toList();
  }

  List<MapEntry<String, dynamic>> _objectOverviewRows(
    Map<String, dynamic> listInfo,
    Map<String, dynamic> metadata,
  ) {
    return _orderedObjectRows({...listInfo, ...metadata});
  }

  bool _hasValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  String _objectTypeLabel(Map<String, dynamic> info, bool isView) {
    if (isView) return 'view';
    final type = (info['type'] ?? info['kind'] ?? info['object_type'])
        ?.toString();
    if (type != null && type.isNotEmpty) return type;
    return 'object';
  }

  String? _objectVersionLabel(Map<String, dynamic> info) {
    final value =
        info['version'] ??
        info['current_version'] ??
        info['version_id'] ??
        info['revision'];
    if (value == null || value.toString().isEmpty) return null;
    final text = value.toString();
    return text.startsWith('v') ? text : 'v$text';
  }

  String _versionLabel(Map<String, dynamic> version) {
    final value =
        version['version'] ??
        version['id'] ??
        version['version_id'] ??
        version['revision'] ??
        '?';
    final text = value.toString();
    return text.startsWith('v') ? text : 'v$text';
  }

  String _valueText(dynamic value) {
    if (value == null) return '?';
    if (value is bool) return value ? 'yes' : 'no';
    if (value is List) return '${value.length} items';
    if (value is Map) {
      final entries = value.entries.take(4).map((entry) {
        return '${_titleCase(entry.key.toString())}: ${_valueText(entry.value)}';
      });
      return entries.join(', ');
    }
    return value.toString();
  }

  String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Widget _buildOverviewTab() {
    final listInfo = _selectedObjectInfo ?? const <String, dynamic>{};
    final metadata = _metadataData ?? const <String, dynamic>{};
    final sourceRows = _objectOverviewRows(listInfo, metadata);
    final selectedId = _selectedObject ?? '';
    final isView =
        selectedId.startsWith('view_') ||
        selectedId == 'counter_dashboard' ||
        selectedId == 'server_status';

    return Container(
      color: Colors.black26,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _objectMetric(
                  Icons.badge_outlined,
                  'Owner',
                  _valueText(listInfo['owner']),
                  Colors.blue,
                ),
                _objectMetric(
                  Icons.category_outlined,
                  'Type',
                  _objectTypeLabel(listInfo, isView),
                  isView ? Colors.blue : Colors.green,
                ),
                _objectMetric(
                  Icons.history_outlined,
                  'Version',
                  _objectVersionLabel({...listInfo, ...metadata}) ?? '?',
                  Colors.purple,
                ),
                _objectMetric(
                  Icons.storage_outlined,
                  'State',
                  metadata.isEmpty ? 'metadata?' : 'available',
                  metadata.isEmpty ? Colors.orange : Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 900;
                final cards = [
                  _objectInfoCard(
                    context,
                    'Object List Row',
                    Icons.inventory_2_outlined,
                    Colors.blue,
                    _orderedObjectRows(listInfo),
                  ),
                  _objectInfoCard(
                    context,
                    'Object Metadata',
                    Icons.info_outline,
                    Colors.green,
                    _orderedObjectRows(metadata),
                  ),
                ];
                if (!twoColumns) {
                  return Column(
                    children: [
                      for (final card in cards) ...[
                        card,
                        if (card != cards.last) const SizedBox(height: 12),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards.first),
                    const SizedBox(width: 12),
                    Expanded(child: cards.last),
                  ],
                );
              },
            ),
            if (sourceRows.isNotEmpty) ...[
              const SizedBox(height: 16),
              _rawObjectPanel('Raw object detail', {
                'list_row': listInfo,
                if (metadata.isNotEmpty) 'metadata': metadata,
              }),
            ],
            if (_executeResponse != null) ...[
              const SizedBox(height: 16),
              _rawObjectPanel('Admin execute response', _executeResponse!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCodeTab() {
    final sourceWritesEnabled = ScrollData().sourceWritesEnabled;
    return Container(
      color: Colors.black26,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Text(
                  'Source Code',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const Spacer(),
                _objectChip(
                  sourceWritesEnabled ? 'SOURCE EDITS ENABLED' : 'READ ONLY',
                  sourceWritesEnabled ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                _objectChip(
                  sourceWritesEnabled
                      ? 'SOURCE WRITES ENABLED'
                      : 'SOURCE WRITES OFF',
                  sourceWritesEnabled ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: sourceWritesEnabled
                      ? 'Save through PUT /admin/objects/{object_id}?source=true'
                      : 'Source writes are locked: /admin/status.capabilities.source_writes.enabled is false',
                  child: OutlinedButton.icon(
                    onPressed:
                        sourceWritesEnabled &&
                            !_sourceSaving &&
                            _sourceCode != null
                        ? _showSourceEditDialog
                        : null,
                    icon: _sourceSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit, size: 14),
                    label: Text(
                      _sourceSaving
                          ? 'Saving...'
                          : sourceWritesEnabled
                          ? 'Edit Source'
                          : 'Edit locked',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_sourceSaveResponse != null)
            Builder(
              builder: (context) {
                final color = _sourceSaveResponse!['error'] == null
                    ? Colors.green
                    : Colors.red;
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.18)),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent(
                      '  ',
                    ).convert(_sourceSaveResponse),
                    maxLines: 5,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                );
              },
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _sourceCode ?? '// Loading source...',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: _sourceCode != null
                      ? Colors.green[300]
                      : Colors.white24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTab() {
    final changes = _changesData ?? const [];
    return Container(
      color: Colors.black26,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Object Activity',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _objectChip('READ ONLY', Colors.green),
            ],
          ),
          const SizedBox(height: 16),
          if (changes.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No object activity',
                  style: TextStyle(color: Colors.white24),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: changes.length + 1,
                itemBuilder: (context, i) {
                  if (i == changes.length) {
                    return _rawObjectPanel('Raw object changes', {
                      'changes': changes,
                    });
                  }
                  final raw = changes[i];
                  final change = _mapFromDynamic(raw);
                  String pick(List<String> keys, [String fallback = '']) {
                    for (final key in keys) {
                      final value = change[key]?.toString();
                      if (value != null && value.trim().isNotEmpty) {
                        return value;
                      }
                    }
                    return fallback;
                  }

                  String valueText(dynamic value) {
                    if (value == null) return '';
                    if (value is Map || value is List) {
                      return const JsonEncoder.withIndent('  ').convert(value);
                    }
                    return value.toString();
                  }

                  final kind = pick(['kind'], 'source');
                  final action = pick([
                    'action',
                    'type',
                    'event_type',
                    'change_type',
                  ], '${kind}_change');
                  final timestamp = pick([
                    'timestamp',
                    'created_at',
                    'changed_at',
                    'time',
                  ]);
                  final actor = pick([
                    'actor',
                    'author',
                    'user',
                    'user_id',
                    'principal',
                  ], 'unknown');
                  final message = pick([
                    'summary',
                    'message',
                    'description',
                    'note',
                  ], action);
                  final target = _mapFromDynamic(change['target']);
                  final targetParts = <String>[
                    for (final key in const [
                      'object_id',
                      'collection',
                      'record_id',
                      'package_id',
                      'file',
                    ])
                      if (target[key]?.toString().trim().isNotEmpty == true)
                        '${key.replaceAll('_id', '')}: ${target[key]}',
                  ];
                  final targetText = targetParts.isEmpty
                      ? valueText(change['target'])
                      : targetParts.join(' | ');
                  final version = pick([
                    'version_id',
                    'to_version_id',
                    'version',
                    'revision',
                  ]);
                  final fromVersion = pick([
                    'from_version_id',
                    'from_version',
                    'previous_version_id',
                  ]);
                  final correlation = pick(['correlation_id', 'request_id']);
                  String short(String value, int limit) {
                    if (value.length <= limit) return value;
                    return '${value.substring(0, limit)}...';
                  }

                  final normalizedAction = action.toLowerCase();
                  final normalizedKind = kind.toLowerCase();
                  final color = normalizedAction.contains('rollback')
                      ? Colors.orange
                      : normalizedAction.contains('delete')
                      ? Colors.red
                      : normalizedKind == 'file'
                      ? Colors.teal
                      : normalizedKind == 'record'
                      ? Colors.blue
                      : normalizedKind == 'package'
                      ? Colors.amber
                      : Colors.green;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _objectChip(kind.toUpperCase(), color),
                            const SizedBox(width: 6),
                            _objectChip(action, color),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _objectChip(
                              'actor: ${short(actor, 32)}',
                              Colors.blue,
                            ),
                            if (timestamp.isNotEmpty)
                              _objectChip(short(timestamp, 32), Colors.white54),
                            if (version.isNotEmpty)
                              _objectChip(
                                'version: ${short(version, 24)}',
                                Colors.purple,
                              ),
                            if (targetText.isNotEmpty)
                              _objectChip(short(targetText, 42), Colors.teal),
                            if (fromVersion.isNotEmpty)
                              _objectChip(
                                'from: ${short(fromVersion, 24)}',
                                Colors.orange,
                              ),
                            if (correlation.isNotEmpty)
                              _objectChip(
                                'corr: ${short(correlation, 18)}',
                                Colors.white54,
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStateTab() {
    return Container(
      color: Colors.black26,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Text(
                  'State (TSV)',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const Spacer(),
                _objectChip('READ ONLY', Colors.green),
              ],
            ),
          ),
          Expanded(
            child: _stateData == null || _stateData!.isEmpty
                ? Center(
                    child: Text(
                      'No state data',
                      style: TextStyle(color: Colors.white24),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: DataTable(
                      headingRowHeight: 32,
                      dataRowMinHeight: 32,
                      dataRowMaxHeight: 32,
                      columnSpacing: 32,
                      headingTextStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white54,
                      ),
                      dataTextStyle: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                      columns: const [
                        DataColumn(label: Text('KEY')),
                        DataColumn(label: Text('VALUE')),
                      ],
                      rows: _stateData!.entries.map((kv) {
                        final isMeta = kv.key.startsWith('_');
                        final val = kv.value?.toString() ?? '';
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                kv.key,
                                style: TextStyle(
                                  color: isMeta
                                      ? Colors.blue[200]
                                      : Colors.white70,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                val.length > 100
                                    ? '${val.substring(0, 100)}...'
                                    : val,
                                style: TextStyle(
                                  color: isMeta
                                      ? Colors.white38
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTab() {
    return Container(
      color: Colors.black26,
      padding: const EdgeInsets.all(12),
      child: _logsData == null || _logsData!.isEmpty
          ? Center(
              child: Text('No logs', style: TextStyle(color: Colors.white24)),
            )
          : ListView.builder(
              itemCount: _logsData!.length,
              itemBuilder: (context, i) {
                final log = _logsData![i];
                final time =
                    log['timestamp']?.toString() ??
                    log['time']?.toString() ??
                    '';
                final level = log['level']?.toString() ?? 'INFO';
                final msg = log['message']?.toString() ?? log.toString();
                return _objLog(time, level, msg);
              },
            ),
    );
  }

  Widget _buildVersionsTab() {
    final versions = _versionsData ?? const [];
    final currentVersion = _objectVersionLabel({
      ...?_selectedObjectInfo,
      ...?_metadataData,
    });
    return Container(
      color: Colors.black26,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Version History',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _objectChip('READ ONLY', Colors.green),
            ],
          ),
          const SizedBox(height: 16),
          if (versions.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No version data',
                  style: TextStyle(color: Colors.white24),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: versions.length,
                itemBuilder: (context, i) {
                  final raw = versions[i];
                  final version = _mapFromDynamic(raw);
                  final label = _versionLabel(version);
                  final isCurrent =
                      currentVersion != null && label == currentVersion;
                  final created =
                      version['created_at']?.toString() ??
                      version['date']?.toString() ??
                      version['timestamp']?.toString() ??
                      '';
                  final author =
                      version['author']?.toString() ??
                      version['actor']?.toString() ??
                      version['user']?.toString() ??
                      'unknown';
                  final message =
                      version['message']?.toString() ??
                      version['description']?.toString() ??
                      version['change']?.toString() ??
                      '';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? Colors.green.withOpacity(0.05)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCurrent
                            ? Colors.green.withOpacity(0.2)
                            : Colors.white10,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? Colors.green.withOpacity(0.15)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isCurrent ? Colors.green : Colors.white54,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          created,
                          style: TextStyle(fontSize: 12, color: Colors.white38),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          author,
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                        if (isCurrent) _objectChip('CURRENT', Colors.green),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _objLog(String time, String level, String msg) {
    final color = switch (level) {
      'INFO' => Colors.green,
      'DEBUG' => Colors.grey,
      'ROUTE' => Colors.blue,
      'ERROR' => Colors.red,
      _ => Colors.white54,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$time ',
              style: TextStyle(
                color: Colors.white30,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: '[$level] ',
              style: TextStyle(
                color: color,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: msg,
              style: TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Collection Browser (admin)
// ---------------------------------------------------------------------------

class CollectionBrowser extends StatefulWidget {
  const CollectionBrowser({super.key});

  @override
  State<CollectionBrowser> createState() => _CollectionBrowserState();
}

class _CollectionBrowserState extends State<CollectionBrowser> {
  List<Map<String, dynamic>> _collections = [];
  String? _selectedCollection;
  Map<String, dynamic>? _collectionDetail;
  Map<String, dynamic>? _collectionSchema;
  List<dynamic> _records = [];
  List<dynamic> _collectionChanges = [];
  Map<String, dynamic>? _selectedRecord;
  List<dynamic> _recordChanges = [];
  String _tab = 'Records';
  bool _loading = true;
  bool _detailLoading = false;
  bool _recordLoading = false;
  bool _writing = false;
  Map<String, dynamic>? _writeResponse;
  String? _error;
  String? _rtCollection;
  VoidCallback? _rtDispose;

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  @override
  void dispose() {
    _rtDispose?.call();
    super.dispose();
  }

  /// Keep one realtime subscription tracking the visible collection. On a
  /// record event, quietly refetch the record list + changes without
  /// blanking the panel or losing the selected record.
  void _bindRealtime(String? collection) {
    if (collection == _rtCollection) return;
    _rtDispose?.call();
    _rtCollection = collection;
    _rtDispose = collection == null
        ? null
        : ScrollRealtime().bind(collection, _refetchRecordsQuietly);
  }

  Future<void> _refetchRecordsQuietly() async {
    final collection = _selectedCollection;
    if (collection == null || !mounted) return;
    final results = await Future.wait<dynamic>([
      ScrollAPI().listAdminCollectionRecords(collection, limit: 100),
      ScrollAPI().listAdminCollectionChanges(collection, limit: 100),
    ]);
    if (!mounted || collection != _selectedCollection) return;
    setState(() {
      _records = results[0] is List ? results[0] as List : _records;
      _collectionChanges = results[1] is List
          ? results[1] as List
          : _collectionChanges;
    });
  }

  Future<void> _loadCollections() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ScrollAPI().listAdminCollections();
      final collections = raw
          .map(_mapFromDynamic)
          .where((collection) => _collectionName(collection).isNotEmpty)
          .toList();
      final current = _selectedCollection;
      final selected =
          collections.any((item) => _collectionName(item) == current)
          ? current
          : (collections.isNotEmpty
                ? _collectionName(collections.first)
                : null);
      if (!mounted) return;
      setState(() {
        _collections = collections;
        _selectedCollection = selected;
        _loading = false;
      });
      _bindRealtime(selected);
      if (selected != null) await _loadCollection(selected);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadCollection(String collection) async {
    setState(() {
      _detailLoading = true;
      _collectionDetail = null;
      _collectionSchema = null;
      _records = [];
      _collectionChanges = [];
      _selectedRecord = null;
      _recordChanges = [];
    });
    final api = ScrollAPI();
    final responses = await Future.wait<dynamic>([
      api.getAdminCollection(collection),
      api.listAdminCollectionRecords(collection, limit: 100),
      api.listAdminCollectionChanges(collection, limit: 100),
      api.getAdminSchema(collection),
    ]);
    if (!mounted) return;
    setState(() {
      _collectionDetail = _mapOrNull(responses[0]);
      _records = responses[1] is List ? responses[1] as List : const [];
      _collectionChanges = responses[2] is List
          ? responses[2] as List
          : const [];
      _collectionSchema = _mapOrNull(responses[3]);
      _detailLoading = false;
    });
  }

  Future<void> _selectCollection(String collection) async {
    setState(() {
      _selectedCollection = collection;
      _tab = 'Records';
    });
    _bindRealtime(collection);
    await _loadCollection(collection);
  }

  Future<void> _selectRecord(dynamic value) async {
    final record = _mapFromDynamic(value);
    final collection = _selectedCollection;
    final id = _recordId(record);
    setState(() {
      _selectedRecord = record;
      _recordChanges = [];
      _recordLoading = id.isNotEmpty;
    });
    if (collection == null || id.isEmpty) {
      setState(() => _recordLoading = false);
      return;
    }
    final api = ScrollAPI();
    final responses = await Future.wait<dynamic>([
      api.getAdminCollectionRecord(collection, id),
      api.listAdminCollectionRecordChanges(collection, id, limit: 100),
    ]);
    if (!mounted) return;
    final detail = _mapOrNull(responses[0]);
    setState(() {
      _selectedRecord = detail == null ? record : {...record, ...detail};
      _recordChanges = responses[1] is List ? responses[1] as List : const [];
      _recordLoading = false;
    });
  }

  Future<Map<String, dynamic>?> _promptRecordJson({
    required String title,
    required String initialJson,
    String confirmLabel = 'Save Record',
  }) async {
    final controller = TextEditingController(text: initialJson);
    String? parseError;
    final submitted = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 640,
                height: 420,
                child: Column(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        maxLines: null,
                        expands: true,
                        decoration: const InputDecoration(
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                          labelText: 'Record JSON',
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (parseError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          parseError!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[300],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    try {
                      final decoded = jsonDecode(controller.text) as Object?;
                      if (decoded is! Map<String, dynamic>) {
                        setDialogState(
                          () => parseError = 'Record JSON must be an object',
                        );
                        return;
                      }
                      Navigator.of(dialogContext).pop(decoded);
                    } catch (e) {
                      setDialogState(() => parseError = 'Invalid JSON: $e');
                    }
                  },
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: Text(confirmLabel),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return submitted;
  }

  Future<bool> _runRecordWrite(
    Future<Map<String, dynamic>> Function() write,
  ) async {
    final collection = _selectedCollection;
    if (collection == null) return false;
    setState(() {
      _writing = true;
      _writeResponse = null;
    });
    final result = await write();
    if (!mounted) return false;
    setState(() {
      _writing = false;
      _writeResponse = result;
    });
    await _loadCollection(collection);
    final status = result['status'];
    return status is int && status >= 200 && status < 300;
  }

  SchemaFormSpec get _schemaSpec =>
      SchemaFormSpec.fromSchema(_collectionSchema);

  Future<void> _showCreateRecordDialog() async {
    final collection = _selectedCollection;
    if (collection == null) return;
    Map<String, dynamic>? record;
    final spec = _schemaSpec;
    if (spec.hasFields) {
      final result = await showSchemaRecordFormDialog(
        context,
        collection: collection,
        spec: spec,
      );
      if (!mounted) return;
      if (result == null) return;
      if (result is Map<String, dynamic>) record = result;
      // schemaFormRawJsonRequested falls through to the JSON editor.
    }
    record ??= await _promptRecordJson(
      title: 'New $collection record',
      initialJson: '{\n  "id": ""\n}',
      confirmLabel: 'Create Record',
    );
    if (record == null || !mounted) return;
    final written = record;
    final ok = await _runRecordWrite(
      () => ScrollAPI().createAdminCollectionRecord(collection, written),
    );
    final id = _recordId(written);
    if (ok && id.isNotEmpty && mounted) await _selectRecord({'id': id});
  }

  Future<void> _showEditRecordDialog() async {
    final collection = _selectedCollection;
    final record = _selectedRecord;
    if (collection == null || record == null) return;
    final id = _recordId(record);
    if (id.isEmpty) return;
    Map<String, dynamic>? updated;
    final spec = _schemaSpec;
    if (spec.hasFields) {
      final result = await showSchemaRecordFormDialog(
        context,
        collection: collection,
        spec: spec,
        initial: record,
      );
      if (!mounted) return;
      if (result == null) return;
      if (result is Map<String, dynamic>) updated = result;
    }
    updated ??= await _promptRecordJson(
      title: 'Edit $collection/$id',
      initialJson: const JsonEncoder.withIndent('  ').convert(record),
    );
    if (updated == null || !mounted) return;
    final written = updated;
    final ok = await _runRecordWrite(
      () => ScrollAPI().updateAdminCollectionRecord(collection, id, written),
    );
    if (ok && mounted) await _selectRecord({'id': id});
  }

  Future<void> _confirmDeleteRecord() async {
    final collection = _selectedCollection;
    final record = _selectedRecord;
    if (collection == null || record == null) return;
    final id = _recordId(record);
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete record?'),
          content: Text(
            'DELETE /admin/collections/$collection/records/$id\n\n'
            'The delete is recorded in the collection change history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Delete Record'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _runRecordWrite(
      () => ScrollAPI().deleteAdminCollectionRecord(collection, id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 250,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'COLLECTIONS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white38,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_collections.length}',
                      style: TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                    IconButton(
                      onPressed: _loading ? null : _loadCollections,
                      icon: const Icon(Icons.refresh, size: 16),
                      tooltip: 'Refresh',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Failed to load collections',
                            style: TextStyle(color: Colors.red[300]),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemCount: _collections.length,
                        itemBuilder: (context, index) {
                          final collection = _collections[index];
                          final name = _collectionName(collection);
                          final selected = name == _selectedCollection;
                          final hasRecords = _hasRecords(collection);
                          return ListTile(
                            dense: true,
                            selected: selected,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.2),
                            leading: Icon(
                              hasRecords
                                  ? Icons.storage_outlined
                                  : Icons.code_outlined,
                              size: 18,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white38,
                            ),
                            title: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                            trailing: Text(
                              hasRecords
                                  ? _collectionCount(collection)
                                  : '${collection['object_count'] ?? '?'} obj',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white38,
                              ),
                            ),
                            onTap: () => _selectCollection(name),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        Container(width: 1, color: Colors.white10),
        Expanded(child: _buildDetail(context)),
      ],
    );
  }

  Widget _buildDetail(BuildContext context) {
    final collection = _selectedCollection;
    if (collection == null) {
      return Center(
        child: Text('No collections', style: TextStyle(color: Colors.white38)),
      );
    }
    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Icon(Icons.storage_outlined, size: 18, color: Colors.teal),
              const SizedBox(width: 8),
              Text(
                collection,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 10),
              if (_selectedHasRecords)
                _chip('RECORD WRITES ADMIN', Colors.orange)
              else
                _chip('OBJECT NAMESPACE', Colors.blue),
              const SizedBox(width: 18),
              ..._tabButton('Overview'),
              ..._tabButton('Records'),
              ..._tabButton('Activity'),
              const Spacer(),
              Tooltip(
                message: _selectedHasRecords
                    ? 'Create through POST /admin/collections/$collection/records'
                    : 'Object namespaces have no record storage — browse these objects on the Objects screen',
                child: FilledButton.icon(
                  onPressed: _writing || !_selectedHasRecords
                      ? null
                      : _showCreateRecordDialog,
                  icon: _writing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add, size: 16),
                  label: const Text('New Record'),
                ),
              ),
            ],
          ),
        ),
        if (_writeResponse != null) _writeResponsePanel(),
        Expanded(
          child: _detailLoading
              ? const Center(child: CircularProgressIndicator())
              : switch (_tab) {
                  'Overview' => _buildOverviewTab(context),
                  'Activity' => _buildActivityTab(context),
                  _ => _buildRecordsTab(context),
                },
        ),
      ],
    );
  }

  Widget _writeResponsePanel() {
    final response = _writeResponse ?? const <String, dynamic>{};
    final status = response['status'];
    final ok = status is int && status >= 200 && status < 300;
    final color = ok ? Colors.green : Colors.red;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(response),
              maxLines: 6,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _writeResponse = null),
            icon: const Icon(Icons.close, size: 14),
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  List<Widget> _tabButton(String label) {
    final active = _tab == label;
    return [
      InkWell(
        onTap: () => setState(() => _tab = label),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white38,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
      const SizedBox(width: 2),
    ];
  }

  Widget _buildOverviewTab(BuildContext context) {
    Map<String, dynamic>? selected;
    for (final item in _collections) {
      if (_collectionName(item) == _selectedCollection) {
        selected = item;
        break;
      }
    }
    final detail = _collectionDetail ?? const <String, dynamic>{};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric(
                Icons.storage_outlined,
                'Records',
                '${_records.length}',
                Colors.teal,
              ),
              _metric(
                Icons.history_outlined,
                'Changes',
                '${_collectionChanges.length}',
                Colors.purple,
              ),
              _metric(
                Icons.shield_outlined,
                'Access',
                _valueText(detail['access'] ?? detail['mode'] ?? 'admin'),
                Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _infoCard(
                  context,
                  'Collection List Row',
                  Icons.list_alt_outlined,
                  Colors.teal,
                  _orderedRows(selected ?? const {}),
                ),
                _infoCard(
                  context,
                  'Collection Detail',
                  Icons.info_outline,
                  Colors.blue,
                  _orderedRows(detail),
                ),
              ];
              if (constraints.maxWidth < 900) {
                return Column(
                  children: [
                    cards.first,
                    const SizedBox(height: 12),
                    cards.last,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards.first),
                  const SizedBox(width: 12),
                  Expanded(child: cards.last),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _rawPanel('Raw collection payload', {
            if (selected != null) 'list_row': selected,
            if (detail.isNotEmpty) 'detail': detail,
          }),
        ],
      ),
    );
  }

  Widget _buildRecordsTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final records = _recordsList(context);
          final detail = _recordDetail(context);
          if (constraints.maxWidth < 880) {
            return Column(
              children: [
                Expanded(child: records),
                const SizedBox(height: 12),
                Expanded(child: detail),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 360, child: records),
              const SizedBox(width: 12),
              Expanded(child: detail),
            ],
          );
        },
      ),
    );
  }

  Widget _recordsList(BuildContext context) {
    return _framed(
      context,
      title: 'Records',
      icon: Icons.article_outlined,
      color: Colors.teal,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_schemaSpec.listMode != 'table') ...[
            _chip(_schemaSpec.listMode.toUpperCase(), Colors.purple),
            const SizedBox(width: 6),
          ],
          _chip('${_records.length}', Colors.teal),
        ],
      ),
      child: _records.isEmpty
          ? Center(
              child: Text(
                _selectedHasRecords
                    ? 'No records'
                    : 'Object namespace — records not applicable.\nBrowse these objects on the Objects screen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView.separated(
              itemCount: _records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final record = _mapFromDynamic(_records[index]);
                final id = _recordId(record);
                final selected =
                    id.isNotEmpty &&
                    id == _recordId(_selectedRecord ?? const {});
                return InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _selectRecord(record),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white10,
                      ),
                    ),
                    // views.list_mode picks the reading mode for the row.
                    child: switch (_schemaSpec.listMode) {
                      'cards' => _recordCardTile(record, id, index),
                      'feed' => _recordFeedTile(record, id, index),
                      _ => _recordTableTile(record, id, index),
                    },
                  ),
                );
              },
            ),
    );
  }

  Widget _recordTableTile(Map<String, dynamic> record, String id, int index) {
    final preview = _recordPreview(record);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          id.isEmpty ? 'record ${index + 1}' : id,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ],
    );
  }

  /// First non-empty list-field value — the record's display title in
  /// cards/feed modes.
  String _recordListTitle(Map<String, dynamic> record, String id, int index) {
    for (final key in _schemaSpec.listFields) {
      final value = record[key];
      if (_hasValue(value)) return _valueText(value);
    }
    return id.isEmpty ? 'record ${index + 1}' : id;
  }

  Widget _recordCardTile(Map<String, dynamic> record, String id, int index) {
    final fields = _schemaSpec.listFields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _recordListTitle(record, id, index),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        for (final key in fields.skip(1))
          if (_hasValue(record[key]) && key != 'is_public')
            Text(
              '${_titleCase(key)}: ${_valueText(record[key])}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (record.containsKey('is_public'))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _chip(
                  schemaBoolIsTrue(record['is_public']) ? 'PUBLIC' : 'PRIVATE',
                  schemaBoolIsTrue(record['is_public'])
                      ? Colors.green
                      : Colors.blueGrey,
                ),
              ),
            Expanded(
              child: Text(
                id,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Colors.white30,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _recordFeedTile(Map<String, dynamic> record, String id, int index) {
    final fields = _schemaSpec.listFields;
    final when = (record['created_at'] ?? record['updated_at'] ?? record['at'])
        ?.toString();
    // The longest remaining list-field value reads as the entry body.
    String? body;
    for (final key in fields.skip(1)) {
      final value = record[key];
      if (!_hasValue(value)) continue;
      final text = _valueText(value);
      if (body == null || text.length > body.length) body = text;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _recordListTitle(record, id, index),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (when != null)
              Text(
                when.length > 16 ? when.substring(0, 16) : when,
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Colors.white30,
                ),
              ),
          ],
        ),
        if (body != null) ...[
          const SizedBox(height: 4),
          Text(
            body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
          ),
        ],
      ],
    );
  }

  Widget _recordDetail(BuildContext context) {
    final record = _selectedRecord;
    final canWrite =
        !_writing && record != null && _recordId(record).isNotEmpty;
    return _framed(
      context,
      title: 'Record Detail',
      icon: Icons.article_outlined,
      color: Colors.blue,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message:
                'Update through PUT /admin/collections/{collection}/records/{record_id}',
            child: OutlinedButton.icon(
              onPressed: canWrite ? _showEditRecordDialog : null,
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('Edit'),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message:
                'Delete through DELETE /admin/collections/{collection}/records/{record_id}',
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: canWrite ? _confirmDeleteRecord : null,
              icon: const Icon(Icons.delete_outline, size: 14),
              label: const Text('Delete'),
            ),
          ),
        ],
      ),
      child: _recordLoading
          ? const Center(child: CircularProgressIndicator())
          : record == null
          ? Center(
              child: Text(
                'No record selected',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView(
              children: [
                ..._orderedRows(record).map((entry) {
                  return _infoRow(entry.key, entry.value);
                }),
                const SizedBox(height: 12),
                _changeList(
                  context,
                  title: 'Record Activity',
                  changes: _recordChanges,
                  expand: false,
                ),
                const SizedBox(height: 12),
                _rawPanel('Raw record payload', {
                  'record': record,
                  if (_recordChanges.isNotEmpty) 'changes': _recordChanges,
                }),
              ],
            ),
    );
  }

  Widget _buildActivityTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _changeList(
        context,
        title: 'Collection Activity',
        changes: _collectionChanges,
      ),
    );
  }

  Widget _changeList(
    BuildContext context, {
    required String title,
    required List<dynamic> changes,
    bool expand = true,
  }) {
    return _framed(
      context,
      title: title,
      icon: Icons.history_outlined,
      color: Colors.purple,
      trailing: _chip('${changes.length}', Colors.purple),
      expandChild: expand,
      child: changes.isEmpty
          ? Center(
              child: Text(
                'No changes',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView.separated(
              shrinkWrap: !expand,
              physics: expand ? null : const NeverScrollableScrollPhysics(),
              itemCount: changes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final change = _mapFromDynamic(changes[index]);
                final action = _firstText(change, const [
                  'action',
                  'type',
                  'event_type',
                  'change_type',
                  'operation',
                ], fallback: 'change');
                final message = _firstText(change, const [
                  'message',
                  'description',
                  'note',
                  'summary',
                ], fallback: action);
                final actor = _firstText(change, const [
                  'actor',
                  'author',
                  'user',
                  'user_id',
                  'principal',
                ], fallback: 'unknown');
                final timestamp = _firstText(change, const [
                  'timestamp',
                  'created_at',
                  'changed_at',
                  'time',
                ]);
                final color = _actionColor(action);
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _chip(action, color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _chip('actor: ${_short(actor, 28)}', Colors.blue),
                          if (timestamp.isNotEmpty)
                            _chip(_short(timestamp, 32), Colors.white54),
                          if (change['record_id'] != null)
                            _chip(
                              'record: ${_short(change['record_id'].toString(), 24)}',
                              Colors.teal,
                            ),
                          if (change['correlation_id'] != null)
                            _chip(
                              'corr: ${_short(change['correlation_id'].toString(), 18)}',
                              Colors.white54,
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _metric(IconData icon, String label, String value, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    List<MapEntry<String, dynamic>> rows,
  ) {
    return _framed(
      context,
      title: title,
      icon: icon,
      color: color,
      trailing: _chip(rows.isEmpty ? 'EMPTY' : 'READ ONLY', color),
      expandChild: false,
      child: rows.isEmpty
          ? Text('Not reported', style: TextStyle(color: Colors.white38))
          : Column(
              children: rows.map((entry) {
                return _infoRow(entry.key, entry.value);
              }).toList(),
            ),
    );
  }

  Widget _framed(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
    Widget? trailing,
    bool expandChild = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              _titleCase(label),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              _valueText(value),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rawPanel(String title, Map<String, dynamic> value) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: TextStyle(fontSize: 12, color: Colors.white54)),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(value),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        _short(text, 44),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<MapEntry<String, dynamic>> _orderedRows(Map<String, dynamic> values) {
    final preferred = [
      'name',
      'collection',
      'id',
      'count',
      'total',
      'record_count',
      'created_at',
      'updated_at',
      'description',
    ];
    final rows = <MapEntry<String, dynamic>>[];
    final used = <String>{};
    for (final key in preferred) {
      final value = values[key];
      if (_hasValue(value)) {
        rows.add(MapEntry(key, value));
        used.add(key);
      }
    }
    for (final entry in values.entries) {
      if (used.contains(entry.key) || !_hasValue(entry.value)) continue;
      rows.add(entry);
    }
    return rows.take(12).toList();
  }

  Map<String, dynamic> _mapFromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is String) return {'name': value};
    return {'value': value};
  }

  Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value == null) return null;
    return _mapFromDynamic(value);
  }

  String _collectionName(Map<String, dynamic> value) {
    final raw =
        value['collection'] ?? value['name'] ?? value['id'] ?? value['key'];
    if (raw is Map) return _collectionName(_mapFromDynamic(raw));
    return raw?.toString() ?? '';
  }

  String _collectionCount(Map<String, dynamic> value) {
    final raw =
        value['count'] ??
        value['record_count'] ??
        value['records_count'] ??
        value['total'];
    return raw == null ? '' : raw.toString();
  }

  /// Servers report object namespaces (directory prefixes like `system`)
  /// alongside record collections; only the latter have record storage.
  bool _hasRecords(Map<String, dynamic> value) {
    final raw = value['has_records'];
    if (raw is bool) return raw;
    return true;
  }

  bool get _selectedHasRecords {
    for (final item in _collections) {
      if (_collectionName(item) == _selectedCollection) {
        return _hasRecords(item);
      }
    }
    return true;
  }

  String _recordId(Map<String, dynamic> value) {
    final raw =
        value['id'] ?? value['record_id'] ?? value['key'] ?? value['name'];
    return raw?.toString() ?? '';
  }

  String _recordPreview(Map<String, dynamic> record) {
    final parts = <String>[];
    // views.list_fields from the schema picks the preview columns.
    final listFields = _schemaSpec.listFields;
    if (listFields.isNotEmpty) {
      for (final key in listFields) {
        final value = record[key];
        if (!_hasValue(value)) continue;
        parts.add('${_titleCase(key)}: ${_valueText(value)}');
        if (parts.length == 3) break;
      }
      if (parts.isNotEmpty) return parts.join('  ');
    }
    for (final entry in record.entries) {
      if (entry.key == 'id' || entry.key == 'record_id') continue;
      if (!_hasValue(entry.value)) continue;
      parts.add('${_titleCase(entry.key)}: ${_valueText(entry.value)}');
      if (parts.length == 2) break;
    }
    return parts.join('  ');
  }

  String _firstText(
    Map<String, dynamic> value,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final raw = value[key]?.toString();
      if (raw != null && raw.trim().isNotEmpty) return raw;
    }
    return fallback;
  }

  Color _actionColor(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('delete')) return Colors.red;
    if (normalized.contains('update') || normalized.contains('change')) {
      return Colors.orange;
    }
    if (normalized.contains('create') || normalized.contains('insert')) {
      return Colors.green;
    }
    return Colors.purple;
  }

  bool _hasValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  String _valueText(dynamic value) {
    if (value == null) return '?';
    if (value is bool) return value ? 'yes' : 'no';
    if (value is List) return '${value.length} items';
    if (value is Map) {
      final entries = value.entries.take(3).map((entry) {
        return '${_titleCase(entry.key.toString())}: ${_valueText(entry.value)}';
      });
      return entries.join(', ');
    }
    return value.toString();
  }

  String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _short(String value, int limit) {
    if (value.length <= limit) return value;
    return '${value.substring(0, limit)}...';
  }
}

class ProbeCrudPanel extends StatefulWidget {
  const ProbeCrudPanel({super.key});

  @override
  State<ProbeCrudPanel> createState() => _ProbeCrudPanelState();
}

class _ProbeCrudPanelState extends State<ProbeCrudPanel> {
  final _idController = TextEditingController(text: 'probe_001');
  final _statusController = TextEditingController(text: 'created');
  final _noteController = TextEditingController(text: 'admin write test');
  Map<String, dynamic>? _schema;
  Map<String, dynamic>? _lastResponse;
  List<dynamic> _records = [];
  List<dynamic> _changes = [];
  String _message = 'Ready';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _idController.dispose();
    _statusController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) {
    final api = ScrollAPI();
    final base = api.objectServerUrl;
    if (base == null || base.isEmpty) {
      return Future.value({'error': 'Object server is not connected'});
    }
    return api.rawRequest(method, '$base$path', data: data);
  }

  Future<void> _refresh({String? completionMessage}) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _message = 'Refreshing probe';
    });

    final schemaResponse = await _request('GET', 'schemas/dbbasic_probe');
    final recordsResponse = await _request(
      'GET',
      'collections/dbbasic_probe/records',
    );
    final changesResponse = await _request(
      'GET',
      'collections/dbbasic_probe/changes',
    );

    if (!mounted) return;
    final schemaBody = schemaResponse['body'];
    final records = _listFromBody(recordsResponse['body'], 'records');
    final changes = _listFromBody(changesResponse['body'], 'changes');
    setState(() {
      _schema = schemaBody is Map<String, dynamic> ? schemaBody : null;
      _records = records;
      _changes = changes;
      _lastResponse = recordsResponse;
      _message =
          completionMessage ??
          'Schema ${_statusText(schemaResponse)}, records ${_statusText(recordsResponse)}, changes ${_statusText(changesResponse)}';
      _busy = false;
    });
  }

  Future<void> _mutate(
    String label,
    Future<Map<String, dynamic>> Function() action,
  ) async {
    setState(() {
      _busy = true;
      _message = '$label in progress';
    });
    final response = await action();
    if (!mounted) return;
    final summary = '$label ${_statusText(response)}';
    if (_isOk(response)) {
      setState(() => _lastResponse = response);
      await _refresh(completionMessage: summary);
      return;
    }
    setState(() {
      _lastResponse = response;
      _message = summary;
      _busy = false;
    });
  }

  Map<String, dynamic> _payload({required bool includeId}) {
    final id = _idController.text.trim();
    return {
      if (includeId) 'id': id,
      'status': _statusController.text.trim(),
      'note': _noteController.text.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<void> _create() {
    return _mutate(
      'Create',
      () => _request(
        'POST',
        'collections/dbbasic_probe/records',
        data: _payload(includeId: true),
      ),
    );
  }

  Future<void> _update() {
    final id = _idController.text.trim();
    return _mutate(
      'Update',
      () => _request(
        'PUT',
        'collections/dbbasic_probe/records/${Uri.encodeComponent(id)}',
        data: _payload(includeId: false),
      ),
    );
  }

  Future<void> _delete() {
    final id = _idController.text.trim();
    return _mutate(
      'Delete',
      () => _request(
        'DELETE',
        'collections/dbbasic_probe/records/${Uri.encodeComponent(id)}',
      ),
    );
  }

  Future<void> _loadRecordChanges() async {
    final id = _idController.text.trim();
    setState(() {
      _busy = true;
      _message = 'Loading record changes';
    });
    final response = await _request(
      'GET',
      'collections/dbbasic_probe/records/${Uri.encodeComponent(id)}/changes',
    );
    if (!mounted) return;
    setState(() {
      _changes = _listFromBody(response['body'], 'changes');
      _lastResponse = response;
      _message = 'Record changes ${_statusText(response)}';
      _busy = false;
    });
  }

  void _selectRecord(dynamic record) {
    final map = _asMap(record);
    final id = map['id']?.toString();
    if (id != null && id.isNotEmpty) _idController.text = id;
    _statusController.text = map['status']?.toString() ?? '';
    _noteController.text = map['note']?.toString() ?? '';
    setState(() => _message = 'Selected ${id ?? 'record'}');
  }

  bool _isOk(Map<String, dynamic> response) {
    final status = response['status'];
    return status is int && status >= 200 && status < 300;
  }

  String _statusText(Map<String, dynamic> response) {
    final error = response['error'];
    if (error != null) return 'error';
    final status = response['status'];
    return status is int ? status.toString() : 'unknown';
  }

  List<dynamic> _listFromBody(dynamic body, String preferredKey) {
    if (body is List) return body;
    if (body is Map) {
      final preferred = body[preferredKey];
      if (preferred is List) return preferred;
      final results = body['results'];
      if (results is List) return results;
      final items = body['items'];
      if (items is List) return items;
    }
    return [];
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return {'value': value};
  }

  String _valueText(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  List<String> _schemaFieldNames() {
    final schema = _schema;
    if (schema == null) return const ['id', 'status', 'note', 'updated_at'];
    final fields = schema['fields'];
    if (fields is Map) return fields.keys.map((key) => key.toString()).toList();
    if (fields is List) {
      return fields
          .map((field) {
            if (field is Map && field['name'] != null) {
              return field['name'].toString();
            }
            return field.toString();
          })
          .where((name) => name.isNotEmpty)
          .toList();
    }
    return const ['id', 'status', 'note', 'updated_at'];
  }

  @override
  Widget build(BuildContext context) {
    final fields = _schemaFieldNames().join(', ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'dbbasic_probe',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 10),
              _statusChip(_busy ? 'BUSY' : _message),
              const Spacer(),
              IconButton(
                onPressed: _busy ? null : () => _refresh(),
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Fields: $fields',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 860;
              final editor = _buildEditor(context);
              final records = _buildRecords(context);
              final changes = _buildChanges(context);
              if (narrow) {
                return Column(
                  children: [
                    editor,
                    const SizedBox(height: 12),
                    records,
                    const SizedBox(height: 12),
                    changes,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 320, child: editor),
                  const SizedBox(width: 12),
                  Expanded(child: records),
                  const SizedBox(width: 12),
                  Expanded(child: changes),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    return _section(
      context,
      title: 'Record',
      child: Column(
        children: [
          _field(_idController, 'id'),
          const SizedBox(height: 8),
          _field(_statusController, 'status'),
          const SizedBox(height: 8),
          _field(_noteController, 'note', maxLines: 3),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Create'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _update,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Update'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _loadRecordChanges,
                icon: const Icon(Icons.history, size: 16),
                label: const Text('Changes'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10),
            ),
            child: SelectableText(
              _lastResponse == null
                  ? '// No response yet'
                  : const JsonEncoder.withIndent('  ').convert(_lastResponse),
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                fontFamily: 'monospace',
                color: _lastResponse == null ? Colors.white24 : Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecords(BuildContext context) {
    return _section(
      context,
      title: 'Records',
      child: SizedBox(
        height: 260,
        child: _records.isEmpty
            ? Center(
                child: Text(
                  'No records',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
              )
            : ListView.separated(
                itemCount: _records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final map = _asMap(_records[index]);
                  final id = _valueText(map['id']);
                  final status = _valueText(map['status']);
                  final note = _valueText(map['note']);
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _selectRecord(map),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  id.isEmpty ? 'record ${index + 1}' : id,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (note.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    note,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (status.isNotEmpty) _statusChip(status),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildChanges(BuildContext context) {
    return _section(
      context,
      title: 'Changes',
      child: SizedBox(
        height: 260,
        child: _changes.isEmpty
            ? Center(
                child: Text(
                  'No changes',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
              )
            : ListView.separated(
                itemCount: _changes.length,
                separatorBuilder: (_, __) => const Divider(height: 14),
                itemBuilder: (context, index) {
                  final map = _asMap(_changes[index]);
                  final label = _valueText(
                    map['action'] ?? map['event'] ?? map['type'],
                  );
                  final id = _valueText(
                    map['record_id'] ?? map['id'] ?? map['object_id'],
                  );
                  final time = _valueText(
                    map['created_at'] ?? map['updated_at'] ?? map['timestamp'],
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label.isEmpty ? 'change ${index + 1}' : label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (id.isNotEmpty) _statusChip(id),
                        ],
                      ),
                      if (time.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          time,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.white38),
                        ),
                      ],
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
      ),
      style: const TextStyle(fontSize: 13),
    );
  }

  Widget _statusChip(String text) {
    final normalized = text.length > 28 ? '${text.substring(0, 25)}...' : text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.green.withValues(alpha: 0.18)),
      ),
      child: Text(
        normalized,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: Colors.green.shade300,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Placeholder
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Invoice Form — sub-data, permissions, the real test
// ---------------------------------------------------------------------------

class InvoiceFormView extends StatelessWidget {
  const InvoiceFormView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 750),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invoice #1043',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          'Draft — not yet sent',
                          style: TextStyle(fontSize: 13, color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.chevron_left, size: 20),
                        tooltip: 'Previous',
                        visualDensity: VisualDensity.compact,
                      ),
                      const Text(
                        '#1043',
                        style: TextStyle(fontSize: 12, color: Colors.white38),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.chevron_right, size: 20),
                        tooltip: 'Next',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Customer section — auto-loaded sub-data
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'CUSTOMER',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white38,
                            letterSpacing: 1,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'auto-loaded from contacts',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'Customer',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            value: 'Acme Corp',
                            items:
                                [
                                      'Acme Corp',
                                      'TechStart',
                                      'DataFlow',
                                      'CloudNine',
                                    ]
                                    .map(
                                      (v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(v),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (_) {},
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Auto-loaded customer details
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.blue.withOpacity(0.15),
                        ),
                      ),
                      child: Column(
                        children: [
                          _subDataRow(
                            'Contact',
                            'Alice Chen — alice@acmecorp.com',
                          ),
                          _subDataRow(
                            'Address',
                            '123 Business Ave, Houston TX 77002',
                          ),
                          _subDataRow('Payment Terms', 'Net 30'),
                          _subDataRow('Outstanding', '\$4,200 (2 invoices)'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Invoice details
              Row(
                children: [
                  Expanded(
                    child: AdminFieldOverlay(
                      fieldName: 'Invoice Date',
                      fieldType: 'date',
                      required: true,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Invoice Date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                        controller: TextEditingController(text: '2026-04-08'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AdminFieldOverlay(
                      fieldName: 'Due Date',
                      fieldType: 'date',
                      required: true,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Due Date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                        controller: TextEditingController(text: '2026-05-08'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AdminFieldOverlay(
                      fieldName: 'Status',
                      fieldType: 'dropdown',
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        value: 'draft',
                        items: ['draft', 'sent', 'paid', 'overdue', 'cancelled']
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Line items — sub-data table
              AdminFieldOverlay(
                fieldName: 'Line Items',
                fieldType: 'sub_table',
                rolePermissions: const {'sales': 'edit'},
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'LINE ITEMS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white38,
                            letterSpacing: 1,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text(
                            'Add Line',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DataTable(
                        headingRowHeight: 36,
                        dataRowMinHeight: 40,
                        dataRowMaxHeight: 40,
                        columnSpacing: 16,
                        headingTextStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white54,
                        ),
                        dataTextStyle: const TextStyle(fontSize: 13),
                        columns: const [
                          DataColumn(label: Text('Product')),
                          DataColumn(label: Text('Description')),
                          DataColumn(label: Text('Qty'), numeric: true),
                          DataColumn(label: Text('Unit Price'), numeric: true),
                          DataColumn(label: Text('Total'), numeric: true),
                          DataColumn(label: Text('')),
                        ],
                        rows: [
                          _lineItem(
                            'Web Hosting',
                            'Annual plan — Pro tier',
                            1,
                            299.00,
                          ),
                          _lineItem(
                            'SSL Certificate',
                            'Wildcard, 1 year',
                            2,
                            79.00,
                          ),
                          _lineItem(
                            'Support Hours',
                            'Priority support block',
                            10,
                            150.00,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Totals
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _totalRow('Subtotal', '\$1,957.00'),
                    _totalRow('Tax (8.25%)', '\$161.45'),
                    const Divider(),
                    _totalRow('Total', '\$2,118.45', bold: true, large: true),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Notes
              AdminFieldOverlay(
                fieldName: 'Notes',
                fieldType: 'textarea',
                rolePermissions: const {'sales': 'read'},
                child: TextField(
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  controller: TextEditingController(
                    text:
                        'Payment due within 30 days. Thank you for your business.',
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Ownership & permissions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 16,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Owner: you',
                          style: TextStyle(fontSize: 12, color: Colors.white38),
                        ),
                        const Spacer(),
                        Text(
                          'Access: ROLE-BASED',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      children: [
                        Icon(Icons.visibility, size: 14, color: Colors.white24),
                        const SizedBox(width: 6),
                        Text(
                          'Field Permissions (your role: admin)',
                          style: TextStyle(fontSize: 11, color: Colors.white38),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _permChip('Customer', true, true),
                        _permChip('Dates', true, true),
                        _permChip('Line Items', true, true),
                        _permChip('Totals', true, false),
                        _permChip('Notes', true, true),
                        _permChip('Status', true, true),
                        _permChip('Cost Price', false, false),
                        _permChip('Margin', false, false),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 13,
                          color: Colors.white24,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '"sales" role cannot see Cost Price or Margin fields. Totals are read-only for non-admin.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white30,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('Save & Send'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('PDF'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Print'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: Colors.amber,
                    ),
                    label: const Text(
                      'AI Fill',
                      style: TextStyle(color: Colors.amber),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _lineItem(String product, String desc, int qty, double price) {
    return DataRow(
      cells: [
        DataCell(Text(product)),
        DataCell(
          Text(desc, style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        DataCell(Text('$qty')),
        DataCell(Text('\$${price.toStringAsFixed(2)}')),
        DataCell(
          Text(
            '\$${(qty * price).toStringAsFixed(2)}',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        DataCell(
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.close, size: 14),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _subDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _totalRow(
    String label,
    String value, {
    bool bold = false,
    bool large = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: large ? 15 : 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: large ? 18 : 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: bold ? Colors.green[300] : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _permChip(String field, bool canView, bool canEdit) {
    final color = !canView
        ? Colors.red
        : (canEdit ? Colors.green : Colors.orange);
    final label = !canView ? 'hidden' : (canEdit ? 'edit' : 'read');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$field ',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Placeholder
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Schema Editor (admin read-only schema inspection)
// ---------------------------------------------------------------------------

class SchemaEditorView extends StatefulWidget {
  const SchemaEditorView({super.key});

  @override
  State<SchemaEditorView> createState() => _SchemaEditorViewState();
}

class _SchemaEditorViewState extends State<SchemaEditorView> {
  List<Map<String, dynamic>> _schemas = [];
  String? _selectedSchema;
  Map<String, dynamic>? _schemaDetail;
  List<dynamic> _versions = [];
  dynamic _versionDetail;
  int? _selectedVersionNumber;
  String _tab = 'Fields';
  bool _loading = true;
  bool _detailLoading = false;
  bool _versionLoading = false;
  bool _writing = false;
  Map<String, dynamic>? _writeResponse;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSchemas();
  }

  Future<void> _loadSchemas() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ScrollAPI().listAdminSchemas();
      final schemas = raw
          .map(_mapFromDynamic)
          .where((schema) => _schemaName(schema).isNotEmpty)
          .toList();
      final current = _selectedSchema;
      final selected = schemas.any((item) => _schemaName(item) == current)
          ? current
          : (schemas.isNotEmpty ? _schemaName(schemas.first) : null);
      if (!mounted) return;
      setState(() {
        _schemas = schemas;
        _selectedSchema = selected;
        _loading = false;
      });
      if (selected != null) await _loadSchema(selected);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadSchema(String schema) async {
    setState(() {
      _detailLoading = true;
      _schemaDetail = null;
      _versions = [];
      _versionDetail = null;
      _selectedVersionNumber = null;
    });
    final api = ScrollAPI();
    final responses = await Future.wait<dynamic>([
      api.getAdminSchema(schema),
      api.getAdminSchemaVersions(schema, limit: 10),
    ]);
    if (!mounted) return;
    setState(() {
      _schemaDetail = _mapOrNull(responses[0]);
      _versions = responses[1] is List ? responses[1] as List : const [];
      _detailLoading = false;
    });
  }

  Future<void> _selectSchema(String schema) async {
    setState(() {
      _selectedSchema = schema;
      _tab = 'Fields';
    });
    await _loadSchema(schema);
  }

  Future<void> _loadVersion(dynamic rawVersion) async {
    final schema = _selectedSchema;
    final version = _versionNumber(rawVersion);
    if (schema == null || version == null) {
      setState(() {
        _versionDetail = rawVersion;
        _selectedVersionNumber = null;
      });
      return;
    }
    setState(() {
      _versionLoading = true;
      _versionDetail = null;
      _selectedVersionNumber = version;
    });
    final detail = await ScrollAPI().getAdminSchemaVersion(schema, version);
    if (!mounted) return;
    setState(() {
      _versionDetail = detail ?? rawVersion;
      _versionLoading = false;
    });
  }

  Future<void> _showEditSchemaDialog() async {
    final schema = _selectedSchema;
    if (schema == null) return;
    final detail = _schemaDetail ?? const <String, dynamic>{};
    final schemaBody = detail['schema'] is Map
        ? _mapFromDynamic(detail['schema'])
        : detail;
    final schemaController = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(schemaBody),
    );
    final authorController = TextEditingController(text: 'scroll-operator');
    final messageController = TextEditingController();
    String? parseError;
    final submitted = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text('Edit $schema schema'),
              content: SizedBox(
                width: 680,
                height: 520,
                child: Column(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: schemaController,
                        maxLines: null,
                        expands: true,
                        decoration: const InputDecoration(
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                          labelText: 'Schema JSON',
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: authorController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Author',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: messageController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Message',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (parseError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          parseError!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[300],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    try {
                      final decoded =
                          jsonDecode(schemaController.text) as Object?;
                      if (decoded is! Map<String, dynamic>) {
                        setDialogState(
                          () => parseError = 'Schema JSON must be an object',
                        );
                        return;
                      }
                      Navigator.of(dialogContext).pop(decoded);
                    } catch (e) {
                      setDialogState(() => parseError = 'Invalid JSON: $e');
                    }
                  },
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save Schema'),
                ),
              ],
            );
          },
        );
      },
    );
    final author = authorController.text;
    final message = messageController.text;
    schemaController.dispose();
    authorController.dispose();
    messageController.dispose();
    if (submitted == null || !mounted) return;
    await _runSchemaWrite(
      () => ScrollAPI().updateAdminSchema(
        schema,
        schema: submitted,
        author: author,
        message: message,
      ),
    );
  }

  Future<void> _confirmRollbackSchema() async {
    final schema = _selectedSchema;
    final version = _selectedVersionNumber;
    if (schema == null || version == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rollback schema?'),
          content: Text(
            'POST /admin/schemas/$schema with '
            '{"action": "rollback", "version_id": $version}\n\n'
            'The restored schema is recorded as a new schema version.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange[800],
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.history, size: 16),
              label: Text('Rollback to v$version'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _runSchemaWrite(
      () => ScrollAPI().rollbackAdminSchema(schema, version),
    );
  }

  Future<void> _runSchemaWrite(
    Future<Map<String, dynamic>> Function() write,
  ) async {
    final schema = _selectedSchema;
    if (schema == null) return;
    setState(() {
      _writing = true;
      _writeResponse = null;
    });
    final result = await write();
    if (!mounted) return;
    setState(() {
      _writing = false;
      _writeResponse = result;
    });
    await _loadSchema(schema);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 240,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'SCHEMAS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white38,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_schemas.length}',
                      style: TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                    IconButton(
                      onPressed: _loading ? null : _loadSchemas,
                      icon: const Icon(Icons.refresh, size: 16),
                      tooltip: 'Refresh',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Failed to load schemas',
                            style: TextStyle(color: Colors.red[300]),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemCount: _schemas.length,
                        itemBuilder: (context, index) {
                          final schema = _schemas[index];
                          final name = _schemaName(schema);
                          final selected = name == _selectedSchema;
                          return ListTile(
                            dense: true,
                            selected: selected,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.2),
                            leading: Icon(
                              Icons.schema_outlined,
                              size: 18,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white38,
                            ),
                            title: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                            trailing: Text(
                              _schemaCount(schema),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white38,
                              ),
                            ),
                            onTap: () => _selectSchema(name),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        Container(width: 1, color: Colors.white10),
        Expanded(child: _buildDetail(context)),
      ],
    );
  }

  Widget _buildDetail(BuildContext context) {
    final schema = _selectedSchema;
    if (schema == null) {
      return Center(
        child: Text('No schemas', style: TextStyle(color: Colors.white38)),
      );
    }
    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Icon(Icons.schema_outlined, size: 18, color: Colors.purple),
              const SizedBox(width: 8),
              Text(
                schema,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 10),
              _chip('SCHEMA WRITES ADMIN', Colors.orange),
              const SizedBox(width: 18),
              ..._tabButton('Overview'),
              ..._tabButton('Fields'),
              ..._tabButton('Versions'),
              const Spacer(),
              Tooltip(
                message: 'Replace through PUT /admin/schemas/$schema',
                child: FilledButton.icon(
                  onPressed: _writing ? null : _showEditSchemaDialog,
                  icon: _writing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit, size: 16),
                  label: const Text('Edit Schema'),
                ),
              ),
            ],
          ),
        ),
        if (_writeResponse != null) _writeResponsePanel(),
        Expanded(
          child: _detailLoading
              ? const Center(child: CircularProgressIndicator())
              : switch (_tab) {
                  'Overview' => _buildOverviewTab(context),
                  'Versions' => _buildVersionsTab(context),
                  _ => _buildFieldsTab(context),
                },
        ),
      ],
    );
  }

  Widget _writeResponsePanel() {
    final response = _writeResponse ?? const <String, dynamic>{};
    final status = response['status'];
    final ok = status is int && status >= 200 && status < 300;
    final color = ok ? Colors.green : Colors.red;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(response),
              maxLines: 6,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _writeResponse = null),
            icon: const Icon(Icons.close, size: 14),
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  List<Widget> _tabButton(String label) {
    final active = _tab == label;
    return [
      InkWell(
        onTap: () => setState(() => _tab = label),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white38,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
      const SizedBox(width: 2),
    ];
  }

  Widget _buildOverviewTab(BuildContext context) {
    Map<String, dynamic>? selected;
    for (final item in _schemas) {
      if (_schemaName(item) == _selectedSchema) {
        selected = item;
        break;
      }
    }
    final detail = _schemaDetail ?? const <String, dynamic>{};
    final fields = _schemaFields(detail);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric(
                Icons.view_column_outlined,
                'Fields',
                '${fields.length}',
                Colors.purple,
              ),
              _metric(
                Icons.history_outlined,
                'Versions',
                '${_versions.length}',
                Colors.blue,
              ),
              _metric(
                Icons.shield_outlined,
                'Access',
                _valueText(detail['access'] ?? detail['mode'] ?? 'admin'),
                Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _infoCard(
                  context,
                  'Schema List Row',
                  Icons.list_alt_outlined,
                  Colors.purple,
                  _orderedRows(selected ?? const {}),
                ),
                _infoCard(
                  context,
                  'Schema Detail',
                  Icons.info_outline,
                  Colors.blue,
                  _orderedRows(detail),
                ),
              ];
              if (constraints.maxWidth < 900) {
                return Column(
                  children: [
                    cards.first,
                    const SizedBox(height: 12),
                    cards.last,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards.first),
                  const SizedBox(width: 12),
                  Expanded(child: cards.last),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _rawPanel('Raw schema payload', {
            if (selected != null) 'list_row': selected,
            if (detail.isNotEmpty) 'detail': detail,
          }),
        ],
      ),
    );
  }

  Widget _buildFieldsTab(BuildContext context) {
    final fields = _schemaFields(_schemaDetail ?? const {});
    return Container(
      color: Colors.black26,
      padding: const EdgeInsets.all(16),
      child: _framed(
        context,
        title: 'Fields',
        icon: Icons.view_column_outlined,
        color: Colors.purple,
        trailing: _chip('${fields.length}', Colors.purple),
        child: fields.isEmpty
            ? Center(
                child: Text(
                  'No fields',
                  style: TextStyle(color: Colors.white38),
                ),
              )
            : SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 36,
                    dataRowMinHeight: 42,
                    dataRowMaxHeight: 52,
                    columnSpacing: 24,
                    headingTextStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white54,
                    ),
                    columns: const [
                      DataColumn(label: Text('Field')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Required')),
                      DataColumn(label: Text('Relation')),
                      DataColumn(label: Text('Validation')),
                    ],
                    rows: fields.map((field) {
                      final name = _fieldValue(field, const ['name', 'field']);
                      final type = _fieldValue(field, const [
                        'type',
                        'field_type',
                        'kind',
                      ], fallback: '?');
                      final required = _boolValue(
                        field['required'] ?? field['nullable'] == false,
                      );
                      final relation = _fieldValue(field, const [
                        'relation',
                        'references',
                        'ref',
                        'foreign_key',
                      ]);
                      final validation = _fieldValue(field, const [
                        'validation',
                        'constraints',
                        'rule',
                        'rules',
                      ]);
                      final typeColor = _typeColor(type);
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              name,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
                          ),
                          DataCell(_chip(type, typeColor)),
                          DataCell(
                            required
                                ? Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.green,
                                  )
                                : Icon(
                                    Icons.remove,
                                    size: 16,
                                    color: Colors.white24,
                                  ),
                          ),
                          DataCell(
                            Text(
                              relation.isEmpty ? '-' : relation,
                              style: TextStyle(
                                color: relation.isEmpty
                                    ? Colors.white24
                                    : Colors.blue,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              validation.isEmpty ? '-' : validation,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildVersionsTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final list = _framed(
            context,
            title: 'Versions',
            icon: Icons.history_outlined,
            color: Colors.blue,
            trailing: _chip('${_versions.length}', Colors.blue),
            child: _versions.isEmpty
                ? Center(
                    child: Text(
                      'No versions',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.separated(
                    itemCount: _versions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final version = _mapFromDynamic(_versions[index]);
                      final label = _versionLabel(version);
                      final created = _fieldValue(version, const [
                        'created_at',
                        'timestamp',
                        'date',
                      ]);
                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _loadVersion(_versions[index]),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              _chip(label, Colors.blue),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  created.isEmpty ? 'version detail' : created,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          );
          final detail = _framed(
            context,
            title: 'Version Detail',
            icon: Icons.info_outline,
            color: Colors.purple,
            trailing: Tooltip(
              message:
                  'Restore through POST /admin/schemas/{collection} with action=rollback',
              child: OutlinedButton.icon(
                onPressed: !_writing && _selectedVersionNumber != null
                    ? _confirmRollbackSchema
                    : null,
                icon: const Icon(Icons.history, size: 14),
                label: Text(
                  _selectedVersionNumber == null
                      ? 'Rollback'
                      : 'Rollback to v$_selectedVersionNumber',
                ),
              ),
            ),
            child: _versionLoading
                ? const Center(child: CircularProgressIndicator())
                : _versionDetail == null
                ? Center(
                    child: Text(
                      'No version selected',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : SingleChildScrollView(
                    child: SelectableText(
                      const JsonEncoder.withIndent(
                        '  ',
                      ).convert(_versionDetail),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ),
          );
          if (constraints.maxWidth < 860) {
            return Column(
              children: [
                Expanded(child: list),
                const SizedBox(height: 12),
                Expanded(child: detail),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 360, child: list),
              const SizedBox(width: 12),
              Expanded(child: detail),
            ],
          );
        },
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    List<MapEntry<String, dynamic>> rows,
  ) {
    return _framed(
      context,
      title: title,
      icon: icon,
      color: color,
      trailing: _chip(rows.isEmpty ? 'EMPTY' : 'READ ONLY', color),
      expandChild: false,
      child: rows.isEmpty
          ? Text('Not reported', style: TextStyle(color: Colors.white38))
          : Column(
              children: rows.map((entry) {
                return _infoRow(entry.key, entry.value);
              }).toList(),
            ),
    );
  }

  Widget _framed(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
    Widget? trailing,
    bool expandChild = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              _titleCase(label),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              _valueText(value),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rawPanel(String title, Map<String, dynamic> value) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: TextStyle(fontSize: 12, color: Colors.white54)),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(value),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        _short(text, 44),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _schemaFields(Map<String, dynamic> schema) {
    final candidate =
        schema['fields'] ??
        schema['columns'] ??
        schema['properties'] ??
        _mapFromDynamic(schema['schema'])['fields'];
    if (candidate is Map) {
      return candidate.entries.map((entry) {
        final value = _mapFromDynamic(entry.value);
        return {'name': entry.key.toString(), ...value};
      }).toList();
    }
    if (candidate is List) {
      return candidate.map((field) {
        final map = _mapFromDynamic(field);
        return map['name'] == null && map['field'] == null
            ? {'name': field.toString()}
            : map;
      }).toList();
    }
    return const [];
  }

  List<MapEntry<String, dynamic>> _orderedRows(Map<String, dynamic> values) {
    final preferred = [
      'name',
      'collection',
      'id',
      'version',
      'fields_count',
      'field_count',
      'created_at',
      'updated_at',
      'description',
    ];
    final rows = <MapEntry<String, dynamic>>[];
    final used = <String>{};
    for (final key in preferred) {
      final value = values[key];
      if (_hasValue(value)) {
        rows.add(MapEntry(key, value));
        used.add(key);
      }
    }
    for (final entry in values.entries) {
      if (used.contains(entry.key) || !_hasValue(entry.value)) continue;
      rows.add(entry);
    }
    return rows.take(12).toList();
  }

  Map<String, dynamic> _mapFromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is String) return {'name': value};
    return {'value': value};
  }

  Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value == null) return null;
    return _mapFromDynamic(value);
  }

  String _schemaName(Map<String, dynamic> value) {
    final raw =
        value['collection'] ?? value['schema'] ?? value['name'] ?? value['id'];
    if (raw is Map) return _schemaName(_mapFromDynamic(raw));
    return raw?.toString() ?? '';
  }

  String _schemaCount(Map<String, dynamic> value) {
    final raw =
        value['field_count'] ??
        value['fields_count'] ??
        value['count'] ??
        value['total'];
    return raw == null ? '' : raw.toString();
  }

  String _fieldValue(
    Map<String, dynamic> value,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final raw = value[key];
      if (!_hasValue(raw)) continue;
      return _valueText(raw);
    }
    return fallback;
  }

  bool _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase();
      return normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'required';
    }
    return false;
  }

  int? _versionNumber(dynamic raw) {
    final map = _mapFromDynamic(raw);
    final value =
        map['version'] ?? map['id'] ?? map['version_id'] ?? map['revision'];
    if (value is int) return value;
    final text = value?.toString() ?? raw.toString();
    final match = RegExp(r'\d+').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  String _versionLabel(Map<String, dynamic> version) {
    final value =
        version['version'] ??
        version['id'] ??
        version['version_id'] ??
        version['revision'] ??
        '?';
    final text = value.toString();
    return text.startsWith('v') ? text : 'v$text';
  }

  Color _typeColor(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('relation') || normalized.contains('ref')) {
      return Colors.blue;
    }
    if (normalized.contains('computed')) return Colors.purple;
    if (normalized.contains('enum')) return Colors.orange;
    if (normalized.contains('list') || normalized.contains('array')) {
      return Colors.teal;
    }
    return Colors.white54;
  }

  bool _hasValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  String _valueText(dynamic value) {
    if (value == null) return '?';
    if (value is bool) return value ? 'yes' : 'no';
    if (value is List) return '${value.length} items';
    if (value is Map) {
      final entries = value.entries.take(3).map((entry) {
        return '${_titleCase(entry.key.toString())}: ${_valueText(entry.value)}';
      });
      return entries.join(', ');
    }
    return value.toString();
  }

  String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _short(String value, int limit) {
    if (value.length <= limit) return value;
    return '${value.substring(0, limit)}...';
  }
}

// ---------------------------------------------------------------------------
// Package Manager (admin) — install objects from dbbasic.com
// ---------------------------------------------------------------------------

class PackageManagerView extends StatefulWidget {
  const PackageManagerView({super.key});

  @override
  State<PackageManagerView> createState() => _PackageManagerViewState();
}

class _PackageManagerViewState extends State<PackageManagerView> {
  final _searchController = TextEditingController();
  bool _refreshing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await ScrollData().loadAll();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final data = ScrollData();
    final allPackages = data.adminPackages.map(_PackageStatus.fromMap).toList();
    final query = _searchController.text.trim().toLowerCase();
    final packages = allPackages.where((package) {
      if (query.isEmpty) return true;
      return package.name.toLowerCase().contains(query) ||
          package.status.toLowerCase().contains(query) ||
          package.source.toLowerCase().contains(query);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Package Manager',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(width: 12),
              Text(
                data.hasAdminStatus ? data.packageSummary : '/admin/status',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
              const Spacer(),
              IconButton(
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh packages',
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 250,
                height: 36,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search packages...',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            data.hasAdminStatus
                ? 'Package posture from the connected object server. Installs stay disabled on public staging unless explicitly enabled.'
                : 'Package status is unavailable until /admin/status returns an authenticated response.',
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: packages.isEmpty
                ? _emptyPackages(context, data.hasAdminStatus)
                : ListView.separated(
                    itemCount: packages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = packages[i];
                      final color = _statusColor(p.status);
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                p.installed
                                    ? Icons.check
                                    : Icons.extension_outlined,
                                size: 20,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          p.displayName,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (p.version.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          'v${p.version}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.white38,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      _packageChip(p.source, Colors.blue),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    p.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _packageChip(p.statusLabel, color),
                                const SizedBox(height: 8),
                                if (p.installed)
                                  OutlinedButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.check, size: 14),
                                    label: const Text('Installed'),
                                  )
                                else
                                  Tooltip(
                                    message:
                                        'Package installs are disabled on public staging',
                                    child: OutlinedButton.icon(
                                      onPressed: null,
                                      icon: const Icon(Icons.lock, size: 14),
                                      label: const Text('Install locked'),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyPackages(BuildContext context, bool hasAdminStatus) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasAdminStatus ? Icons.search_off : Icons.lock_outline,
              size: 32,
              color: Colors.white38,
            ),
            const SizedBox(height: 10),
            Text(
              hasAdminStatus
                  ? 'No packages match this search'
                  : 'Package posture unavailable',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              hasAdminStatus
                  ? 'Clear the search filter to see reported packages.'
                  : 'Connect with an admin Bearer token so /admin/status can report package state.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _packageChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'installed') return Colors.green;
    if (normalized == 'available') return Theme.of(context).colorScheme.primary;
    if (normalized == 'disabled' || normalized == 'blocked') {
      return Colors.orange;
    }
    return Colors.white54;
  }
}

class _PackageStatus {
  final String name;
  final String displayName;
  final String description;
  final String source;
  final String version;
  final String status;

  const _PackageStatus({
    required this.name,
    required this.displayName,
    required this.description,
    required this.source,
    required this.version,
    required this.status,
  });

  bool get installed => status.toLowerCase() == 'installed';
  String get statusLabel => _titleCase(status);

  factory _PackageStatus.fromMap(Map<String, dynamic> data) {
    final name =
        data['name']?.toString() ??
        data['id']?.toString() ??
        data['package']?.toString() ??
        'package';
    final status =
        data['status']?.toString() ??
        data['state']?.toString() ??
        data['value']?.toString() ??
        (data['installed'] == true ? 'installed' : 'available');
    final source =
        data['source']?.toString() ??
        data['author']?.toString() ??
        data['publisher']?.toString() ??
        'object-server';
    final version = data['version']?.toString() ?? '';
    final description =
        data['description']?.toString() ?? _defaultDescription(name, status);
    return _PackageStatus(
      name: name,
      displayName: _titleCase(name),
      description: description,
      source: source,
      version: version,
      status: status,
    );
  }

  static String _defaultDescription(String name, String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'installed') {
      return 'Installed package reported by the connected object server.';
    }
    return 'Available package reported by the connected object server.';
  }

  static String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

// ---------------------------------------------------------------------------
// Placeholder
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Visual Diagram — ER/UML style relationships between collections
// ---------------------------------------------------------------------------

class DiagramView extends StatelessWidget {
  const DiagramView({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background grid
        CustomPaint(size: Size.infinite, painter: _GridPainter()),
        // Connection lines (drawn behind boxes)
        CustomPaint(size: Size.infinite, painter: _RelationPainter()),
        // Collection boxes
        _collectionBox(
          context,
          'Contacts',
          [
            'first_name',
            'last_name',
            'email',
            'phone',
            'organization_id → Orgs',
            'lead_status',
          ],
          left: 60,
          top: 40,
          color: Colors.blue,
        ),
        _collectionBox(
          context,
          'Organizations',
          ['name', 'website', 'industry', 'address', 'phone'],
          left: 380,
          top: 20,
          color: Colors.teal,
        ),
        _collectionBox(
          context,
          'Invoices',
          [
            'customer_id → Contacts',
            'invoice_date',
            'due_date',
            'status',
            'line_items → Products',
            'total (computed)',
          ],
          left: 60,
          top: 320,
          color: Colors.purple,
        ),
        _collectionBox(
          context,
          'Products',
          ['name', 'description', 'price', 'sku', 'stock', 'category'],
          left: 380,
          top: 280,
          color: Colors.orange,
        ),
        _collectionBox(
          context,
          'Orders',
          [
            'customer_id → Contacts',
            'order_date',
            'status',
            'items → Products',
            'shipping_address',
            'total (computed)',
          ],
          left: 680,
          top: 140,
          color: Colors.green,
        ),
        _collectionBox(
          context,
          'Tasks',
          [
            'title',
            'description',
            'project_id → Projects',
            'assignee_id → Users',
            'status',
            'due_date',
          ],
          left: 680,
          top: 420,
          color: Colors.red,
        ),
        _collectionBox(
          context,
          'Projects',
          ['name', 'description', 'status', 'owner_id → Users'],
          left: 380,
          top: 510,
          color: Colors.indigo,
        ),
        // Toolbar
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.zoom_in, size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Zoom In',
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.zoom_out, size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Zoom Out',
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.fit_screen, size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Fit to Screen',
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.add, size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Add Collection',
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.image_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Export Image',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _collectionBox(
    BuildContext context,
    String name,
    List<String> fields, {
    required double left,
    required double top,
    required Color color,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(7),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.storage, size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${fields.length}',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
            ),
            // Fields
            ...fields.map((f) {
              final isRelation = f.contains('→');
              final isComputed = f.contains('(computed)');
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 3,
                ),
                child: Row(
                  children: [
                    Icon(
                      isRelation
                          ? Icons.link
                          : (isComputed ? Icons.functions : Icons.remove),
                      size: 12,
                      color: isRelation
                          ? Colors.blue
                          : (isComputed ? Colors.purple : Colors.white24),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        f,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: isRelation
                              ? Colors.blue[200]
                              : (isComputed
                                    ? Colors.purple[200]
                                    : Colors.white54),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RelationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Contacts → Organizations
    _drawArrow(canvas, paint, const Offset(320, 100), const Offset(380, 60));
    // Invoices → Contacts
    _drawArrow(canvas, paint, const Offset(150, 320), const Offset(150, 260));
    // Invoices → Products
    _drawArrow(canvas, paint, const Offset(320, 400), const Offset(380, 360));
    // Orders → Contacts
    paint.color = Colors.green.withOpacity(0.3);
    _drawArrow(canvas, paint, const Offset(680, 200), const Offset(320, 120));
    // Orders → Products
    _drawArrow(canvas, paint, const Offset(680, 240), const Offset(640, 340));
    // Tasks → Projects
    paint.color = Colors.red.withOpacity(0.3);
    _drawArrow(canvas, paint, const Offset(680, 500), const Offset(640, 540));
  }

  void _drawArrow(Canvas canvas, Paint paint, Offset from, Offset to) {
    canvas.drawLine(from, to, paint);
    // Arrowhead
    final angle = (to - from).direction;
    final arrowSize = 8.0;
    canvas.drawLine(
      to,
      Offset(
        to.dx -
            arrowSize * (to - from).normalized.dx +
            arrowSize * 0.4 * (to - from).normalized.dy,
        to.dy -
            arrowSize * (to - from).normalized.dy -
            arrowSize * 0.4 * (to - from).normalized.dx,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

extension on Offset {
  Offset get normalized {
    final d = distance;
    return d == 0 ? this : Offset(dx / d, dy / d);
  }
}

// ---------------------------------------------------------------------------
// Identity registry (admin)
// ---------------------------------------------------------------------------

enum _IdentitySection { users, accounts, sessions }

class IdentityRegistryView extends StatefulWidget {
  const IdentityRegistryView({super.key});

  @override
  State<IdentityRegistryView> createState() => _IdentityRegistryViewState();
}

class _IdentityRegistryViewState extends State<IdentityRegistryView> {
  _IdentitySection _section = _IdentitySection.users;
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _selectedRow;
  Map<String, dynamic>? _selectedDetail;
  String? _selectedId;
  String? _accountFilter;
  bool _loading = true;
  bool _listLoading = false;
  bool _detailLoading = false;
  bool _passwordWriting = false;
  Map<String, dynamic>? _passwordResponse;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ScrollAPI();
      final responses = await Future.wait<dynamic>([
        api.listAdminIdentityAccounts(),
        api.listAdminIdentityUsers(accountId: _accountFilter),
        api.listAdminIdentitySessions(),
      ]);
      final accounts = _mapsFromList(responses[0]);
      final normalizedFilter =
          _accountFilter != null &&
              accounts.any((account) {
                return _identityId(account, _IdentitySection.accounts) ==
                    _accountFilter;
              })
          ? _accountFilter
          : null;
      final users = normalizedFilter == _accountFilter
          ? _mapsFromList(responses[1])
          : _mapsFromList(await api.listAdminIdentityUsers());
      final sessions = _mapsFromList(responses[2]);
      final rows = _rowsFor(
        _section,
        accounts: accounts,
        users: users,
        sessions: sessions,
      );
      final selected = _selectedForRows(rows);
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _users = users;
        _sessions = sessions;
        _accountFilter = normalizedFilter;
        _selectedRow = selected;
        _selectedId = selected == null ? null : _identityId(selected, _section);
        _selectedDetail = null;
        _loading = false;
      });
      if (selected != null) await _loadDetail(_section, selected);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _reloadUsersForFilter(String? accountId) async {
    setState(() {
      _section = _IdentitySection.users;
      _accountFilter = accountId;
      _listLoading = true;
      _selectedRow = null;
      _selectedId = null;
      _selectedDetail = null;
      _error = null;
    });
    try {
      final raw = await ScrollAPI().listAdminIdentityUsers(
        accountId: accountId,
      );
      final users = _mapsFromList(raw);
      final selected = users.isEmpty ? null : users.first;
      if (!mounted) return;
      setState(() {
        _users = users;
        _selectedRow = selected;
        _selectedId = selected == null
            ? null
            : _identityId(selected, _IdentitySection.users);
        _listLoading = false;
      });
      if (selected != null) {
        await _loadDetail(_IdentitySection.users, selected);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _setSection(_IdentitySection section) async {
    final rows = _rowsFor(section);
    final selected = rows.isEmpty ? null : rows.first;
    setState(() {
      _section = section;
      _selectedRow = selected;
      _selectedId = selected == null ? null : _identityId(selected, section);
      _selectedDetail = null;
    });
    if (selected != null) await _loadDetail(section, selected);
  }

  Future<void> _selectRow(Map<String, dynamic> row) async {
    setState(() {
      _selectedRow = row;
      _selectedId = _identityId(row, _section);
      _selectedDetail = null;
    });
    await _loadDetail(_section, row);
  }

  Future<void> _loadDetail(
    _IdentitySection section,
    Map<String, dynamic> row,
  ) async {
    final id = _identityId(row, section);
    if (id.isEmpty) return;
    setState(() => _detailLoading = true);
    final api = ScrollAPI();
    final result = switch (section) {
      _IdentitySection.accounts => await api.getAdminIdentityAccount(id),
      _IdentitySection.users => await api.getAdminIdentityUser(id),
      _IdentitySection.sessions => await api.getAdminIdentitySession(id),
    };
    if (!mounted || _section != section || _selectedId != id) return;
    setState(() {
      _selectedDetail = result;
      _detailLoading = false;
    });
  }

  Future<void> _showSetPasswordDialog() async {
    final userId = _selectedUserId;
    if (userId == null) return;
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    String? validationError;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text('Set password for $userId'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      autofocus: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'New password',
                        helperText: '8-1024 characters',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Confirm password',
                      ),
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          validationError!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[300],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final password = passwordController.text;
                    if (password.length < 8) {
                      setDialogState(
                        () => validationError =
                            'Password must be at least 8 characters',
                      );
                      return;
                    }
                    if (password != confirmController.text) {
                      setDialogState(
                        () => validationError = 'Passwords do not match',
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  icon: const Icon(Icons.password_outlined, size: 16),
                  label: const Text('Set Password'),
                ),
              ],
            );
          },
        );
      },
    );
    final password = passwordController.text;
    passwordController.dispose();
    confirmController.dispose();
    if (submitted != true || !mounted) return;
    setState(() {
      _passwordWriting = true;
      _passwordResponse = null;
    });
    final result = await ScrollAPI().setAdminUserPassword(userId, password);
    if (!mounted) return;
    setState(() {
      _passwordWriting = false;
      _passwordResponse = result;
    });
  }

  Future<void> _confirmRemovePassword() async {
    final userId = _selectedUserId;
    if (userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove password?'),
          content: Text(
            'DELETE /admin/identity/users/$userId/password\n\n'
            'The user can no longer sign in with a password until a new one is set.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.key_off_outlined, size: 16),
              label: const Text('Remove Password'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _passwordWriting = true;
      _passwordResponse = null;
    });
    final result = await ScrollAPI().removeAdminUserPassword(userId);
    if (!mounted) return;
    setState(() {
      _passwordWriting = false;
      _passwordResponse = result;
    });
  }

  String? get _selectedUserId {
    if (_section != _IdentitySection.users) return null;
    final row = _selectedRow;
    if (row == null) return null;
    final id = _identityId(row, _IdentitySection.users);
    return id.isEmpty ? null : id;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 280,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'IDENTITY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white38,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_rowsFor(_section).length}',
                      style: TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                    IconButton(
                      onPressed: _loading ? null : _loadIdentity,
                      icon: const Icon(Icons.refresh, size: 16),
                      tooltip: 'Refresh',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              _sectionTile(
                context,
                _IdentitySection.users,
                Icons.manage_accounts_outlined,
                'Users',
                _users.length,
                Colors.blue,
              ),
              _sectionTile(
                context,
                _IdentitySection.accounts,
                Icons.business_outlined,
                'Accounts',
                _accounts.length,
                Colors.teal,
              ),
              _sectionTile(
                context,
                _IdentitySection.sessions,
                Icons.vpn_key_outlined,
                'Sessions',
                _sessions.length,
                Colors.purple,
              ),
              const Divider(indent: 16, endIndent: 16),
              if (_section == _IdentitySection.users)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: _accountFilterMenu(context),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Failed to load identity registry',
                            style: TextStyle(color: Colors.red[300]),
                          ),
                        ),
                      )
                    : _listLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _identityList(context),
              ),
            ],
          ),
        ),
        Container(width: 1, color: Colors.white10),
        Expanded(child: _buildDetail(context)),
      ],
    );
  }

  Widget _sectionTile(
    BuildContext context,
    _IdentitySection section,
    IconData icon,
    String label,
    int count,
    Color color,
  ) {
    final selected = _section == section;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.2),
      leading: Icon(
        icon,
        size: 18,
        color: selected ? Theme.of(context).colorScheme.primary : color,
      ),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: _chip(
        '$count',
        selected ? Theme.of(context).colorScheme.primary : color,
      ),
      onTap: () => _setSection(section),
    );
  }

  Widget _accountFilterMenu(BuildContext context) {
    final value = _accountFilter ?? '';
    final accountsWithIds = _accounts.where((account) {
      return _identityId(account, _IdentitySection.accounts).isNotEmpty;
    });
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
          icon: const Icon(Icons.expand_more, size: 16),
          style: const TextStyle(fontSize: 12, color: Colors.white70),
          items: [
            const DropdownMenuItem(value: '', child: Text('All accounts')),
            ...accountsWithIds.map((account) {
              final id = _identityId(account, _IdentitySection.accounts);
              final label = _identityTitle(account, _IdentitySection.accounts);
              return DropdownMenuItem(
                value: id,
                child: Text(_short(label, 28)),
              );
            }),
          ],
          onChanged: _listLoading
              ? null
              : (next) => _reloadUsersForFilter(
                  next == null || next.isEmpty ? null : next,
                ),
        ),
      ),
    );
  }

  Widget _identityList(BuildContext context) {
    final rows = _rowsFor(_section);
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'No ${_sectionLabel(_section).toLowerCase()}',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final row = rows[index];
        final id = _identityId(row, _section);
        final selected = id.isNotEmpty && id == _selectedId;
        final status = _identityStatus(row);
        final statusColor = _statusColor(status);
        return ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: 0.2),
          leading: Icon(
            _sectionIcon(_section),
            size: 18,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : _sectionColor(_section),
          ),
          title: Text(
            _identityTitle(row, _section),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontFamily: id == _identityTitle(row, _section)
                  ? 'monospace'
                  : null,
            ),
          ),
          subtitle: Text(
            _identitySubtitle(row, _section),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
          trailing: status.isEmpty ? null : _chip(status, statusColor),
          onTap: () => _selectRow(row),
        );
      },
    );
  }

  Widget _buildDetail(BuildContext context) {
    final color = _sectionColor(_section);
    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Icon(_sectionIcon(_section), size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                _sectionLabel(_section),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              if (_section == _IdentitySection.users &&
                  ScrollData().passwordLoginEnabled)
                _chip('PASSWORD WRITES ADMIN', Colors.orange)
              else
                _chip('READ ONLY', Colors.green),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _loading ? null : _loadIdentity,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _metric(
                            Icons.business_outlined,
                            'Accounts',
                            '${_accounts.length}',
                            Colors.teal,
                          ),
                          _metric(
                            Icons.manage_accounts_outlined,
                            'Users',
                            '${_users.length}',
                            Colors.blue,
                          ),
                          _metric(
                            Icons.vpn_key_outlined,
                            'Sessions',
                            '${_sessions.length}',
                            Colors.purple,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final overview = _overviewCard(context);
                          final detail = _detailCard(context);
                          if (constraints.maxWidth < 900) {
                            return Column(
                              children: [
                                overview,
                                const SizedBox(height: 12),
                                detail,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: overview),
                              const SizedBox(width: 12),
                              Expanded(child: detail),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _rawPanel('Raw identity payload', {
                        'section': _sectionLabel(_section).toLowerCase(),
                        if (_accountFilter != null)
                          'account_filter': _accountFilter,
                        'list_row': _selectedRow,
                        'detail': _selectedDetail,
                      }),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _overviewCard(BuildContext context) {
    final rows = _rowsFor(_section);
    final selected = _selectedRow ?? const <String, dynamic>{};
    return _framed(
      context,
      title: '${_sectionLabel(_section)} List Row',
      icon: Icons.list_alt_outlined,
      color: _sectionColor(_section),
      trailing: _chip(
        rows.isEmpty ? 'EMPTY' : '${rows.length}',
        _sectionColor(_section),
      ),
      expandChild: false,
      child: rows.isEmpty
          ? Text('Not reported', style: TextStyle(color: Colors.white38))
          : Column(
              children: _orderedRows(selected).map((entry) {
                return _infoRow(entry.key, entry.value);
              }).toList(),
            ),
    );
  }

  Widget _detailCard(BuildContext context) {
    final row = _selectedRow;
    final detail = {
      if (row != null) ...row,
      if (_selectedDetail != null) ..._selectedDetail!,
    };
    return _framed(
      context,
      title: '${_singularLabel(_section)} Detail',
      icon: Icons.info_outline,
      color: Colors.blue,
      trailing: _section == _IdentitySection.users
          ? _passwordActions()
          : _chip('READ ONLY', Colors.green),
      expandChild: false,
      child: _detailLoading
          ? const Center(child: CircularProgressIndicator())
          : detail.isEmpty
          ? Text(
              'No ${_sectionLabel(_section).toLowerCase()} selected',
              style: TextStyle(color: Colors.white38),
            )
          : Column(
              children: [
                ..._orderedRows(detail).map((entry) {
                  return _infoRow(entry.key, entry.value);
                }),
                if (_passwordResponse != null) _passwordResponsePanel(),
              ],
            ),
    );
  }

  Widget _passwordActions() {
    final enabled = ScrollData().passwordLoginEnabled;
    final canWrite = enabled && !_passwordWriting && _selectedUserId != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: enabled
              ? 'Set through POST /admin/identity/users/{user_id}/password'
              : 'Password writes are locked: /admin/status.capabilities.identity.password_login_enabled is false',
          child: OutlinedButton.icon(
            onPressed: canWrite ? _showSetPasswordDialog : null,
            icon: const Icon(Icons.password_outlined, size: 14),
            label: Text(enabled ? 'Set Password' : 'Password locked'),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: enabled
              ? 'Remove through DELETE /admin/identity/users/{user_id}/password'
              : 'Password writes are locked: /admin/status.capabilities.identity.password_login_enabled is false',
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: canWrite ? _confirmRemovePassword : null,
            icon: const Icon(Icons.key_off_outlined, size: 14),
            label: const Text('Remove'),
          ),
        ),
      ],
    );
  }

  Widget _passwordResponsePanel() {
    final response = _passwordResponse ?? const <String, dynamic>{};
    final status = response['status'];
    final ok = status is int && status >= 200 && status < 300;
    final color = ok ? Colors.green : Colors.red;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(response),
              maxLines: 6,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _passwordResponse = null),
            icon: const Icon(Icons.close, size: 14),
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _framed(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
    Widget? trailing,
    bool expandChild = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              _titleCase(label),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              _valueText(_safeValue(label, value)),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rawPanel(String title, Map<String, dynamic> value) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: TextStyle(fontSize: 12, color: Colors.white54)),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(_redacted(value)),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        _short(text, 44),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _mapsFromList(dynamic value) {
    if (value is! List) return const [];
    return value.map(_mapFromDynamic).toList();
  }

  List<Map<String, dynamic>> _rowsFor(
    _IdentitySection section, {
    List<Map<String, dynamic>>? accounts,
    List<Map<String, dynamic>>? users,
    List<Map<String, dynamic>>? sessions,
  }) {
    return switch (section) {
      _IdentitySection.accounts => accounts ?? _accounts,
      _IdentitySection.users => users ?? _users,
      _IdentitySection.sessions => sessions ?? _sessions,
    };
  }

  Map<String, dynamic>? _selectedForRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return null;
    final current = _selectedId;
    if (current != null) {
      for (final row in rows) {
        if (_identityId(row, _section) == current) return row;
      }
    }
    return rows.first;
  }

  List<MapEntry<String, dynamic>> _orderedRows(Map<String, dynamic> values) {
    final preferred = [
      'id',
      'account_id',
      'user_id',
      'session_id',
      'email',
      'username',
      'name',
      'role',
      'status',
      'state',
      'active',
      'created_at',
      'updated_at',
      'expires_at',
      'revoked_at',
      'last_seen_at',
      'description',
    ];
    final rows = <MapEntry<String, dynamic>>[];
    final used = <String>{};
    for (final key in preferred) {
      final value = values[key];
      if (_hasValue(value)) {
        rows.add(MapEntry(key, value));
        used.add(key);
      }
    }
    for (final entry in values.entries) {
      if (used.contains(entry.key) || !_hasValue(entry.value)) continue;
      rows.add(entry);
    }
    return rows.take(14).toList();
  }

  Map<String, dynamic> _mapFromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is String) return {'id': value};
    return {'value': value};
  }

  String _identityId(Map<String, dynamic> row, _IdentitySection section) {
    final keys = switch (section) {
      _IdentitySection.accounts => const [
        'account_id',
        'id',
        'account',
        'name',
        'key',
      ],
      _IdentitySection.users => const [
        'user_id',
        'id',
        'email',
        'username',
        'name',
      ],
      _IdentitySection.sessions => const ['session_id', 'id', 'key', 'name'],
    };
    for (final key in keys) {
      final value = row[key];
      if (_hasValue(value)) return value.toString();
    }
    return '';
  }

  String _identityTitle(Map<String, dynamic> row, _IdentitySection section) {
    final keys = switch (section) {
      _IdentitySection.accounts => const ['name', 'slug', 'account_id', 'id'],
      _IdentitySection.users => const [
        'email',
        'username',
        'display_name',
        'name',
        'user_id',
        'id',
      ],
      _IdentitySection.sessions => const [
        'session_id',
        'id',
        'user_id',
        'account_id',
      ],
    };
    for (final key in keys) {
      final value = row[key];
      if (_hasValue(value)) return value.toString();
    }
    return _singularLabel(section).toLowerCase();
  }

  String _identitySubtitle(Map<String, dynamic> row, _IdentitySection section) {
    final keys = switch (section) {
      _IdentitySection.accounts => const ['account_id', 'status', 'created_at'],
      _IdentitySection.users => const [
        'account_id',
        'role',
        'status',
        'created_at',
      ],
      _IdentitySection.sessions => const [
        'user_id',
        'account_id',
        'status',
        'expires_at',
        'revoked_at',
      ],
    };
    final parts = <String>[];
    for (final key in keys) {
      final value = row[key];
      if (!_hasValue(value)) continue;
      parts.add('${_titleCase(key)}: ${_valueText(_safeValue(key, value))}');
      if (parts.length == 3) break;
    }
    return parts.isEmpty ? _identityId(row, section) : parts.join('  ');
  }

  String _identityStatus(Map<String, dynamic> row) {
    final value =
        row['status'] ??
        row['state'] ??
        row['active'] ??
        row['revoked'] ??
        row['enabled'];
    if (!_hasValue(value)) return '';
    if (value is bool) return value ? 'active' : 'inactive';
    return value.toString();
  }

  IconData _sectionIcon(_IdentitySection section) {
    return switch (section) {
      _IdentitySection.accounts => Icons.business_outlined,
      _IdentitySection.users => Icons.manage_accounts_outlined,
      _IdentitySection.sessions => Icons.vpn_key_outlined,
    };
  }

  Color _sectionColor(_IdentitySection section) {
    return switch (section) {
      _IdentitySection.accounts => Colors.teal,
      _IdentitySection.users => Colors.blue,
      _IdentitySection.sessions => Colors.purple,
    };
  }

  String _sectionLabel(_IdentitySection section) {
    return switch (section) {
      _IdentitySection.accounts => 'Accounts',
      _IdentitySection.users => 'Users',
      _IdentitySection.sessions => 'Sessions',
    };
  }

  String _singularLabel(_IdentitySection section) {
    return switch (section) {
      _IdentitySection.accounts => 'Account',
      _IdentitySection.users => 'User',
      _IdentitySection.sessions => 'Session',
    };
  }

  Color _statusColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('active') ||
        normalized.contains('ok') ||
        normalized.contains('enabled')) {
      return Colors.green;
    }
    if (normalized.contains('revoked') ||
        normalized.contains('expired') ||
        normalized.contains('disabled') ||
        normalized.contains('inactive')) {
      return Colors.orange;
    }
    return Colors.white54;
  }

  dynamic _safeValue(String key, dynamic value) {
    if (_shouldRedact(key) && value is! bool && value != null) {
      return '[redacted]';
    }
    return _redacted(value);
  }

  dynamic _redacted(dynamic value, [String key = '']) {
    if (_shouldRedact(key) && value is! bool && value != null) {
      return '[redacted]';
    }
    if (value is Map) {
      return value.map((itemKey, itemValue) {
        final stringKey = itemKey.toString();
        return MapEntry(stringKey, _redacted(itemValue, stringKey));
      });
    }
    if (value is List) {
      return value.map((item) => _redacted(item, key)).toList();
    }
    return value;
  }

  bool _shouldRedact(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('password') ||
        normalized.contains('authorization') ||
        normalized.contains('credential') ||
        normalized == 'hash' ||
        normalized.endsWith('_hash');
  }

  bool _hasValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  String _valueText(dynamic value) {
    if (value == null) return '?';
    if (value is bool) return value ? 'yes' : 'no';
    if (value is List) return '${value.length} items';
    if (value is Map) {
      final entries = value.entries.take(3).map((entry) {
        return '${_titleCase(entry.key.toString())}: ${_valueText(entry.value)}';
      });
      return entries.join(', ');
    }
    return value.toString();
  }

  String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _short(String value, int limit) {
    if (value.length <= limit) return value;
    return '${value.substring(0, limit)}...';
  }
}

// ---------------------------------------------------------------------------
// Changes (admin read-only timeline)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// AI CHAT — POST /api/ai/chat. One conversation turn per request, using the
// caller's server-stored provider key (Settings → Server AI Keys). Tool
// calls dispatch with the caller's own credentials: the AI can do exactly
// what this session could, permission-checked and audited.
// ---------------------------------------------------------------------------

class AIChatView extends StatefulWidget {
  const AIChatView({super.key});

  @override
  State<AIChatView> createState() => _AIChatViewState();
}

class _ChatTurn {
  _ChatTurn({required this.question});

  final String question;
  String? reply;
  List<dynamic> toolCalls = const [];
  Map<String, dynamic>? usage;
  String? error;
  bool pending = true;
}

class _AIChatViewState extends State<AIChatView> {
  final _messageController = TextEditingController();
  final _toolsController = TextEditingController(
    text: 'global_search, list_collections',
  );
  final _chatScroll = ScrollController();
  final List<_ChatTurn> _turns = [];
  String _model = 'anthropic:claude-haiku-4-5';
  bool _sending = false;
  int _replayedTurns = 0;
  bool _prefsRecordExists = false;

  static const _models = [
    'anthropic:claude-haiku-4-5',
    'anthropic:claude-sonnet-5',
    'anthropic:claude-opus-4-8',
    'openai:gpt-4o-mini',
    'openai:gpt-4o',
  ];

  @override
  void initState() {
    super.initState();
    _loadShellState();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _toolsController.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  List<String> get _tools => [
    for (final tool in _toolsController.text.split(','))
      if (tool.trim().isNotEmpty) tool.trim(),
  ];

  /// Preferences + history live in shell_preferences / shell_commands
  /// records shared with the web /shell page, so both surfaces stay in
  /// sync and a conversation continues across them.
  Future<void> _loadShellState() async {
    final api = ScrollAPI();
    final userId = api.sessionUserId;
    if (userId == null) return;

    final prefsResult = await api.getUserCollectionRecord(
      'shell_preferences',
      userId,
    );
    if (!mounted) return;
    final prefsBody = prefsResult['body'];
    final prefs = prefsBody is Map
        ? (prefsBody['record'] is Map ? prefsBody['record'] as Map : prefsBody)
        : null;
    final prefsStatus = prefsResult['status'];
    if (prefsStatus is int && prefsStatus >= 200 && prefsStatus < 300) {
      _prefsRecordExists = true;
      final model = prefs?['model']?.toString();
      final tools = prefs?['tools'];
      setState(() {
        if (model != null && model.isNotEmpty) _model = model;
        if (tools is List && tools.isNotEmpty) {
          _toolsController.text = tools.join(', ');
        } else if (tools is String && tools.trim().isNotEmpty) {
          _toolsController.text = tools;
        }
      });
    }

    final logResult = await api.listUserCollectionRecords(
      'shell_commands',
      limit: 200,
    );
    if (!mounted || _turns.isNotEmpty) return;
    final logBody = logResult['body'];
    final rows = logBody is Map && logBody['records'] is List
        ? (logBody['records'] as List)
        : const [];
    final aiRows = [
      for (final row in rows)
        if (row is Map && row['kind']?.toString() == 'ai') row,
    ]..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
    final replay = aiRows.length > 30
        ? aiRows.sublist(aiRows.length - 30)
        : aiRows;
    final turns = <_ChatTurn>[];
    for (final row in replay) {
      final question =
          (row['input'] ?? row['message'] ?? row['command'] ?? row['text'])
              ?.toString();
      final reply = (row['reply'] ?? row['response'] ?? row['output'])
          ?.toString();
      if (question == null || question.isEmpty) continue;
      turns.add(
        _ChatTurn(question: question)
          ..pending = false
          ..reply = reply,
      );
    }
    if (turns.isEmpty) return;
    setState(() {
      _turns.addAll(turns);
      _replayedTurns = turns.length;
    });
    _scrollToEnd();
  }

  Future<void> _persistPreferences() async {
    final api = ScrollAPI();
    final userId = api.sessionUserId;
    if (userId == null) return;
    final changes = {'model': _model, 'tools': _tools};
    final result = _prefsRecordExists
        ? await api.putUserCollectionRecord(
            'shell_preferences',
            userId,
            changes,
          )
        : await api.createUserCollectionRecord('shell_preferences', {
            'id': userId,
            ...changes,
          });
    final status = result['status'];
    if (status is int && status >= 200 && status < 300) {
      _prefsRecordExists = true;
    }
  }

  /// Prior completed turns as [{role, content}] — the server caps history
  /// at 40 entries, so send at most the last 20 exchanges.
  List<Map<String, String>> _historyPayload() {
    final history = <Map<String, String>>[];
    for (final turn in _turns) {
      if (turn.pending || turn.reply == null) continue;
      history.add({'role': 'user', 'content': turn.question});
      history.add({'role': 'assistant', 'content': turn.reply!});
    }
    return history.length > 40 ? history.sublist(history.length - 40) : history;
  }

  Future<void> _send() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _sending) return;
    final history = _historyPayload();
    final turn = _ChatTurn(question: message);
    setState(() {
      _turns.add(turn);
      _sending = true;
      _messageController.clear();
    });
    _scrollToEnd();
    final result = await ScrollAPI().aiChat(
      message: message,
      model: _model,
      tools: _tools,
      history: history,
    );
    if (!mounted) return;
    final status = result['status'];
    final body = result['body'];
    setState(() {
      turn.pending = false;
      _sending = false;
      if (status is int && status >= 200 && status < 300 && body is Map) {
        turn.reply = (body['reply'] ?? body['message'] ?? body['content'])
            ?.toString();
        turn.toolCalls = body['tool_calls'] is List
            ? body['tool_calls'] as List
            : const [];
        turn.usage = body['usage'] is Map
            ? Map<String, dynamic>.from(body['usage'] as Map)
            : null;
        if (turn.reply == null) {
          turn.error = 'No reply in response: ${jsonEncode(body)}';
        }
      } else {
        final detail = body is Map && body['error'] != null
            ? body['error'].toString()
            : (result['error']?.toString() ?? jsonEncode(body));
        turn.error = 'HTTP ${status ?? '?'} — $detail';
      }
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final needsUser = ScrollAPI().sessionUserId == null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('AI Chat', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 8),
              _chatChip('POST /api/ai/chat', Colors.blue),
              const SizedBox(width: 8),
              _chatChip('CALLER-SCOPED TOOLS', Colors.green),
              const Spacer(),
              DropdownButton<String>(
                value: _model,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
                dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
                items: {..._models, _model}
                    .map(
                      (model) =>
                          DropdownMenuItem(value: model, child: Text(model)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _model = value);
                  _persistPreferences();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _toolsController,
            onSubmitted: (_) => _persistPreferences(),
            onEditingComplete: _persistPreferences,
            decoration: const InputDecoration(
              labelText: 'Tools (comma-separated MCP tool names)',
              helperText:
                  'Any subset of the server\'s MCP catalog — a small list '
                  'keeps fast models fast. Empty = no tools. Model + tools '
                  'sync with the web /shell via shell_preferences.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
          if (needsUser)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Chat uses a provider key stored for YOUR user on the '
                'server (Settings → Server AI Keys). Sign in with email + '
                'password first — a deployment token has no user to hold '
                'a key.',
                style: TextStyle(fontSize: 12, color: Colors.amber[300]),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: _turns.isEmpty
                ? const Center(
                    child: Text(
                      'Ask the server\'s AI anything — it can call the MCP '
                      'tools above with your session\'s permissions.\n'
                      'Conversations continue across Scroll and the web '
                      '/shell page.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  )
                : ListView(
                    controller: _chatScroll,
                    children: [
                      if (_replayedTurns > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '↺ resumed $_replayedTurns turn'
                            '${_replayedTurns == 1 ? '' : 's'} from the '
                            'shell log',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white30,
                            ),
                          ),
                        ),
                      for (final turn in _turns) _turnWidget(turn),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Message the server\'s AI...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 16),
                label: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _turnWidget(_ChatTurn turn) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6, left: 80),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              turn.question,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        if (turn.pending)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (turn.error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6, right: 80),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              turn.error!,
              style: TextStyle(fontSize: 12, color: Colors.red[200]),
            ),
          ),
        if (turn.toolCalls.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 6, right: 80),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                dense: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  '${turn.toolCalls.length} tool call'
                  '${turn.toolCalls.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: SelectableText(
                      const JsonEncoder.withIndent(
                        '  ',
                      ).convert(turn.toolCalls),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (turn.reply != null)
          Container(
            margin: const EdgeInsets.only(bottom: 4, right: 80),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              turn.reply!,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        if (turn.usage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              turn.usage!.entries
                  .map((entry) => '${entry.key}: ${entry.value}')
                  .join('  ·  '),
              style: const TextStyle(fontSize: 10, color: Colors.white30),
            ),
          ),
      ],
    );
  }

  Widget _chatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GLOBAL SEARCH — GET /api/search across searchable collections. Results
// arrive per-collection; each group renders under its schema's
// views.list_mode (table | cards | feed) and views.list_fields.
// ---------------------------------------------------------------------------

class GlobalSearchView extends StatefulWidget {
  const GlobalSearchView({super.key});

  @override
  State<GlobalSearchView> createState() => _GlobalSearchViewState();
}

class _GlobalSearchViewState extends State<GlobalSearchView> {
  final _queryController = TextEditingController();
  final _queryFocus = FocusNode();
  Map<String, dynamic>? _response;
  final Map<String, SchemaFormSpec> _specs = {};
  bool _loading = false;
  String? _error;
  String? _searchedQuery;

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _searchedQuery = query;
    });
    final response = await ScrollAPI().globalSearch(query, limit: 25);
    if (!mounted) return;
    if (response == null) {
      setState(() {
        _loading = false;
        _error = ScrollAPI().lastError ?? 'Search request failed';
      });
      return;
    }
    setState(() {
      _response = response;
      _loading = false;
    });
    // Fetch schemas for result collections we haven't seen yet, so groups
    // can render list_fields / list_mode. Results show immediately; rows
    // refine as specs arrive.
    final results = _results(response);
    for (final collection in results.keys) {
      if (_specs.containsKey(collection)) continue;
      ScrollAPI().getAdminSchema(collection).then((detail) {
        if (!mounted || detail == null) return;
        setState(() {
          _specs[collection] = SchemaFormSpec.fromSchema(detail);
        });
      });
    }
  }

  Map<String, List<Map<String, dynamic>>> _results(
    Map<String, dynamic> response,
  ) {
    final raw = response['results'];
    final results = <String, List<Map<String, dynamic>>>{};
    if (raw is Map) {
      raw.forEach((collection, records) {
        if (records is! List) return;
        results[collection.toString()] = [
          for (final record in records)
            if (record is Map)
              Map<String, dynamic>.from(
                record.map((k, v) => MapEntry(k.toString(), v)),
              ),
        ];
      });
    }
    return results;
  }

  List<String> _rowFields(String collection, Map<String, dynamic> record) {
    final listFields = _specs[collection]?.listFields ?? const [];
    if (listFields.isNotEmpty) return listFields;
    return [
      for (final key in record.keys)
        if (key != 'id') key,
    ].take(4).toList();
  }

  String _recordTitle(String collection, Map<String, dynamic> record) {
    for (final field in _rowFields(collection, record)) {
      final value = record[field];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return record['id']?.toString() ?? '(record)';
  }

  void _showRecord(String collection, Map<String, dynamic> record) {
    final recordId = record['id']?.toString() ?? '';
    final hasPublicFlag = record.containsKey('is_public');
    final isPublic = schemaBoolIsTrue(record['is_public']);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$collection / $recordId'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(record),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          if (hasPublicFlag && recordId.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _togglePublic(collection, recordId, makePublic: !isPublic);
              },
              icon: Icon(
                isPublic ? Icons.lock_outline : Icons.public,
                size: 16,
              ),
              label: Text(isPublic ? 'Make Private' : 'Make Public'),
            ),
          if (recordId.isNotEmpty)
            TextButton.icon(
              // Permalink convention: /{collection}/{id} via site_routes.
              onPressed: () {
                final base = ScrollAPI().objectServerUrl;
                if (base != null) {
                  Process.run('open', ['$base$collection/$recordId']);
                }
              },
              icon: const Icon(Icons.open_in_browser, size: 16),
              label: const Text('Open Page'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePublic(
    String collection,
    String recordId, {
    required bool makePublic,
  }) async {
    final result = await ScrollAPI().updateAdminCollectionRecord(
      collection,
      recordId,
      {'is_public': makePublic ? 'true' : 'false'},
    );
    if (!mounted) return;
    final status = result['status'];
    final ok = status is int && status >= 200 && status < 300;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '$collection/$recordId is now '
                    '${makePublic ? 'public' : 'private'}'
              : 'Update failed: HTTP ${status ?? result['error'] ?? '?'}',
        ),
        backgroundColor: ok ? Colors.green[800] : Colors.red[800],
      ),
    );
    if (ok) _search();
  }

  Widget? _publicBadge(Map<String, dynamic> record) {
    if (!record.containsKey('is_public')) return null;
    final isPublic = schemaBoolIsTrue(record['is_public']);
    return _searchChip(
      isPublic ? 'PUBLIC' : 'PRIVATE',
      isPublic ? Colors.green : Colors.blueGrey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final response = _response;
    final results = response == null ? null : _results(response);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Search', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 8),
              _searchChip('GET /api/search', Colors.blue),
              const SizedBox(width: 8),
              _searchChip('PERMISSION-AWARE', Colors.green),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  focusNode: _queryFocus,
                  autofocus: true,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Search all collections your session can read...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Search'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red[300], fontSize: 12),
              ),
            ),
          Expanded(child: _body(context, results)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    Map<String, List<Map<String, dynamic>>>? results,
  ) {
    if (results == null) {
      return const Center(
        child: Text(
          'Terms are AND-ed across each collection\'s searchable fields.\n'
          'Collections opt in via their schema — denied collections are '
          'skipped server-side.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }
    final total = _response?['total_count'];
    final warnings = _response?['warnings'];
    final nonEmpty = results.entries.where((e) => e.value.isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      return Center(
        child: Text(
          'No matches for "${_searchedQuery ?? ''}"',
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${total ?? nonEmpty.fold<int>(0, (n, e) => n + e.value.length)} '
            'result(s) for "${_searchedQuery ?? ''}"',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        if (warnings is List && warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              warnings.join(' · '),
              style: TextStyle(color: Colors.amber[300], fontSize: 12),
            ),
          ),
        for (final entry in nonEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Row(
              children: [
                Icon(
                  switch (_specs[entry.key]?.listMode) {
                    'cards' => Icons.grid_view_outlined,
                    'feed' => Icons.view_agenda_outlined,
                    _ => Icons.table_rows_outlined,
                  },
                  size: 15,
                  color: Colors.white54,
                ),
                const SizedBox(width: 8),
                Text(
                  entry.key,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.value.length}',
                  style: const TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ],
            ),
          ),
          if (_specs[entry.key]?.listMode == 'cards')
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final record in entry.value)
                  _recordCard(entry.key, record),
              ],
            )
          else
            for (final record in entry.value) _recordRow(entry.key, record),
        ],
      ],
    );
  }

  Widget _recordCard(String collection, Map<String, dynamic> record) {
    final fields = _rowFields(collection, record);
    return InkWell(
      onTap: () => _showRecord(collection, record),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _recordTitle(collection, record),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            for (final field in fields.skip(1))
              if (record[field] != null && field != 'is_public')
                Text(
                  '$field: ${record[field]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
            if (_publicBadge(record) case final badge?)
              Padding(padding: const EdgeInsets.only(top: 6), child: badge),
          ],
        ),
      ),
    );
  }

  Widget _recordRow(String collection, Map<String, dynamic> record) {
    final fields = _rowFields(collection, record);
    final detail = [
      for (final field in fields.skip(1))
        if (record[field] != null && field != 'is_public')
          '$field: ${record[field]}',
    ].join('  ·  ');
    return InkWell(
      onTap: () => _showRecord(collection, record),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                _recordTitle(collection, record),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (detail.isNotEmpty)
              Expanded(
                flex: 3,
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
            if (_publicBadge(record) case final badge?)
              Padding(padding: const EdgeInsets.only(right: 8), child: badge),
            Text(
              record['id']?.toString() ?? '',
              style: const TextStyle(fontSize: 11, color: Colors.white30),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OPS EVENTS — GET /admin/ops. One admin-gated stream: object execution
// failures + auth activity (login_failed rows are what the lockout gate
// reads, login_locked marks a tripped lock). Never contains key material.
// ---------------------------------------------------------------------------

class OpsEventsView extends StatefulWidget {
  const OpsEventsView({super.key});

  @override
  State<OpsEventsView> createState() => _OpsEventsViewState();
}

class _OpsEventsViewState extends State<OpsEventsView> {
  final _identifierController = TextEditingController();
  String _kind = 'All';
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ScrollAPI().listAdminOpsEvents(
      kind: _kind == 'All' ? null : _kind,
      identifier: _identifierController.text.trim(),
    );
    if (!mounted) return;
    final status = result['status'];
    final body = result['body'];
    if (status is! int || status < 200 || status >= 300) {
      setState(() {
        _loading = false;
        _error = 'HTTP ${status ?? result['error'] ?? '?'}';
      });
      return;
    }
    final raw = body is Map
        ? (body['events'] ?? body['items'] ?? body['results'])
        : body;
    setState(() {
      _loading = false;
      _events = [
        if (raw is List)
          for (final event in raw)
            if (event is Map)
              Map<String, dynamic>.from(
                event.map((k, v) => MapEntry(k.toString(), v)),
              ),
      ];
    });
  }

  Color _eventColor(Map<String, dynamic> event) {
    if (event['kind']?.toString() == 'execution_error') return Colors.red;
    return switch (event['event']?.toString()) {
      'login_failed' => Colors.orange,
      'login_locked' => Colors.red,
      'login_succeeded' => Colors.green,
      'session_minted' => Colors.blue,
      'logout' => Colors.blueGrey,
      _ => Colors.purple,
    };
  }

  String _eventTitle(Map<String, dynamic> event) {
    if (event['kind']?.toString() == 'execution_error') {
      final object = event['object_id'] ?? '?';
      final method = event['method'] ?? '';
      return 'execution_error  $object${method == '' ? '' : '.$method'}';
    }
    return (event['event'] ?? 'auth').toString();
  }

  String _eventDetail(Map<String, dynamic> event) {
    final parts = <String>[];
    for (final key in const [
      'identifier',
      'user_id',
      'auth_method',
      'label',
      'error_type',
      'message',
      'correlation_id',
    ]) {
      final value = event[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        parts.add('$key: $value');
      }
    }
    return parts.join('  ·  ');
  }

  void _showEvent(Map<String, dynamic> event) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_eventTitle(event)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(event),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Ops Events', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 8),
              _opsChip('READ ONLY', Colors.green),
              const SizedBox(width: 8),
              _opsChip('GET /admin/ops', Colors.blue),
              const SizedBox(width: 12),
              Text(
                '${_events.length} events',
                style: TextStyle(fontSize: 13, color: Colors.white38),
              ),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 180,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _kind,
                    isExpanded: true,
                    dropdownColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainer,
                    icon: const Icon(Icons.expand_more, size: 16),
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    items: const ['All', 'auth', 'execution_error']
                        .map(
                          (kind) =>
                              DropdownMenuItem(value: kind, child: Text(kind)),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _kind = value);
                      _load();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 240,
                height: 38,
                child: TextField(
                  controller: _identifierController,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    hintText: 'identifier (e.g. dan@q9.is)',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.person_search, size: 16),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.filter_alt_outlined, size: 16),
                label: const Text('Apply'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Failed to load ops events: $_error',
                style: TextStyle(color: Colors.red[300], fontSize: 12),
              ),
            ),
          Expanded(
            child: _loading && _events.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _events.isEmpty
                ? const Center(
                    child: Text(
                      'No ops events',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.separated(
                    itemCount: _events.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      final color = _eventColor(event);
                      final when =
                          (event['at'] ??
                                  event['timestamp'] ??
                                  event['created_at'] ??
                                  '')
                              .toString();
                      return InkWell(
                        onTap: () => _showEvent(event),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 6,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.circle, size: 8, color: color),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 260,
                                child: Text(
                                  _eventTitle(event),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: color,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _eventDetail(event),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                              Text(
                                when.length > 19 ? when.substring(0, 19) : when,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: Colors.white30,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _opsChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class ChangesView extends StatefulWidget {
  const ChangesView({super.key});

  @override
  State<ChangesView> createState() => _ChangesViewState();
}

class _ChangesViewState extends State<ChangesView> {
  final _searchController = TextEditingController();
  final _objectController = TextEditingController();
  final _collectionController = TextEditingController();
  final _recordController = TextEditingController();
  final _packageController = TextEditingController();
  final _fileController = TextEditingController();
  String _kind = 'All';
  Map<String, dynamic>? _response;
  List<Map<String, dynamic>> _changes = [];
  Map<String, dynamic>? _selectedChange;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    final cached = ScrollData().adminChangesResponse;
    if (cached != null) {
      _response = cached;
      _changes = _rowsFromResponse(cached);
      _selectedChange = _changes.isNotEmpty ? _changes.first : null;
      _loading = false;
    }
    _loadChanges();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _objectController.dispose();
    _collectionController.dispose();
    _recordController.dispose();
    _packageController.dispose();
    _fileController.dispose();
    super.dispose();
  }

  Future<void> _loadChanges() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ScrollAPI().listAdminChanges(
        limit: 100,
        offset: 0,
        kind: _kind == 'All' ? null : _kind.toLowerCase(),
        objectId: _objectController.text,
        collection: _collectionController.text,
        recordId: _recordController.text,
        packageId: _packageController.text,
        file: _fileController.text,
      );
      final changes = _rowsFromResponse(response);
      if (!mounted) return;
      setState(() {
        _response = response;
        _changes = changes;
        _selectedChange = changes.isNotEmpty ? changes.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _clearFilters() {
    _searchController.clear();
    _objectController.clear();
    _collectionController.clear();
    _recordController.clear();
    _packageController.clear();
    _fileController.clear();
    setState(() => _kind = 'All');
    _loadChanges();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleChanges;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, visible.length),
          const SizedBox(height: 12),
          _filters(context),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Failed to load admin changes',
                style: TextStyle(color: Colors.red[300], fontSize: 12),
              ),
            ),
          Expanded(
            child: _loading && _changes.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final list = _changeList(context, visible);
                      final detail = _changeDetail(context);
                      if (constraints.maxWidth < 980) {
                        return Column(
                          children: [
                            Expanded(child: list),
                            const SizedBox(height: 12),
                            Expanded(child: detail),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(flex: 6, child: list),
                          const SizedBox(width: 12),
                          Expanded(flex: 4, child: detail),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, int visibleCount) {
    return Row(
      children: [
        Text('Changes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: 8),
        _chip('READ ONLY', Colors.green),
        const SizedBox(width: 8),
        _chip('GET /admin/changes', Colors.blue),
        const SizedBox(width: 12),
        Text(
          '$visibleCount/${_responseCount() ?? _changes.length} changes',
          style: TextStyle(fontSize: 13, color: Colors.white38),
        ),
        const Spacer(),
        if (_loading)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _loading ? null : _loadChanges,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _filters(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          height: 38,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search summary, target, actor...',
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 16),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Container(
          width: 150,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _kind,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
              icon: const Icon(Icons.expand_more, size: 16),
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              items: const ['All', 'source', 'file', 'record', 'package']
                  .map(
                    (kind) => DropdownMenuItem(value: kind, child: Text(kind)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _kind = value);
              },
            ),
          ),
        ),
        _filterField(_objectController, 'object_id', Icons.code_outlined),
        _filterField(
          _collectionController,
          'collection',
          Icons.storage_outlined,
        ),
        _filterField(_recordController, 'record_id', Icons.tag_outlined),
        _filterField(
          _packageController,
          'package_id',
          Icons.extension_outlined,
        ),
        _filterField(_fileController, 'file', Icons.description_outlined),
        FilledButton.icon(
          onPressed: _loading ? null : _loadChanges,
          icon: const Icon(Icons.filter_alt_outlined, size: 16),
          label: const Text('Apply'),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _clearFilters,
          icon: const Icon(Icons.clear, size: 16),
          label: const Text('Clear'),
        ),
      ],
    );
  }

  Widget _filterField(
    TextEditingController controller,
    String hint,
    IconData icon,
  ) {
    return SizedBox(
      width: 160,
      height: 38,
      child: TextField(
        controller: controller,
        onSubmitted: (_) => _loadChanges(),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12),
          prefixIcon: Icon(icon, size: 16),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }

  Widget _changeList(BuildContext context, List<Map<String, dynamic>> visible) {
    return _framed(
      context,
      title: 'Admin Timeline',
      icon: Icons.manage_history_outlined,
      color: Colors.blue,
      trailing: Wrap(
        spacing: 6,
        children: [
          _chip('${_countByKind(visible, 'source')} source', Colors.green),
          _chip('${_countByKind(visible, 'file')} file', Colors.teal),
          _chip('${_countByKind(visible, 'record')} record', Colors.blue),
          _chip('${_countByKind(visible, 'package')} package', Colors.amber),
        ],
      ),
      child: visible.isEmpty
          ? Center(
              child: Text(
                'No changes',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView.separated(
              itemCount: visible.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final change = visible[index];
                final kind = _kindFor(change);
                final color = _kindColor(kind);
                final selected =
                    identical(change, _selectedChange) ||
                    _changeKey(change) == _changeKey(_selectedChange);
                return InkWell(
                  onTap: () => setState(() => _selectedChange = change),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected
                          ? color.withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? color.withValues(alpha: 0.35)
                            : Colors.white10,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(_kindIcon(kind), size: 16, color: color),
                            const SizedBox(width: 8),
                            _chip(kind.toUpperCase(), color),
                            const SizedBox(width: 6),
                            _chip(_actionFor(change), _actionColor(change)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _summaryFor(change),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          children: [
                            if (_timestampFor(change).isNotEmpty)
                              _chip(
                                _short(_timestampFor(change), 30),
                                Colors.white54,
                              ),
                            if (_actorFor(change).isNotEmpty)
                              _chip(
                                'actor: ${_short(_actorFor(change), 28)}',
                                Colors.indigo,
                              ),
                            if (_targetText(change).isNotEmpty)
                              _chip(
                                _short(_targetText(change), 48),
                                Colors.teal,
                              ),
                            if (_correlationFor(change).isNotEmpty)
                              _chip(
                                'corr: ${_short(_correlationFor(change), 18)}',
                                Colors.white54,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _changeDetail(BuildContext context) {
    final change = _selectedChange;
    return _framed(
      context,
      title: 'Change Detail',
      icon: Icons.receipt_long_outlined,
      color: change == null ? Colors.white54 : _kindColor(_kindFor(change)),
      trailing: _chip('READ ONLY', Colors.green),
      child: change == null
          ? Center(
              child: Text(
                'No change selected',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView(
              children: [
                _infoRow('kind', _kindFor(change)),
                _infoRow('change_id', _changeIdFor(change)),
                _infoRow('action', _actionFor(change)),
                _infoRow('timestamp', _timestampFor(change)),
                _infoRow('actor', _actorFor(change)),
                _infoRow('summary', _summaryFor(change)),
                _infoRow('target', _targetText(change)),
                _infoRow('correlation_id', _correlationFor(change)),
                const SizedBox(height: 8),
                _rawPanel('Raw change', change),
                if (_response != null)
                  _rawPanel('Raw timeline metadata', {
                    'status': _response!['status'],
                    'count': _response!['count'],
                    'total': _response!['total'],
                    'limit': _response!['limit'],
                    'offset': _response!['offset'],
                  }),
              ],
            ),
    );
  }

  Widget _framed(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              _titleCase(label),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              _valueText(value),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rawPanel(String title, Map<String, dynamic> value) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: TextStyle(fontSize: 12, color: Colors.white54)),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(value),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        _short(text, 48),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _visibleChanges {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _changes;
    return _changes.where((change) {
      return _rowText(change).toLowerCase().contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> _rowsFromResponse(Map<String, dynamic>? response) {
    if (response == null) return const [];
    for (final key in const [
      'changes',
      'items',
      'events',
      'results',
      'records',
      'rows',
    ]) {
      final value = response[key];
      if (value is List) return value.map(_mapFromDynamic).toList();
    }
    final data = response['data'];
    if (data is List) return data.map(_mapFromDynamic).toList();
    if (data is Map) {
      for (final key in const [
        'changes',
        'items',
        'events',
        'results',
        'records',
        'rows',
      ]) {
        final value = data[key];
        if (value is List) return value.map(_mapFromDynamic).toList();
      }
    }
    return const [];
  }

  int? _responseCount() {
    final response = _response;
    if (response == null) return null;
    for (final key in const ['total', 'count', 'change_count']) {
      final parsed = _intFromDynamic(response[key]);
      if (parsed != null) return parsed;
    }
    final data = response['data'];
    if (data is Map) {
      for (final key in const ['total', 'count', 'change_count']) {
        final parsed = _intFromDynamic(data[key]);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  int _countByKind(List<Map<String, dynamic>> rows, String kind) {
    return rows.where((row) => _kindFor(row).toLowerCase() == kind).length;
  }

  String _rowText(Map<String, dynamic> change) {
    return [
      _kindFor(change),
      _actionFor(change),
      _summaryFor(change),
      _timestampFor(change),
      _actorFor(change),
      _targetText(change),
      _correlationFor(change),
      _changeIdFor(change),
    ].join(' ');
  }

  String _changeKey(Map<String, dynamic>? change) {
    if (change == null) return '';
    final id = _changeIdFor(change);
    if (id.isNotEmpty) return id;
    return '${_timestampFor(change)}|${_kindFor(change)}|${_summaryFor(change)}';
  }

  String _kindFor(Map<String, dynamic> change) {
    return _stringFor(change, const ['kind', 'category'], 'change');
  }

  String _changeIdFor(Map<String, dynamic> change) {
    return _stringFor(change, const ['change_id', 'id', 'event_id']);
  }

  String _actionFor(Map<String, dynamic> change) {
    return _stringFor(change, const [
      'action',
      'type',
      'event_type',
      'change_type',
    ], '${_kindFor(change)}_change');
  }

  String _timestampFor(Map<String, dynamic> change) {
    return _stringFor(change, const [
      'timestamp',
      'created_at',
      'changed_at',
      'time',
    ]);
  }

  String _actorFor(Map<String, dynamic> change) {
    final actor = change['actor'];
    if (actor is Map) {
      final map = _mapFromDynamic(actor);
      return _stringFor(map, const [
        'user_id',
        'id',
        'name',
        'email',
        'principal',
      ], _valueText(map));
    }
    return _stringFor(change, const [
      'actor',
      'author',
      'user',
      'user_id',
      'principal',
    ]);
  }

  String _summaryFor(Map<String, dynamic> change) {
    return _stringFor(change, const [
      'summary',
      'message',
      'description',
      'note',
    ], _actionFor(change));
  }

  String _correlationFor(Map<String, dynamic> change) {
    return _stringFor(change, const ['correlation_id', 'request_id']);
  }

  String _targetText(Map<String, dynamic> change) {
    final rawTarget = change['target'];
    final target = rawTarget is Map ? _mapFromDynamic(rawTarget) : const {};
    final parts = <String>[];
    void addPart(String key, String label) {
      final value = target[key]?.toString().trim();
      if (value != null && value.isNotEmpty) parts.add('$label: $value');
    }

    addPart('object_id', 'object');
    addPart('collection', 'collection');
    addPart('record_id', 'record');
    addPart('package_id', 'package');
    addPart('file', 'file');
    if (parts.isNotEmpty) return parts.join(' | ');
    if (rawTarget != null) return _valueText(rawTarget);
    return _stringFor(change, const [
      'object_id',
      'collection',
      'record_id',
      'package_id',
      'file',
    ]);
  }

  Color _actionColor(Map<String, dynamic> change) {
    final action = _actionFor(change).toLowerCase();
    if (action.contains('delete') || action.contains('remove')) {
      return Colors.red;
    }
    if (action.contains('restore') || action.contains('rollback')) {
      return Colors.orange;
    }
    if (action.contains('create') || action.contains('install')) {
      return Colors.green;
    }
    return _kindColor(_kindFor(change));
  }

  Color _kindColor(String kind) {
    return switch (kind.toLowerCase()) {
      'source' => Colors.green,
      'file' => Colors.teal,
      'record' => Colors.blue,
      'package' => Colors.amber,
      _ => Colors.white54,
    };
  }

  IconData _kindIcon(String kind) {
    return switch (kind.toLowerCase()) {
      'source' => Icons.code_outlined,
      'file' => Icons.description_outlined,
      'record' => Icons.storage_outlined,
      'package' => Icons.extension_outlined,
      _ => Icons.manage_history_outlined,
    };
  }

  String _stringFor(
    Map<String, dynamic> map,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final text = _valueText(value).trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  Map<String, dynamic> _mapFromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return {'value': value};
  }

  int? _intFromDynamic(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _valueText(dynamic value) {
    if (value == null) return '';
    if (value is Map || value is List) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return value.toString();
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  String _short(String value, int limit) {
    if (value.length <= limit) return value;
    return '${value.substring(0, limit)}...';
  }
}

// ---------------------------------------------------------------------------
// File Manager (admin)
// ---------------------------------------------------------------------------

class FileManagerView extends StatefulWidget {
  const FileManagerView({super.key});

  @override
  State<FileManagerView> createState() => _FileManagerViewState();
}

class _FileManagerViewState extends State<FileManagerView> {
  final _searchController = TextEditingController();
  final _objectFilterController = TextEditingController();
  Map<String, dynamic>? _inventory;
  List<Map<String, dynamic>> _files = [];
  Map<String, dynamic>? _selectedFile;
  Map<String, dynamic>? _fileResponse;
  String _typeFilter = 'All';
  bool _loading = true;
  bool _contentLoading = false;
  bool _mutating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _objectFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
      _fileResponse = null;
    });
    try {
      final objectFilter = _objectFilterController.text.trim();
      final response = await ScrollAPI().listAdminFiles(
        limit: 100,
        offset: 0,
        objectId: objectFilter.isEmpty ? null : objectFilter,
      );
      final files = _filesFromInventory(response ?? const {});
      final typeOptions = _typeOptionsFor(files);
      final selected = _selectedForFiles(files);
      if (!mounted) return;
      setState(() {
        _inventory = response;
        _files = files;
        _selectedFile = selected;
        if (!typeOptions.contains(_typeFilter)) _typeFilter = 'All';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _viewFile(Map<String, dynamic> file) async {
    final objectId = _objectId(file);
    final name = _fileName(file);
    if (objectId.isEmpty || name.isEmpty) {
      setState(() {
        _selectedFile = file;
        _fileResponse = {
          'error': 'File row must include object_id and name to fetch content',
        };
      });
      return;
    }
    setState(() {
      _selectedFile = file;
      _contentLoading = true;
      _fileResponse = null;
    });
    final response = await ScrollAPI().getAdminFileContent(objectId, name);
    if (!mounted) return;
    setState(() {
      _fileResponse = response;
      _contentLoading = false;
    });
  }

  Future<void> _showUploadDialog() async {
    if (!_fileWritesEnabled) return;
    final objectController = TextEditingController(
      text: _objectFilterController.text.trim(),
    );
    final nameController = TextEditingController();
    final contentController = TextEditingController();
    bool overwrite = false;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Upload Object File'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: objectController,
                      decoration: const InputDecoration(
                        labelText: 'Object ID',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'File name',
                        hintText: 'assets/report.txt',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 180,
                      child: TextField(
                        controller: contentController,
                        maxLines: null,
                        expands: true,
                        decoration: const InputDecoration(
                          labelText: 'Text content',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: overwrite,
                      onChanged: (value) {
                        setDialogState(() => overwrite = value == true);
                      },
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Overwrite existing file with PUT'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  icon: const Icon(Icons.upload, size: 16),
                  label: const Text('Upload'),
                ),
              ],
            );
          },
        );
      },
    );
    if (submitted != true) {
      objectController.dispose();
      nameController.dispose();
      contentController.dispose();
      return;
    }
    final objectId = objectController.text.trim();
    final name = nameController.text.trim();
    final content = contentController.text;
    objectController.dispose();
    nameController.dispose();
    contentController.dispose();
    if (objectId.isEmpty || name.isEmpty) {
      setState(() {
        _fileResponse = {'error': 'Object ID and file name are required'};
      });
      return;
    }
    setState(() {
      _mutating = true;
      _fileResponse = null;
    });
    final response = overwrite
        ? await ScrollAPI().overwriteAdminFile(
            objectId,
            name: name,
            content: content,
          )
        : await ScrollAPI().createAdminFile(
            objectId,
            name: name,
            content: content,
          );
    if (!mounted) return;
    await _loadFiles();
    if (!mounted) return;
    setState(() {
      _fileResponse = response;
      _mutating = false;
    });
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    if (!_fileWritesEnabled) return;
    final objectId = _objectId(file);
    final name = _fileName(file);
    if (objectId.isEmpty || name.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete object file?'),
          content: Text('$objectId/$name'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() {
      _mutating = true;
      _fileResponse = null;
    });
    final response = await ScrollAPI().deleteAdminFile(objectId, name);
    if (!mounted) return;
    await _loadFiles();
    if (!mounted) return;
    setState(() {
      _fileResponse = response;
      _mutating = false;
      if (_fileKey(_selectedFile ?? const {}) == _fileKey(file)) {
        _selectedFile = null;
      }
    });
  }

  String _formatSize(dynamic size) {
    if (size == null) return '?';
    final bytes = size is int ? size : int.tryParse(size.toString()) ?? 0;
    if (bytes > 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes > 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const SizedBox(height: 12),
          _filters(context),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Failed to load file inventory',
                style: TextStyle(color: Colors.red[300], fontSize: 12),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final list = _fileList(context);
                      final detail = _fileDetail(context);
                      if (constraints.maxWidth < 980) {
                        return Column(
                          children: [
                            Expanded(child: list),
                            const SizedBox(height: 12),
                            Expanded(child: detail),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(flex: 6, child: list),
                          const SizedBox(width: 12),
                          Expanded(flex: 4, child: detail),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Text('Files', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: 8),
        _chip(
          _fileWritesEnabled ? 'FILE WRITES ENABLED' : 'READ ONLY',
          _fileWritesEnabled ? Colors.orange : Colors.green,
        ),
        if (_maxFileBytesLabel.isNotEmpty) ...[
          const SizedBox(width: 6),
          _chip('max $_maxFileBytesLabel', Colors.white54),
        ],
        const SizedBox(width: 12),
        Text(
          '${_visibleFiles.length}/${_totalCount()} files',
          style: TextStyle(fontSize: 13, color: Colors.white38),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _loading ? null : _loadFiles,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Refresh'),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: _fileWriteTooltip,
          child: OutlinedButton.icon(
            onPressed: _fileWritesEnabled && !_mutating
                ? _showUploadDialog
                : null,
            icon: _mutating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload, size: 16),
            label: Text(_mutating ? 'Working...' : 'Upload'),
          ),
        ),
      ],
    );
  }

  Widget _filters(BuildContext context) {
    final typeOptions = _typeOptionsFor(_files);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          height: 38,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search filename, type, object...',
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 16),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Container(
          width: 170,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: typeOptions.contains(_typeFilter) ? _typeFilter : 'All',
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
              icon: const Icon(Icons.expand_more, size: 16),
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              items: typeOptions.map((type) {
                return DropdownMenuItem(value: type, child: Text(type));
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _typeFilter = value);
              },
            ),
          ),
        ),
        SizedBox(
          width: 260,
          height: 38,
          child: TextField(
            controller: _objectFilterController,
            onSubmitted: (_) => _loadFiles(),
            decoration: InputDecoration(
              hintText: 'object_id server filter',
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.code, size: 16),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : _loadFiles,
          icon: const Icon(Icons.filter_alt_outlined, size: 16),
          label: const Text('Apply'),
        ),
        if (_objectFilterController.text.trim().isNotEmpty)
          OutlinedButton.icon(
            onPressed: _loading
                ? null
                : () {
                    _objectFilterController.clear();
                    _loadFiles();
                  },
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Clear'),
          ),
      ],
    );
  }

  Widget _fileList(BuildContext context) {
    final files = _visibleFiles;
    return _framed(
      context,
      title: 'Admin File Inventory',
      icon: Icons.folder_outlined,
      color: Colors.blue,
      trailing: _chip('${files.length}', Colors.blue),
      child: files.isEmpty
          ? Center(
              child: Text('No files', style: TextStyle(color: Colors.white38)),
            )
          : SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 54,
                  columnSpacing: 24,
                  headingTextStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white54,
                  ),
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Type')),
                    DataColumn(label: Text('Size')),
                    DataColumn(label: Text('Object')),
                    DataColumn(label: Text('Modified')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: files.map((file) {
                    final type = _fileType(file);
                    final color = _typeColor(type);
                    final selected =
                        _fileKey(file) == _fileKey(_selectedFile ?? const {});
                    return DataRow(
                      selected: selected,
                      cells: [
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_fileIcon(type), size: 16, color: color),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 260,
                                ),
                                child: Text(
                                  _fileName(file),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          onTap: () => setState(() => _selectedFile = file),
                        ),
                        DataCell(_chip(type, color)),
                        DataCell(
                          Text(
                            _formatSize(_fileSize(file)),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        DataCell(
                          Text(
                            _short(_objectId(file), 28),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            _short(_modified(file), 24),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _viewFile(file),
                                icon: const Icon(
                                  Icons.download_outlined,
                                  size: 16,
                                ),
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Fetch via admin file route',
                              ),
                              Tooltip(
                                message: _fileWriteTooltip,
                                child: IconButton(
                                  onPressed: _fileWritesEnabled && !_mutating
                                      ? () => _deleteFile(file)
                                      : null,
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
    );
  }

  Widget _fileDetail(BuildContext context) {
    final file = _selectedFile;
    return _framed(
      context,
      title: 'File Detail',
      icon: Icons.insert_drive_file_outlined,
      color: Colors.teal,
      trailing: _chip('READ ONLY', Colors.green),
      child: file == null
          ? Center(
              child: Text(
                'No file selected',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView(
              children: [
                _infoRow('name', _fileName(file)),
                _infoRow('object_id', _objectId(file)),
                _infoRow('type', _fileType(file)),
                _infoRow('size', _formatSize(_fileSize(file))),
                _infoRow('modified', _modified(file)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _contentLoading ? null : () => _viewFile(file),
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: const Text('View / Download'),
                    ),
                    Tooltip(
                      message: _fileWriteTooltip,
                      child: OutlinedButton.icon(
                        onPressed: _fileWritesEnabled && !_mutating
                            ? () => _deleteFile(file)
                            : null,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_contentLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_fileResponse != null) ...[
                  Text(
                    'Fetched Response',
                    style: TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: SelectableText(
                      _contentText(_fileResponse),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _rawPanel('Raw file row', file),
                if (_inventory != null)
                  _rawPanel('Raw inventory response', {
                    'status': _inventory!['status'],
                    'count': _inventory!['count'],
                    'total': _inventory!['total'],
                  }),
              ],
            ),
    );
  }

  Widget _framed(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              _titleCase(label),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              _valueText(value),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rawPanel(String title, Map<String, dynamic> value) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: TextStyle(fontSize: 12, color: Colors.white54)),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(value),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        _short(text, 44),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _visibleFiles {
    final query = _searchController.text.trim().toLowerCase();
    return _files.where((file) {
      final type = _fileType(file);
      if (_typeFilter != 'All' && type != _typeFilter) return false;
      if (query.isEmpty) return true;
      final haystack = [
        _fileName(file),
        _objectId(file),
        type,
        _modified(file),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  bool get _fileWritesEnabled => ScrollData().fileWritesEnabled;

  String get _fileWriteTooltip {
    if (_fileWritesEnabled) {
      return 'File writes are enabled by /admin/status';
    }
    return 'File writes are locked: /admin/status.capabilities.file_writes.enabled is false';
  }

  String get _maxFileBytesLabel {
    final maxBytes = ScrollData().maxObjectFileBytes;
    if (maxBytes == null || maxBytes <= 0) return '';
    return _formatSize(maxBytes);
  }

  List<Map<String, dynamic>> _filesFromInventory(Map<String, dynamic> value) {
    final files = value['files'];
    if (files is List) return files.map(_mapFromDynamic).toList();
    return const [];
  }

  Map<String, dynamic>? _selectedForFiles(List<Map<String, dynamic>> files) {
    if (files.isEmpty) return null;
    final selectedKey = _fileKey(_selectedFile ?? const {});
    for (final file in files) {
      if (_fileKey(file) == selectedKey) return file;
    }
    return files.first;
  }

  List<String> _typeOptionsFor(List<Map<String, dynamic>> files) {
    final types = files.map(_fileType).where((type) => type.isNotEmpty).toSet();
    return ['All', ...types.toList()..sort()];
  }

  int _totalCount() {
    final total = _inventory?['total'] ?? _inventory?['count'];
    if (total is int) return total;
    if (total is num) return total.toInt();
    if (total is String) return int.tryParse(total) ?? _files.length;
    return _files.length;
  }

  Map<String, dynamic> _mapFromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is String) return {'name': value};
    return {'value': value};
  }

  String _fileKey(Map<String, dynamic> file) {
    return '${_objectId(file)}/${_fileName(file)}';
  }

  String _fileName(Map<String, dynamic> file) {
    final raw =
        file['name'] ??
        file['filename'] ??
        file['file_name'] ??
        file['path'] ??
        file['id'];
    return raw?.toString() ?? '';
  }

  String _objectId(Map<String, dynamic> file) {
    final raw =
        file['object_id'] ??
        file['object'] ??
        file['owner_object_id'] ??
        file['parent_id'];
    return raw?.toString() ?? '';
  }

  dynamic _fileSize(Map<String, dynamic> file) {
    return file['size'] ?? file['file_size'] ?? file['bytes'];
  }

  String _modified(Map<String, dynamic> file) {
    final raw =
        file['modified'] ??
        file['modified_at'] ??
        file['updated_at'] ??
        file['created_at'];
    return raw?.toString() ?? '';
  }

  String _fileType(Map<String, dynamic> file) {
    final explicit =
        file['type'] ??
        file['file_type'] ??
        file['mime_type'] ??
        file['content_type'];
    final explicitText = explicit?.toString() ?? '';
    if (explicitText.isNotEmpty) {
      if (explicitText.startsWith('image/')) return 'image';
      if (explicitText.startsWith('video/')) return 'video';
      if (explicitText.startsWith('audio/')) return 'audio';
      if (explicitText.startsWith('text/')) return 'text';
      return explicitText;
    }
    final name = _fileName(file).toLowerCase();
    if (name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp')) {
      return 'image';
    }
    if (name.endsWith('.mp4') || name.endsWith('.mov')) return 'video';
    if (name.endsWith('.mp3') || name.endsWith('.wav')) return 'audio';
    if (name.endsWith('.py') ||
        name.endsWith('.js') ||
        name.endsWith('.ts') ||
        name.endsWith('.dart')) {
      return 'source';
    }
    if (name.endsWith('.json') ||
        name.endsWith('.csv') ||
        name.endsWith('.tsv')) {
      return 'data';
    }
    if (name.endsWith('.md') || name.endsWith('.pdf')) return 'document';
    return 'file';
  }

  IconData _fileIcon(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('image')) return Icons.image_outlined;
    if (normalized.contains('video')) return Icons.videocam_outlined;
    if (normalized.contains('audio')) return Icons.audiotrack_outlined;
    if (normalized.contains('source') || normalized.contains('code')) {
      return Icons.code;
    }
    if (normalized.contains('data') || normalized.contains('json')) {
      return Icons.data_object;
    }
    if (normalized.contains('document') || normalized.contains('pdf')) {
      return Icons.description_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color _typeColor(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('image')) return Colors.green;
    if (normalized.contains('video')) return Colors.blue;
    if (normalized.contains('audio')) return Colors.purple;
    if (normalized.contains('source') || normalized.contains('code')) {
      return Colors.orange;
    }
    if (normalized.contains('data') || normalized.contains('json')) {
      return Colors.teal;
    }
    if (normalized.contains('document') || normalized.contains('pdf')) {
      return Colors.amber;
    }
    return Colors.white54;
  }

  String _contentText(dynamic value) {
    final text = const JsonEncoder.withIndent('  ').convert(value);
    const limit = 6000;
    if (text.length <= limit) return text;
    return '${text.substring(0, limit)}\n... truncated in Scroll preview';
  }

  bool _hasValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  String _valueText(dynamic value) {
    if (!_hasValue(value)) return '?';
    if (value is bool) return value ? 'yes' : 'no';
    if (value is List) return '${value.length} items';
    if (value is Map) {
      final entries = value.entries.take(3).map((entry) {
        return '${_titleCase(entry.key.toString())}: ${_valueText(entry.value)}';
      });
      return entries.join(', ');
    }
    return value.toString();
  }

  String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _short(String value, int limit) {
    if (value.length <= limit) return value;
    return '${value.substring(0, limit)}...';
  }
}

// ---------------------------------------------------------------------------
// Placeholder
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// AI Create — describe what you want, AI builds the object
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Search Results — global search across the platform
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _openaiController = TextEditingController();
  bool _openaiSaved = false;
  bool _showKey = false;
  final _serviceKeyController = TextEditingController();
  String _service = 'anthropic';
  List<String> _serverKeyServices = [];
  String? _serverKeyStatus;
  bool _serverKeyBusy = false;

  String? _activeTheme;
  List<String> _themes = [];
  Map<String, Map<String, dynamic>> _themePreviews = {};
  String? _themeStatus;
  bool _themeBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadServerKeys();
    _loadThemes();
  }

  Future<void> _load() async {
    final key = await ScrollAPI().getOpenAIKey();
    if (mounted && key != null) {
      setState(() => _openaiController.text = key);
    }
  }

  Future<void> _loadThemes() async {
    final info = await ScrollAPI().getStyleInfo();
    if (!mounted || info == null) return;
    final available = info['available'];
    final previews = info['previews'];
    setState(() {
      _activeTheme = info['active']?.toString();
      _themes = [
        if (available is List)
          for (final theme in available) theme.toString(),
      ];
      _themePreviews = {
        if (previews is Map)
          for (final entry in previews.entries)
            if (entry.value is Map)
              entry.key.toString(): Map<String, dynamic>.from(
                (entry.value as Map).map((k, v) => MapEntry(k.toString(), v)),
              ),
      };
    });
  }

  Future<void> _applyTheme(String theme) async {
    if (_themeBusy || theme == _activeTheme) return;
    setState(() {
      _themeBusy = true;
      _themeStatus = null;
    });
    final result = await ScrollAPI().setStyleTheme(theme);
    if (!mounted) return;
    final status = result['status'];
    final ok = status is int && status >= 200 && status < 300;
    setState(() {
      _themeBusy = false;
      if (ok) {
        _activeTheme = theme;
        _themeStatus = 'Instance theme is now "$theme"';
      } else if (status == 403) {
        _themeStatus = 'Switching the theme needs an admin session (got 403).';
      } else {
        _themeStatus = 'Failed: HTTP ${status ?? result['error'] ?? '?'}';
      }
    });
  }

  Color? _swatch(Map<String, dynamic>? preview, String key) {
    final hex = preview?[key]?.toString();
    if (hex == null || !hex.startsWith('#')) return null;
    final cleaned = hex.substring(1);
    final value = int.tryParse(
      cleaned.length == 6 ? 'ff$cleaned' : cleaned,
      radix: 16,
    );
    return value == null ? null : Color(value);
  }

  Future<void> _loadServerKeys() async {
    final userId = ScrollAPI().sessionUserId;
    if (userId == null) return;
    final result = await ScrollAPI().listServiceKeys(userId);
    if (!mounted) return;
    final body = result['body'];
    final raw = body is Map ? (body['services'] ?? body['keys']) : null;
    setState(() {
      _serverKeyServices = [
        if (raw is List)
          for (final item in raw)
            if (item is Map)
              (item['service'] ?? '').toString()
            else
              item.toString(),
      ]..removeWhere((service) => service.isEmpty);
    });
  }

  Future<void> _saveServerKey() async {
    final userId = ScrollAPI().sessionUserId;
    final key = _serviceKeyController.text.trim();
    if (userId == null || key.isEmpty) return;
    setState(() => _serverKeyBusy = true);
    final result = await ScrollAPI().setServiceKey(
      userId,
      service: _service,
      key: key,
    );
    if (!mounted) return;
    final status = result['status'];
    final ok = status is int && status >= 200 && status < 300;
    setState(() {
      _serverKeyBusy = false;
      _serverKeyStatus = ok
          ? '$_service key stored on the server'
          : 'Failed: HTTP ${status ?? result['error'] ?? '?'}';
      if (ok) _serviceKeyController.clear();
    });
    if (ok) _loadServerKeys();
  }

  Future<void> _removeServerKey(String service) async {
    final userId = ScrollAPI().sessionUserId;
    if (userId == null) return;
    setState(() => _serverKeyBusy = true);
    final result = await ScrollAPI().removeServiceKey(userId, service);
    if (!mounted) return;
    final status = result['status'];
    final ok = status is int && status >= 200 && status < 300;
    setState(() {
      _serverKeyBusy = false;
      _serverKeyStatus = ok
          ? '$service key removed'
          : 'Failed: HTTP ${status ?? result['error'] ?? '?'}';
    });
    if (ok) _loadServerKeys();
  }

  Future<void> _saveOpenAI() async {
    await ScrollAPI().setOpenAIKey(_openaiController.text.trim());
    if (mounted) {
      setState(() => _openaiSaved = true);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _openaiSaved = false);
    }
  }

  Future<void> _disconnect() async {
    ScrollRealtime().shutdown();
    await ScrollAPI().disconnect();
    ScrollData().clear();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ConnectScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ScrollAPI();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),

              // Connection info
              Text(
                'CONNECTION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _settingRow(
                      'Object Server',
                      api.objectServerUrl ?? 'Not connected',
                    ),
                    if (api.hasPlatform)
                      _settingRow('Platform', api.platformUrl ?? ''),
                    _settingRow(
                      'Status',
                      'Connected',
                      valueColor: Colors.green,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Disconnect'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[300],
                ),
              ),

              const SizedBox(height: 32),

              // OpenAI key
              Text(
                'AI INTEGRATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your OpenAI API key is used for AI features (AI Fill, natural language queries). '
                'Stored only on this device. Never sent to askrobots.com.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _openaiController,
                obscureText: !_showKey,
                decoration: InputDecoration(
                  labelText: 'OpenAI API Key',
                  hintText: 'sk-...',
                  prefixIcon: const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Colors.amber,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showKey ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                    ),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                  border: const OutlineInputBorder(),
                  helperText: 'Get one at platform.openai.com/api-keys',
                  helperStyle: TextStyle(fontSize: 11, color: Colors.white24),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _saveOpenAI,
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Save API Key'),
                  ),
                  if (_openaiSaved) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Saved!',
                      style: TextStyle(color: Colors.green, fontSize: 13),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 32),

              // Server-side AI provider keys (write-only)
              Text(
                'SERVER AI KEYS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Keys stored on the object server power its AI Chat '
                '(POST /api/ai/chat). Write-only: the server never returns '
                'key material, only which services have one.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 12),
              if (api.sessionUserId == null)
                Text(
                  'Sign in with email + password to manage server keys — '
                  'a deployment token has no user identity to attach '
                  'keys to.',
                  style: TextStyle(fontSize: 12, color: Colors.amber[300]),
                )
              else ...[
                if (_serverKeyServices.isNotEmpty) ...[
                  for (final service in _serverKeyServices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.key, size: 14, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            '$service — key stored',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: _serverKeyBusy
                                ? null
                                : () => _removeServerKey(service),
                            child: Text(
                              'Remove',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red[300],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    DropdownButton<String>(
                      value: _service,
                      items: const [
                        DropdownMenuItem(
                          value: 'anthropic',
                          child: Text('anthropic'),
                        ),
                        DropdownMenuItem(
                          value: 'openai',
                          child: Text('openai'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _service = value);
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _serviceKeyController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Provider API key',
                          hintText: 'sk-...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _serverKeyBusy ? null : _saveServerKey,
                      child: const Text('Store on Server'),
                    ),
                  ],
                ),
                if (_serverKeyStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _serverKeyStatus!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _serverKeyStatus!.startsWith('Failed')
                            ? Colors.red[300]
                            : Colors.green,
                      ),
                    ),
                  ),
              ],

              const SizedBox(height: 32),

              // Instance theme — the server's design system is a themeable
              // object (/style). Switching reskins every surface at once.
              Text(
                'INSTANCE THEME',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The object server\'s theme is data served at /style — one '
                'reversible edit reskins every web page and generated UI. '
                'Switching needs an admin session.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 12),
              if (_themes.isEmpty)
                Text(
                  'No themes reported by /style?info=true.',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final theme in _themes) _themeCard(context, theme),
                  ],
                ),
              if (_themeStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _themeStatus!,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          _themeStatus!.startsWith('Failed') ||
                              _themeStatus!.contains('403')
                          ? Colors.red[300]
                          : Colors.green,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themeCard(BuildContext context, String theme) {
    final preview = _themePreviews[theme];
    final active = theme == _activeTheme;
    final bg = _swatch(preview, 'bg') ?? Colors.black;
    final panel = _swatch(preview, 'panel') ?? Colors.white10;
    final accent = _swatch(preview, 'accent') ?? Colors.amber;
    final text = _swatch(preview, 'text') ?? Colors.white;
    return InkWell(
      onTap: _themeBusy ? null : () => _applyTheme(theme),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Colors.white12,
            width: active ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Swatch preview built from the theme's own tokens.
            Container(
              height: 56,
              color: bg,
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 36,
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aa',
                        style: TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 32,
                        height: 6,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  Text(theme, style: const TextStyle(fontSize: 13)),
                  const Spacer(),
                  if (active)
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

class SearchResultsView extends StatefulWidget {
  final String query;
  final void Function(String, Widget, [IconData]) onNavigate;
  const SearchResultsView({
    super.key,
    required this.query,
    required this.onNavigate,
  });

  @override
  State<SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends State<SearchResultsView> {
  Map<String, dynamic>? _results;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    _results = await ScrollAPI().search(widget.query);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_results == null) {
      return Center(
        child: Text('No results', style: TextStyle(color: Colors.white24)),
      );
    }

    final totalCount = _results!['total_count'] ?? 0;
    final resultsMap = _results!['results'] as Map<String, dynamic>? ?? {};

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search: "${widget.query}"',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '$totalCount results found',
            style: TextStyle(fontSize: 13, color: Colors.white38),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: resultsMap.entries.expand((typeEntry) {
                final typeName = typeEntry.key;
                final typeData = typeEntry.value as Map<String, dynamic>? ?? {};
                final items = typeData['results'] as List? ?? [];
                if (items.isEmpty) return <Widget>[];
                return [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          _typeIcon(typeName),
                          size: 16,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          typeName.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white38,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${items.length}',
                          style: TextStyle(fontSize: 11, color: Colors.white24),
                        ),
                      ],
                    ),
                  ),
                  ...items.map<Widget>((item) {
                    final title =
                        item['title']?.toString() ??
                        item['name']?.toString() ??
                        '?';
                    final snippet = item['snippet']?.toString() ?? '';
                    final status = item['status']?.toString();
                    return Card(
                      child: ListTile(
                        leading: Icon(_typeIcon(typeName), size: 20),
                        title: Text(
                          title,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: snippet.isNotEmpty
                            ? Text(
                                snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white38,
                                ),
                              )
                            : null,
                        trailing: status != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white54,
                                  ),
                                ),
                              )
                            : null,
                        onTap: () {},
                      ),
                    );
                  }),
                ];
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(String type) {
    return switch (type) {
      'tasks' => Icons.check_circle_outline,
      'notes' => Icons.note,
      'articles' => Icons.article,
      'links' => Icons.link,
      'contacts' => Icons.people,
      'projects' => Icons.folder,
      'files' => Icons.attach_file,
      _ => Icons.search,
    };
  }
}

// ---------------------------------------------------------------------------
// AI Create
// ---------------------------------------------------------------------------

class AICreateView extends StatefulWidget {
  const AICreateView({super.key});

  @override
  State<AICreateView> createState() => _AICreateViewState();
}

class _AICreateViewState extends State<AICreateView> {
  final _descController = TextEditingController();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController(
    text: 'def GET(request):\n    return {"hello": "world"}\n',
  );
  String _objectType = 'view';
  bool _saving = false;
  bool _generating = false;
  String? _saveResult;
  String? _lastSavedName;

  Future<void> _generate() async {
    if (_descController.text.trim().isEmpty) {
      setState(() => _saveResult = 'Describe what you want to build');
      return;
    }
    final key = await ScrollAPI().getOpenAIKey();
    if (key == null || key.isEmpty) {
      setState(() => _saveResult = 'Add your OpenAI API key in Settings first');
      return;
    }
    setState(() {
      _generating = true;
      _saveResult = 'AI is writing code...';
    });
    final result = await ScrollAPI().aiGenerateObject(
      description: _descController.text.trim(),
      objectType: _objectType,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _generating = false;
        _nameController.text = result['name'] ?? '';
        _codeController.text = result['code'] ?? '';
        _saveResult = 'Generated! Review and click Save & Deploy.';
      });
    } else {
      final err = ScrollAPI().lastError ?? 'AI generation failed';
      setState(() {
        _generating = false;
        _saveResult = err.length > 100
            ? 'Failed: ${err.substring(0, 100)}...'
            : 'Failed: $err';
      });
    }
  }

  Future<void> _saveObject() async {
    if (!_sourceWritesEnabled) {
      setState(() {
        _saveResult =
            'Object creation is locked: /admin/status.capabilities.source_writes.enabled is false';
      });
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      setState(() => _saveResult = 'Enter an object name');
      return;
    }
    setState(() {
      _saving = true;
      _saveResult = null;
    });
    final result = await ScrollAPI().createObject(
      _nameController.text.trim(),
      _codeController.text,
    );
    if (mounted) {
      setState(() {
        _saving = false;
        if (result != null) {
          _lastSavedName = _nameController.text.trim();
          final methods = result is Map ? result['methods'] : null;
          final warnings = result is Map ? result['warnings'] : null;
          if (warnings is List && warnings.isNotEmpty) {
            _saveResult = 'Saved with warnings: ${warnings.join(' ')}';
          } else if (methods is List && methods.isEmpty) {
            _saveResult =
                'Saved, but the source defines no HTTP methods — the object cannot execute. Define GET(request), POST(request), PUT(request), or DELETE(request).';
          } else {
            _saveResult =
                'Created! Object ${_nameController.text} is live'
                '${methods is List && methods.isNotEmpty ? ' (methods: ${methods.join(', ')})' : ''}. '
                'Open it from Admin → Objects.';
          }
        } else {
          final err = ScrollAPI().lastError ?? 'Unknown error';
          _saveResult = err.length > 100
              ? 'Failed: ${err.substring(0, 100)}...'
              : 'Failed: $err';
        }
      });
    }
  }

  Future<void> _testRun() async {
    if (_lastSavedName == null) return;
    final result = await ScrollAPI().executeAdminObject(_lastSavedName!);
    if (!mounted) return;
    final status = result['status'] as int?;
    final body = result['body'];
    if (status != null && status >= 200 && status < 300) {
      if (body is String && body.trimLeft().startsWith('<')) {
        setState(
          () => _saveResult =
              'Test run OK — returned HTML (${body.length} bytes)',
        );
      } else {
        setState(() => _saveResult = 'Test run OK — returned JSON');
      }
    } else if (status != null) {
      setState(() => _saveResult = 'Test run failed — HTTP $status');
    } else {
      setState(() => _saveResult = 'Test run failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceWritesEnabled = _sourceWritesEnabled;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 28, color: Colors.amber),
                  const SizedBox(width: 12),
                  Text(
                    'AI Create',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Describe what you want to build. AI can draft the object, data store, or view.',
                      style: TextStyle(fontSize: 13, color: Colors.white54),
                    ),
                  ),
                  _capabilityChip(
                    sourceWritesEnabled
                        ? 'SOURCE WRITES ENABLED'
                        : 'DEPLOY LOCKED',
                    sourceWritesEnabled ? Colors.orange : Colors.green,
                  ),
                ],
              ),
              if (!sourceWritesEnabled) ...[
                const SizedBox(height: 8),
                Text(
                  'Save & Deploy stays disabled until /admin/status reports source_writes.enabled=true.',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ],
              const SizedBox(height: 24),

              // Input
              TextField(
                controller: _descController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText:
                      'Examples:\n'
                      '• "Create a deals pipeline with Lead, Qualified, Proposal, Closed Won columns"\n'
                      '• "Build an expense tracker with categories and monthly totals"\n'
                      '• "Make a customer feedback form with rating and comments"',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.white24),
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Create as:',
                    style: TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'view',
                        label: Text('View', style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.language, size: 14),
                      ),
                      ButtonSegment(
                        value: 'data',
                        label: Text(
                          'Data Store',
                          style: TextStyle(fontSize: 12),
                        ),
                        icon: Icon(Icons.storage, size: 14),
                      ),
                      ButtonSegment(
                        value: 'object',
                        label: Text('Object', style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.code, size: 14),
                      ),
                      ButtonSegment(
                        value: 'trigger',
                        label: Text('Trigger', style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.schedule, size: 14),
                      ),
                    ],
                    selected: {_objectType},
                    onSelectionChanged: (v) =>
                        setState(() => _objectType = v.first),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _generating ? null : _generate,
                    icon: _generating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black87,
                            ),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(_generating ? 'Generating...' : 'Generate'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              const SizedBox(height: 12),
              // Object name
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Object Name',
                  hintText: 'my_deals_pipeline',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              if (_saveResult != null) ...[
                const SizedBox(height: 8),
                Text(
                  _saveResult!,
                  style: TextStyle(
                    fontSize: 13,
                    color: _saveResult!.startsWith('Created')
                        ? Colors.green
                        : Colors.red[300],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Generated preview / code editor
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.06),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(11),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'AI Generated — preview before saving',
                            style: TextStyle(fontSize: 12, color: Colors.amber),
                          ),
                          const Spacer(),
                          Text(
                            'view_deals_pipeline',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black26,
                      height: 150,
                      child: TextField(
                        controller: _codeController,
                        maxLines: null,
                        expands: true,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(8),
                        ),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.green[300],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(11),
                        ),
                      ),
                      child: Row(
                        children: [
                          FilledButton.icon(
                            onPressed: sourceWritesEnabled && !_saving
                                ? _saveObject
                                : null,
                            icon: _saving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save, size: 16),
                            label: Text(
                              _saving
                                  ? 'Saving...'
                                  : sourceWritesEnabled
                                  ? 'Save & Deploy'
                                  : 'Deploy Locked',
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _lastSavedName != null ? _testRun : null,
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: const Text('Test Run'),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _generating ? null : _generate,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Regenerate'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                sourceWritesEnabled
                    ? 'Once saved, this view will be instantly available through its object route.'
                    : 'Generation remains available as a draft workflow while public staging is read-only.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white38,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _sourceWritesEnabled => ScrollData().sourceWritesEnabled;

  Widget _capabilityChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Placeholder
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Permissions posture (admin)
// ---------------------------------------------------------------------------

class PermissionsView extends StatefulWidget {
  const PermissionsView({super.key});

  @override
  State<PermissionsView> createState() => _PermissionsViewState();
}

class _PermissionsViewState extends State<PermissionsView> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final data = ScrollData();
    final status = data.effectivePermissionsStatus;
    final policy = data.effectivePermissionsPolicy;
    final permissions = _section(status, const ['permissions']);
    final readiness = _section(status, const ['readiness']);
    final warnings = _stringList(status['warnings'] ?? permissions['warnings']);
    final blockers = _stringList(
      readiness['blockers'] ?? permissions['blockers'],
    );
    final state = _permissionState(status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security_outlined, size: 22, color: state.color),
              const SizedBox(width: 10),
              Text(
                'Permissions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(width: 10),
              _statusChip(state.label, state.color),
              const SizedBox(width: 12),
              Text(
                'GET /permissions/status',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white38,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _refreshing ? null : _refreshPermissions,
                icon: _refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh permissions',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (status.isEmpty)
            _emptyPermissions(context)
          else ...[
            _lockedControlBar(context),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric(
                  Icons.power_settings_new_outlined,
                  'Enforcement',
                  _shortStateLabel(state.label),
                  state.color,
                  wide: true,
                ),
                _metric(
                  Icons.fact_check_outlined,
                  'Can Enable',
                  _yesNo(_boolAt(readiness, const ['can_enable_enforcement'])),
                  _boolAt(readiness, const ['can_enable_enforcement']) == true
                      ? Colors.green
                      : Colors.orange,
                ),
                _metric(
                  Icons.report_problem_outlined,
                  'Blockers',
                  '${blockers.length}',
                  blockers.isEmpty ? Colors.green : Colors.orange,
                ),
                _metric(
                  Icons.warning_amber_outlined,
                  'Warnings',
                  '${warnings.length}',
                  warnings.isEmpty ? Colors.green : Colors.amber,
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 980;
                final cards = [
                  _statusCard(
                    context,
                    'Enforcement',
                    Icons.security_outlined,
                    state.color,
                    _enforcementRows(status),
                  ),
                  _statusCard(
                    context,
                    'Identity Path',
                    Icons.badge_outlined,
                    Colors.blue,
                    _identityRows(status),
                  ),
                  _statusCard(
                    context,
                    'Policy Shape',
                    Icons.account_tree_outlined,
                    Colors.purple,
                    _policyRows(status, policy),
                  ),
                  _statusCard(
                    context,
                    'Readiness',
                    Icons.checklist_outlined,
                    blockers.isEmpty ? Colors.green : Colors.orange,
                    _readinessRows(status),
                  ),
                ];
                if (!twoColumns) {
                  return Column(
                    children: [
                      for (final card in cards) ...[
                        card,
                        if (card != cards.last) const SizedBox(height: 12),
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards
                      .map(
                        (card) => SizedBox(
                          width: (constraints.maxWidth - 12) / 2,
                          child: card,
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            if (blockers.isNotEmpty)
              _messageList(
                context,
                'Readiness Blockers',
                Icons.block_outlined,
                Colors.orange,
                blockers,
              ),
            if (blockers.isNotEmpty) const SizedBox(height: 12),
            if (warnings.isNotEmpty)
              _messageList(
                context,
                'Warnings',
                Icons.warning_amber_outlined,
                Colors.amber,
                warnings,
              ),
            if (warnings.isNotEmpty) const SizedBox(height: 12),
            _rawJsonPanel('Raw permissions status', {
              'permissions_status': status,
              if (policy.isNotEmpty) 'permissions_policy': policy,
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _refreshPermissions() async {
    setState(() => _refreshing = true);
    await ScrollData().loadAll();
    if (mounted) setState(() => _refreshing = false);
  }

  Widget _lockedControlBar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _lockedAction(
            Icons.toggle_off_outlined,
            'Enforcement',
            'env-controlled rollout',
          ),
          _lockedAction(
            Icons.edit_note_outlined,
            'Policy Editor',
            'read-only in Scroll',
          ),
          _lockedAction(
            Icons.person_add_disabled_outlined,
            'Session Login',
            'gateway-token controlled',
          ),
        ],
      ),
    );
  }

  Widget _lockedAction(IconData icon, String label, String detail) {
    return Tooltip(
      message: detail,
      child: OutlinedButton.icon(
        onPressed: null,
        icon: Icon(icon, size: 15),
        label: Text(label),
      ),
    );
  }

  Widget _emptyPermissions(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_outline, size: 36, color: Colors.white38),
          const SizedBox(height: 10),
          const Text(
            'Permissions status unavailable',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Connect with an admin Bearer token to read permission readiness.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    IconData icon,
    String label,
    String value,
    Color color, {
    bool wide = false,
  }) {
    return Container(
      width: wide ? 190 : 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    List<MapEntry<String, dynamic>> rows,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _statusChip(rows.isEmpty ? 'EMPTY' : 'READ ONLY', color),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'Not reported',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            )
          else
            ...rows.map((entry) => _statusRow(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _statusRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              _titleCase(label),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 7,
            child: Text(
              _valueLabel(value),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: _valueColor(value),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageList(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    List<String> messages,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _statusChip('${messages.length}', color),
            ],
          ),
          const SizedBox(height: 10),
          for (final message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle, size: 6, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rawJsonPanel(String title, Map<String, dynamic> value) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: TextStyle(fontSize: 12, color: Colors.white54)),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(value),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  List<MapEntry<String, dynamic>> _enforcementRows(
    Map<String, dynamic> status,
  ) {
    final permissions = _section(status, const ['permissions']);
    return [
      _entry(
        'enforcement_requested',
        _permissionBool(status, permissions, 'enforcement_requested'),
      ),
      _entry(
        'enforcement_enabled',
        _permissionBool(status, permissions, 'enforcement_enabled'),
      ),
      _entry(
        'enforcement_blocked',
        _permissionBool(status, permissions, 'enforcement_blocked'),
      ),
      _entry(
        'audit_enabled',
        _permissionBool(status, permissions, 'audit_enabled'),
      ),
      _entry(
        'trusted_headers_enabled',
        _permissionBool(status, permissions, 'trusted_headers_enabled'),
      ),
      _entry(
        'session_login_enabled',
        _permissionBool(status, permissions, 'session_login_enabled'),
      ),
      _entry(
        'session_login_token_configured',
        _permissionBool(status, permissions, 'session_login_token_configured'),
      ),
    ];
  }

  List<MapEntry<String, dynamic>> _identityRows(Map<String, dynamic> status) {
    final permissions = _section(status, const ['permissions']);
    final identity = _section(status, const ['identity']);
    final capabilities = _section(status, const ['capabilities']);
    final capabilityIdentity = _section(capabilities, const ['identity']);
    return [
      _entry(
        'trusted_headers',
        _firstValue([
          permissions['trusted_headers_enabled'],
          identity['trusted_headers_enabled'],
          capabilityIdentity['trusted_headers_enabled'],
        ]),
      ),
      _entry(
        'session_login',
        _firstValue([
          permissions['session_login_enabled'],
          identity['session_login_enabled'],
          capabilityIdentity['session_login_enabled'],
        ]),
      ),
      _entry(
        'session_login_token',
        _firstValue([
          permissions['session_login_token_configured'],
          identity['session_login_token_configured'],
          capabilityIdentity['session_login_token_configured'],
        ]),
      ),
      _entry(
        'session_admin_gates',
        _firstValue([
          identity['session_admin_gates_enabled'],
          capabilityIdentity['session_admin_gates_enabled'],
          capabilityIdentity['admin_gates_enabled'],
        ]),
      ),
      _entry(
        'active_users',
        _firstValue([
          identity['active_users'],
          identity['active_user_count'],
          status['active_users'],
          status['active_user_count'],
        ]),
      ),
      _entry(
        'active_sessions',
        _firstValue([
          identity['active_sessions'],
          identity['active_session_count'],
          status['active_sessions'],
          status['active_session_count'],
        ]),
      ),
    ];
  }

  List<MapEntry<String, dynamic>> _policyRows(
    Map<String, dynamic> status,
    Map<String, dynamic> policy,
  ) {
    final shape = _section(status, const ['policy_shape']);
    final policyShape = _section(policy, const ['shape']);
    final source = {...policy, ...shape, ...policyShape};
    return [
      _entry(
        'access_mode',
        _firstValue([
          source['access_mode'],
          source['mode'],
          source['default_access'],
        ]),
      ),
      _entry(
        'rules_count',
        _firstValue([
          source['rules_count'],
          source['rule_count'],
          _listLength(source['rules']),
        ]),
      ),
      _entry(
        'allow_rules',
        _firstValue([
          source['allow_rules'],
          source['allow_count'],
          _listLength(source['allow']),
        ]),
      ),
      _entry(
        'deny_rules',
        _firstValue([
          source['deny_rules'],
          source['deny_count'],
          _listLength(source['deny']),
        ]),
      ),
      _entry(
        'principals',
        _firstValue([source['principals'], source['principal_count']]),
      ),
      _entry(
        'actions',
        _firstValue([source['actions'], source['action_count']]),
      ),
      _entry(
        'collections',
        _firstValue([source['collections'], source['collection_count']]),
      ),
    ];
  }

  List<MapEntry<String, dynamic>> _readinessRows(Map<String, dynamic> status) {
    final permissions = _section(status, const ['permissions']);
    final readiness = _section(status, const ['readiness']);
    return [
      _entry('can_enable_enforcement', readiness['can_enable_enforcement']),
      _entry('blockers', _stringList(readiness['blockers']).length),
      _entry('warnings', _stringList(status['warnings']).length),
      _entry(
        'admin_recovery',
        _firstValue([
          readiness['admin_recovery_token_configured'],
          permissions['admin_recovery_token_configured'],
        ]),
      ),
      _entry(
        'identity_path',
        _firstValue([
          readiness['identity_path_available'],
          readiness['has_non_admin_identity_path'],
        ]),
      ),
    ];
  }

  MapEntry<String, dynamic> _entry(String key, dynamic value) {
    return MapEntry(key, value ?? 'not reported');
  }

  _PermissionState _permissionState(Map<String, dynamic> status) {
    final permissions = _section(status, const ['permissions']);
    final requested =
        _permissionBool(status, permissions, 'enforcement_requested') == true;
    final enabled =
        _permissionBool(status, permissions, 'enforcement_enabled') == true;
    final blocked =
        _permissionBool(status, permissions, 'enforcement_blocked') == true ||
        _stringList(
          _section(status, const ['readiness'])['blockers'],
        ).isNotEmpty;
    final audit = _permissionBool(status, permissions, 'audit_enabled') == true;
    if (enabled) return _PermissionState('ENFORCEMENT ACTIVE', Colors.green);
    if (requested && blocked) {
      return _PermissionState('REQUESTED BLOCKED', Colors.orange);
    }
    if (audit || requested) return _PermissionState('AUDIT MODE', Colors.blue);
    return _PermissionState('ENFORCEMENT OFF', Colors.white54);
  }

  bool? _permissionBool(
    Map<String, dynamic> status,
    Map<String, dynamic> permissions,
    String key,
  ) {
    final capabilities = _section(status, const ['capabilities']);
    final permissionCaps = _section(capabilities, const ['permissions']);
    final identityCaps = _section(capabilities, const ['identity']);
    return _boolFromValue(
      _firstValue([
        permissions[key],
        status[key],
        permissionCaps[key],
        identityCaps[key],
      ]),
    );
  }

  Map<String, dynamic> _section(
    Map<String, dynamic> source,
    List<String> path,
  ) {
    dynamic current = source;
    for (final part in path) {
      if (current is Map) {
        current = current[part];
      } else {
        return const {};
      }
    }
    if (current is Map<String, dynamic>) return current;
    if (current is Map) {
      return current.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  bool? _boolAt(Map<String, dynamic> source, List<String> path) {
    dynamic current = source;
    for (final part in path) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    return _boolFromValue(current);
  }

  bool? _boolFromValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase();
      if (normalized == 'true' || normalized == 'yes' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == 'no' || normalized == '0') {
        return false;
      }
    }
    return null;
  }

  dynamic _firstValue(List<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      return value;
    }
    return null;
  }

  int? _listLength(dynamic value) {
    if (value is List) return value.length;
    return null;
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((item) => _valueLabel(item)).toList();
    }
    if (value is Map) {
      return value.entries.map((entry) {
        return '${_titleCase(entry.key.toString())}: ${_valueLabel(entry.value)}';
      }).toList();
    }
    if (value is String && value.trim().isNotEmpty) return [value];
    return const [];
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _shortStateLabel(String label) {
    if (label == 'ENFORCEMENT ACTIVE') return 'active';
    if (label == 'REQUESTED BLOCKED') return 'blocked';
    if (label == 'AUDIT MODE') return 'audit';
    return 'off';
  }

  String _yesNo(bool? value) {
    if (value == null) return '?';
    return value ? 'yes' : 'no';
  }

  String _valueLabel(dynamic value) {
    if (value == null) return '?';
    if (value is bool) return value ? 'yes' : 'no';
    if (value is List) return value.map(_valueLabel).join(', ');
    if (value is Map) {
      final entries = value.entries.take(4).map((entry) {
        return '${_titleCase(entry.key.toString())}: ${_valueLabel(entry.value)}';
      });
      return entries.join(', ');
    }
    return value.toString();
  }

  String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Color _valueColor(dynamic value) {
    if (value is bool) return value ? Colors.green : Colors.orange;
    final normalized = value?.toString().toLowerCase() ?? '';
    if (normalized == 'yes' ||
        normalized == 'true' ||
        normalized == 'ok' ||
        normalized == 'ready' ||
        normalized == 'enabled' ||
        normalized == 'active') {
      return Colors.green;
    }
    if (normalized == 'no' ||
        normalized == 'false' ||
        normalized == 'blocked' ||
        normalized == 'disabled' ||
        normalized == 'missing' ||
        normalized == 'not reported') {
      return Colors.orange;
    }
    return Colors.white70;
  }
}

class _PermissionState {
  final String label;
  final Color color;

  const _PermissionState(this.label, this.color);
}

// ---------------------------------------------------------------------------
// API Explorer (admin)
// ---------------------------------------------------------------------------

class APIExplorerView extends StatefulWidget {
  const APIExplorerView({super.key});

  @override
  State<APIExplorerView> createState() => _APIExplorerViewState();
}

class _APIExplorerViewState extends State<APIExplorerView> {
  String _selectedEndpoint = 'GET /health';
  final _urlController = TextEditingController();
  final _bodyController = TextEditingController();
  String? _response;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _updateUrl();
    _bodyController.text = _defaultBodyFor(_selectedEndpoint);
  }

  String get _method => _selectedEndpoint.split(' ').first;

  String get _path {
    final parts = _selectedEndpoint.split(' ');
    return parts.length > 1 ? parts.sublist(1).join(' ') : '';
  }

  bool get _usesPlatform => _path.startsWith('/api/');

  bool get _hasBody =>
      _method == 'POST' || _method == 'PUT' || _method == 'PATCH';

  void _updateUrl() {
    final api = ScrollAPI();
    final base = _usesPlatform
        ? (api.platformUrl ?? '')
        : (api.objectServerUrl ?? '');
    _urlController.text = _joinUrl(base, _path);
  }

  String _joinUrl(String base, String path) {
    if (base.isEmpty) return path;
    final normalizedBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$normalizedBase$normalizedPath';
  }

  String _defaultBodyFor(String endpoint) {
    if (endpoint.startsWith('POST /admin/objects/') &&
        endpoint.endsWith('/execute')) {
      return const JsonEncoder.withIndent(
        '  ',
      ).convert({'method': 'GET', 'payload': {}});
    }
    if (endpoint.startsWith('POST /admin/objects')) {
      return const JsonEncoder.withIndent('  ').convert({
        'name': 'codex_probe_object',
        'code':
            'def GET(request):\n    return {"status": "ok", "source": "admin"}\n',
      });
    }
    if (endpoint.startsWith('PUT /admin/objects/') &&
        endpoint.contains('source=true')) {
      return const JsonEncoder.withIndent('  ').convert({
        'code':
            'def GET(request):\n    return {"status": "updated", "source": "admin"}\n',
      });
    }
    if (endpoint == 'POST /identity/session') {
      return const JsonEncoder.withIndent('  ').convert({
        'email': 'dan@example.com',
        'password': 'change-me-now',
        'label': 'api explorer login',
      });
    }
    if (endpoint.startsWith('POST /admin/identity/users/') &&
        endpoint.endsWith('/password')) {
      return const JsonEncoder.withIndent(
        '  ',
      ).convert({'password': 'change-me-now'});
    }
    if (endpoint.startsWith('POST /admin/collections/') &&
        endpoint.endsWith('/records')) {
      return const JsonEncoder.withIndent('  ').convert({
        'id': 'probe_001',
        'status': 'created',
        'note': 'admin record write test',
      });
    }
    if (endpoint.startsWith('PUT /admin/collections/') &&
        endpoint.contains('/records/')) {
      return const JsonEncoder.withIndent(
        '  ',
      ).convert({'status': 'updated', 'note': 'admin record update test'});
    }
    if (endpoint.startsWith('PUT /admin/schemas/')) {
      return const JsonEncoder.withIndent('  ').convert({
        'schema': {
          'fields': [
            {'name': 'status', 'type': 'string', 'required': false},
            {'name': 'note', 'type': 'string', 'required': false},
          ],
        },
        'author': 'scroll-operator',
        'message': 'schema update test',
      });
    }
    if (endpoint.startsWith('POST /admin/schemas/')) {
      return const JsonEncoder.withIndent(
        '  ',
      ).convert({'action': 'rollback', 'version_id': 1});
    }
    if (endpoint.startsWith('POST /collections/dbbasic_probe/records')) {
      return const JsonEncoder.withIndent('  ').convert({
        'id': 'probe_001',
        'status': 'created',
        'note': 'admin write test',
      });
    }
    if (endpoint.startsWith('PUT /collections/dbbasic_probe/records/')) {
      return const JsonEncoder.withIndent(
        '  ',
      ).convert({'status': 'updated', 'note': 'update path works'});
    }
    return '{}';
  }

  Color _methodColor(String method) {
    return switch (method) {
      'GET' => Colors.green,
      'POST' => Colors.blue,
      'PUT' => Colors.orange,
      'PATCH' => Colors.purple,
      'DELETE' => Colors.red,
      _ => Colors.white54,
    };
  }

  Future<void> _send() async {
    setState(() {
      _loading = true;
      _response = null;
    });
    try {
      final api = ScrollAPI();
      final url = _urlController.text;
      Map<String, dynamic>? body;
      if (_hasBody && _bodyController.text.trim().isNotEmpty) {
        final decoded = jsonDecode(_bodyController.text) as Object?;
        if (decoded is! Map<String, dynamic>) {
          setState(() {
            _response = 'Error: JSON body must be an object';
            _loading = false;
          });
          return;
        }
        body = decoded;
      }
      final result = await api.rawRequest(
        _method,
        url,
        data: body,
        platformAuth: _usesPlatform,
      );
      _response = const JsonEncoder.withIndent('  ').convert(result);
    } catch (e) {
      _response = 'Error: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final endpoints = [
      (
        'Object Server: Probe',
        [
          'GET /health',
          'GET /admin/status',
          'GET /daemon/status',
          'GET /identity/session',
        ],
      ),
      (
        'Object Server: Daemon',
        [
          'GET /daemon/scheduler/tasks',
          'GET /daemon/queue/messages',
          'GET /events/deliveries',
        ],
      ),
      (
        'Object Server: Permissions',
        ['GET /permissions/status', 'GET /permissions/policy'],
      ),
      (
        'Object Server: Identity Auth',
        [
          'POST /identity/session',
          'GET /identity/session',
          'DELETE /identity/session',
        ],
      ),
      (
        'Object Server: Admin Identity',
        [
          'GET /admin/identity/accounts',
          'GET /admin/identity/accounts/account_001',
          'GET /admin/identity/users',
          'GET /admin/identity/users?account_id=account_001',
          'GET /admin/identity/users/user_001',
          'POST /admin/identity/users/user_001/password',
          'DELETE /admin/identity/users/user_001/password',
          'GET /admin/identity/sessions',
          'GET /admin/identity/sessions/session_001',
        ],
      ),
      (
        'Object Server: Admin Files',
        [
          'GET /admin/files',
          'GET /admin/files?limit=100&offset=0',
          'GET /admin/files?object_id=system_write_probe',
          'GET /admin/files/system_write_probe',
          'GET /admin/files/system_write_probe?file=example.txt',
          'GET /admin/objects/system_write_probe?files=true',
          'GET /admin/objects/system_write_probe?file=example.txt',
        ],
      ),
      (
        'Object Server: Admin Changes',
        [
          'GET /admin/changes',
          'GET /admin/changes?limit=100&offset=0',
          'GET /admin/changes?kind=source&limit=100',
          'GET /admin/changes?kind=file&object_id=system_write_probe&limit=100',
          'GET /admin/changes?kind=record&collection=dbbasic_probe&limit=100',
          'GET /admin/changes?kind=package&limit=100',
          'GET /admin/objects/system_write_probe?changes=true&limit=100',
        ],
      ),
      (
        'Object Server: Admin Objects',
        [
          'GET /admin/objects',
          'POST /admin/objects',
          'GET /admin/objects/system_write_probe',
          'GET /admin/objects/system_write_probe?metadata=true',
          'GET /admin/objects/system_write_probe?source=true&format=json',
          'PUT /admin/objects/system_write_probe?source=true',
          'POST /admin/objects/system_write_probe/execute',
          'GET /admin/objects/system_write_probe?state=true',
          'GET /admin/objects/system_write_probe?logs=true&limit=100',
          'GET /admin/objects/system_write_probe?versions=true&limit=10',
          'GET /admin/objects/system_write_probe?version=1',
          'GET /admin/objects/system_write_probe?changes=true&limit=100',
        ],
      ),
      (
        'Object Server: Admin Collections',
        [
          'GET /admin/collections',
          'GET /admin/collections/dbbasic_probe',
          'GET /admin/collections/dbbasic_probe/records',
          'POST /admin/collections/dbbasic_probe/records',
          'GET /admin/collections/dbbasic_probe/records/probe_001',
          'PUT /admin/collections/dbbasic_probe/records/probe_001',
          'DELETE /admin/collections/dbbasic_probe/records/probe_001',
          'GET /admin/collections/dbbasic_probe/changes',
          'GET /admin/collections/dbbasic_probe/records/probe_001/changes',
        ],
      ),
      (
        'Object Server: Admin Schemas',
        [
          'GET /admin/schemas',
          'GET /admin/schemas/dbbasic_probe',
          'PUT /admin/schemas/dbbasic_probe',
          'POST /admin/schemas/dbbasic_probe',
          'GET /admin/schemas/dbbasic_probe?versions=true&limit=10',
          'GET /admin/schemas/dbbasic_probe?version=1',
        ],
      ),
      (
        'Object Server: Legacy',
        [
          'GET /health?metrics=true&format=json',
          'GET /cluster/stations?format=json',
          'GET /cluster/info',
        ],
      ),
      (
        'Platform: Legacy',
        [
          'GET /api/contacts/',
          'GET /api/contacts/?limit=5',
          'GET /api/tasks/',
          'GET /api/projects/',
          'GET /api/files/?limit=10',
          'GET /api/search/?q=deals',
        ],
      ),
    ];
    final currentMethodColor = _methodColor(_method);

    return Row(
      children: [
        // Endpoint list
        Container(
          width: 260,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'ENDPOINTS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white38,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${endpoints.fold<int>(0, (sum, e) => sum + e.$2.length)}',
                      style: TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  children: endpoints.map((group) {
                    return ExpansionTile(
                      dense: true,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                      title: Text(
                        group.$1,
                        style: const TextStyle(fontSize: 13),
                      ),
                      initiallyExpanded: group.$1 == 'Object Server: Probe',
                      children: group.$2.map((ep) {
                        final method = ep.split(' ')[0];
                        final methodColor = _methodColor(method);
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          selected: _selectedEndpoint == ep,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withOpacity(0.2),
                          contentPadding: const EdgeInsets.only(
                            left: 24,
                            right: 8,
                          ),
                          title: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$method ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: methodColor,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                TextSpan(
                                  text: ep.substring(method.length + 1),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedEndpoint = ep;
                              _updateUrl();
                              _bodyController.text = _defaultBodyFor(ep);
                            });
                          },
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Container(width: 1, color: Colors.white10),
        // API test panel
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Request
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: currentMethodColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _method,
                        style: TextStyle(
                          fontSize: 12,
                          color: currentMethodColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        style: TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _loading ? null : _send,
                      child: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Send'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_hasBody) ...[
                  Text(
                    'JSON Body',
                    style: TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 130,
                    child: TextField(
                      controller: _bodyController,
                      maxLines: null,
                      expands: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(10),
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Auth info
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.withOpacity(0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock, size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        _usesPlatform
                            ? 'LEGACY PLATFORM — Token auth'
                            : 'OBJECT SERVER — Bearer admin token',
                        style: TextStyle(fontSize: 11, color: Colors.green),
                      ),
                      const Spacer(),
                      Text(
                        _usesPlatform
                            ? 'Token auth: ........'
                            : 'Bearer token: ........',
                        style: TextStyle(fontSize: 11, color: Colors.white24),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Response',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: SelectableText(
                      _response ?? '// Click Send to make a request',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _response != null
                            ? Colors.white70
                            : Colors.white24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SQL Query (admin — power user feature)
// ---------------------------------------------------------------------------

class SQLQueryView extends StatelessWidget {
  const SQLQueryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Query editor
        Container(
          height: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'SQL Query',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'via object server',
                      style: TextStyle(fontSize: 10, color: Colors.orange),
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: Colors.amber,
                    ),
                    label: Text(
                      'AI: natural language',
                      style: TextStyle(fontSize: 12, color: Colors.amber),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Run'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  maxLines: null,
                  expands: true,
                  controller: TextEditingController(
                    text:
                        'SELECT c.first_name, c.last_name, c.email,\n'
                        '       COUNT(i.id) as invoice_count,\n'
                        '       SUM(i.total) as total_spent\n'
                        'FROM contacts c\n'
                        'LEFT JOIN invoices i ON i.customer_id = c.id\n'
                        'GROUP BY c.id\n'
                        'HAVING SUM(i.total) > 1000\n'
                        'ORDER BY total_spent DESC\n'
                        'LIMIT 20;',
                  ),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Colors.green[300],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Results
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.05),
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                '8 rows returned in 45ms',
                style: TextStyle(fontSize: 12, color: Colors.green),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: Text('Export CSV', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () {},
                child: Text('Explain', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowHeight: 32,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 30,
                columnSpacing: 32,
                headingTextStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white54,
                ),
                dataTextStyle: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                columns: const [
                  DataColumn(label: Text('first_name')),
                  DataColumn(label: Text('last_name')),
                  DataColumn(label: Text('email')),
                  DataColumn(label: Text('invoice_count'), numeric: true),
                  DataColumn(label: Text('total_spent'), numeric: true),
                ],
                rows:
                    [
                          [
                            'Alice',
                            'Chen',
                            'alice@acmecorp.com',
                            '12',
                            '\$45,200',
                          ],
                          ['Bob', 'Smith', 'bob@techstart.io', '8', '\$23,400'],
                          [
                            'Carol',
                            'Davis',
                            'carol@dataflow.com',
                            '15',
                            '\$18,750',
                          ],
                          [
                            'Dan',
                            'Wilson',
                            'dan@cloudnine.co',
                            '6',
                            '\$12,300',
                          ],
                          [
                            'Eva',
                            'Martinez',
                            'eva@acmecorp.com',
                            '9',
                            '\$8,900',
                          ],
                          [
                            'Frank',
                            'Lee',
                            'frank@techstart.io',
                            '4',
                            '\$5,600',
                          ],
                          [
                            'Grace',
                            'Kim',
                            'grace@dataflow.com',
                            '7',
                            '\$3,200',
                          ],
                          [
                            'Henry',
                            'Park',
                            'henry@cloudnine.co',
                            '3',
                            '\$1,450',
                          ],
                        ]
                        .map(
                          (row) => DataRow(
                            cells: row
                                .map((cell) => DataCell(Text(cell)))
                                .toList(),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Backup & Restore (admin)
// ---------------------------------------------------------------------------

class BackupView extends StatefulWidget {
  const BackupView({super.key});

  @override
  State<BackupView> createState() => _BackupViewState();
}

class _BackupViewState extends State<BackupView> {
  List<Map<String, dynamic>> _backups = [];
  bool _loading = true;
  bool _creating = false;
  String? _downloadingId;
  String? _error;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Refresh capabilities (the flags may predate the backup-API deploy)
    // and the inventory together.
    final status = await ScrollAPI().getAdminStatus();
    final result = await ScrollAPI().listBackups();
    if (!mounted) return;
    if (status != null) ScrollData().adminStatus = status;
    final code = result['status'];
    final body = result['body'];
    if (code is int && code >= 200 && code < 300 && body is Map) {
      final raw = body['backups'];
      setState(() {
        _backups = [
          if (raw is List)
            for (final b in raw)
              if (b is Map)
                Map<String, dynamic>.from(
                  b.map((k, v) => MapEntry(k.toString(), v)),
                ),
        ];
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        // 404/401 here just means the capability isn't live for this
        // session; the locked placeholder covers it.
        _error = code is int && code != 200 ? 'HTTP $code' : null;
      });
    }
  }

  Future<void> _backupNow() async {
    setState(() {
      _creating = true;
      _status = null;
    });
    final result = await ScrollAPI().createBackup();
    if (!mounted) return;
    final code = result['status'];
    final ok = code is int && code >= 200 && code < 300;
    setState(() {
      _creating = false;
      _statusIsError = !ok;
      _status = ok
          ? 'Backup created.'
          : 'Backup failed: HTTP ${code ?? result['error'] ?? '?'}';
    });
    if (ok) _refresh();
  }

  Future<void> _download(Map<String, dynamic> backup) async {
    final id = backup['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() {
      _downloadingId = id;
      _status = null;
    });
    final result = await ScrollAPI().downloadBackup(id);
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _downloadingId = null;
        _statusIsError = true;
        _status = 'Download failed: ${ScrollAPI().lastError ?? 'error'}';
      });
      return;
    }
    // Native Save dialog — sandbox-safe: the user's choice grants write
    // access to that location.
    try {
      final location = await getSaveLocation(suggestedName: result.filename);
      if (location == null) {
        if (mounted) setState(() => _downloadingId = null);
        return; // cancelled
      }
      await File(location.path).writeAsBytes(result.bytes);
      if (!mounted) return;
      setState(() {
        _downloadingId = null;
        _statusIsError = false;
        _status =
            'Saved ${_formatSize(result.bytes.length)} to '
            '${location.path}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingId = null;
        _statusIsError = true;
        _status = 'Could not save file: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ScrollData();
    final capability = data.backupCapability;
    final apiExposed = data.backupApiExposed;
    final canCreate = data.backupCanCreate;
    final canRestore = data.backupCanRestore;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Backup & Restore',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(width: 10),
              _chip(
                apiExposed ? 'BACKUP API AVAILABLE' : 'Backup API not exposed',
                apiExposed ? Colors.green : Colors.white54,
              ),
              const Spacer(),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: canCreate
                    ? 'Create a full-runtime backup now'
                    : 'Backup creation not available for this session',
                child: FilledButton.icon(
                  onPressed: (canCreate && !_creating) ? _backupNow : null,
                  icon: _creating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup, size: 16),
                  label: const Text('Backup Now'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            apiExposed
                ? 'On-demand backups run now and can be downloaded. A backup '
                      'contains all runtime data (including credentials), so '
                      'these routes are admin-only. Restore stays a CLI '
                      'operation on the server.'
                : 'Backup inventory, creation, and download are not exposed '
                      'through the admin API for this session.',
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
          if (_status != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (_statusIsError ? Colors.red : Colors.green).withValues(
                  alpha: 0.12,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusIsError ? Icons.error_outline : Icons.check_circle,
                    size: 16,
                    color: _statusIsError ? Colors.red[300] : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      _status!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _statusIsError
                            ? Colors.red[200]
                            : Colors.green[200],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _status = null),
                    icon: const Icon(Icons.close, size: 14),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _backupStat(
                context,
                'Backup API',
                apiExposed ? 'available' : 'not exposed',
                Icons.backup_outlined,
                apiExposed ? Colors.green : Colors.white54,
              ),
              _backupStat(
                context,
                'Create',
                canCreate ? 'available' : 'locked',
                Icons.add_circle_outline,
                canCreate ? Colors.green : Colors.white54,
              ),
              _backupStat(
                context,
                'Download',
                data.backupCanDownload ? 'available' : 'locked',
                Icons.download_outlined,
                data.backupCanDownload ? Colors.green : Colors.white54,
              ),
              _backupStat(
                context,
                'Restore',
                canRestore ? 'available' : 'CLI only',
                Icons.restore_outlined,
                canRestore ? Colors.green : Colors.orange,
              ),
              _backupStat(
                context,
                'Schedule',
                data.backupScheduled ? (data.backupSchedule ?? 'on') : 'off',
                Icons.schedule_outlined,
                data.backupScheduled ? Colors.green : Colors.white54,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _inventoryPanel(context, apiExposed),
          if (capability.isNotEmpty) ...[
            const SizedBox(height: 16),
            _rawPanel('Raw backup capability', capability),
          ],
        ],
      ),
    );
  }

  Widget _inventoryPanel(BuildContext context, bool apiExposed) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_outlined, size: 18, color: Colors.white54),
              const SizedBox(width: 8),
              const Text(
                'Backup Inventory',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _chip(
                _backups.isEmpty ? 'EMPTY' : '${_backups.length}',
                _backups.isEmpty ? Colors.white54 : Colors.teal,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!apiExposed)
            _lockedInventory(context)
          else if (_backups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  _loading
                      ? 'Loading backups…'
                      : 'No backups yet — click "Backup Now" to create one.',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ),
            )
          else
            for (final backup in _backups) _backupRow(context, backup),
        ],
      ),
    );
  }

  Widget _backupRow(BuildContext context, Map<String, dynamic> backup) {
    final id = backup['id']?.toString() ?? '';
    final kind = backup['kind']?.toString() ?? 'manual';
    final scope = backup['scope']?.toString();
    final created = backup['created_at']?.toString() ?? '';
    final size = backup['size'];
    final downloading = _downloadingId == id;
    final kindColor = switch (kind) {
      'manual' => Colors.teal,
      'package' => Colors.blue,
      'restore-point' => Colors.orange,
      _ => Colors.white54,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          _chip(kind.toUpperCase(), kindColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  id,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                Text(
                  [
                    if (created.isNotEmpty)
                      created.length > 19 ? created.substring(0, 19) : created,
                    if (size is num) _formatSize(size.toInt()),
                    if (scope != null && scope.isNotEmpty && scope != 'null')
                      'scope: $scope',
                  ].join('  ·  '),
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: (ScrollData().backupCanDownload && !downloading)
                ? () => _download(backup)
                : null,
            icon: downloading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined, size: 15),
            label: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Widget _lockedInventory(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 8),
          Icon(Icons.lock_outline, size: 34, color: Colors.white30),
          const SizedBox(height: 10),
          const Text(
            'Backup API not exposed',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'This session cannot read `/admin/backups`. An admin session is '
            'required.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _backupStat(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rawPanel(String title, Map<String, dynamic> value) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: TextStyle(fontSize: 12, color: Colors.white54)),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(value),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

}
