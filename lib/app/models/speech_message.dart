import 'gps_location.dart';

enum MessageType { speech, emergency, system }

enum MessageOrigin { local, remote, system }

MessageType messageTypeFromWire(String rawType) {
  switch (rawType) {
    case 'speech':
      return MessageType.speech;
    case 'emergency':
      return MessageType.emergency;
    default:
      return MessageType.system;
  }
}

String messageTypeToWire(MessageType type) {
  switch (type) {
    case MessageType.speech:
      return 'speech';
    case MessageType.emergency:
      return 'emergency';
    case MessageType.system:
      return 'system';
  }
}

class SpeechMessage {
  const SpeechMessage({
    required this.id,
    required this.type,
    required this.languageCode,
    required this.message,
    required this.timestamp,
    required this.origin,
    this.senderCallsign,
    this.senderRole,
    this.senderSquad,
    this.location,
  });

  final String id;
  final MessageType type;
  final String languageCode;
  final String message;
  final DateTime timestamp;
  final MessageOrigin origin;
  final String? senderCallsign;
  final String? senderRole;
  final String? senderSquad;
  final GpsLocation? location;

  factory SpeechMessage.fromJson(
    Map<String, dynamic> json, {
    MessageOrigin origin = MessageOrigin.remote,
  }) {
    final Object? timestampRaw = json['timestamp'] ?? json['timestampEpochMs'];
    final int timestampMs = switch (timestampRaw) {
      int value => value,
      String value =>
        int.tryParse(value) ?? DateTime.now().millisecondsSinceEpoch,
      _ => DateTime.now().millisecondsSinceEpoch,
    };

    String? callsign;
    String? role;
    String? squad;
    if (json['sender'] is Map) {
      final Map<dynamic, dynamic> s = json['sender'] as Map;
      callsign = (s['callsign'] ?? s['name'])?.toString();
      role = s['role']?.toString();
      squad = s['squad']?.toString();
    } else {
      callsign = (json['senderCallsign'] ?? json['senderName'])?.toString();
      role = json['senderRole']?.toString();
      squad = json['senderSquad']?.toString();
    }

    GpsLocation? loc;
    if (json['location'] is Map) {
      loc = GpsLocation.fromJson(
        Map<String, dynamic>.from(json['location'] as Map),
      );
    } else if (json['lat'] != null && json['lng'] != null) {
      loc = GpsLocation.fromJson(json);
    }

    return SpeechMessage(
      id: (json['id'] ?? DateTime.now().microsecondsSinceEpoch).toString(),
      type: messageTypeFromWire((json['type'] ?? 'speech').toString()),
      languageCode: (json['language'] ?? 'en').toString(),
      message: (json['message'] ?? '').toString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      origin: origin,
      senderCallsign: callsign,
      senderRole: role,
      senderSquad: squad,
      location: loc,
    );
  }

  Map<String, dynamic> toJsonNetwork() {
    final Map<String, dynamic> payload = <String, dynamic>{
      'id': id,
      'type': messageTypeToWire(type),
      'language': languageCode,
      'message': message,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };

    if (senderCallsign != null || senderRole != null || senderSquad != null) {
      payload['sender'] = <String, dynamic>{
        if (senderCallsign != null) 'callsign': senderCallsign,
        if (senderRole != null) 'role': senderRole,
        if (senderSquad != null) 'squad': senderSquad,
      };
    }

    if (location != null) {
      payload['location'] = location!.toJson();
    }

    return payload;
  }

  SpeechMessage copyWith({
    MessageType? type,
    String? languageCode,
    String? message,
    DateTime? timestamp,
    MessageOrigin? origin,
    String? senderCallsign,
    String? senderRole,
    String? senderSquad,
    GpsLocation? location,
  }) {
    return SpeechMessage(
      id: id,
      type: type ?? this.type,
      languageCode: languageCode ?? this.languageCode,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      origin: origin ?? this.origin,
      senderCallsign: senderCallsign ?? this.senderCallsign,
      senderRole: senderRole ?? this.senderRole,
      senderSquad: senderSquad ?? this.senderSquad,
      location: location ?? this.location,
    );
  }
}
