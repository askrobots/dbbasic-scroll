import 'api.dart';

/// Cached data from the object server and platform API.
/// Loads once on connect, refreshes on demand.
class ScrollData {
  static final ScrollData _instance = ScrollData._();
  factory ScrollData() => _instance;
  ScrollData._();

  // Object server
  Map<String, dynamic>? adminStatus;
  Map<String, dynamic>? daemonStatus;
  Map<String, dynamic>? daemonSchedulerTasksResponse;
  Map<String, dynamic>? daemonQueueMessagesResponse;
  Map<String, dynamic>? eventDeliveriesResponse;
  Map<String, dynamic>? adminChangesResponse;
  Map<String, dynamic>? permissionsStatus;
  Map<String, dynamic>? permissionsPolicy;
  Map<String, dynamic>? health;
  Map<String, dynamic>? cluster;
  List<dynamic> objects = [];
  bool clusterAvailable = false;
  bool usingHealthFallback = false;

  // Platform counts
  int projectCount = 0;
  int contactCount = 0;
  int taskCount = 0;
  int fileCount = 0;
  int objectCount = 0;

  // Station info
  List<dynamic> stations = [];
  String uptime = '';
  int requests = 0;
  int errors = 0;
  double rps = 0;
  double errorRate = 0;
  String version = '';
  Map<String, dynamic>? responseTime;

  bool loaded = false;

  /// Reset every cached value. Call on disconnect so a later connection
  /// (possibly a different token/identity) never renders stale data.
  void clear() {
    adminStatus = null;
    daemonStatus = null;
    daemonSchedulerTasksResponse = null;
    daemonQueueMessagesResponse = null;
    eventDeliveriesResponse = null;
    adminChangesResponse = null;
    permissionsStatus = null;
    permissionsPolicy = null;
    health = null;
    cluster = null;
    objects = [];
    stations = [];
    clusterAvailable = false;
    usingHealthFallback = false;
    projectCount = 0;
    contactCount = 0;
    taskCount = 0;
    fileCount = 0;
    objectCount = 0;
    uptime = '';
    requests = 0;
    errors = 0;
    rps = 0;
    errorRate = 0;
    version = '';
    responseTime = null;
    loaded = false;
  }

  Future<void> loadAll() async {
    final api = ScrollAPI();

    // Fields are swapped in as responses arrive (never blanked first), so a
    // widget rebuilding mid-load renders last-known data instead of zeros.
    // Object server health — the stats live behind metrics=true (auth
    // required); fall back to the public plain /health if that is denied.
    health = await api.getHealth(metrics: true) ?? await api.getHealth();
    adminStatus = await api.getAdminStatus();
    daemonStatus = await api.getDaemonStatus();
    daemonSchedulerTasksResponse = await api.getDaemonSchedulerTasks();
    daemonQueueMessagesResponse = await api.getDaemonQueueMessages();
    eventDeliveriesResponse = await api.getEventDeliveries();
    adminChangesResponse = await api.listAdminChanges();
    permissionsStatus = await api.getPermissionsStatus();
    permissionsPolicy = await api.getPermissionsPolicy();
    if (health != null) {
      uptime = health!['uptime']?.toString() ?? '';
      requests = health!['requests'] as int? ?? 0;
      errors = health!['errors'] as int? ?? 0;
      rps = (health!['rps'] as num?)?.toDouble() ?? 0;
      errorRate = (health!['error_rate'] as num?)?.toDouble() ?? 0;
      version = health!['version']?.toString() ?? '';
      responseTime = health!['response_time_ms'] as Map<String, dynamic>?;
    }

    // Cluster stations are optional on the OSS object server. If unavailable,
    // show the connected server as a single node based on /health.
    List<dynamic> newStations = [];
    var newClusterAvailable = false;
    var newFallback = false;
    final clusterData = await api.getClusterStations();
    if (clusterData is Map<String, dynamic>) {
      cluster = clusterData;
      final clusterStations = clusterData['stations'];
      if (clusterStations is List && clusterStations.isNotEmpty) {
        newStations = clusterStations;
        newClusterAvailable = true;
      }
    }
    if (newStations.isEmpty && health != null) {
      newStations = [_singleServerStation(api.objectServerUrl ?? '')];
      newFallback = true;
    }
    stations = newStations;
    clusterAvailable = newClusterAvailable;
    usingHealthFallback = newFallback;

    // Objects
    objects = await api.listObjects();
    objectCount = _inventoryInt('objects') ?? objects.length;

    // Platform counts (if connected)
    if (api.hasPlatform) {
      projectCount = await api.platformCount('projects');
      contactCount = await api.platformCount('contacts');
      taskCount = await api.platformCount('tasks');
      fileCount = await api.platformCount('files');
    }

    loaded = true;
  }

