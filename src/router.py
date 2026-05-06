import logging
import uuid
import threading
from datetime import datetime, timezone
from typing import Dict, Any
from protocol import MessageProtocol
import database

logger = logging.getLogger(__name__)

class MessageRouter:
    VALID_ACTIONS = {"send", "accept", "block"}
    VALID_GROUP_ACTIONS = {"add", "remove"}

    def __init__(self, active_users: Dict[str, MessageProtocol], lock):
        self.active_users = active_users
        self.lock = lock
        # ACK tracking: maps msg_id -> offline_messages DB row id
        self._pending_acks = {}
        self._ack_lock = threading.Lock()
        # Dispatch Table for scalability [Critique 1]
        self.handlers = {
            "direct_msg": self._route_direct,
            "group_msg": self._route_group,
            "friend_request": self._handle_friend_action,
            "create_group": self._handle_create_group,
            "group_manage": self._handle_group_manage,
            "leave_group": self._handle_leave_group,
            "get_friends": self._handle_get_friends,
            "get_groups": self._handle_get_groups,
            "get_group_members": self._handle_get_group_members,
            "ack": self._handle_ack,
            "ping": self._handle_ping,
        }

    def handle_request(self, sender: str, msg: dict):
        """Entry point with exception isolation [Critique 3]."""
        m_type = msg.get("type")
        handler = self.handlers.get(m_type)
        
        try:
            if handler:
                handler(sender, msg)
            else:
                logger.warning(f"[ROUTER] Unknown type '{m_type}' from '{sender}'")
                self._send_to(sender, {"type": "error", "message": f"Unknown type: {m_type}"})
        except Exception as e:
            logger.error(f"[ROUTER] Crash for {sender}: {e}", exc_info=True)
            self._send_to(sender, {"type": "error", "message": "Internal router error"})

    # ---------------------------------------------------------------
    #  Messaging Handlers
    # ---------------------------------------------------------------

    def _route_direct(self, sender: str, msg: dict):
        """Task 1: 1-to-1 Routing with Input Validation [Critique 2]."""
        target = msg.get("target")
        content = msg.get("content")
        
        if not (isinstance(target, str) and target and isinstance(content, str) and content):
            self._send_to(sender, {"type": "error", "message": "Invalid target or content"})
            return

        if not database.is_friend(sender, target):
            self._send_to(sender, {"type": "error", "message": "Friendship required"})
            return

        with self.lock:
            target_p = self.active_users.get(target)

        msg_id = msg.get("msg_id") or str(uuid.uuid4())
        now_utc = datetime.now(timezone.utc).isoformat()
        delivery_packet = {
            "type": "direct_msg",
            "msg_id": msg_id,
            "sender": sender,
            "content": content,
            "timestamp": now_utc,
        }

        # Attempt live delivery, fallback to queue [Critique 7/8]
        if target_p and target_p.send(delivery_packet):
            self._send_to(sender, {"type": "receipt", "status": "delivered", "target": target, "msg_id": msg_id})
        else:
            database.queue_offline_message(sender, target, "user", content)
            self._send_to(sender, {"type": "receipt", "status": "queued", "target": target, "msg_id": msg_id})

    def _route_group(self, sender: str, msg: dict):
        """Task 2: Group Fan-out with Lock Snapshots [Critique 4/5]."""
        g_id, content = msg.get("group_id"), msg.get("content")

        if not (isinstance(g_id, str) and g_id and isinstance(content, str) and content):
            self._send_to(sender, {"type": "error", "message": "Invalid group_id or content"})
            return

        members = database.get_group_members(g_id)

        if sender not in members:
            self._send_to(sender, {"type": "error", "message": "Not a group member"})
            return

        # Snapshot active protocols to release lock fast [Critique 4]
        with self.lock:
            recipients = {m: self.active_users.get(m) for m in members if m != sender}

        for member, protocol in recipients.items():
            msg_id = str(uuid.uuid4())
            now_utc = datetime.now(timezone.utc).isoformat()
            group_packet = {
                "type": "group_msg",
                "msg_id": msg_id,
                "sender": sender,
                "group_id": g_id,
                "content": content,
                "timestamp": now_utc,
            }

            if protocol and protocol.send(group_packet):
                continue # Delivered
            
            # Queuing if offline OR if the live send fails [Critique 7]
            database.queue_offline_message(sender, member, "group", content, group_id=g_id)
            logger.info(f"Queued group msg for {member}")

    # ---------------------------------------------------------------
    #  ACK & Keepalive Handlers
    # ---------------------------------------------------------------

    def _handle_ack(self, sender: str, msg: dict):
        """Processes a message acknowledgement from the client.
        If the ACK corresponds to a synced offline message, deletes it from the DB."""
        ack_id = msg.get("msg_id")
        if not ack_id:
            return

        with self._ack_lock:
            ack_data = self._pending_acks.pop(ack_id, None)

        if ack_data is not None:
            offline_db_id = ack_data["db_id"]
            original_sender = ack_data["sender"]
            msg_type = ack_data["type"]
            
            database.delete_single_offline_message(offline_db_id)
            logger.info(f"[ACK] '{sender}' confirmed msg_id={ack_id}, deleted offline row {offline_db_id}")
            
            # Send a delayed delivery receipt to the original sender if it was a direct message
            if msg_type == "direct_msg":
                self._send_to(original_sender, {
                    "type": "receipt",
                    "status": "delivered",
                    "target": sender
                })

    def _handle_ping(self, sender: str, msg: dict):
        """Responds to a client keepalive ping with a pong."""
        self._send_to(sender, {"type": "pong"})

    # ---------------------------------------------------------------
    #  Friend Request Handler
    # ---------------------------------------------------------------

    def _handle_friend_action(self, sender: str, msg: dict):
        """Task 3: Friendship Protocol with Action Allowlist [Critique 6]."""
        target, action = msg.get("target"), msg.get("action")
        
        if action not in self.VALID_ACTIONS:
            self._send_to(sender, {"type": "error", "message": f"Invalid action: {action}"})
            return

        # Verify the target user actually exists before processing
        if not database.user_exists(target):
            self._send_to(sender, {"type": "error", "message": f"User '{target}' does not exist."})
            return

        if database.update_friendship(sender, target, action):
            self._send_to(sender, {"type": "friend_res", "success": True, "message": f"Friend {action} succeeded."})
            if action == "send":
                with self.lock:
                    target_p = self.active_users.get(target)
                if target_p:
                    target_p.send({"type": "friend_notif", "from": sender})
        else:
            self._send_to(sender, {"type": "error", "message": "Friend action failed."})

    # ---------------------------------------------------------------
    #  Group Management Handlers
    # ---------------------------------------------------------------

    def _handle_create_group(self, sender: str, msg: dict):
        """Creates a new group. The sender becomes the creator and first member."""
        group_id = msg.get("group_id")

        if not (isinstance(group_id, str) and group_id):
            self._send_to(sender, {"type": "error", "message": "Missing or invalid group_id."})
            return

        if database.create_group(group_id, sender):
            self._send_to(sender, {"type": "group_res", "success": True, "message": f"Group '{group_id}' created.", "group_id": group_id})
        else:
            self._send_to(sender, {"type": "group_res", "success": False, "message": "Group ID already taken.", "group_id": group_id})

    def _handle_group_manage(self, sender: str, msg: dict):
        """Adds or removes members from a group. Only the group creator can do this."""
        group_id = msg.get("group_id")
        target = msg.get("target")
        action = msg.get("action")  # "add" or "remove"

        if action not in self.VALID_GROUP_ACTIONS:
            self._send_to(sender, {"type": "error", "message": f"Invalid group action: {action}"})
            return

        if not database.is_group_creator(group_id, sender):
            self._send_to(sender, {"type": "error", "message": "Only the group creator can manage members."})
            return

        if not database.user_exists(target):
            self._send_to(sender, {"type": "error", "message": f"User '{target}' does not exist."})
            return

        if action == "add":
            success = database.add_group_member(group_id, target)
            result_msg = f"'{target}' added to group." if success else f"'{target}' is already a member."
        else:  # "remove"
            success = database.remove_group_member(group_id, target)
            result_msg = f"'{target}' removed from group." if success else f"'{target}' is not a member."

        self._send_to(sender, {"type": "group_res", "success": success, "message": result_msg, "group_id": group_id})

        # Notify the target if they are online and were added
        if success and action == "add":
            with self.lock:
                target_p = self.active_users.get(target)
            if target_p:
                target_p.send({"type": "group_notif", "group_id": group_id, "message": f"You were added to '{group_id}'."})

    def _handle_leave_group(self, sender: str, msg: dict):
        """Allows a user to voluntarily leave a group."""
        group_id = msg.get("group_id")

        if not (isinstance(group_id, str) and group_id):
            self._send_to(sender, {"type": "error", "message": "Missing or invalid group_id."})
            return

        if database.remove_group_member(group_id, sender):
            self._send_to(sender, {"type": "group_res", "success": True, "message": f"You left '{group_id}'."})
        else:
            self._send_to(sender, {"type": "group_res", "success": False, "message": "You are not a member of this group."})

    # ---------------------------------------------------------------
    #  Data Query Handlers
    # ---------------------------------------------------------------

    def _handle_get_friends(self, sender: str, msg: dict):
        """Returns the sender's friends list and pending incoming requests."""
        friends = database.get_friends(sender)
        pending = database.get_pending_requests(sender)
        self._send_to(sender, {
            "type": "friends_list",
            "friends": friends,
            "pending_requests": pending,
        })

    def _handle_get_groups(self, sender: str, msg: dict):
        """Returns all groups the sender belongs to."""
        groups = database.get_user_groups(sender)
        self._send_to(sender, {
            "type": "groups_list",
            "groups": groups,
        })

    def _handle_get_group_members(self, sender: str, msg: dict):
        """Returns the full member list for a group (sender must be a member)."""
        group_id = msg.get("group_id")
        if not (isinstance(group_id, str) and group_id):
            self._send_to(sender, {"type": "error", "message": "Invalid group_id"})
            return
        members = database.get_group_members(group_id)
        if sender not in members:
            self._send_to(sender, {"type": "error", "message": "Not a member of this group"})
            return
        self._send_to(sender, {"type": "group_members", "group_id": group_id, "members": members})

    # ---------------------------------------------------------------
    #  Utility Methods
    # ---------------------------------------------------------------

    def _send_to(self, username: str, payload: dict):
        """Utility for private system replies."""
        with self.lock:
            p = self.active_users.get(username)
        if p: p.send(payload)

    def sync_offline_messages(self, username: str):
        """
        Fetches queued messages and pushes them to the newly connected user.
        Uses ACK-based delivery: messages are only deleted from the DB
        when the client sends back an ACK for each msg_id.
        """
        pending = database.fetch_offline_messages(username)
        if not pending:
            return

        logger.info(f"[SYNC] Pushing {len(pending)} missed messages to '{username}'...")
        
        with self.lock:
            protocol = self.active_users.get(username)
        
        if not protocol:
            return

        for msg in pending:
            msg_id = str(uuid.uuid4())
            # Prepare the packet for the mobile app
            # Ensure timestamp is explicitly marked as UTC
            ts = msg["timestamp"]
            if ts and not ts.endswith('Z') and '+' not in ts:
                ts = ts + 'Z'
            sync_packet = {
                "type": msg["type"],
                "msg_id": msg_id,
                "sender": msg["sender"],
                "content": msg["content"],
                "timestamp": ts,
                "is_sync": True  # Tell the Flutter app this is an old message
            }
            # Include group_id for group messages so the app routes correctly
            if msg.get("group_id"):
                sync_packet["group_id"] = msg["group_id"]
            
            if protocol.send(sync_packet):
                # Register the pending ACK — only delete from DB when client ACKs
                with self._ack_lock:
                    self._pending_acks[msg_id] = {
                        "db_id": msg["id"],
                        "sender": msg["sender"],
                        "type": msg["type"]
                    }
            else:
                # Send failed, leave the message in the DB for next login
                logger.warning(f"[SYNC] Failed to deliver msg {msg['id']} to '{username}', keeping in queue.")

    def sync_outbound_status(self, username: str):
        """
        Tells the user which of their sent messages are STILL pending delivery.
        Any target NOT in this list implies all messages sent to them are delivered.
        """
        pending_targets = database.get_pending_targets_for_sender(username)
        with self.lock:
            p = self.active_users.get(username)
        if p:
            p.send({
                "type": "outbound_status",
                "pending_targets": pending_targets
            })