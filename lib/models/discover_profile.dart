import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/user_firestore.dart';

// --- Firestore user keys for swipe matching + fromDoc() --------------------------------

const _validGenderKeys = <String>{'woman', 'man', 'non_binary', 'other'};

const _validPreferenceKeys = <String>{
  'everyone',
  'women',
  'men',
  'non_binary',
};

const _legacyGenderAlias = <String, String>{
  'female': 'woman',
  'male': 'man',
  'nb': 'non_binary',
  'enby': 'non_binary',
  'nonbinary': 'non_binary',
  'non-binary': 'non_binary',
  'x': 'non_binary',
};

const _legacyPrefAlias = <String, String>{
  'woman': 'women',
  'women': 'women',
  'man': 'men',
  'men': 'men',
  'all': 'everyone',
  'any': 'everyone',
  'anyone': 'everyone',
  'nonbinary': 'non_binary',
  'non-binary': 'non_binary',
};

/// Normalized Firestore `gender` for mutual match logic and [DiscoverProfile.gender].
String? parseGenderKeyForMatch(String? raw) {
  if (raw == null) {
    return null;
  }
  final t = raw.trim().toLowerCase();
  if (t.isEmpty || t == 'unspecified') {
    return null;
  }
  if (_validGenderKeys.contains(t)) {
    return t;
  }
  return _legacyGenderAlias[t];
}

/// Normalized [UserFirestore]-style `genderPreference` key.
String parsePreferenceKeyForMatch(String? raw) {
  if (raw == null) {
    return UserFirestore.defaultGenderPreference;
  }
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) {
    return UserFirestore.defaultGenderPreference;
  }
  if (_validPreferenceKeys.contains(t)) {
    return t;
  }
  final legacy = _legacyPrefAlias[t];
  if (legacy != null) {
    return legacy;
  }
  return UserFirestore.defaultGenderPreference;
}

/// Profile summary used for swipe cards, profile modals, and Likes.
class DiscoverProfile {
  DiscoverProfile({
    required this.uid,
    required this.displayName,
    required this.bio,
    required this.imageUrl,
    required this.imageUrls,
    required this.interests,
    this.city,
    this.gender,
    required this.genderPreference,
  });

  final String uid;
  final String displayName;
  final String bio;
  final String? imageUrl;
  final List<String> imageUrls;
  final List<String> interests;
  final String? city;
  final String? gender;
  final String genderPreference;

  bool get hasPresentation =>
      imageUrl != null && imageUrl!.isNotEmpty && displayName.trim().isNotEmpty;

  static DiscoverProfile fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final urls = data['profileImageUrls'];
    final allUrls = <String>[];
    String? url;
    if (urls is List) {
      for (final entry in urls) {
        if (entry is String && entry.trim().isNotEmpty) {
          allUrls.add(entry.trim());
        }
      }
      if (allUrls.isNotEmpty) {
        url = allUrls.first;
      }
    }
    final rawInterests = data['interests'];
    final interests = <String>[];
    if (rawInterests is List) {
      for (final entry in rawInterests) {
        if (entry is String && entry.trim().isNotEmpty) {
          interests.add(entry.trim());
        }
      }
    }
    return DiscoverProfile(
      uid: doc.id,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : (data['email'] as String?)?.split('@').first ?? 'Someone',
      bio: (data['bio'] as String?)?.trim() ?? '',
      imageUrl: url,
      imageUrls: allUrls,
      interests: interests,
      city: (data['city'] as String?)?.trim(),
      gender: parseGenderKeyForMatch(data['gender'] as String?),
      genderPreference: parsePreferenceKeyForMatch(
        data['genderPreference'] as String?,
      ),
    );
  }
}
