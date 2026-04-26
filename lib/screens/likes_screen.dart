import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/discover_profile.dart';
import '../services/like_match_service.dart';
import '../widgets/firebase_profile_image.dart';
import '../widgets/its_a_match_dialog.dart';
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

Future<void> _openLikerProfileForUid(
  BuildContext context,
  String likerUid,
) async {
  if (!context.mounted) {
    return;
  }
  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(likerUid)
      .get();
  if (!context.mounted) {
    return;
  }
  if (!doc.exists) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("That profile isn’t available."),
        duration: Duration(seconds: 4),
      ),
    );
    return;
  }
  _openLikerProfileSheet(listContext: context, userDoc: doc);
}

void _openLikerProfileSheet({
  required BuildContext listContext,
  required DocumentSnapshot<Map<String, dynamic>> userDoc,
}) {
  if (!userDoc.exists) {
    return;
  }
  final profile = DiscoverProfile.fromDoc(userDoc);
  final me = FirebaseAuth.instance.currentUser?.uid;
  if (me == null) {
    return;
  }

  showModalBottomSheet<void>(
    context: listContext,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (sheetContext) {
      var busy = false;
      return StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> runPass() async {
            if (busy) {
              return;
            }
            setModalState(() => busy = true);
            try {
              await LikeMatchService.recordSwipeAndProcessMatch(
                fromUid: me,
                toUid: profile.uid,
                liked: false,
              );
              if (sheetContext.mounted) {
                Navigator.of(sheetContext).pop();
              }
            } catch (e) {
              if (listContext.mounted) {
                ScaffoldMessenger.of(listContext).showSnackBar(
                  SnackBar(
                    content: Text('Could not save pass: $e'),
                    duration: const Duration(seconds: 6),
                  ),
                );
              }
            } finally {
              if (context.mounted) {
                setModalState(() => busy = false);
              }
            }
          }

          Future<void> runLike() async {
            if (busy) {
              return;
            }
            setModalState(() => busy = true);
            try {
              final result = await LikeMatchService.recordSwipeAndProcessMatch(
                fromUid: me,
                toUid: profile.uid,
                liked: true,
              );
              if (!sheetContext.mounted) {
                return;
              }
              Navigator.of(sheetContext).pop();
              if (result == RecordSwipeResult.newMutualMatch &&
                  listContext.mounted) {
                await showItsAMatchDialog(listContext, profile);
              }
            } catch (e) {
              if (listContext.mounted) {
                ScaffoldMessenger.of(listContext).showSnackBar(
                  SnackBar(
                    content: Text('Could not save like: $e'),
                    duration: const Duration(seconds: 6),
                  ),
                );
              }
            } finally {
              if (context.mounted) {
                setModalState(() => busy = false);
              }
            }
          }

          return SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height,
            child: UserProfileDetailSheet(
              profile: profile,
              showSwipeActions: true,
              isActionInProgress: busy,
              onPass: () => unawaited(runPass()),
              onLike: () => unawaited(runLike()),
            ),
          );
        },
      );
    },
  );
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
        void openProfile() {
          // Always fetch on tap: stream can still be [waiting] or the user doc missing.
          unawaited(_openLikerProfileForUid(context, likerUid));
        }

        // Stack: Image (and web HtmlElementView) can intercept hits before a parent
        // InkWell/GestureDetector, so a transparent layer is painted on top of the
        // image. One outer GestureDetector makes the full card a single target.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: openProfile,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
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
                      // Explicit target above the image (Image / HtmlElementView can block parent gestures).
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: openProfile,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
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
        );
      },
    );
  }
}
