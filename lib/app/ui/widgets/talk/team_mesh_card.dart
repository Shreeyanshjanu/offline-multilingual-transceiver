import 'package:flutter/material.dart';

import '../../../models/connection_config.dart';
import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';
import '../pulsing_dot.dart';
import 'mesh_role_selector.dart';

class TeamMeshCard extends StatefulWidget {
  const TeamMeshCard({super.key, required this.controller});

  final AppController controller;

  @override
  State<TeamMeshCard> createState() => _TeamMeshCardState();
}

class _TeamMeshCardState extends State<TeamMeshCard> {
  late final TextEditingController _hostController;
  String? _gatewayStatusMessage;
  bool _isGatewayError = false;
  bool _isDetectingGateway = false;

  @override
  void initState() {
    super.initState();
    final String host = widget.controller.connectionConfig.host;
    _hostController = TextEditingController(
      text: host.isEmpty ? '' : host,
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _autoDetectGateway({bool showFeedback = true}) async {
    if (_isDetectingGateway) return;
    setState(() {
      _isDetectingGateway = true;
    });

    final String? gateway = await widget.controller.fetchWifiGatewayIp();
    if (!mounted) return;

    if (gateway != null && gateway.isNotEmpty) {
      setState(() {
        _hostController.text = gateway;
        _gatewayStatusMessage = 'Gateway found: $gateway';
        _isGatewayError = false;
        _isDetectingGateway = false;
      });
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-detected Leader Gateway: $gateway'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
      }
    } else {
      setState(() {
        _gatewayStatusMessage =
            '⚠️ You are not connected to the operator. Please check Wi-Fi.';
        _isGatewayError = true;
        _isDetectingGateway = false;
      });
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'You are not connected to the operator. Please check Wi-Fi.'),
            duration: Duration(seconds: 3),
            backgroundColor: AppColors.errorContainer,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = widget.controller;
    final ConnectionConfig config = controller.connectionConfig;
    final bool connected = controller.isConnected;

    if (controller.isNetworkActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: <Widget>[
            const PulsingDot(color: AppColors.tertiary, size: 8, ping: true),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    controller.backgroundConnection.state == 'reconnecting'
                        ? 'RECONNECTING'
                        : config.runAsServer
                            ? 'HOST MESH ACTIVE'
                            : 'SQUAD LINKED',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.tertiary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    controller.backgroundConnection.state == 'reconnecting'
                        ? 'Retrying the local network connection'
                        : config.runAsServer
                            ? (connected
                                ? 'Peers connected on port 7070'
                                : 'Waiting for peers on port 7070')
                            : 'Connected to ${config.host}',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => controller.disconnect(),
                  child: Text(
                    'DISCONNECT',
                    style: AppTypography.labelCaps.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.wifi_tethering,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Text(
                  'TEAM MESH NETWORK',
                  style: AppTypography.labelCaps.copyWith(fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'OFFLINE DIRECT',
                  textAlign: TextAlign.end,
                  style: AppTypography.telemetrySm.copyWith(
                    fontSize: 10,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          MeshRoleSelector(
            config: config,
            onRoleChanged: (bool runAsServer) {
              controller.updateConnectionConfig(
                  config.copyWith(runAsServer: runAsServer));
              if (!runAsServer) _autoDetectGateway(showFeedback: true);
            },
          ),
          if (!config.runAsServer) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: TextField(
                controller: _hostController,
                style: AppTypography.telemetryMd.copyWith(fontSize: 13),
                decoration: InputDecoration(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  hintText: 'Leader IP address',
                  prefixIcon: const Icon(Icons.router,
                      size: 16, color: AppColors.outlineVariant),
                  suffixIcon: Semantics(
                    button: true,
                    label: 'Detect Wi-Fi Gateway IP from Android',
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: 48, minWidth: 48),
                      child: IconButton(
                        icon: _isDetectingGateway
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.secondary,
                                ),
                              )
                            : const Icon(Icons.sync,
                                size: 18, color: AppColors.secondary),
                        tooltip: 'Auto-detect Leader Gateway IP',
                        onPressed: () => _autoDetectGateway(showFeedback: true),
                      ),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: _isGatewayError
                          ? AppColors.error.withValues(alpha: 0.8)
                          : AppColors.outline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: _isGatewayError
                          ? AppColors.error
                          : AppColors.secondary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            if (_gatewayStatusMessage != null) ...<Widget>[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _isGatewayError
                      ? AppColors.errorContainer.withValues(alpha: 0.35)
                      : AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _isGatewayError
                        ? AppColors.error.withValues(alpha: 0.6)
                        : AppColors.tertiary.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _isGatewayError
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      size: 14,
                      color: _isGatewayError
                          ? AppColors.error
                          : AppColors.tertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _gatewayStatusMessage!,
                        style: AppTypography.labelCaps.copyWith(
                          color: _isGatewayError
                              ? AppColors.onErrorContainer
                              : AppColors.tertiary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),

          // Connect Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: config.runAsServer
                    ? AppColors.tertiary
                    : AppColors.secondary,
                foregroundColor: config.runAsServer
                    ? AppColors.onTertiary
                    : AppColors.onSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: () async {
                if (!config.runAsServer &&
                    _hostController.text.trim().isEmpty) {
                  await _autoDetectGateway(showFeedback: true);
                  if (!mounted) return;
                  if (_isGatewayError || _hostController.text.trim().isEmpty) {
                    return;
                  }
                }
                controller.updateConnectionConfig(
                  config.copyWith(
                    host: _hostController.text.trim().isEmpty
                        ? '192.168.4.1'
                        : _hostController.text.trim(),
                    port: ConnectionConfig.networkPort,
                  ),
                );
                await controller.connect();
              },
              icon: Icon(
                config.runAsServer ? Icons.sensors : Icons.link,
                size: 16,
                color: config.runAsServer
                    ? AppColors.onTertiary
                    : AppColors.onSecondary,
              ),
              label: Text(
                config.runAsServer ? 'START LEADER MESH' : 'CONNECT TO LEADER',
                style: AppTypography.labelCaps.copyWith(
                  color: config.runAsServer
                      ? AppColors.onTertiary
                      : AppColors.onSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
