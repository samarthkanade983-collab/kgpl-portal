import 'large_video_source.dart';
import 'large_video_uploader_native.dart'
    if (dart.library.js_interop) 'large_video_uploader_web.dart' as impl;

export 'large_video_source.dart';

Future<SelectedLargeVideo?> pickLargeVideo({
  required List<String> allowedExtensions,
}) =>
    impl.pickLargeVideo(allowedExtensions: allowedExtensions);

LargeVideoUploader createLargeVideoUploader(SelectedLargeVideo video) =>
    impl.createLargeVideoUploader(video);
