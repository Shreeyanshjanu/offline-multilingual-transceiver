import 'package:flutter/material.dart';

import '../../../state/app_controller.dart';
import '../../../theme/app_theme.dart';

class MessageComposer extends StatefulWidget {
  const MessageComposer({super.key, required this.controller});

  final AppController controller;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final TextEditingController _msgInputController = TextEditingController();

  @override
  void dispose() {
    _msgInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = widget.controller;
    const List<String> presets = <String>[
      '👍 I am OK',
      '🆘 Need Help',
      '📍 Arrived at Location',
      '📡 Check In',
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(top: BorderSide(color: AppColors.outline, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Horizontal Presets Action Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: presets.map((String text) {
                final bool isSos = text.contains('Need Help');
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: isSos
                        ? AppColors.errorContainer.withValues(alpha: 0.45)
                        : AppColors.surfaceContainerLow,
                    side: BorderSide(
                      color: isSos
                          ? AppColors.error
                          : AppColors.outline.withValues(alpha: 0.7),
                      width: isSos ? 1.2 : 0.8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    label: Text(
                      text,
                      style: AppTypography.bodySm.copyWith(
                        fontSize: 12,
                        fontWeight: isSos ? FontWeight.w700 : FontWeight.w500,
                        color: isSos ? AppColors.error : AppColors.onSurface,
                      ),
                    ),
                    onPressed: () {
                      if (isSos) {
                        controller.sendEmergencyPreset();
                      } else {
                        controller.sendTypedMessage(text);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // Message Input Field
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              2,
              16,
              MediaQuery.paddingOf(context).bottom + 10,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: TextField(
                      controller: _msgInputController,
                      decoration: const InputDecoration(
                        hintText: 'Type a dispatch message...',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (String val) {
                        if (val.trim().isNotEmpty) {
                          controller.sendTypedMessage(val.trim());
                          _msgInputController.clear();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                      elevation: 0,
                    ),
                    onPressed: () {
                      final String val = _msgInputController.text.trim();
                      if (val.isNotEmpty) {
                        controller.sendTypedMessage(val);
                        _msgInputController.clear();
                      }
                    },
                    child: const Icon(Icons.arrow_upward, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
