import sqlite3
import bcrypt
import os
import logging
from contextlib import contextmanager

# 1. Robust Path Resolution [Suggestion 2]
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, '..', 'data', 'im_system.db')

# 2. Logging Setup [Suggestion 8]
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# 3. Timing-Safe Setup [Suggestion 1]
_DUMMY_HASH = bcrypt.hashpw(b"dummy_password", bcrypt.gensalt()).decode('utf-8')

@contextmanager
def get_connection():
    """Context manager for safe DB operations and auto-commit/rollback [Suggestion 5]."""
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    except Exception as e:
        conn.rollback()
        logger.error(f"Database error: {e}")
        raise
    finally:
        conn.close()

def init_db():
    """Initializes the schema with strict constraints and indexes [Suggestions 3, 4, 6, 7]."""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    
    with get_connection() as conn:
        # Users Table
        conn.execute('''
            CREATE TABLE IF NOT EXISTS users (
                username      TEXT PRIMARY KEY,
                password_hash TEXT NOT NULL
            )
        ''')
        
        # Friendships with Status Enforcements [Suggestion 4]
        conn.execute('''
            CREATE TABLE IF NOT EXISTS friendships (
                requester TEXT NOT NULL REFERENCES users(username),
                receiver  TEXT NOT NULL REFERENCES users(username),
                status    TEXT NOT NULL DEFAULT 'pending' 
                          CHECK (status IN ('pending', 'accepted', 'blocked')),
                PRIMARY KEY (requester, receiver)
            )
        ''')
        conn.execute("CREATE INDEX IF NOT EXISTS idx_friendships_receiver ON friendships(receiver)")

        # Group Architecture
        conn.execute('''
            CREATE TABLE IF NOT EXISTS groups (
                group_id   TEXT PRIMARY KEY,
                created_by TEXT NOT NULL REFERENCES users(username)
            )
        ''')

        conn.execute('''
            CREATE TABLE IF NOT EXISTS group_members (
                group_id TEXT NOT NULL REFERENCES groups(group_id),
                username TEXT NOT NULL REFERENCES users(username),
                PRIMARY KEY (group_id, username)
            )
        ''')

        # Robust Message Queue with Cascading Deletes [Suggestion 3]
        conn.execute('''
            CREATE TABLE IF NOT EXISTS offline_messages (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                sender      TEXT NOT NULL REFERENCES users(username) ON DELETE CASCADE,
                target      TEXT NOT NULL,
                target_type TEXT NOT NULL CHECK (target_type IN ('user', 'group')),
                content     TEXT NOT NULL,
                group_id    TEXT,
                timestamp   DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        conn.execute("CREATE INDEX IF NOT EXISTS idx_msg_target ON offline_messages(target, target_type)")
        
    logger.info("Complete schema initialized with strict constraints.")

def _hash_password(password: str) -> str:
    """Internal helper for password hashing [Suggestion 9]."""
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

def register_user(username: str, password: str) -> bool:
    try:
        with get_connection() as conn:
            conn.execute(
                "INSERT INTO users (username, password_hash) VALUES (?, ?)",
                (username, _hash_password(password))
            )
        logger.info(f"User '{username}' registered.")
        return True
    except sqlite3.IntegrityError:
        return False

def login_user(username: str, password: str) -> bool:
    """Timing-safe login to prevent user enumeration [Suggestion 1]."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT password_hash FROM users WHERE username = ?", (username,))
        result = cursor.fetchone()
        
        # Always run checkpw, even if user doesn't exist
        stored_hash = result[0] if result else _DUMMY_HASH
        is_valid = bcrypt.checkpw(password.encode('utf-8'), stored_hash.encode('utf-8'))
        
        if result and is_valid:
            logger.info(f"Login successful: {username}")
            return True
        return False

def is_friend(user_a: str, user_b: str) -> bool:
    """Task 3: Verifies if two users have an 'accepted' friendship status."""
    with get_connection() as conn:
        cursor = conn.cursor()
        # Check both directions as the requester/receiver roles are arbitrary
        cursor.execute('''
            SELECT 1 FROM friendships 
            WHERE status = 'accepted' AND (
                (requester = ? AND receiver = ?) OR 
                (requester = ? AND receiver = ?)
            )
        ''', (user_a, user_b, user_b, user_a))
        return cursor.fetchone() is not None

def queue_offline_message(sender: str, target: str, t_type: str, content: str, group_id: str = None):
    """Task 1: Persists messages for users who are currently disconnected."""
    with get_connection() as conn:
        conn.execute('''
            INSERT INTO offline_messages (sender, target, target_type, content, group_id) 
            VALUES (?, ?, ?, ?, ?)
        ''', (sender, target, t_type, content, group_id))

def get_group_members(group_id: str) -> list[str]:
    """Task 2: Retrieves all usernames associated with a group."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT username FROM group_members WHERE group_id = ?", (group_id,))
        return [row[0] for row in cursor.fetchall()]

def update_friendship(sender: str, target: str, action: str) -> bool:
    """Task 3: Logic for sending, accepting, or blocking friend requests."""
    with get_connection() as conn:
        try:
            if action == "send":
                conn.execute("INSERT INTO friendships (requester, receiver, status) VALUES (?, ?, 'pending')", (sender, target))
            elif action == "accept":
                conn.execute("UPDATE friendships SET status = 'accepted' WHERE requester = ? AND receiver = ?", (target, sender))
            elif action == "block":
                conn.execute("INSERT OR REPLACE INTO friendships (requester, receiver, status) VALUES (?, ?, 'blocked')", (sender, target))
            return True
        except sqlite3.Error:
            return False

def fetch_offline_messages(username: str) -> list[dict]:
    """Retrieves all pending messages for a user from the queue."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute('''
            SELECT id, sender, content, timestamp, target_type, group_id 
            FROM offline_messages 
            WHERE target = ? 
            ORDER BY timestamp ASC
        ''', (username,))
        
        return [
            {
                "id": row[0],
                "sender": row[1],
                "content": row[2],
                "timestamp": row[3],
                "type": "direct_msg" if row[4] == "user" else "group_msg",
                "group_id": row[5]
            } 
            for row in cursor.fetchall()
        ]

def delete_offline_messages(message_ids: list[int]):
    """Removes messages from the queue after successful delivery."""
    if not message_ids:
        return
    with get_connection() as conn:
        # Use placeholders for the IN clause
        placeholders = ', '.join(['?'] * len(message_ids))
        conn.execute(f"DELETE FROM offline_messages WHERE id IN ({placeholders})", message_ids)

def delete_single_offline_message(message_id: int):
    """Removes a single message from the queue (used by ACK handler)."""
    with get_connection() as conn:
        conn.execute("DELETE FROM offline_messages WHERE id = ?", (message_id,))

def user_exists(username: str) -> bool:
    """Checks whether a username is registered in the system."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT 1 FROM users WHERE username = ?", (username,))
        return cursor.fetchone() is not None

def create_group(group_id: str, creator: str) -> bool:
    """Creates a new group and adds the creator as the first member."""
    try:
        with get_connection() as conn:
            conn.execute(
                "INSERT INTO groups (group_id, created_by) VALUES (?, ?)",
                (group_id, creator)
            )
            conn.execute(
                "INSERT INTO group_members (group_id, username) VALUES (?, ?)",
                (group_id, creator)
            )
        logger.info(f"Group '{group_id}' created by '{creator}'.")
        return True
    except sqlite3.IntegrityError:
        return False

def add_group_member(group_id: str, username: str) -> bool:
    """Adds a user to an existing group."""
    try:
        with get_connection() as conn:
            conn.execute(
                "INSERT INTO group_members (group_id, username) VALUES (?, ?)",
                (group_id, username)
            )
        return True
    except sqlite3.IntegrityError:
        return False

def remove_group_member(group_id: str, username: str) -> bool:
    """Removes a user from a group. Returns True if the user was actually removed."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "DELETE FROM group_members WHERE group_id = ? AND username = ?",
            (group_id, username)
        )
        return cursor.rowcount > 0

def is_group_creator(group_id: str, username: str) -> bool:
    """Checks if a user is the creator (admin) of a group."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT 1 FROM groups WHERE group_id = ? AND created_by = ?",
            (group_id, username)
        )
        return cursor.fetchone() is not None

def get_friends(username: str) -> list[str]:
    """Returns all accepted friends for a user (bidirectional lookup)."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute('''
            SELECT CASE WHEN requester = ? THEN receiver ELSE requester END as friend
            FROM friendships
            WHERE status = 'accepted' AND (requester = ? OR receiver = ?)
        ''', (username, username, username))
        return [row[0] for row in cursor.fetchall()]

def get_pending_requests(username: str) -> list[str]:
    """Returns usernames of people who sent a pending friend request to this user."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT requester FROM friendships WHERE receiver = ? AND status = 'pending'",
            (username,)
        )
        return [row[0] for row in cursor.fetchall()]

def get_user_groups(username: str) -> list[dict]:
    """Returns all groups a user is a member of, including creator info."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute('''
            SELECT gm.group_id, g.created_by
            FROM group_members gm
            JOIN groups g ON gm.group_id = g.group_id
            WHERE gm.username = ?
        ''', (username,))
        return [{"group_id": row[0], "created_by": row[1]} for row in cursor.fetchall()]