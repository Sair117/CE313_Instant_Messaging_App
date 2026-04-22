"""
Comprehensive Test Suite for the IM Server Backend
===================================================
Tests both the database layer (unit) and the full TCP server (integration).

Usage:
    cd CE313_Instant_Messaging_App
    python -m tests.test_all

All tests use a temporary database so your real data is never touched.
"""

import unittest
import sys
import os
import threading
import time
import socket
import json
import struct
import shutil

# ---------------------------------------------------------------------------
#  Path setup — ensure 'src' is importable
# ---------------------------------------------------------------------------
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(PROJECT_ROOT, 'src')
sys.path.insert(0, SRC_DIR)

# Override DB path BEFORE any database functions are called
TEST_DATA_DIR = os.path.join(PROJECT_ROOT, 'tests', '_test_data')
os.makedirs(TEST_DATA_DIR, exist_ok=True)

import database
database.DB_PATH = os.path.join(TEST_DATA_DIR, 'test_im.db')

from protocol import MessageProtocol, ConnectionClosedError


# ---------------------------------------------------------------------------
#  Test Client Helper — simulates a Flutter client over TCP
# ---------------------------------------------------------------------------
class TestClient:
    """Lightweight TCP client that speaks the same length-prefixed JSON
    protocol as the Flutter app."""

    def __init__(self, host='127.0.0.1', port=5050):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.settimeout(5.0)
        self.sock.connect((host, port))
        self.protocol = MessageProtocol(self.sock)

    def send(self, msg: dict):
        self.protocol.send(msg)

    def receive(self) -> dict:
        return self.protocol.receive()

    def register(self, username, password) -> dict:
        self.send({"type": "register", "username": username, "password": password})
        return self.receive()

    def login(self, username, password) -> dict:
        self.send({"type": "login", "username": username, "password": password})
        return self.receive()

    def close(self):
        try:
            self.sock.close()
        except Exception:
            pass


# ===================================================================
#  PART 1: DATABASE UNIT TESTS
# ===================================================================

class Test_DB_01_Users(unittest.TestCase):
    """User registration, login, and existence checks."""

    @classmethod
    def setUpClass(cls):
        if os.path.exists(database.DB_PATH):
            os.remove(database.DB_PATH)
        database.init_db()

    def test_01_register_user(self):
        self.assertTrue(database.register_user("alice", "pass123"))

    def test_02_register_duplicate_fails(self):
        self.assertFalse(database.register_user("alice", "other"))

    def test_03_login_success(self):
        self.assertTrue(database.login_user("alice", "pass123"))

    def test_04_login_wrong_password(self):
        self.assertFalse(database.login_user("alice", "wrong"))

    def test_05_login_nonexistent_user(self):
        self.assertFalse(database.login_user("ghost", "pass123"))

    def test_06_user_exists(self):
        self.assertTrue(database.user_exists("alice"))
        self.assertFalse(database.user_exists("ghost"))


class Test_DB_02_Friendships(unittest.TestCase):
    """Friend request send, accept, block, and bidirectional checks."""

    @classmethod
    def setUpClass(cls):
        if os.path.exists(database.DB_PATH):
            os.remove(database.DB_PATH)
        database.init_db()
        database.register_user("alice", "p")
        database.register_user("bob", "p")
        database.register_user("charlie", "p")

    def test_01_send_request(self):
        self.assertTrue(database.update_friendship("alice", "bob", "send"))

    def test_02_not_friends_while_pending(self):
        self.assertFalse(database.is_friend("alice", "bob"))

    def test_03_accept_request(self):
        self.assertTrue(database.update_friendship("bob", "alice", "accept"))

    def test_04_now_friends_bidirectional(self):
        self.assertTrue(database.is_friend("alice", "bob"))
        self.assertTrue(database.is_friend("bob", "alice"))

    def test_05_block_user(self):
        self.assertTrue(database.update_friendship("charlie", "alice", "block"))


