import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/discover_profile.dart';
import '../widgets/firebase_profile_image.dart';
import '../widgets/user_profile_detail_sheet.dart';

int _atMillis(Map<String, dynamic>? data) {
  final at = data?['at'];
  if (at is Timestamp) {
    return at.millisecondsSinceEpoch;
  }
  return 0;
}

List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedLikerDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final out = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(docs);
  out.sort(
    (a, b) => _atMillis(b.data()).compareTo(_atMillis(a.data())),
  );
  return out;
}

/// People who have right-swiped you, via `users/{me}/likesReceived/{fromUid}`.
class LikesScreen extends StatelessWidget {
  const LikesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      return const Center(child: Text('Sign in to see your likes.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // No orderBy: avoids a composite index, and still sorts in memory.
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('likesReceived')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final err = snapshot.error.toString();
          final isPerm = err.contains('permission-denied');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Could not load likes.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isPerm
                        ? 'Firestore rules in your Firebase project are missing or out of date. '
                            'From the project root run:\n'
                            'firebase deploy --only firestore:rules\n\n'
                            'Then restart the app.'
                        : err,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = _sortedLikerDocs(snapshot.data?.docs ?? []);
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No likes yet. Keep swiping—when someone likes you, they will show up here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final likerUid = docs[i].id;
            return _LikerTile(likerUid: likerUid);
          },
        );
      },
    );
  }
}

class _LikerTile extends StatelessWidget {
  const _LikerTile({required this.likerUid});

  final String likerUid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(likerUid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final name = (data['displayName'] as String?)?.trim();
        final label = (name != null && name.isNotEmpty)
            ? name
            : (data['email'] as String?)?.split('@').first ?? 'Member';
        final urls = data['profileImageUrls'];
        String? imageUrl;
        if (urls is List) {
          for (final e in urls) {
            if (e is String && e.trim().isNotEmpty) {
              imageUrl = e.trim();
              break;
            }
          }
        }
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              final doc = snap.data;
              if (doc == null || !doc.exists) {
                return;
              }
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (ctx) {
                  return SizedBox(
                    height: MediaQuery.sizeOf(ctx).height,
                    child: UserProfileDetailSheet(
                      profile: DiscoverProfile.fromDoc(doc),
                      showSwipeActions: true,
                      onPass: () {
                        Navigator.of(ctx).pop();
                      },
                      onLike: () {
                        Navigator.of(ctx).pop();
                      },
                    ),
                  );
                },
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: imageUrl != null
                        ? FirebaseProfileImage(
                            url: imageUrl,
                            fit: BoxFit.cover,
                          )
                        : ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.person,
                              size: 56,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
