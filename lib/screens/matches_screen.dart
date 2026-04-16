import 'package:flutter/material.dart';

class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Matches',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}
