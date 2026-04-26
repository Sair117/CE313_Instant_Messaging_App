import 'package:flutter/foundation.dart';
import '../services/connection_service.dart';
import '../providers/chat_provider.dart';

/// Manages group list, creation, membership, and real-time notifications.
class GroupsProvider extends ChangeNotifier {
  final ConnectionService _conn;

  // group_id → {created_by, members (if loaded)}
  final Map<String, Map<String, dynamic>> _groups = {};
  String _lastError = '';
  String _lastSuccess = '';

  GroupsProvider(this._conn);

  Map<String, Map<String, dynamic>> get groups => _groups;
  List<String> get groupIds => _groups.keys.toList();
  String get lastError => _lastError;
  String get lastSuccess => _lastSuccess;

  /// Handle incoming messages related to groups.
  void handleMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'groups_list':
        _groups.clear();
        for (final g in (msg['groups'] as List)) {
          _groups[g['group_id']] = {'created_by': g['created_by']};
        }
        break;
      case 'group_res':
        if (msg['success'] == true) {
          _lastSuccess = msg['message'] ?? 'Success';
          _lastError = '';
          fetchGroups(); // Refresh
        } else {
          _lastError = msg['message'] ?? 'Failed';
          _lastSuccess = '';
        }
        break;
      case 'group_notif':
        // You were added to a group
        final groupId = msg['group_id'] as String;
        _groups[groupId] = {'created_by': ''};
        _lastSuccess = msg['message'] ?? 'Added to group';
        fetchGroups();
        break;
    }
    notifyListeners();
  }

  /// Fetch all groups the user belongs to.
  void fetchGroups() {
    _conn.send({'type': 'get_groups'});
  }

  /// Create a new group.
  void createGroup(String groupId) {
    _lastError = '';
    _lastSuccess = '';
    _conn.send({'type': 'create_group', 'group_id': groupId});
  }

  /// Add a member to a group (creator only).
  void addMember(String groupId, String username) {
    _lastError = '';
    _conn.send({
      'type': 'group_manage',
      'group_id': groupId,
      'target': username,
      'action': 'add',
    });
  }

  /// Remove a member from a group (creator only).
  void removeMember(String groupId, String username) {
    _lastError = '';
    _conn.send({
      'type': 'group_manage',
      'group_id': groupId,
      'target': username,
      'action': 'remove',
    });
  }

  /// Leave a group and remove its conversation.
  void leaveGroup(String groupId, {ChatProvider? chatProvider}) {
    _conn.send({'type': 'leave_group', 'group_id': groupId});
    _groups.remove(groupId);
    // Also remove the group conversation from chat history
    chatProvider?.deleteConversation(groupId);
    notifyListeners();
  }

  bool isCreator(String groupId, String username) {
    return _groups[groupId]?['created_by'] == username;
  }

  void clear() {
    _groups.clear();
    _lastError = '';
    _lastSuccess = '';
    notifyListeners();
  }
}
