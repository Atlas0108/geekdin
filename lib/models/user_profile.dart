import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore `users/{uid}` profile fields used for onboarding completion.
abstract final class UserProfile {
  static bool isComplete(Map<String, dynamic>? data) {
    if (data == null) {
      return false;
    }
    final displayName = (data['displayName'] as String?)?.trim() ?? '';
    if (displayName.isEmpty) {
      return false;
    }
    final images = data['profileImageUrls'];
    if (images is! List || images.isEmpty) {
      return false;
    }
    final birthdate = data['birthdate'];
    if (birthdate is! Timestamp && birthdate is! DateTime) {
      return false;
    }
    final gender = (data['gender'] as String?)?.trim() ?? '';
    if (gender.isEmpty || gender == 'unspecified') {
      return false;
    }
    final city = (data['city'] as String?)?.trim() ?? '';
    if (city.isEmpty) {
      return false;
    }
    final lat = data['latitude'];
    final lng = data['longitude'];
    if (lat is! num || lng is! num) {
      return false;
    }
    final agePreference = data['agePreference'];
    if (agePreference is! Map) {
      return false;
    }
    final min = agePreference['min'];
    final max = agePreference['max'];
    if (min is! num || max is! num || min > max) {
      return false;
    }
    return true;
  }
}
