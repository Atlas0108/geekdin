import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../models/discover_profile.dart';
import '../services/chat_message_service.dart';
import '../widgets/firebase_profile_image.dart';
import '../widgets/user_profile_detail_sheet.dart';

/// Full 1:1 thread backed by [ChatMessageService] (Firestore).
class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.otherUid,
  });

  final String otherUid;

  /// Uses the root [Navigator] from [context] (typical for shell tabs).
  static void open(BuildContext context, String otherUid) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ChatThreadScreen(otherUid: otherUid),
      ),
    );
  }

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  static const _bg = Color(0xFF000000);
  static const _bubbleYou = Color(0xFF1E2A2E);
  static const _bubbleThem = Color(0xFF2A2A2A);
  static const _accent = Color(0xFF00E5FF);

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _controller.text.trim();
    if (t.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    _controller.clear();
    try {
      await ChatMessageService.sendText(toUid: widget.otherUid, text: t);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: Text('Sign in required.', style: TextStyle(color: Colors.white70))),
      );
    }

    return ColoredBox(
      color: _bg,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0A0A),
          foregroundColor: Colors.white,
          elevation: 0,
          title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(widget.otherUid)
                .snapshots(),
            builder: (context, snap) {
              final u = snap.data?.data() ?? {};
              final name = (u['displayName'] as String?)?.trim();
              final label = (name != null && name.isNotEmpty)
                  ? name
                  : (u['email'] as String?)?.split('@').first ?? 'Chat';
              return Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
            },
          ),
          actions: [
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.otherUid)
                  .snapshots(),
              builder: (context, snap) {
                final d = snap.data;
                if (d == null || !d.exists) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  tooltip: 'Profile',
                  icon: const Icon(Icons.person_outline),
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: _bg,
                      builder: (ctx) {
                        return SizedBox(
                          height: MediaQuery.sizeOf(ctx).height,
                          child: UserProfileDetailSheet(
                            profile: DiscoverProfile.fromDoc(d),
                            showSwipeActions: false,
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.otherUid)
                    .snapshots(),
                builder: (context, userSnap) {
                  String? otherPhotoUrl;
                  final u = userSnap.data?.data();
                  if (u != null) {
                    final urls = u['profileImageUrls'];
                    if (urls is List) {
                      for (final e in urls) {
                        if (e is String && e.trim().isNotEmpty) {
                          otherPhotoUrl = e.trim();
                          break;
                        }
                      }
                    }
                  }
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: ChatMessageService.watchMessages(me, widget.otherUid),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '${snap.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                        );
                      }
                      if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                        return const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                          ),
                        );
                      }
                      final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'Say hi! Send a message to start the conversation.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38, fontSize: 15),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final m = ChatMessage.fromDoc(docs[i]);
                          final isMe = m.senderId == me;
                          final prev = i > 0 ? ChatMessage.fromDoc(docs[i - 1]) : null;
                          final isFirstInTheirRun =
                              !isMe && (prev == null || prev.senderId == me);
                          return _BubbleRow(
                            message: m,
                            isMe: isMe,
                            bubbleYou: _bubbleYou,
                            bubbleThem: _bubbleThem,
                            accent: _accent,
                            isFirstInTheirRun: isFirstInTheirRun,
                            otherPhotoUrl: otherPhotoUrl,
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Material(
                color: const Color(0xFF0E0E0E),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 5,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Message…',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                            filled: true,
                            fillColor: const Color(0xFF1A1A1A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          textInputAction: TextInputAction.newline,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _sending
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                              ),
                            )
                          : IconButton.filledTonal(
                              onPressed: _send,
                              style: IconButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: const Color(0xFF001416),
                              ),
                              icon: const Icon(Icons.send_rounded, size: 22),
                            ),
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

class _BubbleRow extends StatelessWidget {
  const _BubbleRow({
    required this.message,
    required this.isMe,
    required this.bubbleYou,
    required this.bubbleThem,
    required this.accent,
    this.isFirstInTheirRun = false,
    this.otherPhotoUrl,
  });

  final ChatMessage message;
  final bool isMe;
  final Color bubbleYou;
  final Color bubbleThem;
  final Color accent;
  final bool isFirstInTheirRun;
  final String? otherPhotoUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            if (isFirstInTheirRun)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF2A2A2A),
                  child: otherPhotoUrl != null && otherPhotoUrl!.isNotEmpty
                      ? ClipOval(
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: FirebaseProfileImage(
                              url: otherPhotoUrl!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      : const Icon(Icons.person, size: 18, color: Colors.white38),
                ),
              )
            else
              const SizedBox(width: 40),
          ],
          Flexible(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isMe ? bubbleYou : bubbleThem,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                border: isMe
                    ? Border.all(color: accent.withValues(alpha: 0.25))
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  message.text,
                  style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.35),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
