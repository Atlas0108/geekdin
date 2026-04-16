import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/profile_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const GeekdinApp());
}

class GeekdinApp extends StatelessWidget {
  const GeekdinApp({super.key});

  static const Color _lightSeed = Colors.deepPurple;

  static ThemeData _lightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _lightSeed),
      brightness: Brightness.light,
    );
  }

  /// Dark UI with electric cyan / magenta / lime accents on near-black surfaces.
  static ThemeData _darkNeonTheme() {
    const neonCyan = Color(0xFF00E5FF);
    const neonMagenta = Color(0xFFFF3AD4);
    const neonLime = Color(0xFFC8FF33);

    final scheme = ColorScheme.fromSeed(
      seedColor: neonCyan,
      brightness: Brightness.dark,
    ).copyWith(
      primary: neonCyan,
      onPrimary: const Color(0xFF001416),
      primaryContainer: const Color(0xFF00404A),
      onPrimaryContainer: const Color(0xFF9CF9FF),
      secondary: neonMagenta,
      onSecondary: const Color(0xFF2D0018),
      secondaryContainer: const Color(0xFF5C1040),
      onSecondaryContainer: const Color(0xFFFFB8E8),
      tertiary: neonLime,
      onTertiary: const Color(0xFF161A00),
      tertiaryContainer: const Color(0xFF3D4500),
      onTertiaryContainer: const Color(0xFFE8FF9A),
      surface: const Color(0xFF06060A),
      onSurface: const Color(0xFFE8E8F0),
      surfaceContainerLowest: const Color(0xFF030308),
      surfaceContainerLow: const Color(0xFF0C0C12),
      surfaceContainer: const Color(0xFF12121A),
      surfaceContainerHigh: const Color(0xFF1A1A24),
      surfaceContainerHighest: const Color(0xFF242432),
      onSurfaceVariant: const Color(0xFFC4C4D0),
      outline: const Color(0xFF5A5A6E),
      outlineVariant: const Color(0xFF3A3A4A),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geekdin',
      theme: _lightTheme(),
      darkTheme: _darkNeonTheme(),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

/// Shows [LoginScreen] when signed out; otherwise [ProfileGate] for onboarding + home.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user != null) {
          return ProfileGate(user: user);
        }
        return const LoginScreen();
      },
    );
  }
}
