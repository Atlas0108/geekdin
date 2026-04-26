import 'dart:async' show unawaited, StreamSubscription;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';

import '../services/user_firestore.dart';
import '../widgets/firebase_profile_image.dart';

// --- Discovery compatibility (gender + who-you're-into) ----------------------

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

String? _normalizeGenderKeyForMatch(String? raw) {
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

String _normalizePreferenceKeyForMatch(String? raw) {
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

/// Whether [whoYouWant] (stored `genderPreference`) includes [other]s gender
/// (stored `gender` key, e.g. `woman` / `man`).
bool _preferenceIncludesGender({
  required String whoYouWant,
  required String otherGender,
}) {
  switch (whoYouWant) {
    case 'everyone':
      return true;
    case 'women':
      return otherGender == 'woman';
    case 'men':
      return otherGender == 'man';
    case 'non_binary':
      return otherGender == 'non_binary' || otherGender == 'other';
    default:
      return false;
  }
}

/// Both sides' "into" setting includes the other side's gender.
bool _mutualPreferenceMatch({
  required String viewerGender,
  required String viewerPreference,
  required String? otherGender,
  required String otherPreference,
}) {
  final oGender = _normalizeGenderKeyForMatch(otherGender);
  if (oGender == null) {
    return false;
  }
  final oPref = _normalizePreferenceKeyForMatch(otherPreference);
  return _preferenceIncludesGender(
        whoYouWant: viewerPreference,
        otherGender: oGender,
      ) &&
      _preferenceIncludesGender(
        whoYouWant: oPref,
        otherGender: viewerGender,
      );
}

/// Fingerprint of fields that change how the swipe list is built (for you, not the candidate pool).
String _discoveryPrefsSignature(Map<String, dynamic>? data) {
  if (data == null) {
    return '';
  }
  final ap = data['agePreference'];
  var apStr = '';
  if (ap is Map) {
    apStr = '${ap['min']},${ap['max']}';
  }
  return [
    data['gender']?.toString() ?? '',
    data['genderPreference']?.toString() ?? '',
    apStr,
    data['distance']?.toString() ?? '',
    data['isGlobal']?.toString() ?? '',
  ].join('|');
}

/// Tinder-style stack via [CardSwiper]. Persists under `users/{me}/swipes/{theirUid}`.
class SwipeScreen extends StatefulWidget {
  const SwipeScreen({super.key});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  final List<DiscoverProfile> _deck = [];
  bool _loading = true;
  String? _error;
  int _activeCardIndex = 0;

  final CardSwiperController _swiperController = CardSwiperController();

  /// Latched swipe direction while user is dragging:
  /// -1 = left, 1 = right, null = idle.
  final ValueNotifier<int?> _activeSwipeDirection = ValueNotifier<int?>(null);

  /// Cancels when [SwipeScreen] is disposed.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

  /// Last seen `users/{me}` discovery prefs; reload when this string changes.
  String? _lastDiscoveryPrefsSignature;

  /// Bumped on each [_loadDeck] start so stale async results are ignored.
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _subscribeToUserDoc();
  }

  @override
  void dispose() {
    unawaited(_userDocSub?.cancel());
    _activeSwipeDirection.dispose();
    unawaited(_swiperController.dispose());
    super.dispose();
  }

  void _subscribeToUserDoc() {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }

    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(me)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) {
          return;
        }
        final sig = _discoveryPrefsSignature(snap.data());
        if (sig == _lastDiscoveryPrefsSignature) {
          return;
        }
        _lastDiscoveryPrefsSignature = sig;
        unawaited(_loadDeck());
      },
      onError: (Object e) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
          _error = '$e';
        });
      },
    );
  }

  Future<void> _loadDeck() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }

    final gen = ++_loadGen;
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(me).get();
      final myData = myDoc.data() ?? {};
      final myGender = _normalizeGenderKeyForMatch(myData['gender'] as String?);
      final myPref = _normalizePreferenceKeyForMatch(
        myData['genderPreference'] as String?,
      );
      if (myGender == null) {
        if (mounted && gen == _loadGen) {
          setState(() {
            _loading = false;
            _error =
                'Set your gender and who you are interested in in settings before swiping.';
          });
        }
        return;
      }

      final swipedSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('swipes')
          .get();
      final swiped = swipedSnap.docs.map((d) => d.id).toSet();

      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .limit(80)
          .get();

      final next = <DiscoverProfile>[];
      for (final doc in usersSnap.docs) {
        if (doc.id == me) {
          continue;
        }
        if (swiped.contains(doc.id)) {
          continue;
        }
        final p = DiscoverProfile.fromDoc(doc);
        if (!p.hasPresentation) {
          continue;
        }
        if (_mutualPreferenceMatch(
          viewerGender: myGender,
          viewerPreference: myPref,
          otherGender: p.gender,
          otherPreference: p.genderPreference,
        )) {
          next.add(p);
        }
      }

      if (!mounted || gen != _loadGen) {
        return;
      }
      setState(() {
        _deck
          ..clear()
          ..addAll(next);
        _activeCardIndex = 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted && gen == _loadGen) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  /// Clears persisted likes/passes so the deck can show the same profiles again.
  Future<void> _resetSwipesAndReloadDeck() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final swipesRef = FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('swipes');
      const batchSize = 500;
      while (true) {
        final snap = await swipesRef.limit(batchSize).get();
        if (snap.docs.isEmpty) {
          break;
        }
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        if (snap.docs.length < batchSize) {
          break;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
      return;
    }

    await _loadDeck();
  }

  Future<void> _recordSwipe(String targetUid, bool liked) async {
    final me = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(me)
        .collection('swipes')
        .doc(targetUid)
        .set({'liked': liked, 'at': FieldValue.serverTimestamp()});
  }

  /// Persists the swiped profile (index is stable until [onEnd] clears the deck).
  Future<void> _persistSwipe(int previousIndex, bool liked) async {
    if (previousIndex < 0 || previousIndex >= _deck.length) {
      return;
    }
    final profile = _deck[previousIndex];
    try {
      await _recordSwipe(profile.uid, liked);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save swipe — try again.')),
      );
      _swiperController.undo();
    }
  }

  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    _activeSwipeDirection.value = null;
    if (currentIndex != null) {
      _activeCardIndex = currentIndex;
    }
    final liked = direction == CardSwiperDirection.right;
    unawaited(_persistSwipe(previousIndex, liked));
    return true;
  }

  // ignore: unused_element_parameter
  bool _onUndo(
    int? previousIndex,
    int currentIndex,
    CardSwiperDirection direction,
  ) {
    _activeSwipeDirection.value = null;
    _activeCardIndex = currentIndex;
    return true;
  }

  Future<void> _onDeckEnd() async {
    if (!mounted) {
      return;
    }
    _activeSwipeDirection.value = null;
    _activeCardIndex = 0;
    setState(() => _deck.clear());
  }

  DiscoverProfile? get _activeProfile {
    if (_deck.isEmpty) {
      return null;
    }
    final index = _activeCardIndex.clamp(0, _deck.length - 1);
    return _deck[index];
  }

  Future<void> _openActiveProfile() async {
    final profile = _activeProfile;
    if (profile == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: _ProfileDetailsSheet(
            profile: profile,
            onPass: () {
              Navigator.of(context).pop();
              _swiperController.swipe(CardSwiperDirection.left);
            },
            onLike: () {
              Navigator.of(context).pop();
              _swiperController.swipe(CardSwiperDirection.right);
            },
          ),
        );
      },
    );
  }

  void _onSwipeDirectionChange(
    CardSwiperDirection horizontalDirection,
    CardSwiperDirection verticalDirection,
  ) {
    if (horizontalDirection == CardSwiperDirection.none) {
      if (_activeSwipeDirection.value != null) {
        _activeSwipeDirection.value = null;
      }
      return;
    }
    if (_activeSwipeDirection.value == null) {
      if (horizontalDirection.isCloseTo(CardSwiperDirection.right)) {
        _activeSwipeDirection.value = 1;
      } else if (horizontalDirection.isCloseTo(CardSwiperDirection.left)) {
        _activeSwipeDirection.value = -1;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_deck.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'No more profiles to show',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Check back later or ask friends to join.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: _resetSwipesAndReloadDeck,
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: CardSwiper(
            controller: _swiperController,
            cardsCount: _deck.length,
            numberOfCardsDisplayed: _deck.length == 1 ? 1 : 2,
            isLoop: false,
            padding: EdgeInsets.zero,
            threshold: 100,
            allowedSwipeDirection: const AllowedSwipeDirection.symmetric(
              horizontal: true,
            ),
            onSwipe: _onSwipe,
            onUndo: _onUndo,
            onEnd: _onDeckEnd,
            onSwipeDirectionChange: _onSwipeDirectionChange,
            cardBuilder: (context, index, horizontalPct, _) {
              return _SwiperProfileCard(
                profile: _deck[index],
                horizontalThresholdPercentage: horizontalPct,
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 260,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: ValueListenableBuilder<int?>(
                valueListenable: _activeSwipeDirection,
                builder: (context, direction, _) {
                  final hidePass = direction == 1;
                  final hideLike = direction == -1;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ScaleVisibility(
                        visible: !hidePass,
                        child: _CircleAction(
                          accent: const Color(0xFFFF3AD4),
                          icon: Icons.close_rounded,
                          swapColors: direction == -1,
                          onPressed: _deck.isEmpty
                              ? null
                              : () => _swiperController.swipe(
                                  CardSwiperDirection.left,
                                ),
                        ),
                      ),
                      _CircleAction(
                        accent: Theme.of(context).colorScheme.primary,
                        icon: Icons.keyboard_arrow_up_rounded,
                        swapColors: false,
                        onPressed: _activeProfile == null ? null : _openActiveProfile,
                      ),
                      _ScaleVisibility(
                        visible: !hideLike,
                        child: _CircleAction(
                          accent: const Color(0xFF39FF14),
                          icon: Icons.favorite_rounded,
                          swapColors: direction == 1,
                          onPressed: _deck.isEmpty
                              ? null
                              : () => _swiperController.swipe(
                                  CardSwiperDirection.right,
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
  /// Normalized Firestore `gender` key for discovery matching, or null if not usable.
  final String? gender;
  /// Normalized `genderPreference` (defaults to [UserFirestore.defaultGenderPreference]).
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
      gender: _normalizeGenderKeyForMatch(data['gender'] as String?),
      genderPreference: _normalizePreferenceKeyForMatch(
        data['genderPreference'] as String?,
      ),
    );
  }
}

class _ProfileDetailsSheet extends StatelessWidget {
  const _ProfileDetailsSheet({
    required this.profile,
    required this.onPass,
    required this.onLike,
  });

  final DiscoverProfile profile;
  final VoidCallback onPass;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              AspectRatio(
                aspectRatio: 3 / 4,
                child: profile.imageUrl != null
                    ? FirebaseProfileImage(url: profile.imageUrl!)
                    : ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.person,
                          size: 96,
                          color: theme.colorScheme.outline,
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bio', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(
                              profile.bio.isEmpty
                                  ? 'No bio yet.'
                                  : profile.bio,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Interests', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            if (profile.interests.isEmpty)
                              Text(
                                'No interests listed.',
                                style: theme.textTheme.bodyLarge,
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final interest in profile.interests)
                                    Chip(label: Text(interest)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 120),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: const [
                            Shadow(
                              color: Color(0xAA000000),
                              blurRadius: 8,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.45),
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CircleAction(
                    accent: const Color(0xFFFF3AD4),
                    icon: Icons.close_rounded,
                    swapColors: false,
                    onPressed: onPass,
                  ),
                  _CircleAction(
                    accent: const Color(0xFF39FF14),
                    icon: Icons.favorite_rounded,
                    swapColors: false,
                    onPressed: onLike,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwiperProfileCard extends StatelessWidget {
  const _SwiperProfileCard({
    required this.profile,
    required this.horizontalThresholdPercentage,
  });

  final DiscoverProfile profile;
  final int horizontalThresholdPercentage;

  @override
  Widget build(BuildContext context) {
    final h = horizontalThresholdPercentage;
    final likeOpacity = h > 0 ? (h / 100.0).clamp(0.0, 1.0) : 0.0;
    final passOpacity = h < 0 ? ((-h) / 100.0).clamp(0.0, 1.0) : 0.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _ProfileCardFrame(
          profile: profile,
          width: double.infinity,
          height: double.infinity,
        ),
        Positioned(
          top: 24,
          right: 20,
          child: _Stamp(
            label: 'PASS',
            color: const Color(0xFFFF3AD4),
            opacity: passOpacity,
          ),
        ),
        Positioned(
          top: 24,
          left: 20,
          child: _Stamp(
            label: 'LIKE',
            color: const Color(0xFF39FF14),
            opacity: likeOpacity,
          ),
        ),
      ],
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.color,
    required this.opacity,
  });

  final String label;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (opacity < 0.05) {
      return const SizedBox.shrink();
    }
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: label == 'PASS' ? -0.18 : 0.18,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCardFrame extends StatelessWidget {
  const _ProfileCardFrame({
    required this.profile,
    required this.width,
    required this.height,
  });

  final DiscoverProfile profile;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (profile.imageUrl != null)
              FirebaseProfileImage(url: profile.imageUrl!)
            else
              ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: 80,
                  color: theme.colorScheme.outline,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 140),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profile.displayName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (profile.city != null && profile.city!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          profile.city!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ],
                      if (profile.bio.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          profile.bio,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.accent,
    required this.icon,
    required this.swapColors,
    required this.onPressed,
  });

  final Color accent;
  final IconData icon;
  final bool swapColors;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final baseColor = theme.colorScheme.surfaceContainer;
    final inactiveBg = enabled
        ? baseColor
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8);
    final activeBg = enabled ? accent : accent.withValues(alpha: 0.4);
    final inactiveIcon = enabled ? accent : accent.withValues(alpha: 0.45);
    final activeIcon = enabled
        ? baseColor
        : baseColor.withValues(alpha: 0.55);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: swapColors ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      builder: (context, t, _) {
        return Material(
          color: Color.lerp(inactiveBg, activeBg, t),
          shape: const CircleBorder(),
          elevation: enabled ? 6 : 0,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(
                icon,
                size: 36,
                color: Color.lerp(inactiveIcon, activeIcon, t),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScaleVisibility extends StatelessWidget {
  const _ScaleVisibility({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 180),
      curve: visible ? Curves.easeOutBack : Curves.easeIn,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 140),
        child: child,
      ),
    );
  }
}
