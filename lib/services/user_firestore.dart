import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';

/// Persists app user profile documents under `users/{uid}`.
abstract final class UserFirestore {
  static CollectionReference<Map<String, dynamic>> get _users =>
      FirebaseFirestore.instance.collection('users');

  static const String defaultGender = 'unspecified';
  static const String defaultGenderPreference = 'everyone';
  static const int defaultAgeMinPreference = 18;
  static const int defaultAgeMaxPreference = 99;
  static const int defaultDistance = 50;
  static const bool defaultIsGlobal = false;

  static Map<String, dynamic> discoveryPreferenceDefaults() => {
    'gender': defaultGender,
    'genderPreference': defaultGenderPreference,
    'agePreference': {
      'min': defaultAgeMinPreference,
      'max': defaultAgeMaxPreference,
    },
    'distance': defaultDistance,
    'isGlobal': defaultIsGlobal,
  };

  /// Creates the Firestore profile for a newly registered account.
  static Future<void> createProfileForNewUser(User user) {
    return _users.doc(user.uid).set({
      'email': user.email ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      ...discoveryPreferenceDefaults(),
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
    required String displayName,
    required DateTime birthdate,
    required String gender,
    required String genderPreference,
    required int agePreferenceMin,
    required int agePreferenceMax,
    required String city,
    required double latitude,
    required double longitude,
    required String bio,
    required List<String> interests,
  }) {
    return _users.doc(uid).set({
      'profileImageUrls': profileImageUrls,
      'displayName': displayName,
      'birthdate': Timestamp.fromDate(
        DateTime.utc(birthdate.year, birthdate.month, birthdate.day),
      ),
      'gender': gender,
      'genderPreference': genderPreference,
      'agePreference': {'min': agePreferenceMin, 'max': agePreferenceMax},
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'bio': bio,
      'interests': interests,
      'profileUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> saveDiscoveryPreferences({
    required String uid,
    required String gender,
    required String genderPreference,
    required int agePreferenceMin,
    required int agePreferenceMax,
    required int distance,
    required bool isGlobal,
  }) {
    return _users.doc(uid).set({
      'gender': gender,
      'genderPreference': genderPreference,
      'agePreference': {'min': agePreferenceMin, 'max': agePreferenceMax},
      'distance': distance,
      'isGlobal': isGlobal,
      'preferenceUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
