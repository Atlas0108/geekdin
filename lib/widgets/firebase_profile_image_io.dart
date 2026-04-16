import 'package:flutter/widgets.dart';

/// Not used on non-web builds (see [FirebaseProfileImage] `kIsWeb` branch).
Widget buildFirebaseProfileImageForWeb(String url, BoxFit fit) {
  assert(
    false,
    'buildFirebaseProfileImageForWeb must only be called when kIsWeb is true',
  );
  return const SizedBox.shrink();
}
