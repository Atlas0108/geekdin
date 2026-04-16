// Intentional: real DOM img + platform view to avoid Image.network/fetch CORS on Storage.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

final Map<String, VoidCallback> _errorCallbacks = {};

String _cssObjectFit(BoxFit fit) {
  switch (fit) {
    case BoxFit.contain:
      return 'contain';
    case BoxFit.fill:
      return 'fill';
    case BoxFit.fitHeight:
      return 'scale-down';
    case BoxFit.fitWidth:
      return 'scale-down';
    case BoxFit.none:
      return 'none';
    case BoxFit.scaleDown:
      return 'scale-down';
    case BoxFit.cover:
      return 'cover';
  }
}

/// Uses a real HTML &lt;img&gt; (platform view) so the browser does not use
/// `fetch()` for decode — avoids Storage CORS issues with Flutter web.
Widget buildFirebaseProfileImageForWeb(String url, BoxFit fit) {
  final u = url.trim();
  if (u.isEmpty) {
    return const _BrokenIcon();
  }
  return _WebImg(url: u, fit: fit);
}

class _BrokenIcon extends StatelessWidget {
  const _BrokenIcon();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.broken_image_outlined, size: 48, color: theme.colorScheme.outline),
    );
  }
}

class _WebImg extends StatefulWidget {
  const _WebImg({required this.url, required this.fit});

  final String url;
  final BoxFit fit;

  @override
  State<_WebImg> createState() => _WebImgState();
}

class _WebImgState extends State<_WebImg> {
  late final String _viewType;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _viewType =
        'fb_profile_${widget.url.hashCode}_${identityHashCode(this)}';
    _errorCallbacks[_viewType] = _onImgError;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final img = html.ImageElement()
        ..src = widget.url
        ..style.objectFit = _cssObjectFit(widget.fit)
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block'
        // Let drags/taps hit Flutter (e.g. swipe GestureDetector) instead of the DOM layer.
        ..style.pointerEvents = 'none'
        ..style.userSelect = 'none'
        ..draggable = false;
      img.onError.listen((_) {
        _errorCallbacks[_viewType]?.call();
      });
      return img;
    });
  }

  void _onImgError() {
    if (!mounted) {
      return;
    }
    setState(() => _failed = true);
  }

  @override
  void dispose() {
    _errorCallbacks.remove(_viewType);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const _BrokenIcon();
    }
    return HtmlElementView(viewType: _viewType);
  }
}
