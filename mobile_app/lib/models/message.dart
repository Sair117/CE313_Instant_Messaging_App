/// Represents the delivery status of a sent message.
enum MessageStatus {
  sending,   // Socket send in progress
  queued,    // Server replied: target was offline, message stored
  delivered, // Server replied: target received it
  failed,    // Socket error during send
}

/// A single chat message.
class Message {
  final String id;           // Local UUID for tracking
  final String? msgId;       // Server-assigned msg_id (for ACKs)
  final String sender;
  final String content;
  final DateTime timestamp;
  final bool isMine;
  final bool isSync;         // Was this synced from offline queue?
  MessageStatus status;

  Message({
    required this.id,
    this.msgId,
    required this.sender,
    required this.content,
    required this.timestamp,
    required this.isMine,
    this.isSync = false,
    this.status = MessageStatus.sending,
  });

  /// Create from a server-received packet.
  factory Message.fromServer(Map<String, dynamic> data, String myUsername) {
    return Message(
      id: data['msg_id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
      msgId: data['msg_id'],
      sender: data['sender'] ?? '',
      content: data['content'] ?? '',
      timestamp: _parseUtcTimestamp(data['timestamp']),
      isMine: data['sender'] == myUsername,
      isSync: data['is_sync'] == true,
      status: MessageStatus.delivered,
    );
  }

  /// Parses a timestamp string from the server, treating it as UTC.
  /// Handles ISO-8601 with 'Z' suffix, '+00:00', or bare timestamps.
  static DateTime _parseUtcTimestamp(dynamic raw) {
    if (raw == null) return DateTime.now().toUtc();
    final str = raw.toString().trim();
    // Try parsing as-is (handles Z suffix and +offset)
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return parsed.isUtc ? parsed : DateTime.parse('${str}Z');
    }
    // If parsing fails, replace space with T and add Z for SQLite format
    final fixed = str.contains('T') ? '${str}Z' : '${str.replaceFirst(' ', 'T')}Z';
    return DateTime.tryParse(fixed) ?? DateTime.now().toUtc();
  }

  /// Convert to a map for local SQLite storage.
  Map<String, dynamic> toMap(String conversationId) => {
        'id': id,
        'msg_id': msgId,
        'conversation_id': conversationId,
        'sender': sender,
        'content': content,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'is_mine': isMine ? 1 : 0,
        'is_sync': isSync ? 1 : 0,
        'status': status.index,
      };

  /// Create from a local SQLite row.
  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      msgId: map['msg_id'],
      sender: map['sender'],
      content: map['content'],
      timestamp: DateTime.parse(map['timestamp']).toUtc(),
      isMine: map['is_mine'] == 1,
      isSync: map['is_sync'] == 1,
      status: MessageStatus.values[map['status'] ?? 0],
    );
  }
}
