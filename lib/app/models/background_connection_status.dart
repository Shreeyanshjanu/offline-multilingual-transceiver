class BackgroundConnectionStatus {
  const BackgroundConnectionStatus({
    this.supported = false,
    this.enabled = false,
    this.serviceRunning = false,
    this.startPending = false,
    this.connectionRequested = false,
    this.connected = false,
    this.state = 'disconnected',
    this.runAsServer = true,
    this.host = '',
    this.port = 7070,
    this.generation = 0,
    this.revision = 0,
    this.unreadCount = 0,
    this.notificationsAllowed = true,
    this.emergencyVolumeBoost = true,
    this.languageCode,
  });

  final bool supported, enabled, serviceRunning, startPending;
  final bool connectionRequested, connected, runAsServer;
  final bool notificationsAllowed, emergencyVolumeBoost;
  final String state, host;
  final String? languageCode;
  final int port, generation, revision, unreadCount;

  factory BackgroundConnectionStatus.fromMap(Map<dynamic, dynamic> map) =>
      BackgroundConnectionStatus(
        supported: true,
        enabled: map['backgroundEnabled'] == true,
        serviceRunning: map['serviceRunning'] == true,
        startPending: map['startPending'] == true,
        connectionRequested: map['connectionRequested'] == true,
        connected: map['connected'] == true,
        state: map['state']?.toString() ?? 'disconnected',
        runAsServer: map['runAsServer'] != false,
        host: map['host']?.toString() ?? '',
        port: (map['port'] as num?)?.toInt() ?? 7070,
        generation: (map['generation'] as num?)?.toInt() ?? 0,
        revision: (map['revision'] as num?)?.toInt() ?? 0,
        unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
        notificationsAllowed: map['notificationsAllowed'] != false,
        emergencyVolumeBoost: map['emergencyVolumeBoost'] != false,
        languageCode: map['languageCode']?.toString(),
      );
}
