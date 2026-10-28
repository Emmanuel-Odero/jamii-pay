/// Mirrors `crates/server`'s `EventPreference` — see
/// `crates/server/src/routes/alerts.rs`.
class AlertPreference {
  const AlertPreference({
    required this.eventKey,
    required this.sms,
    required this.push,
    required this.email,
    required this.locked,
  });

  final String eventKey;
  final bool sms;
  final bool push;
  final bool email;
  final bool locked;

  /// Display label — matches the prototype's `SCR.alerts` copy exactly.
  String get label => switch (eventKey) {
        'money_arrives' => 'Money arrives',
        'money_sent' => 'Money sent',
        'claim_expiring' => 'Claim expiring',
        'group_vote_opened' => 'Group vote opened',
        'recovery_started' => 'Recovery started',
        _ => eventKey,
      };

  AlertPreference copyWith({bool? sms, bool? push, bool? email}) {
    return AlertPreference(
      eventKey: eventKey,
      sms: sms ?? this.sms,
      push: push ?? this.push,
      email: email ?? this.email,
      locked: locked,
    );
  }

  factory AlertPreference.fromJson(Map<String, dynamic> json) {
    return AlertPreference(
      eventKey: json['event_key'] as String,
      sms: json['sms'] as bool,
      push: json['push'] as bool,
      email: json['email'] as bool,
      locked: json['locked'] as bool,
    );
  }

  Map<String, dynamic> toJson() =>
      {'event_key': eventKey, 'sms': sms, 'push': push, 'email': email};
}
