import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'api.dart';

/// Live record-change signals over the object server's `/ws` websocket.
///
/// Signal-not-data: each event carries only {collection, record_id, action}
/// — never the record body — and delivery is permission-filtered server-side
/// (you only receive events for records your row filters would show).
/// Listeners refetch through the normal enforced API when notified.
///
/// One shared connection for the whole app. Screens register interest in a
/// collection via [bind]; the manager ref-counts subscriptions, sends
/// subscribe frames, and reconnects with backoff. Over-subscription is
/// harmless (signals are tiny and permission-gated), so removal keeps the
/// server-side subscription — only local listeners are dropped.
class ScrollRealtime {
  static final ScrollRealtime _instance = ScrollRealtime._();
  factory ScrollRealtime() => _instance;
  ScrollRealtime._();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  final Set<String> _subscriptions = {};
  final Map<String, int> _refCounts = {};
  final Map<String, ValueNotifier<int>> _tickers = {};

  bool _connecting = false;
  bool _wantConnected = false;
  int _backoffMs = 1000;
  Timer? _reconnectTimer;

  /// True while the websocket is open — drives a "live" indicator.
  final ValueNotifier<bool> connected = ValueNotifier(false);

  /// Per-collection counter bumped on each record event, so a widget can
  /// listen cheaply without threading callbacks.
  ValueListenable<int> ticker(String collection) =>
      _tickers.putIfAbsent(collection, () => ValueNotifier(0));

  /// Subscribe [collection] and invoke [onEvent] whenever one of its
  /// records changes. Returns a disposer to call in State.dispose().
  VoidCallback bind(String collection, VoidCallback onEvent) {
    _addSubscription(collection);
    final tick = _tickers.putIfAbsent(collection, () => ValueNotifier(0));
    tick.addListener(onEvent);
    return () {
      tick.removeListener(onEvent);
      _removeSubscription(collection);
    };
  }

  void _addSubscription(String collection) {
    final isNew = !_subscriptions.contains(collection);
    _refCounts[collection] = (_refCounts[collection] ?? 0) + 1;
    _subscriptions.add(collection);
    _ensureConnected();
    if (isNew && connected.value) {
      _sendSubscribe([collection]);
    }
  }

  void _removeSubscription(String collection) {
    final remaining = (_refCounts[collection] ?? 1) - 1;
    if (remaining <= 0) {
      _refCounts.remove(collection);
      // Keep the server subscription (signal-only, permission-filtered);
      // with no local listeners its ticks are simply ignored.
    } else {
      _refCounts[collection] = remaining;
    }
  }

  void _ensureConnected() {
    _wantConnected = true;
    if (_socket == null && !_connecting) _connect();
  }

  Future<void> _connect() async {
    if (_connecting || !_wantConnected) return;
    final url = ScrollAPI().realtimeUrl;
    if (url == null) return;
    _connecting = true;
    try {
      final socket = await WebSocket.connect(
        url,
        headers: ScrollAPI().realtimeHeaders,
      );
      _socket = socket;
      _connecting = false;
      _backoffMs = 1000;
      connected.value = true;
      if (_subscriptions.isNotEmpty) {
        _sendSubscribe(_subscriptions.toList());
      }
      _sub = socket.listen(
        _onMessage,
        onDone: _onDisconnect,
        onError: (_) => _onDisconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _connecting = false;
      connected.value = false;
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    dynamic message;
    try {
      message = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (message is! Map) return;
    if (message['type'] == 'record') {
      final collection = message['collection']?.toString();
      if (collection != null) {
        _tickers[collection]?.value++;
      }
    }
    // {welcome} and any other frames are informational — ignored.
  }

  void _onDisconnect() {
    _sub?.cancel();
    _sub = null;
    _socket = null;
    connected.value = false;
    if (_wantConnected) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _backoffMs), _connect);
    _backoffMs = (_backoffMs * 2).clamp(1000, 30000);
  }

  void _sendSubscribe(List<String> collections) {
    if (collections.isEmpty) return;
    _socket?.add(
      jsonEncode({'action': 'subscribe', 'collections': collections}),
    );
  }

  /// Tear down on disconnect / sign-out. Subscriptions are cleared; a
  /// later bind() reconnects fresh with the new session.
  void shutdown() {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    _subscriptions.clear();
    _refCounts.clear();
    connected.value = false;
  }
}
