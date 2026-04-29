import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tcp_client.dart';

/// High-level connection manager on top of [TcpClient].
/// Handles: heartbeat pings, message dispatching, auto-reconnect, and server config.
class ConnectionService extends ChangeNotifier {
  final TcpClient _tcp = TcpClient();
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  StreamSubscription? _msgSub;
  StreamSubscription? _disconnectSub;

  String _host = '10.0.2.2'; // Android emulator → host machine
  int _port = 5000;
  bool _authenticated = false;
  String? _username;

  // Connection states
  bool get isConnected => _tcp.isConnected;
  bool get isAuthenticated => _authenticated;
  String? get username => _username;
  String get host => _host;
  int get port => _port;

  // Callbacks set by providers to handle incoming messages
  void Function(Map<String, dynamic>)? onMessage;

  /// Load server address from shared preferences.
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString('server_host') ?? '10.0.2.2';
    _port = prefs.getInt('server_port') ?? 5000;
  }

  /// Save server address to shared preferences.
  Future<void> saveSettings(String host, int port) async {
    _host = host;
    _port = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_host', host);
    await prefs.setInt('server_port', port);
    notifyListeners();
  }

  /// Connect to the server.
  Future<bool> connect() async {
    try {
      await _tcp.connect(_host, _port);

      // Listen for incoming messages
      _msgSub?.cancel();
      _msgSub = _tcp.messages.listen((msg) {
        if (msg['type'] == 'pong') return; // Swallow pong responses
        // Forward via event loop to avoid build-phase clashes if UI is currently building
        Future.delayed(Duration.zero, () {
          onMessage?.call(msg);
        });
      });

      // Listen for disconnections
      _disconnectSub?.cancel();
      _disconnectSub = _tcp.onDisconnect.listen((_) {
        _onDisconnected();
      });

      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Send a login request.
  Future<void> login(String username, String password) async {
    _tcp.send({'type': 'login', 'username': username, 'password': password});
  }

  /// Send a register request.
  Future<void> register(String username, String password) async {
    _tcp.send({'type': 'register', 'username': username, 'password': password});
  }

  /// Mark as authenticated and start heartbeat.
  void onAuthSuccess(String username) {
    _authenticated = true;
    _username = username;
    _startHeartbeat();
    notifyListeners();
  }

  /// Send a generic message to the server.
  bool send(Map<String, dynamic> msg) => _tcp.send(msg);

  /// Start periodic ping to keep connection alive.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 55),
      (_) {
        if (_tcp.isConnected) {
          _tcp.send({'type': 'ping'});
        }
      },
    );
  }

  void _onDisconnected() {
    _heartbeatTimer?.cancel();
    _authenticated = false;
    notifyListeners();
  }

  /// Disconnect and clean up.
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _msgSub?.cancel();
    _disconnectSub?.cancel();
    _authenticated = false;
    _username = null;
    await _tcp.disconnect();
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _msgSub?.cancel();
    _disconnectSub?.cancel();
    _tcp.dispose();
    super.dispose();
  }
}