class Test_DB_03_Groups(unittest.TestCase):
    """Group creation, membership, and creator checks."""

    @classmethod
    def setUpClass(cls):
        if os.path.exists(database.DB_PATH):
            os.remove(database.DB_PATH)
        database.init_db()
        database.register_user("admin", "p")
        database.register_user("member", "p")

    def test_01_create_group(self):
        self.assertTrue(database.create_group("team1", "admin"))

    def test_02_duplicate_group_fails(self):
        self.assertFalse(database.create_group("team1", "member"))

    def test_03_creator_is_auto_member(self):
        self.assertIn("admin", database.get_group_members("team1"))

    def test_04_is_group_creator(self):
        self.assertTrue(database.is_group_creator("team1", "admin"))
        self.assertFalse(database.is_group_creator("team1", "member"))

    def test_05_add_member(self):
        self.assertTrue(database.add_group_member("team1", "member"))
        self.assertIn("member", database.get_group_members("team1"))

    def test_06_duplicate_add_fails(self):
        self.assertFalse(database.add_group_member("team1", "member"))

    def test_07_remove_member(self):
        self.assertTrue(database.remove_group_member("team1", "member"))
        self.assertNotIn("member", database.get_group_members("team1"))

    def test_08_remove_nonmember_fails(self):
        self.assertFalse(database.remove_group_member("team1", "member"))


class Test_DB_04_OfflineMessages(unittest.TestCase):
    """Offline message queue, fetch, bulk delete, single delete."""

    @classmethod
    def setUpClass(cls):
        if os.path.exists(database.DB_PATH):
            os.remove(database.DB_PATH)
        database.init_db()
        database.register_user("alice", "p")
        database.register_user("bob", "p")

    def test_01_queue_and_fetch(self):
        database.queue_offline_message("alice", "bob", "user", "Hello!")
        database.queue_offline_message("alice", "bob", "user", "Still there?")
        msgs = database.fetch_offline_messages("bob")
        self.assertEqual(len(msgs), 2)
        self.assertEqual(msgs[0]["content"], "Hello!")
        self.assertEqual(msgs[0]["sender"], "alice")
        self.assertEqual(msgs[0]["type"], "direct_msg")

    def test_02_bulk_delete(self):
        msgs = database.fetch_offline_messages("bob")
        database.delete_offline_messages([m["id"] for m in msgs])
        self.assertEqual(len(database.fetch_offline_messages("bob")), 0)

    def test_03_single_delete(self):
        database.queue_offline_message("alice", "bob", "user", "One more")
        msgs = database.fetch_offline_messages("bob")
        database.delete_single_offline_message(msgs[0]["id"])
        self.assertEqual(len(database.fetch_offline_messages("bob")), 0)

    def test_04_group_message_type(self):
        database.queue_offline_message("alice", "bob", "group", "Group hello")
        msgs = database.fetch_offline_messages("bob")
        self.assertEqual(msgs[0]["type"], "group_msg")
        database.delete_offline_messages([msgs[0]["id"]])


# ===================================================================
#  PART 2: TCP INTEGRATION TESTS
# ===================================================================

# We use a non-standard port so it doesn't clash with a running server.
INTEGRATION_PORT = 5050


def _start_test_server():
    """Starts the real server on a background thread with a test DB."""
    import server as srv
    srv.PORT = INTEGRATION_PORT
    srv.HEARTBEAT_TIMEOUT = 10.0  # Short timeout for testing
    srv.start_server()


class Test_TCP_01_Auth(unittest.TestCase):
    """Registration and login over real TCP."""

    _server_thread = None

    @classmethod
    def setUpClass(cls):
        # Fresh DB for integration tests
        if os.path.exists(database.DB_PATH):
            os.remove(database.DB_PATH)
        database.init_db()

        # Reset server globals (in case of re-import)
        import server as srv
        srv.shutdown_event.clear()
        srv.active_users.clear()

        cls._server_thread = threading.Thread(target=_start_test_server, daemon=True)
        cls._server_thread.start()
        time.sleep(0.5)  # Let the server bind

    @classmethod
    def tearDownClass(cls):
        import server as srv
        srv.shutdown_event.set()
        time.sleep(1.0)

    def _client(self):
        return TestClient('127.0.0.1', INTEGRATION_PORT)

    # --- Tests ---

    def test_01_register_new_user(self):
        c = self._client()
        res = c.register("tcp_alice", "pass123")
        self.assertTrue(res["success"], res)
        c.close()

    def test_02_register_duplicate(self):
        c = self._client()
        res = c.register("tcp_alice", "pass123")
        self.assertFalse(res["success"])
        c.close()

    def test_03_login_success(self):
        c = self._client()
        res = c.login("tcp_alice", "pass123")
        self.assertTrue(res["success"], res)
        c.close()
        time.sleep(0.3)  # Let server process disconnect

    def test_04_login_wrong_password(self):
        c = self._client()
        res = c.login("tcp_alice", "wrongpw")
        self.assertFalse(res["success"])
        c.close()

    def test_05_login_nonexistent(self):
        c = self._client()
        res = c.login("whoami", "pass123")
        self.assertFalse(res["success"])
        c.close()


