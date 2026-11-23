import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class VideoPictureInPicture extends StatefulWidget {
  final String videoUrl;

  const VideoPictureInPicture({super.key, required this.videoUrl});

  @override
  State<VideoPictureInPicture> createState() => _VideoPictureInPictureState();
}

class _VideoPictureInPictureState extends State<VideoPictureInPicture> {
  web.HTMLVideoElement? _video;
  web.MutationObserver? _observer;
  bool _active = false;
  bool _busy = false;
  bool _previousDisabled = false;
  late final JSFunction _onEnter;
  late final JSFunction _onLeave;

  bool get _supported => web.document.pictureInPictureEnabled == true;

  @override
  void initState() {
    super.initState();
    if (!_supported) return;
    _onEnter = ((web.Event event) {
      if (mounted) setState(() => _active = true);
    }).toJS;
    _onLeave = ((web.Event event) {
      _video?.disablePictureInPicture = true;
      if (mounted) setState(() => _active = false);
    }).toJS;
    _observer = web.MutationObserver(
      ((JSArray<web.MutationRecord> records, web.MutationObserver observer) {
        _attachVideo();
      }).toJS,
    );
    _observer!.observe(web.document.body!,
        web.MutationObserverInit(childList: true, subtree: true));
    _attachVideo();
  }

  void _attachVideo() {
    if (_video != null) return;
    final videos = web.document.querySelectorAll('video');
    final source = Uri.base.resolve(widget.videoUrl).toString();
    for (var i = 0; i < videos.length; i++) {
      final video = videos.item(i) as web.HTMLVideoElement;
      if (video.src != source) continue;
      _video = video;
      _previousDisabled = video.disablePictureInPicture;
      _active = web.document.pictureInPictureElement == video;
      video.disablePictureInPicture = !_active;
      video.addEventListener('enterpictureinpicture', _onEnter);
      video.addEventListener('leavepictureinpicture', _onLeave);
      _observer?.disconnect();
      if (mounted) setState(() {});
      break;
    }
  }

  Future<void> _toggle() async {
    final video = _video;
    if (video == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (web.document.pictureInPictureElement == video) {
        await web.document.exitPictureInPicture().toDart;
      } else {
        // Enable only for the explicit toolbar action, not the browser overlay.
        video.disablePictureInPicture = false;
        await video.requestPictureInPicture().toDart;
      }
    } catch (_) {
      video.disablePictureInPicture = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Picture in picture is unavailable in this browser.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _observer?.disconnect();
    final video = _video;
    if (video != null) {
      video.removeEventListener('enterpictureinpicture', _onEnter);
      video.removeEventListener('leavepictureinpicture', _onLeave);
      video.disablePictureInPicture = _previousDisabled;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    return IconButton(
      tooltip: _active ? 'Exit picture in picture' : 'Picture in picture',
      icon: Icon(
        _active ? Icons.close_fullscreen_rounded : Icons.picture_in_picture_alt,
        color: Colors.white,
        size: 22,
      ),
      onPressed: _video == null || _busy ? null : _toggle,
    );
  }
}
