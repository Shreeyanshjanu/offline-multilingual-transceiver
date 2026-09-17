part of 'app_controller.dart';

extension _ConnectionCoordination on AppController {
  void _applyBackgroundStatus(Map<dynamic, dynamic> map,
      {bool restoreConfig = false}) {
    if (_disposed) return;
    final next = BackgroundConnectionStatus.fromMap(map);
    if (next.generation < _backgroundConnection.generation) return;
    if (next.generation == _backgroundConnection.generation &&
        next.revision < _backgroundConnection.revision) {
      return;
    }
    final wasUsingNativeConnection = _usingNativeConnection;
    _backgroundConnection = next;
    _emergencyVolumeBoostEnabled = next.emergencyVolumeBoost;
    if (next.serviceRunning || next.startPending) _usingNativeConnection = true;
    if (!next.connectionRequested &&
        !next.serviceRunning &&
        !next.startPending) {
      _usingNativeConnection = false;
    }
    if (restoreConfig || next.serviceRunning || next.startPending) {
      _connectionConfig = ConnectionConfig(
          host: next.host, port: next.port, runAsServer: next.runAsServer);
    }
    if (wasUsingNativeConnection || _usingNativeConnection || next.enabled) {
      _isConnected = next.connected;
    }
    _notifyStateChanged();
  }

  Future<void> _restoreBackgroundConnection(
      {bool restoreConfig = false}) async {
    try {
      final status = await _nativeBridgeService.getBackgroundConnectionStatus();
      if (status != null) {
        _applyBackgroundStatus(status, restoreConfig: restoreConfig);
      }
    } catch (_) {
      if (!_disposed) _status = 'Could not read background connection status';
    }
  }

  Future<void> _restoreBackgroundMessages() async {
    if (!_backgroundConnection.supported) return;
    try {
      final records = await _nativeBridgeService.getBackgroundMessages();
      if (_disposed) return;
      for (final record in records) {
        if (record is Map) _ingestNativeMessage(record);
      }
    } catch (_) {
      if (!_disposed) _status = 'Could not load background messages';
    }
  }

  Future<void> _connectConfigured() async {
    if (_connectionBusy || _disposed) return;
    final command = ++_connectionCommand;
    _connectionBusy = true;
    _notifyStateChanged();
    try {
      if (_backgroundConnection.enabled) {
        await _connectNative(command);
      } else {
        if (_connectionConfig.runAsServer) {
          await _tcpMessageService.startServer(
              port: ConnectionConfig.networkPort);
        } else {
          await _tcpMessageService.connect(
              host: _connectionConfig.host, port: ConnectionConfig.networkPort);
        }
        if (command != _connectionCommand || _disposed) {
          await _tcpMessageService.close();
          return;
        }
        _isConnected = _tcpMessageService.isConnected;
        _status = _connectionConfig.runAsServer
            ? 'Server listening on port 7070'
            : 'Connected to ${_connectionConfig.host}:7070';
      }
    } catch (error) {
      if (command == _connectionCommand && !_disposed) {
        _status = 'Connection failed: $error';
        await _restoreBackgroundConnection();
      }
    } finally {
      if (command == _connectionCommand) _connectionBusy = false;
      _notifyStateChanged();
    }
  }

  Future<void> _connectNative(int command) async {
    if (_backgroundConnection.serviceRunning ||
        _backgroundConnection.startPending) {
      return;
    }
    final config = _connectionConfig;
    // Complete the handoff before starting a second socket owner.
    await _tcpMessageService.close();
    if (command != _connectionCommand || _disposed) return;
    await _nativeBridgeService.requestConnectionNotifications();
    if (command != _connectionCommand || _disposed) return;
    _usingNativeConnection = true;
    final status = await _nativeBridgeService.startBackgroundConnection(
      runAsServer: config.runAsServer,
      host: config.host,
      port: ConnectionConfig.networkPort,
      languageCode: _selectedLanguage.code,
    );
    if (command != _connectionCommand || _disposed) return;
    _applyBackgroundStatus(status);
    _status = 'Background connection starting';
  }

