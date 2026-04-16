import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';

/// Persists app user profile documents under `users/{uid}`.
abstract final class UserFirestore {
  static CollectionReference<Map<String, dynamic>> get _users =>
      FirebaseFirestore.instance.collection('users');

  /// Creates the Firestore profile for a newly registered account.
  static Future<void> createProfileForNewUser(User user) {
    return _users.doc(user.uid).set({
      'email': user.email ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static bool snapshotShowsCompleteProfile(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) {
      return false;
    }
    return UserProfile.isComplete(snapshot.data());
  }

  static Future<void> saveOnboardingProfile({
    required String uid,
    required List<String> profileImageUrls,
    required String city,
    required double latitude,
    required double longitude,
    required String bio,
    required List<String> interests,
  }) {
    return _users.doc(uid).set(
      {
        'profileImageUrls': profileImageUrls,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'bio': bio,
        'interests': interests,
        'profileUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
