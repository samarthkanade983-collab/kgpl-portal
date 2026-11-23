class SelectedLargeVideo {
  final String name;
  final int size;
  final Object handle;

  SelectedLargeVideo({
    required this.name,
    required this.size,
    required this.handle,
  });
}

class LargeUploadCancelled implements Exception {}

class LargeUploadException implements Exception {
  final String message;

  LargeUploadException(this.message);

  @override
  String toString() => message;
}

typedef UploadProgress = void Function(int sentBytes, int totalBytes);

String formatFileSize(int bytes) {
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Streams a device video to the backend in chunks. Implementations keep the
/// upload id and byte offset so a failed attempt resumes instead of restarting.
abstract class LargeVideoUploader {
  SelectedLargeVideo get video;

  int get uploadedBytes;

  Future<String> upload({
    required UploadProgress onProgress,
    required bool Function() isCancelled,
  });

  Future<void> cancel();
}