  int get activeStations =>
      stations.where((s) => s['is_active'] == true).length;
  String get stationSummary {
    if (adminStatus != null) {
      return adminHealthStatus == 'ok'
          ? 'Admin status healthy'
          : 'Admin status $adminHealthStatus';
    }
    if (usingHealthFallback) {
      return health?['status'] == 'ok'
          ? 'Single OSS server healthy'
          : 'Single OSS server status unknown';
    }
    return '$activeStations stations healthy';
  }

  Map<String, dynamic> _singleServerStation(String serverUrl) {
    final uri = Uri.tryParse(serverUrl);
    final host = uri?.host.isNotEmpty == true ? uri!.host : 'object-server';
    final status = health?['status']?.toString() ?? 'unknown';
    // /health?metrics=true nests machine stats under system/objects.
    final system = health?['system'] is Map
        ? Map<String, dynamic>.from(health!['system'] as Map)
        : const <String, dynamic>{};
    final memory = system['memory'] is Map
        ? Map<String, dynamic>.from(system['memory'] as Map)
        : const <String, dynamic>{};
    final disk = system['disk'] is Map
        ? Map<String, dynamic>.from(system['disk'] as Map)
        : const <String, dynamic>{};
    final objects = health?['objects'] is Map
        ? Map<String, dynamic>.from(health!['objects'] as Map)
        : const <String, dynamic>{};
    return {
      'station_id': 'object-server',
      'is_active': status == 'ok',
      'version': health?['version']?.toString() ?? 'OSS',
      'host': host,
      'port': uri?.hasPort == true ? uri!.port : null,
      'source': 'health',
      'metrics': {
        'status': status,
        'cpu_percent': system['cpu_percent'] ?? health?['cpu_percent'],
        'memory_percent': memory['used_percent'] ?? health?['memory_percent'],
        'disk_percent': disk['used_percent'] ?? health?['disk_percent'],
        'cpu_count': system['cpu_count'] ?? health?['cpu_count'],
        'memory_total_mb': memory['total_mb'] ?? health?['memory_total_mb'],
        'disk_used_gb': disk['used_gb'] ?? health?['disk_used_gb'],
        'disk_total_gb': disk['total_gb'] ?? health?['disk_total_gb'],
        'object_count': objects['count'] ?? health?['object_count'],
      },
    };
  }

  String get requestSummary {
    if (requests > 1000000) {
      return '${(requests / 1000000).toStringAsFixed(1)}M';
    }
    if (requests > 1000) return '${(requests / 1000).toStringAsFixed(1)}k';
    return '$requests';
  }

  bool get hasAdminStatus => adminStatus != null;
  bool get hasDaemonStatus => daemonStatus != null;

  bool get hasDaemonSchedulerTasks => daemonSchedulerTasksResponse != null;
  bool get hasDaemonQueueMessages => daemonQueueMessagesResponse != null;
  bool get hasEventDeliveries => eventDeliveriesResponse != null;
  bool get hasAdminChanges => adminChangesResponse != null;
  bool get hasPermissionsStatus => effectivePermissionsStatus.isNotEmpty;
  bool get hasPermissionsPolicy => effectivePermissionsPolicy.isNotEmpty;
  bool get fileWritesEnabled =>
      _boolFromDynamic(fileWritesCapability['enabled']) == true;
  bool get sourceWritesEnabled =>
      _boolFromDynamic(sourceWritesCapability['enabled']) == true;
  bool get passwordLoginEnabled =>
      _boolFromDynamic(identityCapability['password_login_enabled']) == true;
  bool get sessionAdminGatesEnabled =>
      _boolFromDynamic(identityCapability['session_admin_gates_enabled']) ==
          true ||
      _boolFromDynamic(identityCapability['admin_gates_enabled']) == true;
  bool get backupApiExposed =>
      _boolFromDynamic(backupCapability['enabled']) == true ||
      _boolFromDynamic(backupCapability['available']) == true ||
      _boolFromDynamic(backupCapability['api_exposed']) == true;

  bool get backupCanCreate =>
      _boolFromDynamic(backupCapability['can_create']) == true;
  bool get backupCanDownload =>
      _boolFromDynamic(backupCapability['can_download']) == true;
  bool get backupCanRestore =>
      _boolFromDynamic(backupCapability['can_restore']) == true;
  bool get backupScheduled =>
      _boolFromDynamic(backupCapability['scheduled']) == true;
  String? get backupSchedule =>
      backupCapability['schedule']?.toString().trim().isNotEmpty == true
      ? backupCapability['schedule'].toString()
      : null;

