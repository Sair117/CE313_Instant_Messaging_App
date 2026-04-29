import socket
import threading
import logging
import signal
from typing import Optional
from router import MessageRouter
from concurrent.futures import ThreadPoolExecutor
from protocol import MessageProtocol, ConnectionClosedError
import database

# --- Configuration & Security Limits ---
HOST, PORT = '0.0.0.0', 5000
MAX_CLIENTS = 50
MAX_AUTH_ATTEMPTS = 5
AUTH_TIMEOUT = 30.0 # [Suggestion 3]
HEARTBEAT_TIMEOUT = 120.0  # Seconds of inactivity before disconnecting a client
MAX_CRED_LEN = 32

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# --- Global State & Concurrency Control ---
active_users = {}
active_users_lock = threading.Lock() # Task 2 Requirement
shutdown_event = threading.Event()

router = MessageRouter(active_users, active_users_lock)

def _safe_log(msg: dict) -> dict:
    """Sanitizes sensitive fields like passwords before logging [Suggestion 2]."""
    return {k: ("***" if k == "password" else v) for k, v in msg.items()}

def validate_creds(u: any, p: any) -> bool:
    """Basic input validation for credentials [Suggestion 7]."""
    return (isinstance(u, str) and isinstance(p, str)
            and 1 <= len(u) <= MAX_CRED_LEN
            and 1 <= len(p) <= MAX_CRED_LEN)

def handle_auth(protocol: MessageProtocol) -> Optional[str]:
    """Secure authentication handshake with brute-force protection [Suggestion 4]."""
    attempts = 0
    while attempts < MAX_AUTH_ATTEMPTS and not shutdown_event.is_set():
        msg = protocol.receive()
        if not msg: return None
        
        m_type, user, pwd = msg.get("type"), msg.get("username"), msg.get("password")
        
        if not validate_creds(user, pwd):
            protocol.send({"type": "auth_res", "success": False, "message": "Invalid input format."})
            attempts += 1
            continue

        if m_type == "login":
            if database.login_user(user, pwd):
                with active_users_lock:
                    if user in active_users:
                        protocol.send({"type": "auth_res", "success": False, "message": "Already logged in."})
                        continue
                    active_users[user] = protocol
                protocol.send({"type": "auth_res", "success": True, "message": "Welcome!"})
                return user
            attempts += 1
            protocol.send({"type": "auth_res", "success": False, "message": f"Fail. {MAX_AUTH_ATTEMPTS-attempts} left."})
        
        elif m_type == "register":
            success = database.register_user(user, pwd)
            protocol.send({"type": "auth_res", "success": success, "message": "Registered!" if success else "Taken."})

    protocol.send({"type": "error", "message": "Too many attempts. Goodbye."})
    return None

def handle_client(conn, addr):
    """Main client thread. Non-daemon to ensure cleanup [Suggestion 6]."""
    logger.info(f"[CONNECT] {addr}")
    conn.settimeout(AUTH_TIMEOUT)
    protocol = MessageProtocol(conn)
    username = None

    try:
        username = handle_auth(protocol)
        if not username: return
        router.sync_offline_messages(username)
        router.sync_outbound_status(username)
        conn.settimeout(HEARTBEAT_TIMEOUT)  # Client must send a ping within this interval
        logger.info(f"[SESSION] '{username}' active.")

        while not shutdown_event.is_set():
            msg = protocol.receive()
            if not msg: break
            router.handle_request(username, msg)
            logger.info(f"[MSG] From {username}: {_safe_log(msg)}")


    except socket.timeout:
        logger.warning(f"[HEARTBEAT] {username or addr} timed out after {HEARTBEAT_TIMEOUT}s of inactivity.")
    except ConnectionClosedError:
        logger.info(f"[DISCONNECT] {username or addr} disconnected.")
    except Exception as e:
        logger.error(f"[ERROR] {username or addr}: {e}")
    finally:
        if username:
            with active_users_lock:
                active_users.pop(username, None)
        conn.close()

def start_server():
    database.init_db()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(MAX_CLIENTS)
    server.setblocking(False) # Allows checking shutdown_event [Suggestion 5]

    # [Suggestion 9] Using ThreadPool for better scalability
    with ThreadPoolExecutor(max_workers=MAX_CLIENTS) as executor:
        logger.info(f"[START] Server listening on {PORT}...")
        
        while not shutdown_event.is_set():
            try:
                # Use a small timeout to keep the loop responsive to shutdown_event
                server.settimeout(1.0)
                conn, addr = server.accept()
                executor.submit(handle_client, conn, addr)
            except socket.timeout:
                continue
            except Exception as e:
                if not shutdown_event.is_set(): logger.error(f"Accept error: {e}")
    
    server.close()

if __name__ == "__main__":
    def signal_handler(sig, frame):
        logger.info("\n[SHUTDOWN] Stopping server...")
        shutdown_event.set()
    
    signal.signal(signal.SIGINT, signal_handler)
    start_server()