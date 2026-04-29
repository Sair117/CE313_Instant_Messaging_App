import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../services/connection_service.dart';
import '../services/local_storage.dart';

const _uuid = Uuid();

/// Manages all chat state: conversations, messages, receipts, and ACKs.
class ChatProvider extends ChangeNotifier {
  final ConnectionService _conn;

  // conversationId → list of messages
  final Map<String, List<Message>> _messages = {};
  // localMessageId → conversationId (for receipt tracking)
  final Map<String, String> _pendingReceipts = {};
  // conversationId → metadata
  final Map<String, Map<String, String>> _conversations = {};
  // conversationId → unread message count
  final Map<String, int> _unreadCounts = {};
  // Currently open conversation (null if on home screen)
  String? _activeConversationId;

  ChatProvider(this._conn);

  Map<String, Map<String, String>> get conversations => _conversations;
  Map<String, int> get unreadCounts => _unreadCounts;
  int unreadCount(String convId) => _unreadCounts[convId] ?? 0;

  List<Message> getMessages(String conversationId) =>
      _messages[conversationId] ?? [];

  /// Load persisted conversations and messages from local DB.
  /// Merges with any live messages already in memory (e.g., offline messages
  /// pushed by server before this method runs) using ID deduplication.
  Future<void> loadFromStorage() async {
    try {
      // 1. Snapshot any live messages that arrived before this method runs
      final liveConversations = Map<String, Map<String, String>>.from(_conversations);
      final liveMessages = <String, List<Message>>{};
      for (final entry in _messages.entries) {
        liveMessages[entry.key] = List<Message>.from(entry.value);
      }

      // 2. Load ALL historical data from DB
      final convRows = await LocalStorage.getConversations();
      for (final row in convRows) {
        final convId = row['id'] as String;
        _conversations[convId] = {
          'type': row['type'] as String,
          'name': row['name'] as String,
          'last_message': (row['last_message'] ?? '') as String,
          'last_timestamp': (row['last_timestamp'] ?? '') as String,
        };
        _messages[convId] = await LocalStorage.getMessages(convId);
      }

      // 3. Merge back live messages that aren't already loaded from DB
      for (final entry in liveMessages.entries) {
        final convId = entry.key;

        // Ensure the conversation exists
        if (!_conversations.containsKey(convId) && liveConversations.containsKey(convId)) {
          _conversations[convId] = liveConversations[convId]!;
        }

        // Merge messages by ID deduplication
        _messages.putIfAbsent(convId, () => []);
        final existingIds = _messages[convId]!.map((m) => m.id).toSet();
        for (final msg in entry.value) {
          if (!existingIds.contains(msg.id)) {
            _messages[convId]!.add(msg);
          }
        }
      }

      // Sort all conversations' messages by timestamp
      for (final msgs in _messages.values) {
        msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[loadFromStorage] $e');
    }
  }

  /// Handle an incoming message from the server.
  void handleMessage(Map<String, dynamic> msg, String myUsername) {
    switch (msg['type']) {
      case 'direct_msg':
        _handleDirectMessage(msg, myUsername);
        break;
      case 'group_msg':
        _handleGroupMessage(msg, myUsername);
        break;
      case 'receipt':
        _handleReceipt(msg);
        break;
    }
  }

  void _handleDirectMessage(Map<String, dynamic> data, String myUsername) {
    final sender = data['sender'] as String;
    final convId = sender; // For DMs, conversation ID = the other user's name
    final message = Message.fromServer(data, myUsername);

    _ensureConversation(convId, 'direct', sender);
    _messages.putIfAbsent(convId, () => []);
    _messages[convId]!.add(message);

    // Update conversation last message
    _conversations[convId]!['last_message'] = message.content;
    _conversations[convId]!['last_timestamp'] = message.timestamp.toIso8601String();

    // Persist
    _safeDb(() => LocalStorage.saveMessage(message, convId));
    _safeDb(() => LocalStorage.updateConversationLastMessage(convId, message.content, message.timestamp));

    // Send ACK to server
    if (data['msg_id'] != null) {
      _conn.send({'type': 'ack', 'msg_id': data['msg_id']});
    }

    // Track unread if this conversation is not currently open
    if (_activeConversationId != convId) {
      _unreadCounts[convId] = (_unreadCounts[convId] ?? 0) + 1;
    }

    notifyListeners();
  }

  void _handleGroupMessage(Map<String, dynamic> data, String myUsername) {
    final groupId = data['group_id'] as String;
    final message = Message.fromServer(data, myUsername);

    _ensureConversation(groupId, 'group', groupId);
    _messages.putIfAbsent(groupId, () => []);
    _messages[groupId]!.add(message);

    _conversations[groupId]!['last_message'] = '${message.sender}: ${message.content}';
    _conversations[groupId]!['last_timestamp'] = message.timestamp.toIso8601String();

    _safeDb(() => LocalStorage.saveMessage(message, groupId));
    _safeDb(() => LocalStorage.updateConversationLastMessage(
        groupId, '${message.sender}: ${message.content}', message.timestamp));

    if (data['msg_id'] != null) {
      _conn.send({'type': 'ack', 'msg_id': data['msg_id']});
    }

    // Track unread if this conversation is not currently open
    if (_activeConversationId != groupId) {
      _unreadCounts[groupId] = (_unreadCounts[groupId] ?? 0) + 1;
    }

    notifyListeners();
  }

  void _handleReceipt(Map<String, dynamic> data) {
    final target = data['target'] as String? ?? '';
    final status = data['status'] as String? ?? '';

    // Find the oldest pending message to this target
    final msgs = _messages[target];
    if (msgs == null) return;

    for (int i = 0; i < msgs.length; i++) {
      if (msgs[i].isMine && 
          (msgs[i].status == MessageStatus.sending || msgs[i].status == MessageStatus.queued)) {
        msgs[i].status = status == 'delivered'
            ? MessageStatus.delivered
            : MessageStatus.queued;
        _safeDb(() => LocalStorage.updateMessageStatus(msgs[i].id, msgs[i].status));
        break;
      }
    }
    notifyListeners();
  }

  /// Send a direct message to a user.
  void sendDirectMessage(String target, String content) {
    final localId = _uuid.v4();
    final message = Message(
      id: localId,
      sender: _conn.username ?? '',
      content: content,
      timestamp: DateTime.now().toUtc(),
      isMine: true,
      status: MessageStatus.sending,
    );

    _ensureConversation(target, 'direct', target);
    _messages.putIfAbsent(target, () => []);
    _messages[target]!.add(message);

    _conversations[target]!['last_message'] = content;
    _conversations[target]!['last_timestamp'] = message.timestamp.toIso8601String();

    _safeDb(() => LocalStorage.saveMessage(message, target));
    _safeDb(() => LocalStorage.updateConversationLastMessage(target, content, message.timestamp));

    final sent = _conn.send({
      'type': 'direct_msg',
      'target': target,
      'content': content,
    });

    if (!sent) {
      message.status = MessageStatus.failed;
      _safeDb(() => LocalStorage.updateMessageStatus(localId, MessageStatus.failed));
    }

    notifyListeners();
  }

  /// Send a group message.
  void sendGroupMessage(String groupId, String content) {
    final localId = _uuid.v4();
    final message = Message(
      id: localId,
      sender: _conn.username ?? '',
      content: content,
      timestamp: DateTime.now().toUtc(),
      isMine: true,
      status: MessageStatus.delivered, // Group msgs don't get receipts back
    );

    _ensureConversation(groupId, 'group', groupId);
    _messages.putIfAbsent(groupId, () => []);
    _messages[groupId]!.add(message);

    _conversations[groupId]!['last_message'] = content;
    _conversations[groupId]!['last_timestamp'] = message.timestamp.toIso8601String();

    _safeDb(() => LocalStorage.saveMessage(message, groupId));
    _safeDb(() => LocalStorage.updateConversationLastMessage(groupId, content, message.timestamp));

    _conn.send({
      'type': 'group_msg',
      'group_id': groupId,
      'content': content,
    });

    notifyListeners();
  }

  void _ensureConversation(String id, String type, String name) {
    if (!_conversations.containsKey(id)) {
      _conversations[id] = {
        'type': type,
        'name': name,
        'last_message': '',
        'last_timestamp': '',
      };
      _safeDb(() => LocalStorage.saveConversation(id: id, type: type, name: name));
    }
  }

  /// Start a new conversation (e.g., when tapping a friend).
  void openConversation(String id, String type, String name) {
    _ensureConversation(id, type, name);
    _messages.putIfAbsent(id, () => []);
    markRead(id);
    notifyListeners();
  }

  /// Mark a conversation as active and reset its unread count.
  void markRead(String convId) {
    bool changed = false;
    if (_activeConversationId != convId) {
      _activeConversationId = convId;
      changed = true;
    }
    if (_unreadCounts.containsKey(convId)) {
      _unreadCounts.remove(convId);
      changed = true;
    }
    
    if (changed) {
      notifyListeners();
    }
  }

  /// Clear the active conversation (e.g., when navigating back to home).
  void clearActiveConversation() {
    if (_activeConversationId != null) {
      _activeConversationId = null;
      notifyListeners();
    }
  }

  /// Delete a conversation and its messages from memory and DB.
  void deleteConversation(String convId) {
    _conversations.remove(convId);
    _messages.remove(convId);
    _unreadCounts.remove(convId);
    _safeDb(() async {
      final db = await LocalStorage.database;
      await db.delete('messages', where: 'conversation_id = ?', whereArgs: [convId]);
      await db.delete('conversations', where: 'id = ?', whereArgs: [convId]);
    });
    notifyListeners();
  }

  /// Wraps fire-and-forget DB calls so errors are logged instead of silently lost.
  void _safeDb(Future<void> Function() fn) {
    fn().catchError((e) => debugPrint('[DB WRITE] $e'));
  }

  void clear() {
    _messages.clear();
    _conversations.clear();
    _pendingReceipts.clear();
    _unreadCounts.clear();
    _activeConversationId = null;
    notifyListeners();
  }
}
