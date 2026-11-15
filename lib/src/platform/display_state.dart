import 'dart:ui' show Display, Locale, PlatformDispatcher;
import 'host.dart';

const _rtl = {'ar', 'he', 'fa', 'ur', 'ps', 'sd', 'ug', 'yi', 'dv', 'ckb'};

/// Apple content size categories and the text scale each one gives.
const _categories = <(String, double)>[
  ('XS', 0.82),
  ('S', 0.88),
  ('M', 0.94),
  ('L', 1.0),
  ('XL', 1.12),
  ('XXL', 1.24),
  ('XXXL', 1.35),
  ('AccessibilityM', 1.65),
  ('AccessibilityL', 1.94),
  ('AccessibilityXL', 2.35),
  ('AccessibilityXXL', 2.76),
  ('AccessibilityXXXL', 3.12),
];

/// The Apple size category whose text scale is closest to [scale].
String contentSizeCategoryFor(double scale) {
  var best = _categories.first;
  for (final entry in _categories) {
    if ((entry.$2 - scale).abs() < (best.$2 - scale).abs()) {
      best = entry;
    }
  }
  return best.$1;
}

/// Screen, language and accessibility values read from the Flutter engine.
/// Every read is a cheap property access; nothing is stored.
Map<String, String> readDisplayState(
  PlatformDispatcher dispatcher,
  HostOs host,
) {
  final result = <String, String>{};
  void put(String key, String value) {
    if (value.isNotEmpty) {
      result[key] = value;
    }
  }

  double width = 0, height = 0, scale = 0;
  final displays = dispatcher.displays.toList();
  final Display? main = displays.isEmpty ? null : displays.first;
  if (main != null && main.size.width > 0 && main.devicePixelRatio > 0) {
    width = main.size.width;
    height = main.size.height;
    scale = main.devicePixelRatio;
  } else {
    final views = dispatcher.views.toList();
    if (views.isNotEmpty && views.first.physicalSize.width > 0) {
      width = views.first.physicalSize.width;
      height = views.first.physicalSize.height;
      scale = views.first.devicePixelRatio;
    }
  }
  if (width > 0 && height > 0 && scale > 0) {
    put('screenWidth', shortNumber(width / scale));
    put('screenHeight', shortNumber(height / scale));
    put('screenScale', shortNumber(scale));
    put('screenWidthPx', '${width.round()}');
    put('screenHeightPx', '${height.round()}');
    if (host == HostOs.android) {
      put('screenDpi', '${(scale * 160).round()}');
    }
    if (host.isMobile) {
      put(
        'orientation',
        width == height
            ? 'square'
            : (height > width ? 'portrait' : 'landscape'),
      );
    }
  }
  if (displays.isNotEmpty) {
    put('screenCount', '${displays.length}');
  }
  put('colorScheme', dispatcher.platformBrightness.name);
  final locales = dispatcher.locales;
  final Locale first = locales.isEmpty ? dispatcher.locale : locales.first;
  put('language', first.languageCode);
  put('preferredLanguage', first.languageCode);
  put('region', first.countryCode ?? '');
  put('layoutDirection', _rtl.contains(first.languageCode) ? 'rtl' : 'ltr');
  final fontScale = dispatcher.scaleFontSize(1);
  if (fontScale.isFinite && fontScale > 0) {
    put('fontScale', shortNumber(fontScale));
    if (host == HostOs.ios) {
      put('contentSizeCategory', contentSizeCategoryFor(fontScale));
    }
  }
  final features = dispatcher.accessibilityFeatures;
  put('reduceMotion', '${features.disableAnimations}');
  put('boldText', '${features.boldText}');
  put('invertColors', '${features.invertColors}');
  put('increaseContrast', '${features.highContrast}');
  return result;
}
