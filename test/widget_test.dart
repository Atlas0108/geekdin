import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:geekdin/screens/login_screen.dart';

void main() {
  testWidgets('Login screen shows email, password, and register link', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );

    expect(find.text('Geekdin'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Need an account? Register'), findsOneWidget);
  });
}