class Test_TCP_02_PingPong(unittest.TestCase):
    """Heartbeat keepalive mechanism."""

    _server_thread = None

    @classmethod
    def setUpClass(cls):
        if os.path.exists(database.DB_PATH):
            os.remove(database.DB_PATH)
        database.init_db()
        import server as srv
        srv.shutdown_event.clear()
        srv.active_users.clear()
        cls._server_thread = threading.Thread(target=_start_test_server, daemon=True)
        cls._server_thread.start()
        time.sleep(0.5)

    @classmethod
    def tearDownClass(cls):
        import server as srv
        srv.shutdown_event.set()
        time.sleep(1.0)

    def _client(self):
        return TestClient('127.0.0.1', INTEGRATION_PORT)

    def test_01_ping_returns_pong(self):
        c = self._client()
        c.register("ping_user", "pass123")
        c.close()

        c = self._client()
        res = c.login("ping_user", "pass123")
        self.assertTrue(res["success"])

        c.send({"type": "ping"})
        res = c.receive()
        self.assertEqual(res["type"], "pong")
        c.close()

    def test_02_multiple_pings(self):
        c = self._client()
        c.register("ping_user2", "pass123")
        c.close()

        c = self._client()
        c.login("ping_user2", "pass123")

        for _ in range(5):
            c.send({"type": "ping"})
            res = c.receive()
            self.assertEqual(res["type"], "pong")
        c.close()


class Test_TCP_03_FriendRequests(unittest.TestCase):
    """Friend request flow with user-exists validation."""

    _server_thread = None

    @classmethod
    def setUpClass(cls):
        if os.path.exists(database.DB_PATH):
            os.remove(database.DB_PATH)
        database.init_db()
        import server as srv
        srv.shutdown_event.clear()
        srv.active_users.clear()
        cls._server_thread = threading.Thread(target=_start_test_server, daemon=True)
        cls._server_thread.start()
        time.sleep(0.5)

    @classmethod
    def tearDownClass(cls):
        import server as srv
        srv.shutdown_event.set()
        time.sleep(1.0)

    def _client(self):
        return TestClient('127.0.0.1', INTEGRATION_PORT)

    def _make_user(self, username):
        """Register + login, return connected client."""
        c = self._client()
        c.register(username, "pass123")
        c.close()
        c = self._client()
        res = c.login(username, "pass123")
        self.assertTrue(res["success"], f"Login failed: {res}")
        return c

    def test_01_friend_nonexistent_user_rejected(self):
        c = self._make_user("fr_alice")
        c.send({"type": "friend_request", "target": "ghost999", "action": "send"})
        res = c.receive()
        self.assertEqual(res["type"], "error")
        self.assertIn("does not exist", res["message"])
        c.close()

    def test_02_full_friend_flow(self):
        time.sleep(0.3)
        c1 = self._make_user("fr_bob")
        c2 = self._make_user("fr_carol")

        # Bob sends friend request to Carol
        c1.send({"type": "friend_request", "target": "fr_carol", "action": "send"})
        res = c1.receive()
        self.assertTrue(res.get("success"), f"Friend send failed: {res}")

        # Carol should receive a notification
        notif = c2.receive()
        self.assertEqual(notif["type"], "friend_notif")
        self.assertEqual(notif["from"], "fr_bob")

        # Carol accepts
        c2.send({"type": "friend_request", "target": "fr_bob", "action": "accept"})
        res = c2.receive()
        self.assertTrue(res.get("success"), f"Friend accept failed: {res}")

        # Verify in DB
        self.assertTrue(database.is_friend("fr_bob", "fr_carol"))

        c1.close()
        c2.close()


