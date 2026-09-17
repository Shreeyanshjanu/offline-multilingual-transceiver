import 'dart:ui';
import 'package:flutter/material.dart';

import '../../models/gps_location.dart';
import '../../models/user_profile.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import 'profile/operator_identity_fields.dart';
import 'profile/operator_gps_card.dart';

/// Modal bottom sheet allowing users to register or edit their tactical operator identity
/// and inspect offline GPS telemetry.
class OperatorProfileSheet extends StatefulWidget {
  const OperatorProfileSheet({
    super.key,
    required this.controller,
    this.isFirstLaunch = false,
  });

  final AppController controller;
  final bool isFirstLaunch;

  static Future<void> show(
    BuildContext context,
    AppController controller, {
    bool isFirstLaunch = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: !isFirstLaunch,
      enableDrag: !isFirstLaunch,
      builder: (BuildContext ctx) => OperatorProfileSheet(
        controller: controller,
        isFirstLaunch: isFirstLaunch,
      ),
    );
  }

  @override
  State<OperatorProfileSheet> createState() => _OperatorProfileSheetState();
}

class _OperatorProfileSheetState extends State<OperatorProfileSheet> {
  late final TextEditingController _callsignCtrl;
  late final TextEditingController _squadCtrl;
  late String _selectedRole;
  late bool _shareLocation;
  bool _isRefreshingGps = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final UserProfile profile = widget.controller.userProfile;
    _callsignCtrl = TextEditingController(
      text:
          widget.isFirstLaunch && !profile.isConfigured ? '' : profile.callsign,
    );
    _squadCtrl = TextEditingController(text: profile.squad);
    _selectedRole = profile.role;
    _shareLocation = profile.shareLocation;
  }

  @override
  void dispose() {
    _callsignCtrl.dispose();
    _squadCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshGps() async {
    setState(() => _isRefreshingGps = true);
    await widget.controller.refreshLocation(requestPermission: true);
    if (mounted) {
      setState(() => _isRefreshingGps = false);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final String callsign = _callsignCtrl.text.trim();
    if (callsign.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an operator callsign or name'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final UserProfile updated = widget.controller.userProfile.copyWith(
      callsign: callsign,
      role: _selectedRole,
      squad: _squadCtrl.text.trim().isEmpty
          ? 'Alpha Squad'
          : _squadCtrl.text.trim(),
      shareLocation: _shareLocation,
      isConfigured: true,
    );

    setState(() => _isSaving = true);
    try {
      await widget.controller.saveUserProfile(updated);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not save your profile. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = widget.controller;
    final GpsLocation? location = controller.currentLocation;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.90,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest.withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.outline),
          ),
          padding: EdgeInsets.only(
            top: 12,
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom +
                MediaQuery.viewInsetsOf(context).bottom +
                16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Drag handle
                if (!widget.isFirstLaunch)
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Sheet Header
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.6),
                        ),
                      ),
                      child: const Icon(
                        Icons.person_pin,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.isFirstLaunch
                                ? 'FIRST-TIME OPERATOR SETUP'
                                : 'OPERATOR IDENTITY & TELEMETRY',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.primary,
                              letterSpacing: 1.0,
                            ),
                          ),
                          Text(
                            widget.isFirstLaunch
                                ? 'Initialize Callsign & Role'
                                : 'Radio Identity Settings',
                            style: AppTypography.headlineSm,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                OperatorIdentityFields(
                  callsignController: _callsignCtrl,
                  squadController: _squadCtrl,
                  selectedRole: _selectedRole,
                  onRoleChanged: (String role) =>
                      setState(() => _selectedRole = role),
                ),
                const SizedBox(height: 18),

                OperatorGpsCard(
                  location: location,
                  shareLocation: _shareLocation,
                  isRefreshing: _isRefreshingGps,
                  onRefresh: _refreshGps,
                  onShareLocationChanged: (bool value) =>
                      setState(() => _shareLocation = value),
                ),
                const SizedBox(height: 24),

                // Save button
                Semantics(
                  button: true,
                  label: widget.isFirstLaunch
                      ? 'Save and enter transceiver'
                      : 'Save profile changes',
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isSaving ? null : _save,
                      child: Text(
                        widget.isFirstLaunch
                            ? 'CONFIRM & ENTER TRANSCEIVER'
                            : 'SAVE PROFILE CHANGES',
                        style: AppTypography.labelCaps.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
