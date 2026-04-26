import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/discover_profile.dart';
import '../widgets/firebase_profile_image.dart';
import '../widgets/user_profile_detail_sheet.dart';

/// Chat hub: "New matches" (horizontal) for mutual matches with no [chats] thread yet;
/// "Messages" (list) for matches that have [users/{me}/chats/{otherUid}] with history.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, this.onOpenLikes});

  /// Switches the main shell to the Likes tab (optional).
  final VoidCallback? onOpenLikes;

  static const _bg = Color(0xFF000000);

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      return const Center(child: Text('Sign in to see chats.'));
    }

    return ColoredBox(
      color: _bg,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(me)
            .collection('matches')
            .snapshots(),
        builder: (context, matchSnap) {
          if (matchSnap.hasError) {
            return Center(
              child: Text('${matchSnap.error}', style: const TextStyle(color: Colors.white70)),
            );
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(me)
                .collection('chats')
                .orderBy('lastMessageAt', descending: true)
                .snapshots(),
            builder: (context, chatSnap) {
              if (chatSnap.hasError) {
                final e = chatSnap.error.toString();
                if (e.contains('failed-precondition') ||
                    e.contains('index') ||
                    e.contains('failed to respond')) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Chats need a lastMessageAt field on thread docs, or a Firestore index for lastMessageAt. You can add threads when messaging is wired up.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  );
                }
                return Center(
                  child: Text(
                    e,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              final matchIds = {
                for (final d in matchSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  d.id
              };
              final chatDocs = chatSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final chatIds = {for (final d in chatDocs) d.id};
              final newMatchUids = matchIds.difference(chatIds);
              final messageRows = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              for (final d in chatDocs) {
                if (matchIds.contains(d.id)) {
                  messageRows.add(d);
                }
              }

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Text(
                        'New Matches',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                            ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 168,
                      child: newMatchUids.isEmpty && onOpenLikes == null
                          ? const Center(
                              child: Text(
                                'No new matches',
                                style: TextStyle(color: Colors.white38),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              scrollDirection: Axis.horizontal,
                              children: [
                                if (onOpenLikes != null) ...[
                                  _LikesShortcutTile(
                                    onTap: onOpenLikes!,
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                for (final uid in newMatchUids) ...[
                                  _NewMatchCard(otherUid: uid),
                                  const SizedBox(width: 10),
                                ],
                              ],
                            ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(
                        'Messages',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                            ),
                      ),
                    ),
                  ),
                  if (messageRows.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                        child: Text(
                          'No messages yet. When you start a conversation, it will show up here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          if (i.isOdd) {
                            return const Divider(
                              height: 1,
                              thickness: 1,
                              color: Color(0xFF1A1A1A),
                            );
                          }
                          final doc = messageRows[i ~/ 2];
                          return _MessageThreadTile(
                            otherUid: doc.id,
                            data: doc.data(),
                          );
                        },
                        childCount: messageRows.length * 2 - 1,
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _LikesShortcutTile extends StatelessWidget {
  const _LikesShortcutTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 128,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE8C66A),
                  Color(0xFFB8860B),
                ],
              ),
            ),
            child: const Center(
              child: Text(
                '99+',
                style: TextStyle(
                  color: Color(0xFF1A1206),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.favorite, size: 12, color: Color(0xFFE8C66A)),
              SizedBox(width: 4),
              Text(
                'Likes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewMatchCard extends StatelessWidget {
  const _NewMatchCard({required this.otherUid});

  final String otherUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(otherUid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final name = (data['displayName'] as String?)?.trim();
        final label = (name != null && name.isNotEmpty)
            ? name
            : (data['email'] as String?)?.split('@').first ?? 'Match';
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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final doc = snap.data;
            if (doc == null || !doc.exists) {
              return;
            }
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: ChatScreen._bg,
              builder: (ctx) {
                return SizedBox(
                  height: MediaQuery.sizeOf(ctx).height,
                  child: UserProfileDetailSheet(
                    profile: DiscoverProfile.fromDoc(doc),
                    showSwipeActions: false,
                  ),
                );
              },
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 128,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF1A1A1A),
                ),
                clipBehavior: Clip.antiAlias,
                child: imageUrl != null
                    ? FirebaseProfileImage(
                        url: imageUrl,
                        fit: BoxFit.cover,
                      )
                    : const Center(
                        child: Icon(
                          Icons.person,
                          size: 48,
                          color: Colors.white24,
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 100,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MessageThreadTile extends StatelessWidget {
  const _MessageThreadTile({
    required this.otherUid,
    required this.data,
  });

  final String otherUid;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final lastText = (data['lastMessageText'] as String?)?.trim() ?? '';
    final lastSentByMe = data['lastSentByMe'] as bool? ?? false;
    final at = data['lastMessageAt'];
    final showYourTurn = !lastSentByMe && lastText.isNotEmpty;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(otherUid)
          .snapshots(),
      builder: (context, snap) {
        final u = snap.data?.data() ?? const <String, dynamic>{};
        final name = (u['displayName'] as String?)?.trim();
        final displayName = (name != null && name.isNotEmpty)
            ? name
            : (u['email'] as String?)?.split('@').first ?? 'Match';
        final urls = u['profileImageUrls'];
        String? imageUrl;
        if (urls is List) {
          for (final e in urls) {
            if (e is String && e.trim().isNotEmpty) {
              imageUrl = e.trim();
              break;
            }
          }
        }
        return InkWell(
          onTap: () {
            // Placeholder until chat room exists
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Chat is coming soon.')),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFF2A2A2A),
                  child: ClipOval(
                    child: imageUrl != null
                        ? SizedBox(
                            width: 60,
                            height: 60,
                            child: FirebaseProfileImage(
                              url: imageUrl,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 32,
                            color: Colors.white38,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (lastText.isEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8C66A),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (lastText.isEmpty)
                        Text(
                          'Recently active, match now!',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 14,
                          ),
                        )
                      else
                        Row(
                          children: [
                            if (lastSentByMe)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  Icons.reply,
                                  size: 14,
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                lastText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (showYourTurn)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Your turn',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else if (at is Timestamp)
                  Text(
                    _formatShort(at),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 12,
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

String _formatShort(Timestamp t) {
  final dt = t.toDate();
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) {
    return 'now';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}m';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours}h';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays}d';
  }
  return '${dt.month}/${dt.day}';
}
