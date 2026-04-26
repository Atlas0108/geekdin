import 'package:flutter/material.dart';

import '../models/discover_profile.dart';
import 'firebase_profile_image.dart';

/// Shown when [RecordSwipeResult.newMutualMatch] is returned.
Future<void> showItsAMatchDialog(
  BuildContext context,
  DiscoverProfile other,
) async {
  if (!context.mounted) {
    return;
  }
  final theme = Theme.of(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        title: const Text("It's a match!"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (other.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: FirebaseProfileImage(
                    url: other.imageUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              Icon(
                Icons.person,
                size: 80,
                color: theme.colorScheme.outline,
              ),
            const SizedBox(height: 16),
            Text(
              'You and ${other.displayName} both liked each other.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Nice'),
          ),
        ],
      );
    },
  );
}
