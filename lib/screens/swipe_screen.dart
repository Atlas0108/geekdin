import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';

import '../widgets/firebase_profile_image.dart';

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

  final CardSwiperController _swiperController = CardSwiperController();

  /// Latched swipe direction while user is dragging:
  /// -1 = left, 1 = right, null = idle.
  final ValueNotifier<int?> _activeSwipeDirection = ValueNotifier<int?>(null);

  @override
  void initState() {
    super.initState();
    _loadDeck();
  }

  @override
  void dispose() {
    _activeSwipeDirection.dispose();
    unawaited(_swiperController.dispose());
    super.dispose();
  }

  Future<void> _loadDeck() async {
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
      final swipedSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('swipes')
          .get();
      final swiped = swipedSnap.docs.map((d) => d.id).toSet();

      final usersSnap =
          await FirebaseFirestore.instance.collection('users').limit(80).get();

      final next = <DiscoverProfile>[];
      for (final doc in usersSnap.docs) {
        if (doc.id == me) {
          continue;
        }
        if (swiped.contains(doc.id)) {
          continue;
        }
        final p = DiscoverProfile.fromDoc(doc);
        if (p.hasPresentation) {
          next.add(p);
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _deck
          ..clear()
          ..addAll(next);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
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
        .set({
      'liked': liked,
      'at': FieldValue.serverTimestamp(),
    });
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

  bool _onSwipe(int previousIndex, int? currentIndex, CardSwiperDirection direction) {
    _activeSwipeDirection.value = null;
    final liked = direction == CardSwiperDirection.right;
    unawaited(_persistSwipe(previousIndex, liked));
    return true;
  }

  // ignore: unused_element_parameter
  bool _onUndo(int? previousIndex, int currentIndex, CardSwiperDirection direction) {
    _activeSwipeDirection.value = null;
    return true;
  }

  Future<void> _onDeckEnd() async {
    if (!mounted) {
      return;
    }
    _activeSwipeDirection.value = null;
    setState(() => _deck.clear());
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
              Icon(Icons.inbox_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
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
            allowedSwipeDirection:
                const AllowedSwipeDirection.symmetric(horizontal: true),
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
                          onPressed: _deck.isEmpty
                              ? null
                              : () => _swiperController.swipe(CardSwiperDirection.left),
                        ),
                      ),
                      _ScaleVisibility(
                        visible: !hideLike,
                        child: _CircleAction(
                          accent: const Color(0xFF39FF14),
                          icon: Icons.favorite_rounded,
                          onPressed: _deck.isEmpty
                              ? null
                              : () => _swiperController.swipe(CardSwiperDirection.right),
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
    this.city,
  });

  final String uid;
  final String displayName;
  final String bio;
  final String? imageUrl;
  final String? city;

  bool get hasPresentation =>
      imageUrl != null &&
      imageUrl!.isNotEmpty &&
      displayName.trim().isNotEmpty;

  static DiscoverProfile fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final urls = data['profileImageUrls'];
    String? url;
    if (urls is List && urls.isNotEmpty && urls.first is String) {
      url = (urls.first as String).trim();
    }
    return DiscoverProfile(
      uid: doc.id,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : (data['email'] as String?)?.split('@').first ?? 'Someone',
      bio: (data['bio'] as String?)?.trim() ?? '',
      imageUrl: url,
      city: (data['city'] as String?)?.trim(),
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
          left: 20,
          child: _Stamp(
            label: 'PASS',
            color: const Color(0xFFFF3AD4),
            opacity: passOpacity,
          ),
        ),
        Positioned(
          top: 24,
          right: 20,
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
                child: Icon(Icons.person, size: 80, color: theme.colorScheme.outline),
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
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                      if (profile.bio.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          profile.bio,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
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
    required this.onPressed,
  });

  final Color accent;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Material(
      color: enabled ? accent : accent.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      elevation: enabled ? 6 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Icon(icon, size: 36, color: Colors.white),
        ),
      ),
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

