import 'package:flutter/material.dart';

import '../../models/operation_mode.dart';
import '../../state/app_controller.dart';
import '../widgets/model_status_badge.dart';
import '../widgets/talk/team_mesh_card.dart';
import '../widgets/talk/talk_mode_switcher.dart';
import '../widgets/talk/talk_ptt_station.dart';
import '../widgets/talk/transmission_monitor.dart';
import '../widgets/talk/emergency_sos_bar.dart';
import '../widgets/talk/connection_status_strip.dart';

class TalkScreen extends StatelessWidget {
  const TalkScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final bool isHandsFree =
        controller.operationMode == OperationMode.continuous;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 74, 16, 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 1. Team Mesh Network Card
            TeamMeshCard(controller: controller),
            const SizedBox(height: 8),
            ConnectionStatusStrip(controller: controller),
            const SizedBox(height: 12),

            // 2. Walkie-Talkie Operation Mode Switcher
            TalkModeSwitcher(controller: controller, isHandsFree: isHandsFree),
            const SizedBox(height: 10),

            // 2b. Tactical Speech Model Status & Loading Notice
            ModelStatusBadge(controller: controller),
            const SizedBox(height: 12),

            // 3. Central Push-to-Talk Station
            TalkPttStation(controller: controller, isHandsFree: isHandsFree),
            const SizedBox(height: 16),

            // 4. Unified Transmission Monitor (Waveform + Live Transcript)
            TransmissionMonitor(controller: controller),
            const SizedBox(height: 16),

            // 5. Compact Emergency SOS Broadcast Trigger
            EmergencySosBar(controller: controller),
          ],
        ),
      ),
    );
  }
}
