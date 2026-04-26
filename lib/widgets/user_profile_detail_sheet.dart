import 'package:flutter/material.dart';

import '../models/discover_profile.dart';
import 'firebase_profile_image.dart';

/// Full-screen profile content: hero image, name header, scrollable bio + interests, optional
/// pass/like when [showSwipeActions] is true.
class UserProfileDetailSheet extends StatelessWidget {
  const UserProfileDetailSheet({
    super.key,
    required this.profile,
    this.showSwipeActions = false,
    this.onPass,
    this.onLike,
  });

  final DiscoverProfile profile;
  final bool showSwipeActions;
  final VoidCallback? onPass;
  final VoidCallback? onLike;

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
              SizedBox(height: showSwipeActions ? 120 : 32),
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
          if (showSwipeActions)
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
                    _ProfileCircleAction(
                      accent: const Color(0xFFFF3AD4),
                      icon: Icons.close_rounded,
                      onPressed: onPass,
                    ),
                    _ProfileCircleAction(
                      accent: const Color(0xFF39FF14),
                      icon: Icons.favorite_rounded,
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

class _ProfileCircleAction extends StatelessWidget {
  const _ProfileCircleAction({
    required this.accent,
    required this.icon,
    required this.onPressed,
  });

  final Color accent;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final baseColor = theme.colorScheme.surfaceContainer;
    final bg = enabled ? baseColor : theme.colorScheme.surfaceContainerHighest
        .withValues(alpha: 0.8);
    return Material(
      color: bg,
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
            color: enabled ? accent : accent.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}
