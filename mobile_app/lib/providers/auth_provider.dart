import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/connection_service.dart';
import '../services/local_storage.dart';

enum AuthState { unauthenticated, connecting, authenticating, authenticated, error }

/// Manages authentication state and communicates with [ConnectionService].
class AuthProvider extends ChangeNotifier {
  final ConnectionService _conn;
  StreamSubscription? _sub;

  AuthState _state = AuthState.unauthenticated;
  String _error = '';
  String _username = '';
  String _pendingAction = ''; // 'login' or 'register'
  String _pendingUsername = '';
  String _pendingPassword = '';

  AuthProvider(this._conn);

  AuthState get state => _state;
  String get error => _error;
  String get username => _username;

  /// Start listening for auth responses from the server.
  void listenToServer() {
    // This is called once from main to wire up the connection callback.
    // We store a reference so the provider can handle auth_res messages.
  }

  /// Handle an incoming message (called by the connection's onMessage).
  void handleMessage(Map<String, dynamic> msg) {
    if (msg['type'] != 'auth_res') return;

    if (msg['success'] == true) {
      if (_pendingAction == 'register') {
        // Registration succeeded, now auto-login
        _state = AuthState.authenticating;
        notifyListeners();
        _conn.login(_pendingUsername, _pendingPassword);
        _pendingAction = 'login';
        return;
      }
      // Login succeeded
      _username = _pendingUsername;
      _conn.onAuthSuccess(_username);
      _state = AuthState.authenticated;
      _error = '';
    } else {
      _state = AuthState.error;
      _error = msg['message'] ?? 'Authentication failed';
    }
    notifyListeners();
  }

  /// Attempt to login. First connects to server, then sends login request.
  Future<void> login(String username, String password) async {
    _pendingAction = 'login';
    _pendingUsername = username;
    _pendingPassword = password;
    _state = AuthState.connecting;
    _error = '';
    notifyListeners();

    // Pre-init user's local DB BEFORE connecting, so it's ready
    // when the server pushes offline messages right after auth_res
    await LocalStorage.init(username);

    final connected = await _conn.connect();
    if (!connected) {
      _state = AuthState.error;
      _error = 'Cannot reach server at ${_conn.host}:${_conn.port}';
      notifyListeners();
      return;
    }

    _state = AuthState.authenticating;
    notifyListeners();
    await _conn.login(username, password);
  }

  /// Register a new account, then auto-login on success.
  Future<void> register(String username, String password) async {
    _pendingAction = 'register';
    _pendingUsername = username;
    _pendingPassword = password;
    _state = AuthState.connecting;
    _error = '';
    notifyListeners();

    await LocalStorage.init(username);

    final connected = await _conn.connect();
    if (!connected) {
      _state = AuthState.error;
      _error = 'Cannot reach server at ${_conn.host}:${_conn.port}';
      notifyListeners();
      return;
    }

    _state = AuthState.authenticating;
    notifyListeners();
    await _conn.register(username, password);
  }

  Future<void> logout() async {
    await _conn.disconnect();
    _state = AuthState.unauthenticated;
    _username = '';
    _error = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
