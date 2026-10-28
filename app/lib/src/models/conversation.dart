/// Mirrors `crates/server`'s `ConversationResponse` — see
/// `crates/server/src/routes/messages.rs`'s `list_conversations`.
enum ConversationKind { direct, group }

class Conversation {
  const Conversation({
    required this.kind,
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageSenderWalletId,
    required this.isContact,
  });

  final ConversationKind kind;

  /// The other wallet's id (direct) or the group's id.
  final String id;
  final String name;
  final String lastMessage;
  final DateTime lastMessageAt;

  /// Who sent [lastMessage] — lets `WalletStore`'s notification poll
  /// tell "someone just messaged me" apart from "I just sent this".
  final String lastMessageSenderWalletId;

  /// Only meaningful for [ConversationKind.direct] — `null` for groups
  /// (a group is never "spam", you were invited into it by name). A
  /// direct sender not in this wallet's Contacts is exactly the "Spam"
  /// case `ChatInboxScreen` splits out.
  final bool? isContact;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      kind: json['kind'] == 'group'
          ? ConversationKind.group
          : ConversationKind.direct,
      id: json['id'] as String,
      name: json['name'] as String,
      lastMessage: json['last_message'] as String,
      lastMessageAt: DateTime.parse(json['last_message_at'] as String),
      lastMessageSenderWalletId:
          json['last_message_sender_wallet_id'] as String,
      isContact: json['is_contact'] as bool?,
    );
  }
}
