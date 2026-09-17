import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sih_voice_bridge/app/models/speech_message.dart';
import 'package:sih_voice_bridge/app/services/tcp_message_service.dart';

SpeechMessage message(String id, String text) => SpeechMessage(
    id: id,
    type: MessageType.emergency,
    languageCode: 'hi',
    message: text,
    timestamp: DateTime.now(),
    origin: MessageOrigin.local);

Future<void> until(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 4));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('TCP event did not arrive');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late TcpMessageService server;
  final List<Socket> sockets = [];
  setUp(() async {
    server = TcpMessageService();
    await server.startServer(port: 0);
  });
  tearDown(() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    await server.close();
  });

  Future<Socket> connect() async {
    final socket = await Socket.connect('127.0.0.1', server.listeningPort!);
    socket.setOption(SocketOption.tcpNoDelay, true);
    sockets.add(socket);
    return socket;
  }

  test('server relays to other clients once without echoing to the sender',
      () async {
    final received = <SpeechMessage>[];
    server.onMessage = received.add;
    final sender = await connect();
    final other = await connect();
    final senderFrames = <String>[];
    final otherFrames = <String>[];
    sender
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(senderFrames.add);
    other
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(otherFrames.add);
    sender.write('${jsonEncode(message('relay', 'नमस्ते').toJsonNetwork())}\n');
    await sender.flush();
    await until(() => received.isNotEmpty && otherFrames.isNotEmpty);
    expect(received.single.message, 'नमस्ते');
    final forwarded = jsonDecode(otherFrames.single) as Map;
    expect(forwarded['id'], 'relay');
    expect(forwarded['type'], 'emergency');
    expect(forwarded['language'], 'hi');
    expect(senderFrames, isEmpty);
    await server.send(message('control', 'hello'));
    await until(() => senderFrames.isNotEmpty && otherFrames.length == 2);
    expect(jsonDecode(senderFrames.single)['id'], 'control');
  });

  test('split Hindi UTF-8 and multiple packets preserve exact text', () async {
    final received = <SpeechMessage>[];
    server.onMessage = received.add;
    final sender = await connect();
    final packet = utf8.encode(
        '${jsonEncode(message('unicode', 'नमस्ते दुनिया').toJsonNetwork())}\n');
    final split = packet.indexWhere((byte) => byte >= 128) + 1;
    sender.add(packet.sublist(0, split));
    await sender.flush();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(received, isEmpty);
    sender.add(packet.sublist(split));
    sender.write('${jsonEncode(message('second', 'reply').toJsonNetwork())}\n');
    await sender.flush();
    await until(() => received.length == 2);
    expect(received.map((value) => value.message), ['नमस्ते दुनिया', 'reply']);
  });

  test('malformed UTF-8 is rejected without poisoning the next frame',
      () async {
    final received = <SpeechMessage>[];
    final statuses = <String>[];
    server.onMessage = received.add;
    server.onStatus = statuses.add;
    final sender = await connect();
    sender.add([0xc3, 10]);
    sender.write('${jsonEncode(message('valid', 'hello').toJsonNetwork())}\n');
    await sender.flush();
    await until(() => received.isNotEmpty);
    expect(received.single.id, 'valid');
    expect(statuses.any((value) => value.contains('invalid UTF-8')), isTrue);
  });

  test('oversized frames disconnect the peer and clear connection state',
      () async {
    final received = <SpeechMessage>[];
    final connections = <bool>[];
    server.onMessage = received.add;
    server.onConnectionChanged = connections.add;
    final sender = await connect();
    await until(() => server.isConnected);
    sender.add(List.filled(TcpMessageService.maxMessageBytes + 1, 65));
    await sender.flush();
    await until(() => !server.isConnected);
    expect(received, isEmpty);
    expect(connections.last, isFalse);
    expect(server.isActive, isTrue);
  });
}
