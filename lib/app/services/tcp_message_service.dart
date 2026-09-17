import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/speech_message.dart';

class TcpMessageService {
  static const int applicationPort = 7070;
  static const int maxMessageBytes = 64 * 1024;
  ServerSocket? _serverSocket;
  StreamSubscription<Socket>? _serverSubscription;
  final Set<Socket> _serverClients = {};
  Socket? _clientSocket;
  final Map<Socket, BytesBuilder> _pending = {};
  final Map<Socket, StreamSubscription<List<int>>> _subscriptions = {};

  FutureOr<void> Function(SpeechMessage message)? onMessage;
  void Function(String status)? onStatus;
  void Function(bool connected)? onConnectionChanged;

  bool get isConnected => _clientSocket != null || _serverClients.isNotEmpty;
  bool get isActive => _serverSocket != null || _clientSocket != null;
  int? get listeningPort => _serverSocket?.port;

  Future<void> startServer({required int port}) async {
    await close();
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    onStatus?.call('SERVER LISTENING: 0.0.0.0:${_serverSocket!.port}');
    _serverSubscription = _serverSocket!.listen((Socket socket) {
      _serverClients.add(socket);
      _attachSocket(socket);
      onConnectionChanged?.call(isConnected);
      onStatus?.call('Client connected from ${socket.remoteAddress.address}');
    }, onError: (Object error) {
      onStatus?.call('Server error: $error');
    });
  }

  Future<void> connect({required String host, required int port}) async {
    await close();
    onStatus?.call('CONNECTING TO $host:$port');
    _clientSocket =
        await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    _attachSocket(_clientSocket!);
    onConnectionChanged?.call(isConnected);
    onStatus?.call('CONNECTED TO $host:$port');
  }

  Future<void> send(SpeechMessage message) async {
    final List<Socket> peers = [
      if (_clientSocket != null) _clientSocket!,
      ..._serverClients,
    ];
    if (peers.isEmpty) {
      throw StateError('No TCP peer connected to send the message.');
    }
    final List<int> payload = _encode(message);
    bool written = false;
    for (final Socket peer in peers) {
      try {
        peer.add(payload);
        await peer.flush();
        written = true;
      } catch (error) {
        _detach(peer);
        onStatus?.call('Send failed: $error');
      }
    }
    if (!written) throw StateError('TCP peers disconnected before sending.');
  }

  List<int> _encode(SpeechMessage message) {
    final List<int> payload =
        utf8.encode('${jsonEncode(message.toJsonNetwork())}\n');
    if (payload.length > maxMessageBytes) {
      throw StateError('Message exceeds the 64 KiB limit.');
    }
    return payload;
  }

  void _attachSocket(Socket socket) {
    _pending[socket] = BytesBuilder(copy: false);
    _subscriptions[socket] = socket.listen(
      (List<int> bytes) => _handleChunk(socket, bytes),
      onDone: () {
        _detach(socket);
        onStatus?.call('Socket disconnected.');
      },
      onError: (Object error) {
        _detach(socket);
        onStatus?.call('Socket error: $error');
      },
      cancelOnError: true,
    );
  }

  void _detach(Socket socket) {
    _pending.remove(socket);
    final subscription = _subscriptions.remove(socket);
    if (subscription != null) unawaited(subscription.cancel());
    _serverClients.remove(socket);
    if (identical(_clientSocket, socket)) _clientSocket = null;
    socket.destroy();
    onConnectionChanged?.call(isConnected);
  }

  void _handleChunk(Socket socket, List<int> bytes) {
    final BytesBuilder? buffer = _pending[socket];
    if (buffer == null) return;
    int start = 0;
    for (int index = 0; index <= bytes.length; index++) {
      if (index != bytes.length && bytes[index] != 10) continue;
      if (buffer.length + index - start > maxMessageBytes) {
        onStatus?.call('Dropped oversized TCP packet.');
        _detach(socket);
        return;
      }
      if (index > start) buffer.add(bytes.sublist(start, index));
      if (index < bytes.length) {
        final List<int> frame = buffer.takeBytes();
        // Decode complete newline-delimited frames; UTF-8 may span TCP chunks.
        if (frame.isNotEmpty) {
          try {
            _decodeMessage(socket, utf8.decode(frame));
          } on FormatException catch (error) {
            onStatus?.call('Dropped invalid UTF-8 packet: $error');
          }
        }
      }
      start = index + 1;
    }
  }

  void _decodeMessage(Socket source, String rawJson) {
    try {
      final Object? decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic> || decoded['message'] is! String) {
        onStatus?.call('Dropped malformed packet.');
        return;
      }
      final SpeechMessage message = SpeechMessage.fromJson(decoded);
      if (_serverClients.contains(source)) {
        final List<int> payload = _encode(message);
        // Star topology: forward to every other client, never echo to the sender.
        for (final Socket peer in _serverClients.toList()) {
          if (identical(peer, source)) continue;
          unawaited(_relay(peer, payload));
        }
      }
      unawaited(Future<void>.sync(() => onMessage?.call(message)).catchError(
        (Object error) {
          onStatus?.call('Message handler failed: $error');
        },
      ));
    } catch (error) {
      onStatus?.call('JSON decode error: $error');
    }
  }

  Future<void> _relay(Socket peer, List<int> payload) async {
    try {
      peer.add(payload);
      await peer.flush();
    } catch (error) {
      _detach(peer);
      onStatus?.call('Relay failed: $error');
    }
  }

  Future<void> close() async {
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _serverSocket?.close();
    _serverSocket = null;
    for (final Socket socket in _pending.keys.toList()) {
      _detach(socket);
    }
    onConnectionChanged?.call(false);
  }
}
