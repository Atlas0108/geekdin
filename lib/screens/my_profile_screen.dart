import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/firebase_profile_image.dart';

/// Signed-in user's Firestore profile: photos, bio, city, interests.
class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Not signed in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My profile'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data();
          if (data == null) {
            return const Center(child: Text('No profile document yet.'));
          }

          final displayName = (data['displayName'] as String?)?.trim();
          final email = (data['email'] as String?)?.trim() ?? user.email ?? '';
          final city = (data['city'] as String?)?.trim();
          final bio = (data['bio'] as String?)?.trim() ?? '';
          final urls = data['profileImageUrls'];
          final interests = data['interests'];

          final photos = <String>[];
          if (urls is List) {
            for (final u in urls) {
              if (u is String && u.trim().isNotEmpty) {
                photos.add(u.trim());
              }
            }
          }

          final interestList = <String>[];
          if (interests is List) {
            for (final e in interests) {
              if (e is String && e.trim().isNotEmpty) {
                interestList.add(e.trim());
              }
            }
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (photos.isNotEmpty) ...[
                Text('Photos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: 150,
                          height: 200,
                          child: FirebaseProfileImage(url: photos[i]),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 28),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    'No photos on your profile yet.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              Text(
                displayName?.isNotEmpty == true ? displayName! : 'Your profile',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (city != null && city.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.place_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(city, style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  ],
                ),
              ],
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Bio', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(bio, style: Theme.of(context).textTheme.bodyLarge),
              ],
              if (interestList.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Interests', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in interestList)
                      Chip(label: Text(t)),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
