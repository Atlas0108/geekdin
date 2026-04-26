import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_firestore.dart';
import 'chat_screen.dart';
import 'geekout_screen.dart';
import 'matches_screen.dart';
import 'my_profile_screen.dart';
import 'swipe_screen.dart';

/// Bottom navigation: Swipe (default), Geekout, Matches, Chat, Profile.
class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _index = 0;

  static const _titles = ['Swipe', 'Geekout', 'Matches', 'Chat', 'Profile'];

  bool get _isSwipeTab => _index == 0;
  bool get _isProfileTab => _index == 4;

  Future<void> _openProfileSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = snap.data() ?? const <String, dynamic>{};

    int readInt(dynamic value, int fallback) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.round();
      }
      return fallback;
    }

    final agePref = data['agePreference'];
    final agePrefMap = agePref is Map ? agePref : const <String, dynamic>{};
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: _DiscoverySettingsSheet(
            uid: user.uid,
            initialGender:
                (data['gender'] as String?) ?? UserFirestore.defaultGender,
            initialGenderPreference:
                (data['genderPreference'] as String?) ??
                UserFirestore.defaultGenderPreference,
            initialAgeMin: readInt(
              agePrefMap['min'],
              UserFirestore.defaultAgeMinPreference,
            ),
            initialAgeMax: readInt(
              agePrefMap['max'],
              UserFirestore.defaultAgeMaxPreference,
            ),
            initialDistance: readInt(
              data['distance'],
              UserFirestore.defaultDistance,
            ),
            initialIsGlobal:
                (data['isGlobal'] as bool?) ?? UserFirestore.defaultIsGlobal,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSwipeTab
          ? null
          : AppBar(
              title: Text(_titles[_index]),
              actions: [
                if (_isProfileTab)
                  IconButton(
                    tooltip: 'Discovery settings',
                    onPressed: _openProfileSettings,
                    icon: const Icon(Icons.settings_outlined),
                  )
                else
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout),
                  ),
              ],
            ),
      body: IndexedStack(
        index: _index,
        children: const [
          SwipeScreen(),
          GeekoutScreen(),
          MatchesScreen(),
          ChatScreen(),
          MyProfileScreen(embeddedInShell: true),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.view_carousel_outlined),
            selectedIcon: Icon(Icons.view_carousel),
            label: 'Swipe',
          ),
          NavigationDestination(
            icon: Icon(Icons.celebration_outlined),
            selectedIcon: Icon(Icons.celebration),
            label: 'Geekout',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Matches',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _DiscoverySettingsSheet extends StatefulWidget {
  const _DiscoverySettingsSheet({
    required this.uid,
    required this.initialGender,
    required this.initialGenderPreference,
    required this.initialAgeMin,
    required this.initialAgeMax,
    required this.initialDistance,
    required this.initialIsGlobal,
  });

  final String uid;
  final String initialGender;
  final String initialGenderPreference;
  final int initialAgeMin;
  final int initialAgeMax;
  final int initialDistance;
  final bool initialIsGlobal;

  @override
  State<_DiscoverySettingsSheet> createState() =>
      _DiscoverySettingsSheetState();
}

class _DiscoverySettingsSheetState extends State<_DiscoverySettingsSheet> {
  static const _genderOptions = <String, String>{
    'woman': 'Woman',
    'man': 'Man',
    'non_binary': 'Non-binary',
    'other': 'Other',
  };

  static const _genderPreferenceOptions = <String, String>{
    'everyone': 'Everyone',
    'women': 'Women',
    'men': 'Men',
    'non_binary': 'Non-binary',
  };

  late String _gender = _normalizeGender(widget.initialGender);
  late String _genderPreference = _normalizeGenderPreference(
    widget.initialGenderPreference,
  );
  late RangeValues _ageRange = _initialRange(
    widget.initialAgeMin,
    widget.initialAgeMax,
  );
  late double _distance = widget.initialDistance.clamp(1, 500).toDouble();
  late bool _isGlobal = widget.initialIsGlobal;
  bool _saving = false;
  String? _error;

  static String _normalizeGender(String value) {
    return _genderOptions.containsKey(value)
        ? value
        : _genderOptions.keys.first;
  }

  static String _normalizeGenderPreference(String value) {
    return _genderPreferenceOptions.containsKey(value)
        ? value
        : UserFirestore.defaultGenderPreference;
  }

  static RangeValues _initialRange(int min, int max) {
    final clampedMin = min.clamp(18, 100);
    final clampedMax = max.clamp(18, 100);
    if (clampedMin <= clampedMax) {
      return RangeValues(clampedMin.toDouble(), clampedMax.toDouble());
    }
    return RangeValues(
      UserFirestore.defaultAgeMinPreference.toDouble(),
      UserFirestore.defaultAgeMaxPreference.toDouble(),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await UserFirestore.saveDiscoveryPreferences(
        uid: widget.uid,
        gender: _gender,
        genderPreference: _genderPreference,
        agePreferenceMin: _ageRange.start.round(),
        agePreferenceMax: _ageRange.end.round(),
        distance: _distance.round(),
        isGlobal: _isGlobal,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not save settings: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton.filled(
          tooltip: 'Save and close',
          onPressed: _saving ? null : _save,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            shape: const CircleBorder(),
          ),
          icon: const Icon(Icons.check),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: [
          DropdownButtonFormField<String>(
            value: _gender,
            decoration: const InputDecoration(
              labelText: 'I am a:',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final entry in _genderOptions.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: _saving
                ? null
                : (v) {
                    if (v == null) {
                      return;
                    }
                    setState(() => _gender = v);
                  },
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: _genderPreference,
            decoration: const InputDecoration(
              labelText: 'Interested in:',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final entry in _genderPreferenceOptions.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: _saving
                ? null
                : (v) {
                    if (v == null) {
                      return;
                    }
                    setState(() => _genderPreference = v);
                  },
          ),
          const SizedBox(height: 20),
          const SizedBox(height: 8),
          Text(
            'Age preference: ${_ageRange.start.round()}-${_ageRange.end.round()}',
            style: theme.textTheme.titleMedium,
          ),
          RangeSlider(
            values: _ageRange,
            min: 18,
            max: 100,
            divisions: 82,
            labels: RangeLabels(
              '${_ageRange.start.round()}',
              '${_ageRange.end.round()}',
            ),
            onChanged: _saving ? null : (v) => setState(() => _ageRange = v),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Global discovery'),
            subtitle: const Text(
              'When enabled, match globally instead of by local distance.',
            ),
            value: _isGlobal,
            onChanged: _saving ? null : (v) => setState(() => _isGlobal = v),
          ),
          const SizedBox(height: 8),
          Text(
            'Distance: ${_distance.round()} mi',
            style: theme.textTheme.titleMedium?.copyWith(
              color: _isGlobal ? theme.colorScheme.onSurfaceVariant : null,
            ),
          ),
          Slider(
            value: _distance,
            min: 1,
            max: 500,
            divisions: 499,
            label: '${_distance.round()} mi',
            onChanged: (_saving || _isGlobal)
                ? null
                : (v) => setState(() => _distance = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
