import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/message.dart';

/// Client-side SQLite storage for chat history persistence.
/// Uses a separate database file per user so sessions don't mix.
class LocalStorage {
  static Database? _db;
  static String? _currentUser;

  /// Open (or create) the database for a specific user.
  /// Must be called after login, before any read/write operations.
  static Future<void> init(String username) async {
    // If switching users, close the old DB first
    if (_db != null && _currentUser != username) {
      await _db!.close();
      _db = null;
    }
    _currentUser = username;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'im_app_$username.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            msg_id TEXT,
            conversation_id TEXT NOT NULL,
            sender TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            is_mine INTEGER NOT NULL DEFAULT 0,
            is_sync INTEGER NOT NULL DEFAULT 0,
            status INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_msg_conv ON messages(conversation_id, timestamp)',
        );

        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            name TEXT NOT NULL,
            last_message TEXT,
            last_timestamp TEXT
          )
        ''');
      },
    );
  }

  static Future<Database> get database async {
    if (_db == null) {
      throw StateError('LocalStorage.init(username) must be called before use');
    }
    return _db!;
  }

  /// Close the database (call on logout).
  static Future<void> close() async {
    await _db?.close();
    _db = null;
    _currentUser = null;
  }

  // ---- Messages ----

  static Future<void> saveMessage(Message msg, String conversationId) async {
    final db = await database;
    await db.insert(
      'messages',
      msg.toMap(conversationId),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateMessageStatus(String id, MessageStatus status) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status.index},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<Message>> getMessages(String conversationId) async {
    final db = await database;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(Message.fromMap).toList();
  }

  // ---- Conversations ----

  static Future<void> saveConversation({
    required String id,
    required String type,
    required String name,
    String? lastMessage,
    DateTime? lastTimestamp,
  }) async {
    final db = await database;
    await db.insert(
      'conversations',
      {
        'id': id,
        'type': type,
        'name': name,
        'last_message': lastMessage,
        'last_timestamp': lastTimestamp?.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getConversations() async {
    final db = await database;
    return db.query('conversations', orderBy: 'last_timestamp DESC');
  }

  static Future<void> updateConversationLastMessage(
    String id,
    String message,
    DateTime timestamp,
  ) async {
    final db = await database;
    await db.update(
      'conversations',
      {
        'last_message': message,
        'last_timestamp': timestamp.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Clear all local data (used on logout).
  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('conversations');
  }
}
