import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../core/config/api_config.dart';
import '../core/network/api_service.dart';
import '../core/theme/app_theme.dart';
import 'video_picture_in_picture.dart'
    if (dart.library.html) 'video_picture_in_picture_web.dart';

class AntiCheatPlayer extends StatefulWidget {
  final int videoId;
  final String title;
  final int durationSeconds;
  final int minWatchPercentage;
  final VoidCallback? onCompleted;
  final VoidCallback? onEnded;
  final bool autoPlay;
  final double? maxVideoStageHeight;

  const AntiCheatPlayer({
    super.key,
    required this.videoId,
    required this.title,
    required this.durationSeconds,
    this.minWatchPercentage = 90,
    this.onCompleted,
    this.onEnded,
    this.autoPlay = false,
    this.maxVideoStageHeight,
  });

  @override
  State<AntiCheatPlayer> createState() => _AntiCheatPlayerState();
}

class _AntiCheatPlayerState extends State<AntiCheatPlayer>
    with WidgetsBindingObserver {
  static const _sessionInitTimeout = Duration(seconds: 15);
  static const _videoInitTimeout = Duration(seconds: 20);

  final ApiService _api = ApiService();

  VideoPlayerController? _controller;
  String? _sessionToken;
  String? _mediaUrl;
  bool _lastControllerPlaying = false;
  DateTime? _lastPlayingAt;
  int _activityEpoch = 0;
  Future<void> _heartbeatQueue = Future<void>.value();
  bool _isTabActive = true;
  double _currentPosition = 0;
  double _videoDuration = 0;
  bool _isCompleted = false;
  double _playbackSpeed = 1.0;
  double _resumePosition = 0;
  bool _resumeApplied = false;
  String? _videoError;
  bool _isVideoReady = false;
  bool _isMuted = false;
  bool _isFullscreen = false;
  bool _centerControlsVisible = true;
  bool _endHandled = false;
  bool _showIncompleteNotice = false;
  double _completionPercentage = 0;
  OverlayEntry? _fullscreenOverlay;

  Timer? _heartbeatTimer;
  Timer? _centerControlsTimer;
  bool _isLoadingSession = true;

  bool get _isPlaying => _controller?.value.isPlaying ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _centerControlsTimer?.cancel();
    _fullscreenOverlay?.remove();
    _fullscreenOverlay = null;
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _activityEpoch++;
    if (state == AppLifecycleState.resumed) {
      _refresh(() => _isTabActive = true);
      return;
    }

    final controller = _controller;
    final wasPlaying = controller?.value.isPlaying ?? false;
    _refresh(() => _isTabActive = false);
    _sendHeartbeat(wasPlaying: wasPlaying, wasTabActive: false);
    if (wasPlaying && controller != null) {
      _lastControllerPlaying = false;
      unawaited(controller.pause().then((_) {
        if (mounted) _keepCenterControlsVisible();
      }));
    }
  }

  Future<void> _initializeVideo(Uri mediaUri) async {
    final controller = VideoPlayerController.networkUrl(
      mediaUri,
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
    );
    _controller = controller;
    try {
      await controller.initialize().timeout(_videoInitTimeout);
      if (!mounted) return;
      await controller.setVolume(1.0);
      await controller.setPlaybackSpeed(_playbackSpeed);
      if (!mounted) return;
      controller.addListener(_onControllerUpdate);
      final seconds = controller.value.duration.inMilliseconds / 1000.0;
      _refresh(() {
        _isVideoReady = true;
        if (seconds > 0) _videoDuration = seconds;
      });
      _applyResumePosition();
      _startHeartbeatPulse();
      if (widget.autoPlay) {
        await _startPlayback();
      }
    } on TimeoutException {
      await _failPlayback('This lesson took too long to load. Please retry.');
    } catch (_) {
      await _failPlayback(
          'This lesson could not be loaded. Please refresh and try again.');
    }
  }

  Future<void> _failPlayback(String message) async {
    if (!mounted) return;
    _heartbeatTimer?.cancel();
    _centerControlsTimer?.cancel();
    _refresh(() {
      _sessionToken = null;
      _isLoadingSession = false;
      _isVideoReady = false;
      _centerControlsVisible = true;
      _videoError = message;
    });
    await _controller?.pause();
  }

  void _applyResumePosition() {
    if (_resumeApplied || _resumePosition <= 1) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _resumeApplied = true;
    final max = controller.value.duration.inMilliseconds / 1000.0;
    final target = _resumePosition < max - 2 ? _resumePosition : 0.0;
    if (target > 0) {
      controller.seekTo(Duration(milliseconds: (target * 1000).round()));
    }
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null) return;
    final next = !_isMuted;
    await controller.setVolume(next ? 0.0 : 1.0);
    if (mounted) _refresh(() => _isMuted = next);
  }

  Future<void> _restartVideo() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final wasPlaying = controller.value.isPlaying;
    await controller.seekTo(Duration.zero);
    if (!mounted) return;
    _endHandled = false;
    _showCenterControls(autoHide: wasPlaying);
    _refresh(() {
      _currentPosition = 0;
      _showIncompleteNotice = false;
    });
    await _sendHeartbeat(wasPlaying: wasPlaying);
  }

  void _onControllerUpdate() {
    final value = _controller?.value;
    if (value == null || !value.isInitialized || _videoError != null) return;
    final wasPlaying = value.isPlaying ||
        (_lastControllerPlaying &&
            _lastPlayingAt != null &&
            DateTime.now().difference(_lastPlayingAt!) <=
                const Duration(seconds: 2));
    if (value.isPlaying) {
      _lastControllerPlaying = true;
      _lastPlayingAt = DateTime.now();
    }
    final duration = value.duration.inMilliseconds / 1000.0;
    final position = value.position.inMilliseconds / 1000.0;
    if (!mounted) return;
    _refresh(() {
      _currentPosition = position;
      if (duration > 0) _videoDuration = duration;
    });
    if (duration <= 0) return;

    if (position < duration - 1.5) {
      _endHandled = false;
    } else if (!_endHandled && position >= duration - 0.5) {
      _endHandled = true;
      unawaited(_handleEnded(wasPlaying));
    }
  }

  Future<void> _handleEnded(bool wasPlaying) async {
    await _controller?.pause();
    _keepCenterControlsVisible();
    final heartbeat = _sendHeartbeat(wasPlaying: wasPlaying);
    _lastControllerPlaying = false;
    await heartbeat;
    if (!mounted || _videoError != null) return;
    if (!_isCompleted) {
      _refresh(() => _showIncompleteNotice = true);
      return;
    }
    _refresh(() => _showIncompleteNotice = false);
    widget.onEnded?.call();
  }

  Future<void> _startPlayback() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !_isVideoReady ||
        _videoError != null) return;
    final wasPlaying = controller.value.isPlaying;
    final value = controller.value;
    if (value.duration > Duration.zero && value.position >= value.duration) {
      await controller.seekTo(Duration.zero);
    }
    await controller.play();
    _showCenterControls(autoHide: true);
    await _sendHeartbeat(wasPlaying: wasPlaying);
    if (mounted) _refresh(() => _showIncompleteNotice = false);
  }

  void _showCenterControls({required bool autoHide}) {
    _centerControlsTimer?.cancel();
    if (!_centerControlsVisible) {
      _refresh(() => _centerControlsVisible = true);
    }
    if (autoHide && _isPlaying) {
      _centerControlsTimer = Timer(const Duration(seconds: 1), () {
        _centerControlsTimer = null;
        if (mounted && _isPlaying) {
          _refresh(() => _centerControlsVisible = false);
        }
      });
    }
  }

  void _keepCenterControlsVisible() {
    _centerControlsTimer?.cancel();
    _centerControlsTimer = null;
    if (!_centerControlsVisible) {
      _refresh(() => _centerControlsVisible = true);
    }
  }

  Future<void> _handleVideoSurfaceTap() async {
    if (!_centerControlsVisible) {
      _showCenterControls(autoHide: _isPlaying);
      return;
    }
    if (_isPlaying) {
      await _togglePlayPause();
    } else {
      await _startPlayback();
    }
  }

  Future<void> _initializeSession() async {
    try {
      final res = await _api.post(ApiConfig.internVideoInit,
          {'video_id': widget.videoId}).timeout(_sessionInitTimeout);

      if (!mounted) return;
      final media = res['media_url'];
      final token = res['session_token'];
      if (media is! String || media.trim().isEmpty) {
        throw ApiException('This lesson has no authorized media.');
      }
      final mediaUri =
          Uri.parse('${ApiConfig.serverOrigin}/').resolve(media.trim());
      if ((mediaUri.scheme != 'http' && mediaUri.scheme != 'https') ||
          mediaUri.host.isEmpty ||
          mediaUri.userInfo.isNotEmpty ||
          token is! String ||
          token.isEmpty) {
        throw ApiException('This lesson has no valid playback authorization.');
      }
      _refresh(() {
        _sessionToken = token;
        _mediaUrl = mediaUri.toString();
        _videoDuration =
            ((res['duration_seconds'] as num?) ?? widget.durationSeconds)
                .toDouble();
        _resumePosition =
            ((res['last_position_seconds'] as num?) ?? 0).toDouble();
        _currentPosition = _resumePosition;
        _isCompleted = res['is_completed'] == true;
        _completionPercentage =
            ((res['completion_percentage'] as num?) ?? 0).toDouble();
        _showIncompleteNotice = false;
        _isLoadingSession = false;
      });
      await _initializeVideo(mediaUri);
    } on TimeoutException {
      await _failPlayback('Playback setup timed out. Please retry the lesson.');
    } catch (e) {
      await _failPlayback(e is ApiException
          ? e.message
          : 'Playback could not be authorized. Please refresh and try again.');
    }
  }

  Future<void> _retryPlayback() async {
    _heartbeatTimer?.cancel();
    if (_isFullscreen) _exitFullscreen();
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onControllerUpdate);
    await controller?.dispose();
    if (!mounted) return;
    _refresh(() {
      _sessionToken = null;
      _mediaUrl = null;
      _lastControllerPlaying = false;
      _lastPlayingAt = null;
      _currentPosition = 0;
      _videoDuration = widget.durationSeconds.toDouble();
      _isCompleted = false;
      _completionPercentage = 0;
      _resumePosition = 0;
      _resumeApplied = false;
      _videoError = null;
      _isVideoReady = false;
      _centerControlsVisible = true;
      _isLoadingSession = true;
      _endHandled = false;
      _showIncompleteNotice = false;
    });
    await _initializeSession();
  }

  void _startHeartbeatPulse() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isPlaying && _isTabActive && _sessionToken != null) {
        _sendHeartbeat();
      }
    });
  }

  Future<void> _sendHeartbeat({bool? wasPlaying, bool? wasTabActive}) {
    final token = _sessionToken;
    if (!mounted || token == null || _videoError != null) {
      return Future<void>.value();
    }
    final position = _currentPosition;
    final speed = _playbackSpeed;
    final activityEpoch = _activityEpoch;
    final active = _isTabActive &&
        (wasTabActive ?? _isTabActive) &&
        (wasPlaying ?? _isPlaying);
    final request = _heartbeatQueue.then((_) async {
      if (!mounted || _sessionToken != token || _videoError != null) return;
      try {
        final res = await _api.post(ApiConfig.internVideoHeartbeat, {
          'video_id': widget.videoId,
          'session_token': token,
          'current_position_seconds': position,
          'playback_speed': speed,
          'tab_active':
              active && _isTabActive && activityEpoch == _activityEpoch,
        });
        if (!mounted || _sessionToken != token || _videoError != null) return;
        final completionPercentage = res['completion_percentage'];
        if (completionPercentage is num) {
          _refresh(() {
            _completionPercentage =
                completionPercentage.toDouble().clamp(0, 100).toDouble();
          });
        }
        if (res['is_completed'] == true && !_isCompleted) {
          _refresh(() {
            _isCompleted = true;
            _completionPercentage = 100;
            _showIncompleteNotice = false;
          });
          widget.onCompleted?.call();
        }
      } on ApiException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) {
          await _failPlayback(
              'Playback access denied. ${e.message} Please refresh lessons.');
        }
      } catch (_) {}
    });
    _heartbeatQueue = request;
    return request;
  }

  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !_isVideoReady ||
        _videoError != null) return;

    if (controller.value.isPlaying) {
      final wasPlaying = controller.value.isPlaying;
      await controller.pause();
      _lastControllerPlaying = false;
      _keepCenterControlsVisible();
      await _sendHeartbeat(wasPlaying: wasPlaying);
    } else {
      _endHandled = false;
      await _startPlayback();
    }
    if (mounted) _refresh(() {});
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    _refresh(() => _playbackSpeed = speed);
    await _controller?.setPlaybackSpeed(speed);
  }

  String _formatTime(double seconds) {
    final int totalSec = seconds.toInt();
    final int mins = totalSec ~/ 60;
    final int secs = totalSec % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _refresh(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _fullscreenOverlay?.markNeedsBuild();
  }

  void _toggleFullscreen() {
    if (_isFullscreen) {
      _exitFullscreen();
      return;
    }
    _refresh(() => _isFullscreen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isFullscreen || _fullscreenOverlay != null) return;
      final maxDuration = _videoDuration > 0
          ? _videoDuration
          : widget.durationSeconds.toDouble();
      _fullscreenOverlay = OverlayEntry(
        builder: (ctx) => Positioned.fill(
          child: Material(
            color: Colors.black,
            child: SafeArea(
              child: _buildVideoStage(ctx, maxDuration, fullscreen: true),
            ),
          ),
        ),
      );
      Overlay.of(context).insert(_fullscreenOverlay!);
    });
  }

  void _exitFullscreen() {
    _fullscreenOverlay?.remove();
    _fullscreenOverlay = null;
    _refresh(() => _isFullscreen = false);
  }

  @override
  Widget build(BuildContext context) {
    final maxDuration =
        _videoDuration > 0 ? _videoDuration : widget.durationSeconds.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isFullscreen)
          Container(
            height: 380,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: const Center(
              child: Text(
                'Playing in full screen',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          )
        else
          _buildVideoStage(context, maxDuration),
        const SizedBox(height: 16),
        _buildProgressCard(),
      ],
    );
  }

  Widget _buildVideoStage(BuildContext context, double maxDuration,
      {bool fullscreen = false}) {
    final stageHeight = fullscreen
        ? null
        : (widget.maxVideoStageHeight ?? 380).clamp(160.0, 380.0).toDouble();
    final stage = Container(
      key: const ValueKey('video-stage'),
      height: stageHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: fullscreen ? null : BorderRadius.circular(12),
        border: fullscreen ? null : Border.all(color: AppTheme.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Actual video frame
                if (_videoError != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _videoError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _retryPlayback,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_isLoadingSession)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                else if (_controller != null && _isVideoReady)
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio == 0
                          ? 16 / 9
                          : _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                else
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),

                if (_isVideoReady && _videoError == null)
                  Positioned.fill(
                    child: MouseRegion(
                      onHover: (_) => _showCenterControls(autoHide: _isPlaying),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => unawaited(_handleVideoSurfaceTap()),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),

                // Keep the center controls available while the video is playing.
                if (!_isPlaying && _isVideoReady)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black
                            .withOpacity(_currentPosition > 0 ? 0.35 : 0.2),
                      ),
                    ),
                  ),
                if (!_isPlaying && _isVideoReady)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 150,
                    child: IgnorePointer(
                      child: Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (_isVideoReady &&
                    _videoError == null &&
                    _centerControlsVisible)
                  Positioned.fill(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildCenterControl(
                            tooltip: 'Restart video',
                            icon: Icons.replay_rounded,
                            onPressed: _restartVideo,
                          ),
                          const SizedBox(width: 16),
                          _buildCenterControl(
                            tooltip:
                                _isPlaying ? 'Pause video' : 'Resume video',
                            icon: _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            onPressed: _togglePlayPause,
                            prominent: true,
                          ),
                        ],
                      ),
                    ),
                  ),

                // Anti-Cheat Status Badge (Top Right)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Builder(
                    builder: (ctx) {
                      final isWatching = _isTabActive && _isPlaying;
                      final badgeColor = _isLoadingSession
                          ? AppTheme.primaryBlue
                          : isWatching
                              ? AppTheme.success
                              : AppTheme.textMuted;
                      final badgeText = _isLoadingSession
                          ? 'Preparing lesson'
                          : isWatching
                              ? 'Watching • Progress Live'
                              : 'Paused • Progress saved';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isLoadingSession
                                  ? Icons.hourglass_top_rounded
                                  : isWatching
                                      ? Icons.verified_user
                                      : Icons.pause_circle_outline_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              badgeText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          _buildControlsBar(maxDuration, fullscreen),
        ],
      ),
    );

    return fullscreen ? SizedBox.expand(child: stage) : stage;
  }

  Widget _buildControlsBar(double maxDuration, bool fullscreen) {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              trackHeight: 3,
              activeTrackColor: AppTheme.primaryBlue,
              inactiveTrackColor: Colors.grey.shade700,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: _currentPosition.clamp(0.0, maxDuration).toDouble(),
              max: maxDuration <= 0 ? 1 : maxDuration,
              onChanged: _isVideoReady
                  ? (val) => _refresh(() => _currentPosition = val)
                  : null,
              onChangeEnd: _isVideoReady
                  ? (val) async {
                      await _controller?.seekTo(
                          Duration(milliseconds: (val * 1000).round()));
                      await _sendHeartbeat();
                    }
                  : null,
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: _isPlaying ? 'Pause' : 'Play',
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: _isVideoReady ? _togglePlayPause : null,
              ),
              Expanded(
                child: Text(
                  '${_formatTime(_currentPosition)} / ${_formatTime(maxDuration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: _isMuted ? 'Unmute sound' : 'Mute sound',
                icon: Icon(
                  _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: _isVideoReady ? _toggleMute : null,
              ),
              if (_isVideoReady) VideoPictureInPicture(videoUrl: _mediaUrl!),
              IconButton(
                tooltip: fullscreen ? 'Exit full screen' : 'Full screen',
                icon: Icon(
                  fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: _isVideoReady ? _toggleFullscreen : null,
              ),
              PopupMenuButton<double>(
                enabled: _isVideoReady,
                initialValue: _playbackSpeed,
                tooltip: 'Playback Speed',
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 0.75, child: Text('0.75x')),
                  const PopupMenuItem(value: 1.0, child: Text('1.0x (Normal)')),
                  const PopupMenuItem(value: 1.25, child: Text('1.25x')),
                  const PopupMenuItem(value: 1.5, child: Text('1.5x')),
                ],
                onSelected: _setPlaybackSpeed,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade600),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCenterControl({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool prominent = false,
  }) {
    final size = prominent ? 64.0 : 52.0;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withOpacity(0.65),
        foregroundColor: Colors.white,
        fixedSize: Size(size, size),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, size: prominent ? 36 : 28),
    );
  }

  Widget _buildProgressCard() {
    final maxDuration =
        _videoDuration > 0 ? _videoDuration : widget.durationSeconds.toDouble();
    final positionProgress = maxDuration > 0
        ? (_currentPosition / maxDuration).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final verifiedProgress =
        (_completionPercentage / 100).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Watch Progress',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                _isCompleted
                    ? 'COMPLETED'
                    : '${_completionPercentage.toStringAsFixed(1)}% verified',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: verifiedProgress,
              minHeight: 8,
              backgroundColor: AppTheme.borderColor,
              valueColor: AlwaysStoppedAnimation<Color>(
                _isCompleted ? AppTheme.success : AppTheme.primaryBlue,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Playback position: ${_formatTime(_currentPosition)} / ${_formatTime(maxDuration)} (${(positionProgress * 100).toStringAsFixed(1)}%).',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          if (_showIncompleteNotice && !_isCompleted) ...[
            const SizedBox(height: 8),
            Text(
              'This lesson has not reached its ${widget.minWatchPercentage}% verified-watch requirement. Keep this page active and continue watching to unlock the next lesson.',
              style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.danger,
                  fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Completion is verified by the server; only time spent actively watching counts toward the ${widget.minWatchPercentage}% threshold.',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
