import 'dart:typed_data';

class PickedFile {
  final String name;
  final int size;
  final Uint8List? bytes;

  const PickedFile({required this.name, required this.size, this.bytes});

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  }
}