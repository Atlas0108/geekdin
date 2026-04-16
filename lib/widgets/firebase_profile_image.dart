import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geekdin/firebase_options.dart';
import 'package:http/http.dart' as http;

import 'firebase_profile_image_io.dart'
    if (dart.library.html) 'firebase_profile_image_html.dart' as img_html;

/// Decodes `.../o/{encodedPath}` from a Firebase Storage download URL.
String? objectPathFromFirebaseDownloadUrl(String url) {
  try {
    final uri = Uri.parse(url.trim());
    if (!uri.host.contains('firebasestorage.googleapis.com')) {
      return null;
    }
    const marker = '/o/';
    final i = uri.path.indexOf(marker);
    if (i < 0) {
      return null;
    }
    final encoded = uri.path.substring(i + marker.length);
    return Uri.decodeFull(encoded);
  } catch (_) {
    return null;
  }
}

FirebaseStorage _projectStorage() {
  final raw = DefaultFirebaseOptions.currentPlatform.storageBucket ??
      'geekdin-f7049.firebasestorage.app';
  final gs = raw.startsWith('gs://') ? raw : 'gs://$raw';
  return FirebaseStorage.instanceFor(
    app: Firebase.app(),
    bucket: gs,
  );
}

/// Loads profile photos from Firebase Storage download URLs.
///
/// **Web:** real HTML img via [HtmlElementView] (see `firebase_profile_image_html.dart`)
/// so loads are not blocked by `fetch()` CORS against `firebasestorage.googleapis.com`.
///
/// **Other platforms:** Storage [Reference.getData] + HTTP fallback.
class FirebaseProfileImage extends StatefulWidget {
  const FirebaseProfileImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
  });

  final String url;
  final BoxFit fit;

  @override
  State<FirebaseProfileImage> createState() => _FirebaseProfileImageState();
}

class _FirebaseProfileImageState extends State<FirebaseProfileImage> {
  Uint8List? _bytes;
  bool _failed = false;

  static const _maxBytes = 20 * 1024 * 1024;
  static const _httpHeaders = {'User-Agent': 'GeekdinFlutter/1.0'};

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant FirebaseProfileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kIsWeb) {
      return;
    }
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<Uint8List?> _tryRefGetData(Reference ref) async {
    final data = await ref.getData(_maxBytes);
    if (data != null && data.isNotEmpty) {
      return data;
    }
    return null;
  }

  Future<void> _load() async {
    final u = widget.url.trim();
    if (u.isEmpty) {
      if (mounted) {
        setState(() => _failed = true);
      }
      return;
    }

    Future<void> apply(Uint8List data) async {
      if (!mounted) {
        return;
      }
      setState(() {
        _bytes = data;
        _failed = false;
      });
    }

    final path = objectPathFromFirebaseDownloadUrl(u);
    if (path != null) {
      try {
        final data = await _tryRefGetData(_projectStorage().ref(path));
        if (data != null) {
          await apply(data);
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FirebaseProfileImage ref($path): $e');
        }
      }

      try {
        final data = await _tryRefGetData(FirebaseStorage.instance.ref(path));
        if (data != null) {
          await apply(data);
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FirebaseProfileImage default ref($path): $e');
        }
      }
    }

    if (u.contains('firebasestorage.googleapis.com') || u.startsWith('gs://')) {
      try {
        final ref = FirebaseStorage.instance.refFromURL(u);
        final data = await _tryRefGetData(ref);
        if (data != null) {
          await apply(data);
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FirebaseProfileImage refFromURL: $e');
        }
      }
    }

    try {
      final res = await http.get(Uri.parse(u), headers: _httpHeaders);
      if (!mounted) {
        return;
      }
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await apply(res.bodyBytes);
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FirebaseProfileImage HTTP: $e');
      }
    }

    if (mounted) {
      setState(() => _failed = true);
    }
  }

  Widget _broken(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.broken_image_outlined, size: 48, color: theme.colorScheme.outline),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.url.trim();

    if (kIsWeb) {
      if (u.isEmpty) {
        return _broken(context);
      }
      return KeyedSubtree(
        key: ValueKey(u),
        child: img_html.buildFirebaseProfileImageForWeb(u, widget.fit),
      );
    }

    if (_failed) {
      return _broken(context);
    }
    if (_bytes == null) {
      return const ColoredBox(
        color: Colors.black12,
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: widget.fit,
      gaplessPlayback: true,
    );
  }
}
