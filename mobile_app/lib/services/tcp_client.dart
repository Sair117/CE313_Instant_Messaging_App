import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Low-level TCP client that mirrors the Python `protocol.py`.
/// Uses 4-byte big-endian length-prefix framing over raw TCP.
class TcpClient {
  Socket? _socket;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _disconnectController = StreamController<void>.broadcast();

  List<int> _buffer = [];
  int? _expectedLength;
  bool _connected = false;

  /// Stream of deserialized JSON messages from the server.
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Fires when the connection is lost.
  Stream<void> get onDisconnect => _disconnectController.stream;

  bool get isConnected => _connected;

  /// Connect to the TCP server.
  Future<void> connect(String host, int port) async {
    _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
    _connected = true;
    _buffer = [];
    _expectedLength = null;

    _socket!.listen(
      _onData,
      onError: (error) {
        _connected = false;
        _disconnectController.add(null);
      },
      onDone: () {
        _connected = false;
        _disconnectController.add(null);
      },
      cancelOnError: false,
    );
  }

  /// Send a JSON message with 4-byte length prefix.
  bool send(Map<String, dynamic> msg) {
    if (_socket == null || !_connected) return false;
    try {
      final jsonBytes = utf8.encode(jsonEncode(msg));
      final header = ByteData(4)..setUint32(0, jsonBytes.length, Endian.big);
      _socket!.add(header.buffer.asUint8List());
      _socket!.add(jsonBytes);
      return true;
    } catch (e) {
      _connected = false;
      return false;
    }
  }

  /// Process incoming raw bytes, extract framed messages.
  void _onData(Uint8List data) {
    _buffer.addAll(data);
    _processBuffer();
  }

  void _processBuffer() {
    while (true) {
      // Step 1: Read 4-byte header if we don't have a pending length
      if (_expectedLength == null) {
        if (_buffer.length < 4) return;
        final headerBytes = Uint8List.fromList(_buffer.sublist(0, 4));
        _expectedLength = ByteData.view(headerBytes.buffer).getUint32(0, Endian.big);
        _buffer = _buffer.sublist(4);
      }

      // Step 2: Read payload once we have enough bytes
      if (_buffer.length < _expectedLength!) return;

      final payloadBytes = _buffer.sublist(0, _expectedLength!);
      _buffer = _buffer.sublist(_expectedLength!);
      _expectedLength = null;

      // Step 3: Decode and emit
      try {
        final json = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
        _messageController.add(json);
      } catch (e) {
        // Malformed message — skip
      }
    }
  }

  /// Close the connection.
  Future<void> disconnect() async {
    _connected = false;
    await _socket?.close();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _disconnectController.close();
  }
}
