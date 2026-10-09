import 'package:flutter/widgets.dart';
import 'web_image_view_stub.dart'
    if (dart.library.js_interop) 'web_image_view_web.dart'
    as platform_view;

Widget? platformWebImage({
  required Uri url,
  required String alt,
  BoxFit fit = BoxFit.contain,
  BorderRadius? borderRadius,
}) =>
    platform_view.buildPlatformWebImage(
      url: url,
      alt: alt,
      fit: fit,
      borderRadius: borderRadius,
    );
