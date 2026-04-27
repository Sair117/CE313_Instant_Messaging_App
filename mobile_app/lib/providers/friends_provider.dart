import 'package:flutter/foundation.dart';
import '../services/connection_service.dart';

/// Manages friends list, pending requests, and friend actions.
class FriendsProvider extends ChangeNotifier {
  final ConnectionService _conn;

  List<String> _friends = [];
  List<String> _pendingRequests = [];
  String _lastError = '';
  String _lastSuccess = '';

  FriendsProvider(this._conn);

  List<String> get friends => _friends;
  List<String> get pendingRequests => _pendingRequests;
  String get lastError => _lastError;
  String get lastSuccess => _lastSuccess;
  int get pendingCount => _pendingRequests.length;

  /// Handle incoming messages related to friends.
  void handleMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'friends_list':
        _friends = List<String>.from(msg['friends'] ?? []);
        _pendingRequests = List<String>.from(msg['pending_requests'] ?? []);
        _lastError = '';
        break;
      case 'friend_notif':
        final from = msg['from'] as String;
        if (!_pendingRequests.contains(from)) {
          _pendingRequests.add(from);
        }
        break;
      case 'friend_res':
        if (msg['success'] == true) {
          _lastSuccess = msg['message'] ?? 'Success';
          _lastError = '';
          // Refresh the friends list
          fetchFriends();
        } else {
          _lastError = msg['message'] ?? 'Failed';
          _lastSuccess = '';
        }
        break;
      case 'error':
        // Server errors in response to friend actions
        _lastError = msg['message'] ?? 'Error';
        _lastSuccess = '';
        break;
    }
    notifyListeners();
  }

  /// Fetch the full friends list from the server.
  void fetchFriends() {
    _conn.send({'type': 'get_friends'});
  }

  /// Send a friend request.
  void sendFriendRequest(String target) {
    _lastError = '';
    _lastSuccess = '';
    _conn.send({'type': 'friend_request', 'target': target, 'action': 'send'});
  }

  /// Accept a pending friend request.
  void acceptFriendRequest(String from) {
    _conn.send({'type': 'friend_request', 'target': from, 'action': 'accept'});
    _pendingRequests.remove(from);
    notifyListeners();
  }

  /// Block a user.
  void blockUser(String target) {
    _conn.send({'type': 'friend_request', 'target': target, 'action': 'block'});
    _friends.remove(target);
    _pendingRequests.remove(target);
    notifyListeners();
  }

  void clearMessages() {
    _lastError = '';
    _lastSuccess = '';
  }

  void clear() {
    _friends.clear();
    _pendingRequests.clear();
    _lastError = '';
    _lastSuccess = '';
    notifyListeners();
  }
}
