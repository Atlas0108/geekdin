import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.at,
  });

  final String id;
  final String text;
  final String senderId;
  final DateTime? at;

  static ChatMessage fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final t = data['at'];
    DateTime? at;
    if (t is Timestamp) {
      at = t.toDate();
    }
    return ChatMessage(
      id: doc.id,
      text: (data['text'] as String?)?.trim() ?? '',
      senderId: (data['senderId'] as String?) ?? '',
      at: at,
    );
  }
}
