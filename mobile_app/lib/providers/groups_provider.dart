import 'package:flutter/foundation.dart';
import '../services/connection_service.dart';
import '../providers/chat_provider.dart';

/// Manages group list, creation, membership, and real-time notifications.
class GroupsProvider extends ChangeNotifier {
  final ConnectionService _conn;

  // group_id → {created_by, members: List<String>?}
  final Map<String, Map<String, dynamic>> _groups = {};
  String _lastError = '';
  String _lastSuccess = '';

  GroupsProvider(this._conn);

  Map<String, Map<String, dynamic>> get groups => _groups;
  List<String> get groupIds => _groups.keys.toList();
  String get lastError => _lastError;
  String get lastSuccess => _lastSuccess;

  /// Returns the cached member list for a group, or empty if not yet loaded.
  List<String> getGroupMembers(String groupId) {
    final members = _groups[groupId]?['members'];
    if (members == null) return [];
    return List<String>.from(members as List);
  }

  void handleMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'groups_list':
        // Preserve any already-loaded member lists across a refresh.
        final prev = Map<String, Map<String, dynamic>>.from(_groups);
        _groups.clear();
        for (final g in (msg['groups'] as List)) {
          final gid = g['group_id'] as String;
          _groups[gid] = {
            'created_by': g['created_by'],
            'members': prev[gid]?['members'], // keep loaded members
          };
        }
        break;

      case 'group_members':
        final groupId = msg['group_id'] as String;
        final members = List<String>.from(msg['members'] as List);
        if (_groups.containsKey(groupId)) {
          _groups[groupId]!['members'] = members;
        }
        break;

      case 'group_res':
        if (msg['success'] == true) {
          _lastSuccess = msg['message'] ?? 'Success';
          _lastError = '';
          fetchGroups();
          // If the server tells us which group was affected, refresh its members.
          final groupId = msg['group_id'] as String?;
          if (groupId != null) fetchGroupMembers(groupId);
        } else {
          _lastError = msg['message'] ?? 'Failed';
          _lastSuccess = '';
        }
        break;

      case 'group_notif':
        // Added to a group by someone else.
        final groupId = msg['group_id'] as String;
        _groups[groupId] = {'created_by': '', 'members': null};
        _lastSuccess = msg['message'] ?? 'Added to group';
        fetchGroups();
        break;
    }
    notifyListeners();
  }

  void fetchGroups() {
    _conn.send({'type': 'get_groups'});
  }

  void fetchGroupMembers(String groupId) {
    _conn.send({'type': 'get_group_members', 'group_id': groupId});
  }

  void createGroup(String groupId) {
    _lastError = '';
    _lastSuccess = '';
    _conn.send({'type': 'create_group', 'group_id': groupId});
  }

  void addMember(String groupId, String username) {
    _lastError = '';
    _lastSuccess = '';
    _conn.send({
      'type': 'group_manage',
      'group_id': groupId,
      'target': username,
      'action': 'add',
    });
  }

  void removeMember(String groupId, String username) {
    _lastError = '';
    _lastSuccess = '';
    _conn.send({
      'type': 'group_manage',
      'group_id': groupId,
      'target': username,
      'action': 'remove',
    });
  }

  void leaveGroup(String groupId, {ChatProvider? chatProvider}) {
    _conn.send({'type': 'leave_group', 'group_id': groupId});
    _groups.remove(groupId);
    chatProvider?.deleteConversation(groupId);
    notifyListeners();
  }

  bool isCreator(String groupId, String username) {
    return _groups[groupId]?['created_by'] == username;
  }

  void clearMessages() {
    if (_lastError.isEmpty && _lastSuccess.isEmpty) return;
    _lastError = '';
    _lastSuccess = '';
    notifyListeners();
  }

  void clear() {
    _groups.clear();
    _lastError = '';
    _lastSuccess = '';
    notifyListeners();
  }
}
