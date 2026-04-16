import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_firestore.dart';
import 'main_shell_screen.dart';
import 'profile_setup_screen.dart';

/// After sign-in, requires a complete Firestore profile before [MainShellScreen].
class ProfileGate extends StatelessWidget {
  const ProfileGate({required this.user, super.key});

  final User user;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load profile: ${snapshot.error}'),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final doc = snapshot.data;
        if (doc == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (UserFirestore.snapshotShowsCompleteProfile(doc)) {
          return const MainShellScreen();
        }
        return ProfileSetupScreen(
          user: user,
          initialData: doc.data(),
        );
      },
    );
  }
}
