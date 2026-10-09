import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;
import 'package:flutter/widgets.dart';

final Set<String> _registeredViewTypes = <String>{};

Widget? buildPlatformWebImage({
  required Uri url,
  required String alt,
  BoxFit fit = BoxFit.contain,
  BorderRadius? borderRadius,
}) {
  final urlString = url.toString();
  final objectFit = fit == BoxFit.cover ? 'cover' : 'contain';
  final radius = borderRadius != null ? '${borderRadius.topLeft.x}px' : '0px';
  // Stable view type based on URL, fit, and radius
  final viewType =
      'divan-web-img-${urlString.hashCode.abs()}-$objectFit-${radius.replaceAll('.', '_')}';

  if (!_registeredViewTypes.contains(viewType)) {
    _registeredViewTypes.add(viewType);
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final img = web.document.createElement('img') as web.HTMLImageElement;
      img.src = urlString;
      img.alt = alt;
      img.style.width = '100%';
      img.style.height = '100%';
      img.style.objectFit = objectFit;
      img.style.borderRadius = radius;
      img.style.display = 'block';
      // Prevent HTML element from intercepting pointer gestures intended for Flutter
      img.style.pointerEvents = 'none';
      img.style.userSelect = 'none';
      return img;
    });
  }

  return HtmlElementView(viewType: viewType);
}
