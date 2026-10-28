/// Mirrors `crates/server`'s `ContactResponse` — see
/// `crates/server/src/routes/contacts.rs`.
enum ContactKind { handle, phone, email }

final _emailPattern = RegExp(r'@');
final _phonePattern = RegExp(r'^[+\d\s]+$');

/// Live kind-detection shared by the Add-contact form and Send's
/// recipient field — matches `designs/jammii-pay-prototype.html`'s rules
/// exactly: `@` → email, `/^[+\d\s]+$/` → phone, else treated as a
/// payment ID (only ever confirmed server-side, since only the server
/// knows what's actually registered).
ContactKind detectContactKind(String value) {
  final v = value.trim();
  if (_emailPattern.hasMatch(v)) return ContactKind.email;
  if (v.isNotEmpty && _phonePattern.hasMatch(v)) return ContactKind.phone;
  return ContactKind.handle;
}

class Contact {
  const Contact({
    required this.id,
    required this.name,
    required this.kind,
    required this.value,
    required this.onJamii,
    required this.linkedWalletId,
  });

  final String id;
  final String name;
  final ContactKind kind;
  final String value;

  /// The prototype's "ON JAMII"/"INVITE" chip — true only for `handle`-kind
  /// contacts the server actually resolved to a real wallet.
  final bool onJamii;

  /// Non-null exactly when [onJamii] — the wallet chat (`ChatScreen`)
  /// opens against. An off-Jamii contact has nowhere to receive a message.
  final String? linkedWalletId;

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: ContactKind.values.byName(json['contact_kind'] as String),
      value: json['contact_value'] as String,
      onJamii: json['on_jamii'] as bool,
      linkedWalletId: json['linked_wallet_id'] as String?,
    );
  }
}
