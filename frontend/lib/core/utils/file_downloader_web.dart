import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> downloadBytes(String filename, List<int> bytes, {String mime = 'application/octet-stream'}) async {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final blob = web.Blob(<JSAny>[data.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  Future.delayed(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
}

void openExternalUrl(String url) {
  web.window.open(url, '_blank');
}