import 'dart:convert';
import 'dart:typed_data';

Uint8List buildCertificatePdf({
  required String name,
  required String serial,
  required String course,
  required String date,
  String organization = 'KuhuGrantha Private Limited',
  String signerName = 'Sarah Jenkins',
  String signerTitle = 'Head of Talent & Human Resources',
  String? body,
}) {
  String esc(String s) => s.replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)');
  final c = StringBuffer();
  void text(double x, double y, double size, String s, {bool bold = false}) {
    c.write('BT /${bold ? 'F2' : 'F1'} $size Tf $x $y Td (${esc(s)}) Tj ET\n');
  }

  List<String> wrap(String value, int maxChars) {
    final words = value.trim().split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length > maxChars && current.isNotEmpty) {
        lines.add(current);
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  c.write('0.09 0.13 0.29 RG 2.5 w 40 40 532 712 re S\n');
  c.write('0.78 0.62 0.24 RG 1 w 52 52 508 688 re S\n');
  text(306 - (organization.length * 5.7), 700, 22, organization, bold: true);
  text(228, 672, 12, 'Certificate of Completion');
  text(248, 606, 11, 'This is to certify that');
  text(306 - (name.length * 6.2), 566, 24, name, bold: true);
  text(160, 524, 11, 'has successfully completed the intern training program in');
  text(306 - (course.length * 2.6), 496, 14, course, bold: true);

  final bodyLines = wrap(
    (body == null || body.trim().isEmpty)
        ? 'with all video and assessment milestones fulfilled.'
        : body.trim(),
    82,
  );
  final visibleLines = bodyLines.length > 12 ? bodyLines.sublist(0, 12) : bodyLines;
  var bodyY = 462.0;
  for (final line in visibleLines) {
    text(306 - (line.length * 2.75), bodyY, 11, line);
    bodyY -= 15;
  }

  text(96, 230, 11, 'Certificate Serial: $serial');
  text(96, 210, 11, 'Issue Date: $date');
  text(380, 250, 12, signerName, bold: true);
  c.write('0.09 0.13 0.29 RG 1 w 360 244 m 520 244 l S\n');
  text(380, 230, 9, signerTitle);
  text(380, 216, 9, organization);
  text(214, 120, 9, 'KGPL Intern Training & Management Portal');

  final stream = c.toString();
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> /Contents 4 0 R >>',
    '<< /Length ${stream.length} >>\nstream\n${stream}endstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>',
  ];

  final out = BytesBuilder();
  out.add(utf8.encode('%PDF-1.4\n'));
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.add(utf8.encode('${i + 1} 0 obj\n${objects[i]}\nendobj\n'));
  }
  final xref = out.length;
  out.add(utf8.encode('xref\n0 ${objects.length + 1}\n'));
  out.add(utf8.encode('0000000000 65535 f \n'));
  for (final off in offsets) {
    out.add(utf8.encode('${off.toString().padLeft(10, '0')} 00000 n \n'));
  }
  out.add(utf8.encode('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF'));
  return out.toBytes();
}
