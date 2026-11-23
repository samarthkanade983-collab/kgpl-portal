import 'dart:convert';
import 'dart:typed_data';

import 'safe_convert.dart';

String _esc(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('(', '\\(')
    .replaceAll(')', '\\)');

String watchTimeLabel(int seconds) {
  final int h = seconds ~/ 3600;
  final int m = (seconds % 3600) ~/ 60;
  final int s = seconds % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  return '${m}m ${s}s';
}

/// Landscape A4 intern performance report built without extra packages.
Uint8List buildPerformancePdf({
  required List<dynamic> rows,
  required String generatedAt,
}) {
  const double pageWidth = 842;
  const double pageHeight = 595;
  const double margin = 36;

  const List<({String label, double x})> columns = [
    (label: 'Intern Name', x: 36),
    (label: 'Intern Code', x: 160),
    (label: 'Department', x: 244),
    (label: 'Team Leader', x: 338),
    (label: 'Videos', x: 432),
    (label: 'Watch Time', x: 484),
    (label: 'Tests (Passed / Taken)', x: 560),
    (label: 'Avg Quiz Score', x: 672),
    (label: 'Tasks', x: 748),
  ];

  final List<StringBuffer> pages = [];
  late StringBuffer page;
  double y = 0;
  int pageNo = 0;

  void text(StringBuffer c, double x, double yy, double size, String s,
      {bool bold = false}) {
    c.write('BT /${bold ? 'F2' : 'F1'} $size Tf $x $yy Td (${_esc(s)}) Tj ET\n');
  }

  StringBuffer startPage() {
    pageNo++;
    final c = StringBuffer();
    c.write('0.09 0.13 0.29 RG 1.5 w ${margin - 12} ${pageHeight - 46} ${pageWidth - 2 * (margin - 12)} 30 re S\n');
    text(c, margin, pageHeight - 38, 13, 'KuhuGrantha Private Limited', bold: true);
    text(c, pageWidth - 250, pageHeight - 34, 9, 'Intern Performance Report');
    text(c, pageWidth - 250, pageHeight - 45, 8, 'Generated: $generatedAt');
    double headerY = pageHeight - 72;
    if (pageNo > 1) {
      text(c, margin, pageHeight - 20, 9, 'Intern Performance Report (continued)', bold: true);
      headerY = pageHeight - 44;
    }
    c.write('0.85 0.88 0.93 RG 0.8 w ${margin - 10} ${headerY - 8} m ${pageWidth - margin + 10} ${headerY - 8} l S\n');
    for (final col in columns) {
      text(c, col.x, headerY, 8, col.label, bold: true);
    }
    c.write('0.85 0.88 0.93 RG 0.6 w ${margin - 10} ${headerY - 14} m ${pageWidth - margin + 10} ${headerY - 14} l S\n');
    y = headerY - 30;
    return c;
  }

  String clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}.';

  page = startPage();
  for (final row in rows) {
    if (y < 66) {
      pages.add(page);
      page = startPage();
    }
    final int watchSec = safeInt(row['total_watched_seconds']);
    final int taken = safeInt(row['tests_attempted']);
    final int passed = safeInt(row['tests_passed']);
    final num score = safeDouble(row['avg_test_score']);
    final String scoreLabel = taken == 0 ? 'Not attempted' : '${score.toStringAsFixed(1)}%';

    final values = <String>[
      clip((row['name'] ?? '').toString(), 26),
      clip((row['intern_code'] ?? '-').toString(), 15),
      clip((row['department_name'] ?? 'Not set').toString(), 20),
      clip((row['team_leader_name'] ?? 'Unassigned').toString(), 18),
      '${safeInt(row['videos_completed'])}',
      watchTimeLabel(watchSec),
      '$passed / $taken',
      scoreLabel,
      '${safeInt(row['tasks_submitted'])}',
    ];
    for (var i = 0; i < columns.length; i++) {
      text(page, columns[i].x, y, 8, values[i]);
    }
    y -= 20;
  }
  pages.add(page);

  final int fontRegular = 3 + pages.length * 2;
  final int fontBold = fontRegular + 1;
  final objects = <String>[];
  final kids = <String>[];
  for (var i = 0; i < pages.length; i++) {
    final pageObj = 3 + i * 2;
    final contentObj = pageObj + 1;
    kids.add('$pageObj 0 R');
    objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageWidth $pageHeight] '
        '/Resources << /Font << /F1 $fontRegular 0 R /F2 $fontBold 0 R >> >> '
        '/Contents $contentObj 0 R >>');
    final stream = pages[i].toString();
    objects.add('<< /Length ${stream.length} >>\nstream\n${stream}endstream');
  }

  final all = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>',
    ...objects,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>',
  ];

  final out = BytesBuilder();
  out.add(utf8.encode('%PDF-1.4\n'));
  final offsets = <int>[];
  for (var i = 0; i < all.length; i++) {
    offsets.add(out.length);
    out.add(utf8.encode('${i + 1} 0 obj\n${all[i]}\nendobj\n'));
  }
  final xref = out.length;
  out.add(utf8.encode('xref\n0 ${all.length + 1}\n'));
  out.add(utf8.encode('0000000000 65535 f \n'));
  for (final off in offsets) {
    out.add(utf8.encode('${off.toString().padLeft(10, '0')} 00000 n \n'));
  }
  out.add(utf8.encode(
      'trailer\n<< /Size ${all.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF'));
  return out.toBytes();
}
