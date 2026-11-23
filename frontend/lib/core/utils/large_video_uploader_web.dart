import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../config/api_config.dart';
import '../network/api_service.dart';
import 'large_video_source.dart';

const int _chunkSize = 32 * 1024 * 1024;
const int _chunkAttempts = 3;

class _OffsetMismatch implements Exception {
  final int offset;

  _OffsetMismatch(this.offset);
}

Future<SelectedLargeVideo?> pickLargeVideo({
  required List<String> allowedExtensions,
}) {
  final completer = Completer<SelectedLargeVideo?>();
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
    if (!completer.isCompleted) {
      completer.complete(SelectedLargeVideo(
        name: file.name,
        size: file.size,
        handle: file,
      ));
    }
    input.remove();
  });

  web.EventStreamProviders.cancelEvent.forTarget(input).listen((_) {
    if (!completer.isCompleted) completer.complete(null);
    input.remove();
  });

  web.document.body!.append(input);
  input.click();
  return completer.future;
}

LargeVideoUploader createLargeVideoUploader(SelectedLargeVideo video) =>
    WebLargeVideoUploader(video);

class WebLargeVideoUploader implements LargeVideoUploader {
  @override
  final SelectedLargeVideo video;

  WebLargeVideoUploader(this.video);

  String? _uploadId;
  int _offset = 0;

  web.File get _file => video.handle as web.File;

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

    while (_offset < video.size) {
      if (isCancelled()) {
        await cancel();
        throw LargeUploadCancelled();
      }

      final end = math.min(_offset + _chunkSize, video.size);
      final blob = _file.slice(_offset, end);

      for (var attempt = 1;; attempt++) {
        try {
          await _sendChunk(blob, _offset, headers, onProgress);
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
    web.Blob blob,
    int offset,
    Map<String, String> headers,
    UploadProgress onProgress,
  ) {
    final completer = Completer<void>();
    final xhr = web.XMLHttpRequest();
    xhr.open('PUT', '${ApiConfig.videoUploads}/$_uploadId/chunk?offset=$offset');
    for (final entry in headers.entries) {
      xhr.setRequestHeader(entry.key, entry.value);
    }
    xhr.setRequestHeader('Content-Type', 'application/octet-stream');

    web.EventStreamProviders.progressEvent.forTarget(xhr.upload).listen((event) {
      final progress = event as web.ProgressEvent;
      onProgress(offset + progress.loaded, video.size);
    });

    web.EventStreamProviders.loadEvent.forTarget(xhr).listen((_) {
      if (completer.isCompleted) return;
      final status = xhr.status;
      if (status >= 200 && status < 300) {
        try {
          final body = jsonDecode(xhr.responseText) as Map<String, dynamic>;
          _offset = (body['offset'] as num).toInt();
          onProgress(_offset, video.size);
          completer.complete();
        } catch (error) {
          completer.completeError(LargeUploadException('Unexpected upload response.'));
        }
      } else if (status == 409) {
        try {
          final body = jsonDecode(xhr.responseText) as Map<String, dynamic>;
          completer.completeError(
            _OffsetMismatch((body['offset'] as num).toInt()),
          );
        } catch (_) {
          completer.completeError(LargeUploadException('Upload session changed.'));
        }
      } else {
        completer.completeError(LargeUploadException(_serverMessage(xhr)));
      }
    });

    web.EventStreamProviders.errorEvent.forTarget(xhr).listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(LargeUploadException('Network error while uploading.'));
      }
    });

    xhr.send(blob);
    return completer.future;
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

  String _serverMessage(web.XMLHttpRequest xhr) {
    try {
      final body = jsonDecode(xhr.responseText);
      if (body is Map && body['error'] != null) return body['error'].toString();
    } catch (_) {}
    return 'Upload failed with status ${xhr.status}.';
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
