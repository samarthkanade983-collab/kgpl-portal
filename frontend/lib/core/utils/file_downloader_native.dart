import 'dart:io';

Future<void> downloadBytes(String filename, List<int> bytes, {String mime = 'application/octet-stream'}) async {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
  final dir = Directory('$home/Downloads');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  await File('${dir.path}/$filename').writeAsBytes(bytes, flush: true);
}

void openExternalUrl(String url) {
  if (Platform.isWindows) {
    Process.run('cmd', ['/c', 'start', '', url]);
  } else if (Platform.isMacOS) {
    Process.run('open', [url]);
  } else {
    Process.run('xdg-open', [url]);
  }
}