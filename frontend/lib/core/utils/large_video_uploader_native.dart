import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../network/api_service.dart';
import 'large_video_source.dart';

const int _chunkSize = 32 * 1024 * 1024;
const int _chunkAttempts = 3;

class _FileHandle {
  final String path;

  _FileHandle(this.path);
}

class _OffsetMismatch implements Exception {
  final int offset;

  _OffsetMismatch(this.offset);
}

Future<SelectedLargeVideo?> pickLargeVideo({
  required List<String> allowedExtensions,
}) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    withData: false,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;
  final path = file.path;
  if (path == null) {
    throw LargeUploadException('Could not access the selected file.');
  }
  return SelectedLargeVideo(
    name: file.name,
    size: file.size,
    handle: _FileHandle(path),
  );
}

LargeVideoUploader createLargeVideoUploader(SelectedLargeVideo video) =>
    NativeLargeVideoUploader(video);

class NativeLargeVideoUploader implements LargeVideoUploader {
  @override
  final SelectedLargeVideo video;

  NativeLargeVideoUploader(this.video);

  String? _uploadId;
  int _offset = 0;

  Map<String, String> get _authHeaders {
    final token = ApiService().token;
    if (token == null || token.isEmpty) {
      throw LargeUploadException('Your session expired. Please sign in again.');
    }
    return {'Authorization': 'Bearer $token'};
  }

  @override
  int get uploadedBytes => _offset;

  @override
  Future<String> upload({
    required UploadProgress onProgress,
    required bool Function() isCancelled,
  }) async {
    final headers = _authHeaders;

    if (_uploadId == null) {
      await _start();
    } else {
      await _recoverOffset();
    }

    final file = File((video.handle as _FileHandle).path);

    while (_offset < video.size) {
      if (isCancelled()) {
        await cancel();
        throw LargeUploadCancelled();
      }

      final end = math.min(_offset + _chunkSize, video.size);
      final chunk = await _readChunk(file, _offset, end);

      for (var attempt = 1;; attempt++) {
        try {
          await _sendChunk(chunk, _offset, headers);
          onProgress(_offset, video.size);
          break;
        } on _OffsetMismatch catch (mismatch) {
          _offset = mismatch.offset;
          break;
        } catch (error) {
          if (attempt >= _chunkAttempts) {
            throw LargeUploadException(
              'Connection interrupted at ${_formatBytes(_offset)} of '
              '${_formatBytes(video.size)}. Press Publish again to resume.',
            );
          }
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
          if (isCancelled()) {
            await cancel();
            throw LargeUploadCancelled();
          }
        }
      }
    }

    final response = await http.post(
      Uri.parse('${ApiConfig.videoUploads}/$_uploadId/complete'),
      headers: headers,
    );
    final body = _decode(response);
    _uploadId = null;
    _offset = 0;
    return body['video_path'] as String;
  }

  Future<Uint8List> _readChunk(File file, int start, int end) async {
    final builder = BytesBuilder(copy: false);
    await for (final data in file.openRead(start, end)) {
      builder.add(data);
    }
    return builder.takeBytes();
  }

  Future<void> _start() async {
    final response = await http.post(
      Uri.parse(ApiConfig.videoUploads),
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'file_name': video.name, 'file_size': video.size}),
    );
    final body = _decode(response);
    _uploadId = body['upload_id'] as String;
    _offset = (body['offset'] as num?)?.toInt() ?? 0;
  }

  Future<void> _recoverOffset() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.videoUploads}/$_uploadId'),
      headers: _authHeaders,
    );
    if (response.statusCode == 404) {
      _uploadId = null;
      _offset = 0;
      await _start();
      return;
    }
    final body = _decode(response);
    _offset = (body['offset'] as num?)?.toInt() ?? 0;
  }

  Future<void> _sendChunk(
    Uint8List chunk,
    int offset,
    Map<String, String> headers,
  ) async {
    final response = await http.put(
      Uri.parse('${ApiConfig.videoUploads}/$_uploadId/chunk?offset=$offset'),
      headers: {...headers, 'Content-Type': 'application/octet-stream'},
      body: chunk,
    );

    if (response.statusCode == 409) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw _OffsetMismatch((body['offset'] as num).toInt());
    }

    final body = _decode(response);
    _offset = (body['offset'] as num).toInt();
  }

  @override
  Future<void> cancel() async {
    final id = _uploadId;
    if (id == null) return;
    _uploadId = null;
    _offset = 0;
    try {
      await http.delete(
        Uri.parse('${ApiConfig.videoUploads}/$id'),
        headers: _authHeaders,
      );
    } catch (_) {
      // The server also expires abandoned sessions after 24 hours.
    }
  }
}

Map<String, dynamic> _decode(http.Response response) {
  dynamic body;
  try {
    body = jsonDecode(response.body);
  } catch (_) {
    body = null;
  }
  if (response.statusCode >= 200 && response.statusCode < 300 && body is Map) {
    return body.cast<String, dynamic>();
  }
  final message = body is Map && body['error'] != null
      ? body['error'].toString()
      : 'Upload failed with status ${response.statusCode}.';
  throw LargeUploadException(message);
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