  Future<void> _disconnectConfigured() async {
    ++_connectionCommand;
    _connectionBusy = true;
    _notifyStateChanged();
    try {
      // Native cancellation persists connectionRequested=false before replying.
      if (_backgroundConnection.supported) {
        _applyBackgroundStatus(
            await _nativeBridgeService.stopBackgroundConnection());
      }
      await _tcpMessageService.close();
      _usingNativeConnection = false;
      _isConnected = false;
      _status = 'Disconnected';
    } catch (_) {
      _status =
          'Could not stop the connection. Use Disconnect in the notification to retry.';
      await _restoreBackgroundConnection();
    } finally {
      _connectionBusy = false;
      _notifyStateChanged();
    }
  }

  Future<void> _setBackgroundEnabled(bool enabled) async {
    if (_connectionBusy || _disposed) return;
    final command = ++_connectionCommand;
    final wasActive = isNetworkActive;
    _connectionBusy = true;
    _notifyStateChanged();
    try {
      final status =
          await _nativeBridgeService.setBackgroundConnectionEnabled(enabled);
      if (command != _connectionCommand || _disposed) return;
      _applyBackgroundStatus(status);
      if (enabled && wasActive) {
        await _connectNative(command);
      } else if (enabled) {
        await _nativeBridgeService.requestConnectionNotifications();
        await _restoreBackgroundConnection();
        _status = 'Background connection enabled. Tap Connect to start.';
      } else {
        await _tcpMessageService.close();
        _usingNativeConnection = false;
        _isConnected = false;
        _status =
            'Background connection stopped. Tap Connect for foreground use.';
      }
    } catch (error) {
      if (!_disposed) {
        _status = 'Could not change background connection: $error';
      }
      await _restoreBackgroundConnection();
    } finally {
      if (command == _connectionCommand) _connectionBusy = false;
      _notifyStateChanged();
    }
  }

  void _ingestNativeMessage(Map<dynamic, dynamic> record) {
    if (_disposed || record['wire'] is! Map) return;
    final message = SpeechMessage.fromJson(
        Map<String, dynamic>.from(record['wire'] as Map),
        origin: record['origin'] == 'local'
            ? MessageOrigin.local
            : MessageOrigin.remote);
    final firstObservation = _nativeMessageIds.add(message.id);
    final index = _history.indexWhere((item) => item.id == message.id);
    if (index < 0) {
      _history.insert(0, message);
    } else {
      _history[index] = message;
    }
    _rememberMessage(message);
    if (message.origin == MessageOrigin.remote) {
      for (final entry in <String, BenchmarkEvent>{
        'receivedAt': BenchmarkEvent.t4MessageReceived,
        'tts_started': BenchmarkEvent.t5TtsStart,
        'audio_started': BenchmarkEvent.t6AudioFirstFrame
      }.entries) {
        final timestamp = record[entry.key];
        if (timestamp is num) {
          _benchmarkTracker.mark(message.id, entry.value,
              at: DateTime.fromMillisecondsSinceEpoch(timestamp.toInt()));
        }
      }
      if (firstObservation) {
        _recordBenchmark(_benchmarkTracker.snapshotFor(message.id,
            audioDuration: _estimateAudioDuration(message.message)));
      }
    }
    _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (_messagesVisible && record['read'] != true) {
      unawaited(_acknowledgeNativeMessages([message.id]));
    }
    _notifyStateChanged();
    // Playback is already owned by the service. Never call speakText here.
  }

  Future<void> _acknowledgeNativeMessages(List<String> ids) async {
    if (!_backgroundConnection.supported || ids.isEmpty) return;
    try {
      await _nativeBridgeService.acknowledgeBackgroundMessages(ids);
    } catch (_) {/* Keep messages unread if persistence is unavailable. */}
  }
}
