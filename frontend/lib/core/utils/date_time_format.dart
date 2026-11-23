import 'package:intl/intl.dart';

DateTime? _parseLocal(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty || raw == 'null') return null;
  return DateTime.tryParse(raw)?.toLocal();
}

/// 'yyyy-MM-dd HH:mm:ss' in the viewer's own clock.
String formatTimestamp(dynamic value, {String fallback = '-'}) {
  final dt = _parseLocal(value);
  return dt == null ? fallback : DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
}

/// 'yyyy-MM-dd HH:mm' in the viewer's own clock.
String formatTimestampMinutes(dynamic value, {String fallback = '-'}) {
  final dt = _parseLocal(value);
  return dt == null ? fallback : DateFormat('yyyy-MM-dd HH:mm').format(dt);
}

/// 'yyyy-MM-dd' in the viewer's own clock.
String formatDateOnly(dynamic value, {String fallback = '-'}) {
  final dt = _parseLocal(value);
  return dt == null ? fallback : DateFormat('yyyy-MM-dd').format(dt);
}
