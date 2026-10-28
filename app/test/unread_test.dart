import 'package:flutter_test/flutter_test.dart';
import 'package:jamiipay/src/models/conversation.dart';
import 'package:jamiipay/src/state/wallet_store.dart';

Conversation _thread({
  required String id,
  required DateTime at,
  String sender = 'other-wallet',
}) =>
    Conversation(
      kind: ConversationKind.direct,
      id: id,
      name: 'Test Thread',
      lastMessage: 'hello',
      lastMessageAt: at,
      lastMessageSenderWalletId: sender,
      isContact: true,
    );

void main() {
  group('Unread engine', () {
    test('unknown thread within 72h from someone else is unread', () {
      final store = WalletStore();
      final c = _thread(
          id: 't1', at: DateTime.now().subtract(const Duration(hours: 2)));
      store.conversations = [c];
      expect(store.isUnread(c), isTrue);
      expect(store.unreadChatCount, 1);
      expect(store.bellBadgeCount, 1);
    });

    test('unknown thread older than 72h is baselined read', () {
      final store = WalletStore();
      final c = _thread(
          id: 't1', at: DateTime.now().subtract(const Duration(days: 10)));
      store.conversations = [c];
      expect(store.isUnread(c), isFalse);
      expect(store.unreadChatCount, 0);
    });

    test('recent message from someone else is unread', () {
      final store = WalletStore();
      final c = _thread(
          id: 't1', at: DateTime.now().subtract(const Duration(minutes: 5)));
      // No wallet loaded -> _wallet?.id is null, sender counts as other.
      store.conversations = [c];
      expect(store.isUnread(c), isTrue);
    });

    test('opening a chat marks it read and clears the dot', () async {
      final store = WalletStore();
      final c = _thread(
          id: 't1', at: DateTime.now().subtract(const Duration(minutes: 5)));
      store.conversations = [c];
      expect(store.isUnread(c), isTrue);
      await store.markConversationRead(c);
      expect(store.isUnread(c), isFalse);
      expect(store.unreadChatCount, 0);
    });

    test('newer message after a mark re-dots', () async {
      final store = WalletStore();
      final old = _thread(
          id: 't1', at: DateTime.now().subtract(const Duration(hours: 3)));
      await store.markConversationRead(old);
      final fresh = _thread(
          id: 't1', at: DateTime.now().subtract(const Duration(minutes: 1)));
      store.conversations = [fresh];
      expect(store.isUnread(fresh), isTrue);
    });
  });
}
