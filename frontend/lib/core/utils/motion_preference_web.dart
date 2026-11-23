import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class MotionPreference extends ValueNotifier<bool> {
  MotionPreference()
      : _query = web.window.matchMedia('(prefers-reduced-motion: reduce)'),
        super(false) {
    value = _query.matches;
    _listener = ((web.Event event) {
      value = _query.matches;
    }).toJS;
    _query.addEventListener('change', _listener);
  }

  final web.MediaQueryList _query;
  late final JSFunction _listener;

  @override
  void dispose() {
    _query.removeEventListener('change', _listener);
    super.dispose();
  }
}
