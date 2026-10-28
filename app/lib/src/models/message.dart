/// Mirrors `crates/server`'s `MessageResponse` — see
/// `crates/server/src/routes/messages.rs`. Capped at 66 characters
/// server-side too, not just in the compose field: this is a payments
/// app, not a social app — chat is for a quick nudge, not a conversation.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderWalletId,
    required this.senderName,
    required this.body,
    required this.replyToId,
    required this.replyToPreview,
    required this.pinned,
    required this.createdAt,
  });

  final String id;
  final String senderWalletId;
  final String senderName;
  final String body;
  final String? replyToId;
  final String? replyToPreview;
  final bool pinned;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      senderWalletId: json['sender_wallet_id'] as String,
      senderName: json['sender_name'] as String,
      body: json['body'] as String,
      replyToId: json['reply_to_id'] as String?,
      replyToPreview: json['reply_to_preview'] as String?,
      pinned: json['pinned'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
