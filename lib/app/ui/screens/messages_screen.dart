import 'package:flutter/material.dart';

import '../../models/speech_message.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/messages/dispatch_message_card.dart';
import '../widgets/messages/message_composer.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final List<SpeechMessage> messages = controller.history;

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          // Scrollable messages stream
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 76, 16, 12),
              children: <Widget>[
                // Header Action Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'RECENT DISPATCHES',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.headlineSm,
                          ),
                          Text(
                            messages.isEmpty
                                ? 'Offline radio storage clear'
                                : '${messages.length} message${messages.length == 1 ? '' : 's'} recorded',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (messages.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.onSurfaceVariant,
                          backgroundColor: AppColors.surfaceContainerHigh,
                          minimumSize: const Size(40, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: controller.clearHistory,
                        icon: const Icon(Icons.delete_sweep, size: 16),
                        label: Text('Clear',
                            style: AppTypography.bodySm.copyWith(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // Message bubbles stream
                if (messages.isEmpty)
                  _buildEmptyState()
                else
                  for (final SpeechMessage msg in messages) ...<Widget>[
                    DispatchMessageCard(msg: msg, controller: controller),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),

          // Sticky Bottom Compose Bar
          MessageComposer(controller: controller),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: <Widget>[
            const Icon(Icons.chat_bubble_outline,
                size: 48, color: AppColors.outlineVariant),
            const SizedBox(height: 8),
            Text('No messages yet', style: AppTypography.headlineSm),
            const SizedBox(height: 4),
            Text('Mesh transmissions will log here offline',
                style: AppTypography.bodySm),
          ],
        ),
      ),
    );
  }
}
