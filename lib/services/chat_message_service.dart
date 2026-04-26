import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 1:1 text chat stored at a single canonical path so both users read the same thread:
/// `users/{minUid}/chats/{maxUid}/messages/{messageId}` (uids sorted lexicographically).
/// Thread summary docs remain at `users/{me}/chats/{other}` for the Messages list.
abstract final class ChatMessageService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// (firstUid, secondUid) with `first < second` in string order.
  static (String, String) canonicalPair(String a, String b) {
    if (a.compareTo(b) < 0) {
      return (a, b);
    }
    return (b, a);
  }

  static CollectionReference<Map<String, dynamic>> _messages(
    String a,
    String b,
  ) {
    final (c1, c2) = canonicalPair(a, b);
    return _db
        .collection('users')
        .doc(c1)
        .collection('chats')
        .doc(c2)
        .collection('messages');
  }

  /// Newest at the bottom: ascending [at].
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(
    String userA,
    String userB,
  ) {
    return _messages(userA, userB).orderBy('at', descending: false).snapshots();
  }

  static Future<void> sendText({
    required String toUid,
    required String text,
  }) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      throw StateError('Not signed in');
    }
    final t = text.trim();
    if (t.isEmpty) {
      return;
    }

    final body = <String, dynamic>{
      'text': t,
      'senderId': me,
      'at': FieldValue.serverTimestamp(),
    };

    final batch = _db.batch();
    final msgRef = _messages(me, toUid).doc();
    batch.set(msgRef, body);

    // Both users' thread previews (inbox) under each person's `chats` tree.
    batch.set(
      _db.collection('users').doc(me).collection('chats').doc(toUid),
      {
        'otherUid': toUid,
        'lastMessageText': t,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSentByMe': true,
      },
      SetOptions(merge: true),
    );
    batch.set(
      _db.collection('users').doc(toUid).collection('chats').doc(me),
      {
        'otherUid': me,
        'lastMessageText': t,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSentByMe': false,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }
}