class Test_TCP_04_DirectMessages(unittest.TestCase):
    """1-to-1 messaging with delivery receipts and ACKs."""

    _server_thread = None

    @classmethod
    def setUpClass(cls):
        if os.path.exists(database.DB_PATH):
            os.remove(database.DB_PATH)
        database.init_db()
        import server as srv
        srv.shutdown_event.clear()
        srv.active_users.clear()
        cls._server_thread = threading.Thread(target=_start_test_server, daemon=True)
        cls._server_thread.start()
        time.sleep(0.5)

        # Pre-register two users who are friends
        database.register_user("dm_alice", "pass123")
        database.register_user("dm_bob", "pass123")
        database.update_friendship("dm_alice", "dm_bob", "send")
        database.update_friendship("dm_bob", "dm_alice", "accept")

        # Register a user with no friends
        database.register_user("dm_stranger", "pass123")

    @classmethod
    def tearDownClass(cls):
        import server as srv
        srv.shutdown_event.set()
        time.sleep(1.0)

    def _client(self):
        return TestClient('127.0.0.1', INTEGRATION_PORT)

    def _login(self, username):
        c = self._client()
        res = c.login(username, "pass123")
        self.assertTrue(res["success"], f"Login failed for {username}: {res}")
        return c

    def test_01_direct_message_delivered(self):
        c_alice = self._login("dm_alice")
        c_bob = self._login("dm_bob")

        c_alice.send({"type": "direct_msg", "target": "dm_bob", "content": "Hello Bob!"})

        # Alice gets a delivery receipt
        receipt = c_alice.receive()
        self.assertEqual(receipt["type"], "receipt")
        self.assertEqual(receipt["status"], "delivered")
        self.assertIn("msg_id", receipt)

        # Bob gets the message
        msg = c_bob.receive()
        self.assertEqual(msg["type"], "direct_msg")
        self.assertEqual(msg["sender"], "dm_alice")
        self.assertEqual(msg["content"], "Hello Bob!")
        self.assertIn("msg_id", msg)

        # Bob sends ACK
        c_bob.send({"type": "ack", "msg_id": msg["msg_id"]})

        c_alice.close()
        c_bob.close()

    def test_02_message_requires_friendship(self):
        time.sleep(0.3)
        c = self._login("dm_stranger")
        c.send({"type": "direct_msg", "target": "dm_alice", "content": "Hi!"})
        res = c.receive()
        self.assertEqual(res["type"], "error")
        self.assertIn("Friendship required", res["message"])
        c.close()

    def test_03_offline_message_queued(self):
        time.sleep(0.3)
        # Alice is online, Bob is offline
        c_alice = self._login("dm_alice")
        c_alice.send({"type": "direct_msg", "target": "dm_bob", "content": "Are you there?"})

        receipt = c_alice.receive()
        self.assertEqual(receipt["status"], "queued")

        # Verify it's in the DB
        msgs = database.fetch_offline_messages("dm_bob")
        self.assertTrue(any(m["content"] == "Are you there?" for m in msgs))

        c_alice.close()

    def test_04_offline_messages_synced_on_login(self):
        time.sleep(0.3)
        # Bob logs in and should receive the queued message
        c_bob = self._login("dm_bob")

        msg = c_bob.receive()
        self.assertEqual(msg["type"], "direct_msg")
        self.assertEqual(msg["content"], "Are you there?")
        self.assertTrue(msg.get("is_sync"))
        self.assertIn("msg_id", msg)

        # ACK it
        c_bob.send({"type": "ack", "msg_id": msg["msg_id"]})
        time.sleep(0.3)  # Let server process the ACK

        # Verify it's been removed from the DB
        msgs = database.fetch_offline_messages("dm_bob")
        self.assertFalse(any(m["content"] == "Are you there?" for m in msgs))

        c_bob.close()


