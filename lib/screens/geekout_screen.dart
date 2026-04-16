import 'package:flutter/material.dart';

class GeekoutScreen extends StatelessWidget {
  const GeekoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Geekout',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}