  Map<String, dynamic> get fileWritesCapability {
    return _mapAt(const [
      ['capabilities', 'file_writes'],
      ['capabilities', 'fileWrites'],
      ['file_writes'],
      ['fileWrites'],
    ], root: adminStatus);
  }

  Map<String, dynamic> get sourceWritesCapability {
    return _mapAt(const [
      ['capabilities', 'source_writes'],
      ['capabilities', 'sourceWrites'],
      ['source_writes'],
      ['sourceWrites'],
    ], root: adminStatus);
  }

  Map<String, dynamic> get identityCapability {
    return _mapAt(const [
      ['capabilities', 'identity'],
      ['identity'],
    ], root: adminStatus);
  }

  Map<String, dynamic> get backupCapability {
    return _mapAt(const [
      ['capabilities', 'backups'],
      ['capabilities', 'backup'],
      ['backup'],
      ['backups'],
    ], root: adminStatus);
  }

  Map<String, dynamic> get packagesCapability {
    return _mapAt(const [
      ['capabilities', 'packages'],
      ['packages'],
    ], root: adminStatus);
  }

  bool get packagesCanInstall =>
      _boolFromDynamic(packagesCapability['can_install']) == true;

  int? get maxObjectFileBytes {
    final value =
        fileWritesCapability['max_bytes'] ??
        fileWritesCapability['maxBytes'] ??
        fileWritesCapability['limit'];
    return _intFromDynamic(value);
  }

  String get adminHealthStatus {
    return _stringAt(const [
          ['status'],
          ['health', 'status'],
          ['metrics', 'status'],
        ]) ??
        health?['status']?.toString() ??
        'unknown';
  }

  String get packageSummary {
    final packages = adminPackages;
    if (packages.isEmpty) return 'No package status';
    final installed = packages.where((p) {
      final status = (p['status'] ?? p['state'] ?? p['value'])
          ?.toString()
          .toLowerCase();
      final installed = p['installed'];
      return installed == true || status == 'installed';
    }).length;
    return '$installed/${packages.length} packages installed';
  }

  String get daemonHealthStatus {
    return _stringAt(const [
          ['status'],
          ['daemon', 'status'],
        ], root: daemonStatus) ??
        'unknown';
  }

  Map<String, dynamic> daemonSection(String key) {
    final status = daemonStatus;
    if (status == null) return const {};
    final direct = status[key];
    if (direct is Map<String, dynamic>) return direct;
    if (direct is Map) {
      return direct.map((itemKey, itemValue) {
        return MapEntry(itemKey.toString(), itemValue);
      });
    }
    final snake = _snakeCase(key);
    final snakeValue = status[snake];
    if (snakeValue is Map<String, dynamic>) return snakeValue;
    if (snakeValue is Map) {
      return snakeValue.map((itemKey, itemValue) {
        return MapEntry(itemKey.toString(), itemValue);
      });
    }
    return const {};
  }

  Map<String, dynamic> get effectivePermissionsStatus {
    final direct = _mapFromNullable(permissionsStatus);
    if (direct.isNotEmpty) return direct;
    return _mapAt(const [
      ['permissions'],
      ['permission_status'],
      ['permissionStatus'],
    ], root: adminStatus);
  }

  Map<String, dynamic> get effectivePermissionsPolicy {
    final direct = _mapFromNullable(permissionsPolicy);
    if (direct.isNotEmpty) return direct;
    final fromStatus = _mapAt(const [
      ['policy'],
      ['permissions', 'policy'],
      ['permission_policy'],
      ['permissionPolicy'],
    ], root: permissionsStatus);
    if (fromStatus.isNotEmpty) return fromStatus;
    return _mapAt(const [
      ['permissions', 'policy'],
      ['permission_policy'],
      ['permissionPolicy'],
    ], root: adminStatus);
  }

  List<Map<String, dynamic>> get daemonSchedulerTasks {
    return _itemsFromResponse(daemonSchedulerTasksResponse, const [
      'tasks',
      'items',
      'rows',
      'records',
      'results',
    ]);
  }

  List<Map<String, dynamic>> get daemonQueueMessages {
    return _itemsFromResponse(daemonQueueMessagesResponse, const [
      'messages',
      'items',
      'rows',
      'records',
      'results',
    ]);
  }

  List<Map<String, dynamic>> get eventDeliveries {
    return _itemsFromResponse(eventDeliveriesResponse, const [
      'deliveries',
      'subscriptions',
      'items',
      'rows',
      'records',
      'results',
    ]);
  }

  List<Map<String, dynamic>> get adminChanges {
    return _itemsFromResponse(adminChangesResponse, const [
      'changes',
      'items',
      'events',
      'results',
      'records',
      'rows',
    ]);
  }