class Test_TCP_05_Groups(unittest.TestCase):
    """Group create, manage members, messaging, and leave."""

    _server_thread = None

    @classmethod
    def setUpClass(cls):
        if os.path.exists(database.DB_PATH):
            os.remove(database.DB_PATH)
        database.init_db()
        import server as srv
        srv.shutdown_event.clear()
        srv.active_users.clear()
        cls._server_thread = threading.Thread(target=_start_test_server, daemon=True)
        cls._server_thread.start()
        time.sleep(0.5)

        # Pre-register users
        database.register_user("g_admin", "pass123")
        database.register_user("g_member", "pass123")
        database.register_user("g_other", "pass123")

    @classmethod
    def tearDownClass(cls):
        import server as srv
        srv.shutdown_event.set()
        time.sleep(1.0)

    def _client(self):
        return TestClient('127.0.0.1', INTEGRATION_PORT)

    def _login(self, username):
        c = self._client()
        res = c.login(username, "pass123")
        self.assertTrue(res["success"], f"Login failed for {username}: {res}")
        return c

    def test_01_create_group(self):
        c = self._login("g_admin")
        c.send({"type": "create_group", "group_id": "test_grp"})
        res = c.receive()
        self.assertTrue(res["success"], res)
        c.close()

    def test_02_create_duplicate_group(self):
        time.sleep(0.3)
        c = self._login("g_other")
        c.send({"type": "create_group", "group_id": "test_grp"})
        res = c.receive()
        self.assertFalse(res["success"])
        c.close()

    def test_03_add_member(self):
        time.sleep(0.3)
        c = self._login("g_admin")
        c.send({"type": "group_manage", "group_id": "test_grp", "target": "g_member", "action": "add"})
        res = c.receive()
        self.assertTrue(res["success"], res)
        self.assertIn("g_member", database.get_group_members("test_grp"))
        c.close()

    def test_04_add_nonexistent_user(self):
        time.sleep(0.3)
        c = self._login("g_admin")
        c.send({"type": "group_manage", "group_id": "test_grp", "target": "ghost", "action": "add"})
        res = c.receive()
        self.assertEqual(res["type"], "error")
        self.assertIn("does not exist", res["message"])
        c.close()

    def test_05_non_admin_cannot_manage(self):
        time.sleep(0.3)
        c = self._login("g_member")
        c.send({"type": "group_manage", "group_id": "test_grp", "target": "g_other", "action": "add"})
        res = c.receive()
        self.assertEqual(res["type"], "error")
        self.assertIn("creator", res["message"])
        c.close()

    def test_06_group_message(self):
        time.sleep(0.3)
        c_admin = self._login("g_admin")
        c_member = self._login("g_member")

        c_admin.send({"type": "group_msg", "group_id": "test_grp", "content": "Hello team!"})

        msg = c_member.receive()
        self.assertEqual(msg["type"], "group_msg")
        self.assertEqual(msg["sender"], "g_admin")
        self.assertEqual(msg["group_id"], "test_grp")
        self.assertEqual(msg["content"], "Hello team!")

        c_admin.close()
        c_member.close()

    def test_07_non_member_cant_send(self):
        time.sleep(0.3)
        c = self._login("g_other")
        c.send({"type": "group_msg", "group_id": "test_grp", "content": "Intruder!"})
        res = c.receive()
        self.assertEqual(res["type"], "error")
        self.assertIn("Not a group member", res["message"])
        c.close()

    def test_08_leave_group(self):
        time.sleep(0.3)
        c = self._login("g_member")
        c.send({"type": "leave_group", "group_id": "test_grp"})
        res = c.receive()
        self.assertTrue(res["success"], res)
        self.assertNotIn("g_member", database.get_group_members("test_grp"))
        c.close()

    def test_09_leave_group_not_member(self):
        time.sleep(0.3)
        c = self._login("g_other")
        c.send({"type": "leave_group", "group_id": "test_grp"})
        res = c.receive()
        self.assertFalse(res["success"])
        c.close()


# ===================================================================
#  Run all tests
# ===================================================================

if __name__ == '__main__':
    print("=" * 60)
    print("  IM Server Backend — Full Test Suite")
    print("=" * 60)
    print()
    unittest.main(verbosity=2)
