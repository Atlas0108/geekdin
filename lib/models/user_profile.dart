/// Firestore `users/{uid}` profile fields used for onboarding completion.
abstract final class UserProfile {
  static bool isComplete(Map<String, dynamic>? data) {
    if (data == null) {
      return false;
    }
    final images = data['profileImageUrls'];
    if (images is! List || images.isEmpty) {
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
    final bio = (data['bio'] as String?)?.trim() ?? '';
    if (bio.isEmpty) {
      return false;
    }
    final interests = data['interests'];
    if (interests is! List || interests.isEmpty) {
      return false;
    }
    return true;
  }
}
