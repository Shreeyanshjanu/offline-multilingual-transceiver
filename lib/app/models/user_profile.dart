class UserProfile {
  const UserProfile({
    required this.callsign,
    required this.role,
    this.squad = 'Alpha Squad',
    this.notes = '',
    this.shareLocation = true,
    this.isConfigured = false,
  });

  final String callsign;
  final String role;
  final String squad;
  final String notes;
  final bool shareLocation;
  final bool isConfigured;

  static const List<String> standardRoles = <String>[
    'Squad Leader',
    'Medic',
    'Search & Rescue',
    'Scout',
    'Comms Officer',
    'Field Operator',
  ];

  static const UserProfile initial = UserProfile(
    callsign: 'Operator-1',
    role: 'Field Operator',
    squad: 'Alpha Squad',
    notes: '',
    shareLocation: true,
    isConfigured: false,
  );

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'callsign': callsign,
      'role': role,
      'squad': squad,
      'notes': notes,
      'shareLocation': shareLocation,
      'isConfigured': isConfigured,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      callsign: (json['callsign'] ?? json['name'] ?? 'Operator-1').toString(),
      role: (json['role'] ?? 'Field Operator').toString(),
      squad: (json['squad'] ?? 'Alpha Squad').toString(),
      notes: (json['notes'] ?? '').toString(),
      shareLocation:
          json['shareLocation'] is bool ? json['shareLocation'] as bool : true,
      isConfigured:
          json['isConfigured'] is bool ? json['isConfigured'] as bool : true,
    );
  }

  UserProfile copyWith({
    String? callsign,
    String? role,
    String? squad,
    String? notes,
    bool? shareLocation,
    bool? isConfigured,
  }) {
    return UserProfile(
      callsign: callsign ?? this.callsign,
      role: role ?? this.role,
      squad: squad ?? this.squad,
      notes: notes ?? this.notes,
      shareLocation: shareLocation ?? this.shareLocation,
      isConfigured: isConfigured ?? this.isConfigured,
    );
  }

  @override
  String toString() =>
      'UserProfile(callsign: $callsign, role: $role, squad: $squad, shareLocation: $shareLocation, configured: $isConfigured)';
}
