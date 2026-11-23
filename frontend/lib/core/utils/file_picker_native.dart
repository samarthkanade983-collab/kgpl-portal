import 'package:file_picker/file_picker.dart';
import 'picked_file.dart';

Future<PickedFile?> pickDeviceFile({required List<String> allowedExtensions}) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final f = result.files.first;
  return PickedFile(name: f.name, size: f.size, bytes: f.bytes);
}