  int? get daemonSchedulerTaskCount {
    return _responseInt(daemonSchedulerTasksResponse, const [
      'total',
      'count',
      'task_count',
    ]);
  }

  int? get adminChangeCount {
    return _responseInt(adminChangesResponse, const [
      'total',
      'count',
      'change_count',
      'changes_count',
    ]);
  }

  int? get daemonQueueMessageCount {
    return _responseInt(daemonQueueMessagesResponse, const [
      'total',
      'count',
      'message_count',
    ]);
  }

  int? get eventDeliveryCount {
    return _responseInt(eventDeliveriesResponse, const [
      'total',
      'count',
      'delivery_count',
      'subscription_count',
    ]);
  }

  List<Map<String, dynamic>> get adminPackages {
    final raw = _valueAt(const [
      ['packages'],
      ['package_posture'],
      ['packagePosture'],
    ]);
    if (raw is List) {
      return raw.map(_mapFromDynamic).toList();
    }
    if (raw is Map) {
      final items = raw['items'] ?? raw['packages'];
      if (items is List) return items.map(_mapFromDynamic).toList();
      return raw.entries.map((entry) {
        final value = _mapFromDynamic(entry.value);
        return {'name': entry.key.toString(), ...value};
      }).toList();
    }
    return const [];
  }

  List<MapEntry<String, dynamic>> get inventoryEntries {
    final inventory = _inventoryMap();
    if (inventory.isEmpty) return const [];
    return inventory.entries
        .where((entry) => entry.value is num || entry.value is String)
        .toList();
  }

  List<MapEntry<String, dynamic>> get capabilityEntries {
    final raw = _valueAt(const [
      ['capabilities'],
      ['capability_flags'],
      ['flags'],
      ['config', 'flags'],
    ]);
    if (raw is Map) {
      return raw.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .toList();
    }
    return const [];
  }

  int? inventoryCount(String key) => _inventoryInt(key);

  Map<String, dynamic> _inventoryMap() {
    final raw = _valueAt(const [
      ['inventory'],
      ['inventory_counts'],
      ['counts'],
    ]);
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  Map<String, dynamic> _mapAt(
    List<List<String>> paths, {
    Map<String, dynamic>? root,
  }) {
    final value = _valueAt(paths, root: root);
    return _mapFromNullable(value);
  }

  Map<String, dynamic> _mapFromNullable(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  int? _inventoryInt(String key) {
    final value = _inventoryMap()[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  List<Map<String, dynamic>> _itemsFromResponse(
    Map<String, dynamic>? response,
    List<String> keys,
  ) {
    if (response == null) return const [];
    for (final key in keys) {
      final value = response[key];
      if (value is List) return value.map(_mapFromDynamic).toList();
    }
    final data = response['data'];
    if (data is List) return data.map(_mapFromDynamic).toList();
    if (data is Map) {
      for (final key in keys) {
        final value = data[key];
        if (value is List) return value.map(_mapFromDynamic).toList();
      }
    }
    return const [];
  }

  int? _responseInt(Map<String, dynamic>? response, List<String> keys) {
    if (response == null) return null;
    for (final key in keys) {
      final parsed = _intFromDynamic(response[key]);
      if (parsed != null) return parsed;
    }
    final data = response['data'];
    if (data is Map) {
      for (final key in keys) {
        final parsed = _intFromDynamic(data[key]);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  int? _intFromDynamic(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool? _boolFromDynamic(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase();
      if (normalized == 'true' ||
          normalized == 'yes' ||
          normalized == '1' ||
          normalized == 'enabled') {
        return true;
      }
      if (normalized == 'false' ||
          normalized == 'no' ||
          normalized == '0' ||
          normalized == 'disabled') {
        return false;
      }
    }
    return null;
  }

  String? _stringAt(List<List<String>> paths, {Map<String, dynamic>? root}) {
    for (final path in paths) {
      final value = _valueAt([path], root: root);
      if (value != null) return value.toString();
    }
    return null;
  }

  dynamic _valueAt(List<List<String>> paths, {Map<String, dynamic>? root}) {
    final resolvedRoot = root ?? adminStatus;
    if (resolvedRoot == null) return null;
    for (final path in paths) {
      dynamic current = resolvedRoot;
      for (final part in path) {
        if (current is Map) {
          current = current[part];
        } else {
          current = null;
          break;
        }
      }
      if (current != null) return current;
    }
    return null;
  }

  Map<String, dynamic> _mapFromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return {'value': value};
  }

  String _snakeCase(String value) {
    return value
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)}_${match.group(2)}',
        )
        .replaceAll('-', '_')
        .toLowerCase();
  }
}
