import json
import struct
import socket
import logging
from typing import Optional, Any

# 1. Logging Setup [Consistency with server/database]
logger = logging.getLogger(__name__)

class ConnectionClosedError(Exception):
    """Raised when the peer closes the connection cleanly."""
    pass

class PartialReadError(Exception):
    """Raised when the connection drops mid-message."""
    pass

class MessageProtocol:
    HEADER_FORMAT = '!I'
    HEADER_SIZE = struct.calcsize(HEADER_FORMAT)
    MAX_MESSAGE_BYTES = 16 * 1024 * 1024  # 16 MB limit

    def __init__(self, sock: socket.socket):
        self.sock = sock

    def send(self, msg_dict: dict) -> bool:
        """Serializes and sends a dictionary over the socket."""
        try:
            # Serialization
            data_bytes = json.dumps(msg_dict).encode('utf-8')
            
            # Check if payload is too large before sending header
            if len(data_bytes) > self.MAX_MESSAGE_BYTES:
                logger.error(f"Outgoing message too large: {len(data_bytes)} bytes.")
                return False

            header = struct.pack(self.HEADER_FORMAT, len(data_bytes))
            
            # Send the entire packet (header + payload)
            self.sock.sendall(header + data_bytes)
            return True
        except (OSError, TypeError, ValueError) as e:
            logger.error(f"Protocol send error: {e}")
            return False

    def _recvall(self, n: int) -> bytes:
        """Helper to reliably read exactly n bytes with chunking."""
        data = bytearray()
        while len(data) < n:
            # We must catch socket.timeout separately from general OSError
            # so the server can decide whether to retry or disconnect.
            packet = self.sock.recv(n - len(data))
            if not packet:
                if len(data) == 0:
                    raise ConnectionClosedError("Peer closed the connection.")
                raise PartialReadError(f"Expected {n} bytes, got {len(data)}.")
            data.extend(packet)
        return bytes(data)

    def receive(self) -> Optional[dict]:
        """Reads the header, validates size, and deserializes the payload."""
        try:
            # 1. Read the 4-byte length prefix
            raw_header = self._recvall(self.HEADER_SIZE)
            msglen = struct.unpack(self.HEADER_FORMAT, raw_header)[0]

            # 2. Security Check: Prevent memory exhaustion attacks
            if msglen > self.MAX_MESSAGE_BYTES:
                raise ValueError(f"Message too large: {msglen} bytes.")

            # 3. Read the payload
            data_bytes = self._recvall(msglen)
            
            # 4. Deserialization
            return json.loads(data_bytes.decode('utf-8'))

        except ConnectionClosedError:
            # Clean disconnects return None so the server loop can 'break'
            return None
        except socket.timeout:
            # Propagate timeout to the server to handle (e.g., Auth timeout)
            raise 
        except (PartialReadError, ValueError, OSError, json.JSONDecodeError, struct.error) as e:
            logger.error(f"Protocol receive error: {e}")
            return None