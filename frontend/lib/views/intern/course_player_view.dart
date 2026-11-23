import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/safe_convert.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/anti_cheat_player.dart';

class CoursePlayerView extends StatefulWidget {
  final int courseId;

  const CoursePlayerView({super.key, required this.courseId});

  @override
  State<CoursePlayerView> createState() => _CoursePlayerViewState();
}

class _CoursePlayerViewState extends State<CoursePlayerView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _course;
  Map<String, dynamic>? _activeVideo;
  List<dynamic> _modules = [];
  bool _autoPlayNext = false;
  Future<bool>? _courseFetch;

  @override
  void initState() {
    super.initState();
    _fetchCourseData();
  }

  Future<bool> _fetchCourseData() {
    return _courseFetch ??= _loadCourseData().whenComplete(() {
      _courseFetch = null;
    });
  }

  Future<bool> _loadCourseData() async {
    try {
      final res =
          await _api.get('${ApiConfig.internCourses}/${widget.courseId}');
      if (!mounted) return false;
      final course = res['course'];
      final modules = (course['modules'] as List?) ?? [];

      Map<String, dynamic>? firstVideo;
      Map<String, dynamic>? currentVideo;
      final currentId = _activeVideo?['id'];
      for (final m in modules) {
        for (final v in (m['videos'] as List?) ?? []) {
          if (v['is_unlocked'] != true) continue;
          firstVideo ??= v;
          if (v['id'] == currentId) currentVideo = v;
        }
      }

      setState(() {
        _course = course;
        _modules = modules;
        _activeVideo = currentVideo ?? firstVideo;
        if (_activeVideo?['id'] != currentId) _autoPlayNext = false;
        _isLoading = false;
      });
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _isLoading = false);
      if (_course != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not refresh lessons. Please try again.'),
        ));
      }
      return false;
    }
  }

  Map<String, dynamic>? _nextVideoAfter(Map<String, dynamic>? current) {
    if (current == null) return null;
    final all = <dynamic>[];
    for (final m in _modules) {
      all.addAll((m['videos'] as List?) ?? []);
    }
    final index = all.indexWhere((v) => v['id'] == current['id']);
    if (index == -1 || index + 1 >= all.length) return null;
    final next = all[index + 1] as Map<String, dynamic>;
    return next['is_unlocked'] == true ? next : null;
  }

  Future<void> _handleVideoEnded(int endedVideoId) async {
    final pending = _courseFetch;
    if (pending != null) {
      await pending;
      if (!mounted || _activeVideo?['id'] != endedVideoId) return;
    }
    final refreshed = await _fetchCourseData();
    if (!mounted || !refreshed || _activeVideo?['id'] != endedVideoId) return;
    final completed = _activeVideo?['is_completed'];
    if (completed != true && completed != 1) return;
    final next = _nextVideoAfter(_activeVideo);
    if (next == null) return;
    setState(() {
      _activeVideo = next;
      _autoPlayNext = true;
    });
  }

  Widget _buildTrackProgress({
    required IconData icon,
    required String label,
    required int done,
    required int total,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 6),
        SizedBox(
          width: 136,
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : (done / total).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppTheme.borderColor,
              valueColor: AlwaysStoppedAnimation<Color>(
                  total > 0 && done >= total ? AppTheme.success : color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 34,
          child: Text(
            '$done/$total',
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletionBanner(AuthProvider auth) {
    final int doneV = safeInt(_course!['completed_videos']);
    final int totalV = safeInt(_course!['total_videos']);
    final int doneMaterials = safeInt(_course!['completed_materials']);
    final int totalMaterials = safeInt(_course!['total_materials']);
    final int doneTests = safeInt(_course!['passed_module_tests']);
    final int totalTests = safeInt(_course!['total_module_tests']);
    final int percent = safeInt(_course!['progress_percent']);
    final bool isDone = _course!['is_completed'] == true ||
        safeInt(_course!['is_completed']) == 1;

    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isDone ? const Color(0xFFFEF3C7) : AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDone ? const Color(0xFFD4AF37) : AppTheme.borderColor),
          ),
          child: isDone
              ? Row(
                  children: [
                    const Icon(Icons.workspace_premium_rounded,
                        color: Color(0xFFB45309), size: 26),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Course completed!',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Color(0xFF92400E)),
                          ),
                          Text(
                            'Videos, materials, and module tests are complete.',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF92400E)),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.verified_rounded, size: 18),
                      label: const Text('View Certificate'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB45309),
                          foregroundColor: Colors.white),
                      onPressed: () => auth.setActiveView('certificate'),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.insights_rounded,
                            size: 16, color: AppTheme.textMuted),
                        const SizedBox(width: 8),
                        const Text('Course progress',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(
                          '$percent% overall',
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildTrackProgress(
                      icon: Icons.play_circle_outline_rounded,
                      label: 'Video lessons',
                      done: doneV,
                      total: totalV,
                      color: AppTheme.primaryBlue,
                    ),
                    const SizedBox(height: 8),
                    _buildTrackProgress(
                      icon: Icons.menu_book_outlined,
                      label: 'Study materials',
                      done: doneMaterials,
                      total: totalMaterials,
                      color: AppTheme.success,
                    ),
                    const SizedBox(height: 8),
                    _buildTrackProgress(
                      icon: Icons.quiz_outlined,
                      label: 'Module tests',
                      done: doneTests,
                      total: totalTests,
                      color: AppTheme.accentGold,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildModuleTestTile(AuthProvider auth, dynamic module) {
    final test = module['test'];
    if (test == null) {
      return const ListTile(
        dense: true,
        leading: Icon(Icons.lock_outline, color: AppTheme.textMuted, size: 19),
        title: Text(
          'Module test not configured',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'This module and later modules stay locked until its test is set up.',
          style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
        ),
      );
    }

    final testId = safeInt(test['id']);
    final isPassed = test['is_passed'] == true || safeInt(test['is_passed']) == 1;
    final isUnlocked =
        test['is_unlocked'] == true || safeInt(test['is_unlocked']) == 1;
    final canResume = test['can_resume'] == true;
    final attemptSubmitted = test['attempt_status'] == 'submitted';
    final score = test['score'] == null ? null : safeString(test['score']);
    final subtitle = isPassed
        ? 'Passed${score == null ? '' : ' • $score marks'}'
        : attemptSubmitted
            ? 'Attempt used. Contact your course manager for help.'
            : isUnlocked
                ? '${safeInt(test['passing_score'], 60)}% required • One attempt'
                : safeString(
                    test['lock_reason'],
                    "Complete this module's videos to unlock the test.",
                  );

    return ListTile(
      dense: true,
      leading: Icon(
        isPassed
            ? Icons.check_circle
            : isUnlocked
                ? Icons.quiz_outlined
                : Icons.lock_outline,
        color: isPassed
            ? AppTheme.success
            : isUnlocked
                ? AppTheme.primaryBlue
                : AppTheme.textMuted,
        size: 19,
      ),
      title: Text(
        safeString(test['title'], 'Module test'),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
      ),
      trailing: isPassed
          ? const Text(
              'Passed',
              style: TextStyle(
                color: AppTheme.success,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            )
          : isUnlocked
              ? TextButton(
                  key: ValueKey('start-module-test-$testId'),
                  onPressed: () => auth.openCourseModuleTest(testId),
                  child: Text(canResume ? 'Resume' : 'Take test'),
                )
              : const Text(
                  'Locked',
                  style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final int? activeVideoId = _activeVideo?['id'];

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_course == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Failed to load course player data'),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: () => auth.setActiveView('my_courses'),
                child: const Text('Back to Courses')),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button and Course Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Courses',
                onPressed: () => auth.setActiveView('my_courses'),
              ),
              const SizedBox(width: 8),
              // Mini logo
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.accentGold, width: 1.5),
                  color: Colors.white,
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.school,
                        color: AppTheme.accentGold, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _course!['title'] ?? 'Training Course',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary),
                    ),
                    Text(
                      'Department: ${_course!['department_name'] ?? 'Not set'} • Watch progress saves automatically',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildCompletionBanner(auth),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 65,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final availableHeight = constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : 380.0;
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_activeVideo != null)
                              AntiCheatPlayer(
                                key: ValueKey(_activeVideo!['id']),
                                videoId: _activeVideo!['id'],
                                title:
                                    _activeVideo!['title'] ?? 'Training Video',
                                durationSeconds:
                                    _activeVideo!['duration_seconds'] ?? 300,
                                minWatchPercentage:
                                    _activeVideo!['min_watch_percentage'] ?? 90,
                                autoPlay: _autoPlayNext,
                                maxVideoStageHeight: availableHeight,
                                onCompleted: () => _fetchCourseData(),
                                onEnded: () =>
                                    _handleVideoEnded(activeVideoId!),
                              )
                            else
                              Container(
                                height: 380,
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Text('No unlocked videos available',
                                      style: TextStyle(color: Colors.white)),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(width: 20),

                // Right 35%: Course Curriculum & Lesson Playlist
                Expanded(
                  flex: 35,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Video Lessons by Module',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Refresh lessons',
                              icon: const Icon(Icons.refresh),
                              onPressed: () => _fetchCourseData(),
                            ),
                          ],
                        ),
                        const Text(
                          'Finish each module’s videos and pass its test to unlock the next module.',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Builder(
                            builder: (ctx) {
                              if (_modules.isEmpty) {
                                return const Center(
                                  child: Text(
                                      'No modules in this course yet.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textMuted)),
                                );
                              }
                              return ListView.builder(
                                itemCount: _modules.length,
                                itemBuilder: (ctx, mIdx) {
                                  final mod = _modules[mIdx];
                                  final videos = (mod['videos'] as List?) ?? [];
                                  final String moduleTitle =
                                      (mod['title'] ?? 'Video Lessons')
                                          .toString()
                                          .replaceFirst(
                                              RegExp(r'^module\s*\d+\s*:\s*',
                                                  caseSensitive: false),
                                              '');

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        child: Text(
                                          'MODULE ${mIdx + 1}: $moduleTitle',
                                          style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      ...videos.map((v) {
                                        final bool isSelected =
                                            _activeVideo != null &&
                                                _activeVideo!['id'] == v['id'];
                                        final bool isUnlocked =
                                            v['is_unlocked'] == true;
                                        final bool isComp =
                                            v['is_completed'] == 1 ||
                                                v['is_completed'] == true;
                                        final int duration =
                                            v['duration_seconds'] ?? 0;
                                        final int mins = duration ~/ 60;
                                        final int secs = duration % 60;
                                        final double verifiedPercent =
                                            v['completion_percentage'] is num
                                                ? (v['completion_percentage']
                                                        as num)
                                                    .toDouble()
                                                : isComp
                                                    ? 100
                                                    : 0;

                                        return Container(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFFEFF6FF)
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isSelected
                                                  ? AppTheme.primaryBlue
                                                  : Colors.transparent,
                                            ),
                                          ),
                                          child: ListTile(
                                            dense: true,
                                            enabled: isUnlocked,
                                            leading: Icon(
                                              !isUnlocked
                                                  ? Icons.lock_outline
                                                  : isComp
                                                      ? Icons.check_circle
                                                      : (isSelected
                                                          ? Icons.play_arrow
                                                          : Icons
                                                              .play_circle_outline),
                                              color: isComp
                                                  ? AppTheme.success
                                                  : (isSelected
                                                      ? AppTheme.primaryBlue
                                                      : AppTheme.textMuted),
                                              size: 20,
                                            ),
                                            title: Text(
                                              v['title'] ?? 'Video Lesson',
                                              style: TextStyle(
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                fontSize: 13,
                                                color: isSelected
                                                    ? AppTheme.primaryNavy
                                                    : AppTheme.textPrimary,
                                              ),
                                            ),
                                            subtitle: Text(
                                              isUnlocked
                                                  ? isComp
                                                      ? '${mins}m ${secs}s • Completed'
                                                      : '${verifiedPercent.toStringAsFixed(0)}% verified • ${mins}m ${secs}s • Min ${v['min_watch_percentage'] ?? 90}% watch'
                                                  : safeString(
                                                      v['required_unlock_reason'],
                                                      'Complete ${v['required_video_title'] ?? 'preceding videos'} to unlock',
                                                    ),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textMuted),
                                            ),
                                            onTap: isUnlocked
                                                ? () {
                                                    setState(() {
                                                      _activeVideo = v;
                                                      _autoPlayNext = false;
                                                    });
                                                  }
                                                : null,
                                          ),
                                        );
                                      }),
                                      const Divider(height: 12),
                                      _buildModuleTestTile(auth, mod),
                                      const Divider(height: 16),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
