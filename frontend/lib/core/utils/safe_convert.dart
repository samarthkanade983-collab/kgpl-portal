// Safe parsing utilities for API responses.
// Prevents runtime TypeErrors when MySQL drivers serialize numbers as Strings,
// decimals as strings, or return null values.

double safeDouble(dynamic val, [double fallback = 0.0]) {
  if (val == null) return fallback;
  if (val is double) return val;
  if (val is int) return val.toDouble();
  if (val is num) return val.toDouble();
  final parsed = double.tryParse(val.toString().trim());
  return parsed ?? fallback;
}

int safeInt(dynamic val, [int fallback = 0]) {
  if (val == null) return fallback;
  if (val is int) return val;
  if (val is num) return val.toInt();
  final str = val.toString().trim();
  final intParsed = int.tryParse(str);
  if (intParsed != null) return intParsed;
  final dblParsed = double.tryParse(str);
  if (dblParsed != null) return dblParsed.toInt();
  return fallback;
}

String safeString(dynamic val, [String fallback = '']) {
  if (val == null) return fallback;
  return val.toString();
}
