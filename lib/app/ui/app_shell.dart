import 'dart:ui';
import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import 'screens/messages_screen.dart';
import 'screens/talk_screen.dart';
import 'widgets/operator_profile_sheet.dart';
import 'widgets/tactical_header.dart';

/// The 2-tab cockpit shell for Talk and Messages.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _hasPromptedSetup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstLaunchSetup();
    });
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      widget.controller.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.setMessagesVisible(false);
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.refreshBackgroundConnection();
    }
  }

  void _onControllerUpdate() {
    if (widget.controller.profileSetupNeeded && !_hasPromptedSetup) {
      _checkFirstLaunchSetup();
    }
  }

  void _checkFirstLaunchSetup() {
    if (_hasPromptedSetup || !mounted) return;
    if (widget.controller.profileSetupNeeded) {
      _hasPromptedSetup = true;
      OperatorProfileSheet.show(
        context,
        widget.controller,
        isFirstLaunch: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, _) {
        final List<Widget> screens = <Widget>[
          TalkScreen(controller: widget.controller),
          MessagesScreen(controller: widget.controller),
        ];

        return Scaffold(
          extendBody: true,
          body: Stack(
            children: <Widget>[
              IndexedStack(index: _currentIndex, children: screens),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: TacticalHeader(
                  controller: widget.controller,
                  activeTabTitle: _tabName(_currentIndex),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _TacticalBottomNav(
            currentIndex: _currentIndex,
            onSelect: (int index) {
              widget.controller.setMessagesVisible(index == 1);
              setState(() => _currentIndex = index);
            },
          ),
        );
      },
    );
  }

  String _tabName(int index) {
    switch (index) {
      case 0:
        return 'Talk';
      case 1:
        return 'Messages';
      default:
        return '';
    }
  }
}

class _TacticalBottomNav extends StatelessWidget {
  const _TacticalBottomNav({
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest.withValues(alpha: 0.95),
            border: const Border(
              top: BorderSide(color: AppColors.outline, width: 1),
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 4,
            top: 4,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _NavItem(
                icon: Icons.mic,
                label: 'Talk',
                selected: currentIndex == 0,
                onTap: () => onSelect(0),
              ),
              _NavItem(
                icon: Icons.chat_bubble_outline,
                selectedIcon: Icons.chat_bubble,
                label: 'Messages',
                selected: currentIndex == 1,
                onTap: () => onSelect(1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color =
        selected ? AppColors.primary : AppColors.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label tab',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    selected ? (selectedIcon ?? icon) : icon,
                    color: color,
                    size: 22,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label.toUpperCase(),
                    style: AppTypography.labelCaps.copyWith(
                      color: color,
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
