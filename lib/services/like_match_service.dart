import 'package:cloud_firestore/cloud_firestore.dart';

/// Result of writing a swipe and, for right swipes, checking for a mutual like.
enum RecordSwipeResult {
  /// Left swipe; nothing else to do.
  pass,

  /// You liked them; they have not liked you (or you already had a match row).
  likePending,

  /// You both liked each other; new `matches` rows were created.
  newMutualMatch,
}

/// Persists swipes and creates [users]/*/matches* pairs when there is a mutual like.
///
/// The swipe is always written first. Secondary writes (likesReceived, matches) are
/// best-effort so a missing index or outdated [firestore.rules] in production cannot
/// block the core swipe.
abstract final class LikeMatchService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Writes `users/{fromUid}/swipes/{toUid}`. For right swipes, also writes
  /// `users/{toUid}/likesReceived/{fromUid}` for the Likes tab. When [liked] is
  /// true, checks the reverse swipe and may write
  /// `users/{a}/matches/{b}` and `users/{b}/matches/{a}`.
  static Future<RecordSwipeResult> recordSwipeAndProcessMatch({
    required String fromUid,
    required String toUid,
    required bool liked,
  }) async {
    final fromRef = _db.collection('users').doc(fromUid);
    final swipeRef = fromRef.collection('swipes').doc(toUid);
    final at = FieldValue.serverTimestamp();

    await swipeRef.set({
      'liked': liked,
      'at': at,
      'targetUserId': toUid,
    });

    if (liked) {
      try {
        await _db
            .collection('users')
            .doc(toUid)
            .collection('likesReceived')
            .doc(fromUid)
            .set(
          {
            'at': at,
            'fromUid': fromUid,
          },
          SetOptions(merge: true),
        );
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          rethrow;
        }
        // Likes tab stays empty until rules (likesReceived) are deployed.
      }
    }

    if (!liked) {
      return RecordSwipeResult.pass;
    }

    // Mutual like: we need to know they already right-swiped you. Primary source is
    // `users/{them}/swipes/{me}`. If that doc is missing, read fails, or is unclear,
    // `users/{me}/likesReceived/{them}` still proves they liked you (Likes tab row).
    final theirSwipe = await _tryGetTheirSwipe(
      toUid: toUid,
      fromUid: fromUid,
    );
    if (theirSwipe != null && theirSwipe.exists) {
      if (theirSwipe.data()?['liked'] != true) {
        return RecordSwipeResult.likePending;
      }
    } else {
      // Permission denied (null), or their swipe document missing: confirm via inbox.
      final likesMe = await _tryGetLikesReceivedInbox(
        recipientUid: fromUid,
        likerUid: toUid,
      );
      if (likesMe == null || !likesMe.exists) {
        return RecordSwipeResult.likePending;
      }
    }

    final myMatch = fromRef.collection('matches').doc(toUid);
    if ((await myMatch.get()).exists) {
      return RecordSwipeResult.likePending;
    }

    try {
      final batch = _db.batch();
      final ts = FieldValue.serverTimestamp();
      batch.set(myMatch, {'at': ts, 'otherUid': toUid});
      batch.set(
        _db
            .collection('users')
            .doc(toUid)
            .collection('matches')
            .doc(fromUid),
        {'at': ts, 'otherUid': fromUid},
      );
      // `users/{me}/likesReceived/{them}` — they had liked you; remove from Likes tab.
      batch.delete(fromRef.collection('likesReceived').doc(toUid));
      await batch.commit();
      return RecordSwipeResult.newMutualMatch;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // Match rows missing until rules are deployed; swipe still applied.
        return RecordSwipeResult.likePending;
      }
      rethrow;
    }
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?> _tryGetTheirSwipe({
    required String toUid,
    required String fromUid,
  }) async {
    try {
      return await _db
          .collection('users')
          .doc(toUid)
          .collection('swipes')
          .doc(fromUid)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }

  /// `users/{recipientUid}/likesReceived/{likerUid}` — the liker right-swiped the recipient.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> _tryGetLikesReceivedInbox({
    required String recipientUid,
    required String likerUid,
  }) async {
    try {
      return await _db
          .collection('users')
          .doc(recipientUid)
          .collection('likesReceived')
          .doc(likerUid)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }
}
