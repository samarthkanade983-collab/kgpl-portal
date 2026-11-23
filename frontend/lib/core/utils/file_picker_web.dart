import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'picked_file.dart';

Future<PickedFile?> pickDeviceFile({required List<String> allowedExtensions}) {
  final completer = Completer<PickedFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = allowedExtensions.map((e) => '.$e').join(',')
    ..style.display = 'none';

  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      input.remove();
      return;
    }
    final file = files.item(0)!;
    final reader = web.FileReader();
    web.EventStreamProviders.loadEvent.forTarget(reader).listen((_) {
      final result = reader.result;
      Uint8List bytes = Uint8List(0);
      if (result != null && result.isA<JSArrayBuffer>()) {
        bytes = (result as JSArrayBuffer).toDart.asUint8List();
      }
      if (!completer.isCompleted) {
        completer.complete(PickedFile(name: file.name, size: file.size, bytes: bytes));
      }
      input.remove();
    });
    web.EventStreamProviders.errorEvent.forTarget(reader).listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Could not read the selected file.'));
      }
      input.remove();
    });
    reader.readAsArrayBuffer(file);
  });

  web.EventStreamProviders.cancelEvent.forTarget(input).listen((_) {
    if (!completer.isCompleted) completer.complete(null);
    input.remove();
  });

  web.document.body!.append(input);
  input.click();
  return completer.future;
}