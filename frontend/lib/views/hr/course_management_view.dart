import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/large_video_uploader.dart';
import '../../core/utils/safe_convert.dart';
import '../../core/utils/feedback.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/kgpl_brand_badge.dart';
import '../../widgets/ui_effects.dart';
import 'course_module_test_editor_dialog.dart';

class CourseManagementView extends StatefulWidget {
  const CourseManagementView({super.key});

  @override
  State<CourseManagementView> createState() => _CourseManagementViewState();
}

class _CourseManagementViewState extends State<CourseManagementView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _courses = [];
  List<dynamic> _departments = [];
  List<dynamic> _liveViewers = [];
  Timer? _liveTimer;
  DateTime? _liveUpdatedAt;
  int? _deletingCourseId;
  int? _assigningCourseId;

  @override
  void initState() {
    super.initState();
    _fetchCourses();
    _fetchDepartments();
    _fetchLive();
    _liveTimer =
        Timer.periodic(const Duration(seconds: 12), (_) => _fetchLive());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLive() async {
    try {
      final res = await _api.get('${ApiConfig.hrCourses}/live-watch');
      if (!mounted) return;
      setState(() {
        _liveViewers = (res['active_viewers'] as List?) ?? [];
        _liveUpdatedAt = DateTime.now();
      });
    } catch (_) {
      // Live panel stays on its last snapshot if the refresh fails.
    }
  }

  Future<void> _fetchCourses() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get(ApiConfig.hrCourses);
      setState(() {
        _courses = res['courses'] ?? [];
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchDepartments() async {
    try {
      final res = await _api.get(ApiConfig.hrDepartments);
      if (!mounted) return;
      setState(() => _departments = res['departments'] ?? []);
    } catch (_) {}
  }

  Future<void> _assignCourseToInterns(Map<String, dynamic> course) async {
    final courseId = safeInt(course['id']);
    final departmentId = safeInt(course['department_id']);
    if (courseId <= 0 || departmentId <= 0) {
      showAppFeedback(context, 'Assign this course to a department first.',
          isError: true);
      return;
    }

    setState(() => _assigningCourseId = courseId);
    try {
      final isHrAdmin =
          Provider.of<AuthProvider>(context, listen: false).userRole ==
              'hr_admin';
      final response = isHrAdmin
          ? await _api.get(
              '${ApiConfig.hrUsers}?role=intern&department_id=$departmentId&is_active=true')
          : await _api.get(ApiConfig.tlInterns);
      final rawInterns = isHrAdmin ? response['users'] : response['interns'];
      final interns = <Map<String, dynamic>>[];
      if (rawInterns is List) {
        for (final value in rawInterns) {
          if (value is Map &&
              safeInt(value['department_id']) == departmentId &&
              value['is_active'] != false &&
              value['is_active'] != 0) {
            interns.add(Map<String, dynamic>.from(value));
          }
        }
      }

      if (!mounted) return;
      if (interns.isEmpty) {
        showAppFeedback(
            context, 'No active interns are available for this department.',
            isError: true);
        return;
      }

      final selectedInternIds = <int>{};
      final assignedIds = await showDialog<List<int>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Assign course to interns'),
            content: SizedBox(
              width: 440,
              height: 380,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    safeString(course['title'], 'Selected course'),
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: interns.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final intern = interns[index];
                        final id = safeInt(intern['id']);
                        return CheckboxListTile(
                          value: selectedInternIds.contains(id),
                          onChanged: (selected) {
                            setDialogState(() {
                              if (selected == true) {
                                selectedInternIds.add(id);
                              } else {
                                selectedInternIds.remove(id);
                              }
                            });
                          },
                          title: Text(safeString(intern['name'], 'Intern')),
                          subtitle: Text(safeString(intern['email'])),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: selectedInternIds.isEmpty
                    ? null
                    : () => Navigator.pop(
                        dialogContext, selectedInternIds.toList()),
                icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                label: Text('Assign (${selectedInternIds.length})'),
              ),
            ],
          ),
        ),
      );

      if (assignedIds == null || assignedIds.isEmpty) return;
      await _api.post(ApiConfig.tlAssignCourse, {
        'course_id': courseId,
        'intern_ids': assignedIds,
      });
      if (mounted) {
        showAppFeedback(
            context, 'Course assigned to ${assignedIds.length} intern(s).');
      }
    } catch (error) {
      if (mounted) {
        showAppFeedback(context, 'Could not assign course: $error',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _assigningCourseId = null);
    }
  }

  Future<void> _confirmDeleteCourse(Map<String, dynamic> course) async {
    final int courseId = safeInt(course['id']);
    final String title = safeString(course['title'], 'this course');
    final int lessonCount = safeInt(course['video_count']);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete course?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Text(
            '"$title" and its $lessonCount lessons, materials and watch history will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Course'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingCourseId = courseId);
    try {
      await _api.delete('${ApiConfig.hrCourses}/$courseId');
      await _fetchCourses();
      await _fetchLive();
      if (mounted) {
        showAppFeedback(context, 'Course deleted.');
      }
    } catch (e) {
      if (mounted) {
        showAppFeedback(context, 'Failed to delete course: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _deletingCourseId = null);
    }
  }

  void _showCreateCourseDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final durationController = TextEditingController(text: '14');
    int? selectedDepartmentId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          titlePadding: EdgeInsets.zero,
          title: Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.rocket_launch_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create Training Course Track',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 17)),
                    Text('Add a new learning track for your interns',
                        style:
                            TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Course Title *',
                    hintText: 'e.g. IT Infrastructure & Cloud DevOps',
                    prefixIcon: const Icon(Icons.title_rounded, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Course Description',
                    hintText:
                        'Competencies, real-world deliverables, and syllabus overview...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  value: selectedDepartmentId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Department *',
                    hintText: 'Select department',
                    prefixIcon: const Icon(Icons.apartment_outlined, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _departments
                      .map((d) => DropdownMenuItem<int>(
                            value: safeInt(d['id']),
                            child: Text(safeString(d['name']),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedDepartmentId = val),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: durationController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Estimated Duration (Hours)',
                    prefixIcon: const Icon(Icons.timer_outlined, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Publish Course'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              onPressed: () async {
                if (titleController.text.trim().isEmpty) {
                  showAppFeedback(context, 'Please enter a course title.',
                      isError: true);
                  return;
                }
                if (selectedDepartmentId == null) {
                  showAppFeedback(
                      context, 'Select a department for this course.',
                      isError: true);
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await _api.post(ApiConfig.hrCourses, {
                    'title': titleController.text.trim(),
                    'description': descController.text.trim(),
                    'department_id': selectedDepartmentId,
                    'duration_hours': safeInt(durationController.text, 10),
                    'is_published': 1,
                  });
                  _fetchCourses();
                  if (mounted) {
                    showAppFeedback(
                        context, 'Course created. Use Assign to add interns.');
                  }
                } catch (e) {
                  if (e is ApiException && e.statusCode == 409) {
                    await _fetchCourses();
                    if (mounted) {
                      showAppFeedback(context, e.message, isError: true);
                    }
                  } else if (mounted) {
                    showAppFeedback(context, 'Failed to create course: $e',
                        isError: true);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openCourseCurriculumStudio(Map<String, dynamic> course) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CourseCurriculumStudioDialog(
        courseId: safeInt(course['id']),
        initialTitle: safeString(course['title']),
        onUpdated: _fetchCourses,
      ),
    );
  }

  void _showPostVideoDialog() {
    if (_courses.isEmpty) {
      showAppFeedback(
          context, 'Create a course track first, then post videos to it.',
          isError: true);
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PostVideoDeviceDialog(
        courses: _courses,
        onPosted: () {
          _fetchCourses();
          if (mounted) {
            showAppFeedback(context,
                'Video posted from your device — interns can watch it now.');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalVideos = 0;
    int totalModules = 0;
    int totalMaterials = 0;
    for (final c in _courses) {
      totalVideos += safeInt(c['video_count']);
      totalModules += safeInt(c['module_count']);
      totalMaterials += safeInt(c['material_count']);
    }
    final String liveClock = _liveUpdatedAt == null
        ? 'Syncing'
        : TimeOfDay.fromDateTime(_liveUpdatedAt!).format(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KgplPageHeader(
            title: 'Training Courses & Video Curriculum Studio',
            subtitle:
                'Build tracks, post lessons straight from your device & watch intern activity live',
            icon: Icons.movie_filter_rounded,
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.video_call_rounded, size: 18),
                label: const Text('Post Video'),
                onPressed: _showPostVideoDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create Course'),
                onPressed: _showCreateCourseDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Studio command banner with live watch strip
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0F172A),
                  Color(0xFF1E1B4B),
                  Color(0xFF0C4A6E)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _kpiPill('📚 Active Tracks', '${_courses.length}',
                        const Color(0xFF818CF8), Icons.school_rounded),
                    const SizedBox(width: 12),
                    _kpiPill(
                        '🎬 Video Lessons',
                        '$totalVideos',
                        const Color(0xFF22D3EE),
                        Icons.play_circle_fill_rounded),
                    const SizedBox(width: 12),
                    _kpiPill('🗂️ Modules', '$totalModules',
                        const Color(0xFFA78BFA), Icons.folder_rounded),
                    const SizedBox(width: 12),
                    _kpiPill('📎 Materials', '$totalMaterials',
                        const Color(0xFFFBBF24), Icons.attach_file_rounded),
                    const Spacer(),
                    _liveDot(),
                    const SizedBox(width: 6),
                    Text('${_liveViewers.length} watching • $liveClock',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: _liveViewers.isEmpty
                      ? Row(
                          children: [
                            const Icon(Icons.sensors_off_rounded,
                                color: Colors.white54, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Live watch activity appears here the moment an intern starts a lesson.',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.62),
                                    fontSize: 12),
                              ),
                            ),
                          ],
                        )
                      : SizedBox(
                          height: 46,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _liveViewers.length > 8
                                ? 9
                                : _liveViewers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (ctx, i) {
                              if (i == 8) {
                                return Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                        '+${_liveViewers.length - 8} more watching',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                );
                              }
                              return _liveViewerChip(_liveViewers[i]);
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _courses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.school_outlined,
                                size: 60, color: AppTheme.textMuted),
                            const SizedBox(height: 12),
                            const Text('No courses found yet',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            const Text(
                                'Create your first course track to get started.',
                                style:
                                    TextStyle(color: AppTheme.textSecondary)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Create Course'),
                              onPressed: _showCreateCourseDialog,
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 18,
                          mainAxisSpacing: 18,
                          childAspectRatio: 1.45,
                        ),
                        itemCount: _courses.length,
                        itemBuilder: (ctx, i) {
                          final c = _courses[i];
                          final int videoCount = safeInt(c['video_count']);
                          final int moduleCount = safeInt(c['module_count']);
                          final int materialCount =
                              safeInt(c['material_count']);
                          final int liveViewers = safeInt(c['live_viewers']);
                          final int durationHours =
                              safeInt(c['duration_hours'], 14);
                          final String title = safeString(c['title']);
                          final String desc = safeString(c['description'],
                              'Comprehensive intern training syllabus');
                          final String dept = safeString(c['department_name']);

                          return FadeSlideIn(
                            delay: Duration(milliseconds: 70 * i),
                            child: HoverLift(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Card Top Accent
                                    Container(
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFF6366F1),
                                            Color(0xFFA855F7),
                                            Color(0xFF06B6D4)
                                          ],
                                        ),
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(20),
                                          topRight: Radius.circular(20),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF6366F1)
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                        Icons.play_circle_fill,
                                                        color:
                                                            Color(0xFF6366F1),
                                                        size: 14),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                        '$videoCount ${videoCount == 1 ? 'Video Lesson' : 'Video Lessons'}',
                                                        style: const TextStyle(
                                                            color: Color(
                                                                0xFF6366F1),
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: liveViewers > 0
                                                      ? const Color(0xFFEF4444)
                                                          .withOpacity(0.12)
                                                      : const Color(0xFF10B981)
                                                          .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                        liveViewers > 0
                                                            ? Icons.sensors
                                                            : Icons.bolt,
                                                        color: liveViewers > 0
                                                            ? const Color(
                                                                0xFFEF4444)
                                                            : const Color(
                                                                0xFF10B981),
                                                        size: 13),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                        liveViewers > 0
                                                            ? '$liveViewers WATCHING NOW'
                                                            : 'LIVE TRACK',
                                                        style: TextStyle(
                                                            color: liveViewers >
                                                                    0
                                                                ? const Color(
                                                                    0xFFEF4444)
                                                                : const Color(
                                                                    0xFF10B981),
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: AppTheme.textPrimary),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            desc,
                                            style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 12,
                                                height: 1.3),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 6,
                                            children: [
                                              _metaLabel(
                                                  Icons.apartment_outlined,
                                                  dept.isEmpty
                                                      ? 'No department'
                                                      : dept),
                                              _metaLabel(
                                                  Icons.access_time_rounded,
                                                  '$durationHours Hours'),
                                              _metaLabel(Icons.folder_rounded,
                                                  '$moduleCount Modules'),
                                              _metaLabel(
                                                  Icons.attach_file_rounded,
                                                  '$materialCount Materials'),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.only(
                                          bottomLeft: Radius.circular(20),
                                          bottomRight: Radius.circular(20),
                                        ),
                                        border: Border(
                                            top: BorderSide(
                                                color: Color(0xFFF1F5F9))),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                                '$videoCount ${videoCount == 1 ? 'lesson' : 'lessons'} • $moduleCount ${moduleCount == 1 ? 'module' : 'modules'}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme
                                                        .textSecondary)),
                                          ),
                                          IconButton(
                                            tooltip: 'Assign course to intern',
                                            onPressed: _assigningCourseId ==
                                                    safeInt(c['id'])
                                                ? null
                                                : () => _assignCourseToInterns(
                                                    Map<String, dynamic>.from(
                                                        c as Map)),
                                            style: IconButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFE0F2FE),
                                              padding: const EdgeInsets.all(7),
                                              minimumSize: const Size(32, 32),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(9)),
                                            ),
                                            icon: _assigningCourseId ==
                                                    safeInt(c['id'])
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Color(
                                                                0xFF0284C7)),
                                                  )
                                                : const Icon(
                                                    Icons.person_add_alt_1,
                                                    color: Color(0xFF0284C7),
                                                    size: 18),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            tooltip: 'Delete course',
                                            onPressed: _deletingCourseId ==
                                                    safeInt(c['id'])
                                                ? null
                                                : () => _confirmDeleteCourse(c),
                                            style: IconButton.styleFrom(
                                              backgroundColor:
                                                  AppTheme.dangerLight,
                                              padding: const EdgeInsets.all(7),
                                              minimumSize: const Size(32, 32),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(9)),
                                            ),
                                            icon: _deletingCourseId ==
                                                    safeInt(c['id'])
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: AppTheme
                                                                .danger),
                                                  )
                                                : const Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    color: AppTheme.danger,
                                                    size: 18),
                                          ),
                                          const SizedBox(width: 8),
                                          InkWell(
                                            onTap: () =>
                                                _openCourseCurriculumStudio(c),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 7),
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFF6366F1),
                                                    Color(0xFF4F46E5)
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                boxShadow: [
                                                  BoxShadow(
                                                      color: const Color(
                                                              0xFF6366F1)
                                                          .withOpacity(0.3),
                                                      blurRadius: 6,
                                                      offset:
                                                          const Offset(0, 2)),
                                                ],
                                              ),
                                              child: const Row(
                                                children: [
                                                  Text('Open Studio',
                                                      style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                  SizedBox(width: 4),
                                                  Icon(
                                                      Icons
                                                          .arrow_forward_rounded,
                                                      color: Colors.white,
                                                      size: 13),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _metaLabel(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ],
    );
  }

  Widget _liveDot() {
    return const _LiveDot();
  }

  Widget _liveViewerChip(dynamic viewer) {
    final String name = safeString(viewer['intern_name'], 'Intern');
    final String lesson = safeString(viewer['video_title'], 'Lesson');
    final double pct =
        safeDouble(viewer['completion_percentage']).clamp(0, 100).toDouble();
    return Tooltip(
      message: '$lesson • ${pct.toStringAsFixed(0)}% watched',
      child: Container(
        width: 236,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.14)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: const Color(0xFF6366F1),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'I',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct / 100,
                            minHeight: 4,
                            backgroundColor: Colors.white.withOpacity(0.18),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF34D399)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${pct.toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 9.5)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiPill(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w500)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

// Pulsing "live" indicator used by the watch-activity strip.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Center(
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: const Color(0xFF34D399),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF34D399).withOpacity(0.6),
                    blurRadius: 8,
                    spreadRadius: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// HR Direct Device Video Posting Dialog
// -------------------------------------------------------------
class _PostVideoDeviceDialog extends StatefulWidget {
  final List<dynamic> courses;
  final VoidCallback onPosted;

  const _PostVideoDeviceDialog({required this.courses, required this.onPosted});

  @override
  State<_PostVideoDeviceDialog> createState() => _PostVideoDeviceDialogState();
}

class _PostVideoDeviceDialogState extends State<_PostVideoDeviceDialog> {
  final ApiService _api = ApiService();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _durationCtrl = TextEditingController(text: '10');
  final TextEditingController _minWatchCtrl = TextEditingController(text: '80');
  final TextEditingController _newModuleCtrl = TextEditingController();

  int? _courseId;
  int? _moduleId;
  List<dynamic> _modules = [];
  bool _loadingModules = false;
  bool _useNewModule = false;
  SelectedLargeVideo? _pickedVideo;
  LargeVideoUploader? _uploader;
  bool _isPosting = false;
  bool _uploadCancelRequested = false;
  double _uploadProgress = 0;
  String? _postedTitle;

  @override
  void initState() {
    super.initState();
    if (widget.courses.isNotEmpty) {
      _courseId = safeInt(widget.courses.first['id']);
      _loadModules(_courseId!);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _durationCtrl.dispose();
    _minWatchCtrl.dispose();
    _newModuleCtrl.dispose();
    if (_isPosting) {
      _uploader?.cancel().catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _loadModules(int courseId) async {
    setState(() {
      _loadingModules = true;
      _modules = [];
      _moduleId = null;
    });
    try {
      final res = await _api.get('${ApiConfig.hrCourses}/$courseId');
      final course = res['course'] ?? {};
      final modules = (course['modules'] as List?) ?? [];
      if (!mounted || _courseId != courseId) return;
      setState(() {
        _modules = modules;
        _moduleId = modules.isNotEmpty ? safeInt(modules.first['id']) : null;
      });
    } catch (_) {
      if (mounted && _courseId == courseId) {
        setState(() {
          _modules = [];
          _moduleId = null;
        });
      }
    } finally {
      if (mounted && _courseId == courseId) {
        setState(() => _loadingModules = false);
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await pickLargeVideo(
        allowedExtensions: [
          'mp4',
          'webm',
          'mov',
          'mkv',
          'avi',
          'm4v',
          'ts',
          'wmv',
          'flv',
          'mpeg',
          'mpg',
          '3gp'
        ],
      );
      if (file == null) return;
      setState(() {
        _pickedVideo = file;
        _uploader = createLargeVideoUploader(file);
        _uploadProgress = 0;
        if (_titleCtrl.text.trim().isEmpty) {
          _titleCtrl.text = file.name
              .replaceAll(RegExp(r'\.[^.]+$'), '')
              .replaceAll('_', ' ');
        }
      });
    } catch (e) {
      if (mounted) {
        showAppFeedback(context, 'Could not read the video: $e', isError: true);
      }
    }
  }

  Future<void> _publish() async {
    if (_courseId == null) {
      showAppFeedback(context, 'Choose a course track first.', isError: true);
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      showAppFeedback(context, 'Enter a video lesson title.', isError: true);
      return;
    }
    if (_pickedVideo == null || _uploader == null) {
      showAppFeedback(context, 'Choose a video file from your device first.',
          isError: true);
      return;
    }
    setState(() {
      _isPosting = true;
      _uploadCancelRequested = false;
      _uploadProgress = 0;
    });
    try {
      int? targetModuleId = _moduleId;
      if (_useNewModule) {
        final String newModuleTitle = _newModuleCtrl.text.trim();
        if (newModuleTitle.isEmpty) {
          setState(() => _isPosting = false);
          showAppFeedback(context, 'Name the new module first.', isError: true);
          return;
        }
        final modRes = await _api.post('${ApiConfig.hrCourses}/modules', {
          'course_id': _courseId,
          'title': newModuleTitle,
          'order_sequence': _modules.length + 1,
        });
        targetModuleId = safeInt(modRes['module_id']);
        if (mounted) _loadModules(_courseId!);
      }

      final videoPath = await _uploader!.upload(
        onProgress: (sent, total) {
          if (!mounted) return;
          setState(() {
            _uploadProgress = total > 0 ? sent / total : 0;
          });
        },
        isCancelled: () => _uploadCancelRequested,
      );

      await _api.post('${ApiConfig.hrCourses}/videos', {
        'course_id': _courseId,
        'module_id': targetModuleId,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'video_path': videoPath,
        'duration_seconds': safeInt(_durationCtrl.text, 10) * 60,
        'min_watch_percentage': safeInt(_minWatchCtrl.text, 80),
        'order_sequence': 1,
      });
      if (!mounted) return;
      setState(() {
        _isPosting = false;
        _uploadProgress = 0;
        _uploader = null;
        _postedTitle = _titleCtrl.text.trim();
        _pickedVideo = null;
        _titleCtrl.clear();
        _descCtrl.clear();
        _useNewModule = false;
        _newModuleCtrl.clear();
      });
      widget.onPosted();
    } catch (e) {
      if (mounted) {
        setState(() => _isPosting = false);
        showAppFeedback(
            context,
            e is LargeUploadException || e is LargeUploadCancelled
                ? '$e'
                : 'Failed to post video: $e',
            isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF06B6D4), Color(0xFF6366F1)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.video_call_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Post Video From Device',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                SizedBox(height: 2),
                Text('Publishes straight to the intern video player',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: _postedTitle != null
            ? _postedView()
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<int>(
                      value: _courseId,
                      decoration: InputDecoration(
                        labelText: 'Course Track *',
                        prefixIcon: const Icon(Icons.school_rounded, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      items: widget.courses.map((c) {
                        final dept = safeString(c['department_name']);
                        return DropdownMenuItem<int>(
                          value: safeInt(c['id']),
                          child: Text(
                              dept.isEmpty
                                  ? safeString(c['title'])
                                  : '${safeString(c['title'])} • $dept',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: _isPosting
                          ? null
                          : (val) {
                              if (val == null) return;
                              setState(() => _courseId = val);
                              _loadModules(val);
                            },
                    ),
                    const SizedBox(height: 14),
                    if (_loadingModules)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 3),
                      )
                    else if (_modules.isNotEmpty)
                      DropdownButtonFormField<int>(
                        value: _moduleId,
                        decoration: InputDecoration(
                          labelText: 'Curriculum Module *',
                          prefixIcon:
                              const Icon(Icons.folder_outlined, size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        items: _modules.map((m) {
                          return DropdownMenuItem<int>(
                            value: safeInt(m['id']),
                            child: Text(safeString(m['title']),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: _isPosting
                            ? null
                            : (val) => setState(() => _moduleId = val),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF6366F1).withOpacity(0.2)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                color: Color(0xFF6366F1), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No modules yet — "Module 1: Core Curriculum" will be created automatically.',
                                style: TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: _useNewModule,
                          onChanged: _isPosting
                              ? null
                              : (val) =>
                                  setState(() => _useNewModule = val ?? false),
                          visualDensity: VisualDensity.compact,
                        ),
                        const Text('Put this lesson in a new module',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary)),
                      ],
                    ),
                    if (_useNewModule)
                      TextField(
                        controller: _newModuleCtrl,
                        enabled: !_isPosting,
                        decoration: InputDecoration(
                          labelText: 'New Module Name *',
                          hintText: 'e.g. Module 4: Advanced Practice',
                          prefixIcon: const Icon(
                              Icons.create_new_folder_outlined,
                              size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.movie_rounded,
                                  size: 18, color: Color(0xFF06B6D4)),
                              SizedBox(width: 8),
                              Text('Video File From This Device *',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Supports .mp4, .webm, .mov, .mkv, .avi, .m4v up to 50 GB — resumable chunked upload.',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 12),
                          if (_pickedVideo != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFF06B6D4)
                                        .withOpacity(0.4)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.videocam_rounded,
                                      color: Color(0xFF06B6D4), size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_pickedVideo!.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12.5),
                                            overflow: TextOverflow.ellipsis),
                                        Text(
                                            '${formatFileSize(_pickedVideo!.size)} • Ready to publish',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: AppTheme.textMuted)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18, color: Color(0xFFEF4444)),
                                    onPressed: _isPosting
                                        ? null
                                        : () {
                                            final uploader = _uploader;
                                            setState(() {
                                              _pickedVideo = null;
                                              _uploader = null;
                                              _uploadProgress = 0;
                                            });
                                            uploader
                                                ?.cancel()
                                                .catchError((_) {});
                                          },
                                  ),
                                ],
                              ),
                            )
                          else
                            Center(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.file_upload_outlined,
                                    size: 18),
                                label: const Text('Browse Device for Video'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF0891B2),
                                  side: const BorderSide(
                                      color: Color(0xFF06B6D4)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 12),
                                ),
                                onPressed: _isPosting ? null : _pickVideo,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _titleCtrl,
                      enabled: !_isPosting,
                      decoration: InputDecoration(
                        labelText: 'Video Lesson Title *',
                        hintText: 'e.g. Working with Your First Live Project',
                        prefixIcon:
                            const Icon(Icons.subtitles_rounded, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _durationCtrl,
                            enabled: !_isPosting,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Duration (Minutes) *',
                              prefixIcon:
                                  const Icon(Icons.timer_outlined, size: 20),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _minWatchCtrl,
                            enabled: !_isPosting,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Min Watch Target (%)',
                              prefixIcon:
                                  const Icon(Icons.percent_rounded, size: 20),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _descCtrl,
                      enabled: !_isPosting,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Lesson Description / Summary',
                        hintText: 'Practical concepts covered in this video...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Length',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textMuted)),
                        _quickChip('5 min', () => _durationCtrl.text = '5'),
                        _quickChip('10 min', () => _durationCtrl.text = '10'),
                        _quickChip('20 min', () => _durationCtrl.text = '20'),
                        const SizedBox(width: 4),
                        const Text('Target',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textMuted)),
                        _quickChip('70%', () => _minWatchCtrl.text = '70'),
                        _quickChip('80%', () => _minWatchCtrl.text = '80'),
                        _quickChip('90%', () => _minWatchCtrl.text = '90'),
                      ],
                    ),
                    if (_isPosting) ...[
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        minHeight: 4,
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Uploading ${formatFileSize(_pickedVideo?.size ?? 0)}'
                        '${_uploadProgress > 0 ? ' — ${(_uploadProgress * 100).round()}%' : ''}'
                        ' (resumable, keep this window open).',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: _postedTitle != null
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Post Another Video'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onPressed: () => setState(() => _postedTitle = null),
              ),
            ]
          : [
              TextButton(
                onPressed: _isPosting ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: _isPosting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.publish_rounded, size: 16),
                label: Text(_isPosting ? 'Posting video...' : 'Publish Video'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onPressed: _isPosting ? null : _publish,
              ),
            ],
    );
  }

  Widget _quickChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: _isPosting ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF334155),
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _postedView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFD1FAE5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: Color(0xFF10B981), size: 36),
          ),
          const SizedBox(height: 14),
          const Text('Video posted',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            '"${_postedTitle ?? ''}" is live in the intern player and ready to track watch progress.',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Gen-Z Course Curriculum Studio Dialog with Video Drops & Telemetry
// -------------------------------------------------------------
class _CourseCurriculumStudioDialog extends StatefulWidget {
  final int courseId;
  final String initialTitle;
  final VoidCallback onUpdated;

  const _CourseCurriculumStudioDialog({
    required this.courseId,
    required this.initialTitle,
    required this.onUpdated,
  });

  @override
  State<_CourseCurriculumStudioDialog> createState() =>
      _CourseCurriculumStudioDialogState();
}

class _CourseCurriculumStudioDialogState
    extends State<_CourseCurriculumStudioDialog> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _course;
  List<dynamic> _modules = [];
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _loadCourseDetails();
    _progressTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => _refreshWatchProgress());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  int get _watchingNow {
    final now = DateTime.now();
    final ids = <int>{};
    for (final m in _modules) {
      for (final v in ((m as Map)['videos'] as List?) ?? const []) {
        for (final p in ((v as Map)['intern_progress'] as List?) ?? const []) {
          final raw = (p as Map)['last_watched_at'];
          if (raw == null || safeInt(p['watch_count']) == 0) continue;
          final at = DateTime.tryParse(raw.toString())?.toLocal();
          if (at != null && now.difference(at).inSeconds <= 30) {
            ids.add(safeInt(p['intern_id']));
          }
        }
      }
    }
    return ids.length;
  }

  Future<void> _refreshWatchProgress() async {
    try {
      final res = await _api.get('${ApiConfig.hrCourses}/${widget.courseId}');
      if (!mounted) return;
      final course = res['course'] ?? {};
      setState(() {
        _course = course;
        _modules = (course['modules'] as List?) ?? [];
      });
    } catch (_) {}
  }

  Future<void> _loadCourseDetails() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get('${ApiConfig.hrCourses}/${widget.courseId}');
      final course = res['course'] ?? {};
      final modules = (course['modules'] as List?) ?? [];
      setState(() {
        _course = course;
        _modules = modules;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showAddModuleDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.create_new_folder_rounded,
                  color: Color(0xFF6366F1), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Add Curriculum Module',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Module Title *',
                  hintText: 'e.g. Module 1: Core Infrastructure',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Description / Competencies',
                  hintText: 'Overview of skills learned in this section...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) {
                showAppFeedback(context, 'Please enter a module title.',
                    isError: true);
                return;
              }
              Navigator.pop(ctx);
              try {
                await _api.post('${ApiConfig.hrCourses}/modules', {
                  'course_id': widget.courseId,
                  'title': titleCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'order_sequence': _modules.length + 1,
                });
                _loadCourseDetails();
                widget.onUpdated();
                if (mounted)
                  showAppFeedback(context, 'Module added successfully.');
              } catch (e) {
                if (mounted)
                  showAppFeedback(context, 'Failed to add module: $e',
                      isError: true);
              }
            },
            child: const Text('Add Module'),
          ),
        ],
      ),
    );
  }

  void _showAddVideoDialog({int? preselectedModuleId}) {
    final parentContext = context;
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController(
        text:
            'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4');
    final descCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '15');
    final minWatchCtrl = TextEditingController(text: '80');

    int? selectedModId = preselectedModuleId ??
        (_modules.isNotEmpty ? safeInt(_modules[0]['id']) : null);
    String source = 'device';
    SelectedLargeVideo? pickedVideo;
    LargeVideoUploader? uploader;
    bool isPublishing = false;
    bool uploadCancelRequested = false;
    double uploadProgress = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> pickVideo() async {
            try {
              final file = await pickLargeVideo(
                allowedExtensions: [
                  'mp4',
                  'webm',
                  'mov',
                  'mkv',
                  'avi',
                  'm4v',
                  'ts',
                  'wmv',
                  'flv',
                  'mpeg',
                  'mpg',
                  '3gp'
                ],
              );
              if (file == null) return;
              setModalState(() {
                pickedVideo = file;
                uploader = createLargeVideoUploader(file);
                uploadProgress = 0;
                if (titleCtrl.text.trim().isEmpty) {
                  titleCtrl.text = file.name
                      .replaceAll(RegExp(r'\.[^.]+$'), '')
                      .replaceAll('_', ' ');
                }
              });
            } catch (e) {
              if (context.mounted) {
                showAppFeedback(context, 'Could not read the video: $e',
                    isError: true);
              }
            }
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.video_call_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Text('Add Video Lesson',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Publish a video lesson. Intern watch frequency, replay count, and duration are tracked in real time.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 14),

                    // Quick Instant Lesson Presets
                    const Text(
                        '💡 Instant Video Lesson Presets (Click to autofill):',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6366F1))),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _videoPresetChip(
                          '🧭 Systems & Automation',
                          'System Administration & Automation Foundations',
                          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                          '15',
                          '85',
                          'Core administration tasks, directory structure, scheduled jobs, and repeatable automation.',
                          titleCtrl,
                          urlCtrl,
                          durationCtrl,
                          minWatchCtrl,
                          descCtrl,
                          () => setModalState(() => source = 'url'),
                        ),
                        _videoPresetChip(
                          '🌐 Networking Fundamentals',
                          'Network Addressing, Segmentation & Secure Routing',
                          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
                          '12',
                          '80',
                          'How traffic is addressed, segmented, and routed securely across enterprise environments.',
                          titleCtrl,
                          urlCtrl,
                          durationCtrl,
                          minWatchCtrl,
                          descCtrl,
                          () => setModalState(() => source = 'url'),
                        ),
                        _videoPresetChip(
                          '📦 Application Packaging',
                          'Packaging & Shipping Applications Consistently',
                          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
                          '18',
                          '85',
                          'Packaging fundamentals, version control of releases, and reliable delivery practices.',
                          titleCtrl,
                          urlCtrl,
                          durationCtrl,
                          minWatchCtrl,
                          descCtrl,
                          () => setModalState(() => source = 'url'),
                        ),
                        _videoPresetChip(
                          '☁️ Cloud Traffic Management',
                          'Cloud Networking, Access Policies & Traffic Routing',
                          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
                          '20',
                          '90',
                          'Private networks, access policies, request distribution, health checks, and failover.',
                          titleCtrl,
                          urlCtrl,
                          durationCtrl,
                          minWatchCtrl,
                          descCtrl,
                          () => setModalState(() => source = 'url'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Lesson Title *',
                        hintText: 'e.g. System Fundamentals & Networking',
                        prefixIcon:
                            const Icon(Icons.play_lesson_rounded, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Target Module Selector
                    if (_modules.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        value: selectedModId,
                        decoration: InputDecoration(
                          labelText: 'Curriculum Module Section *',
                          prefixIcon:
                              const Icon(Icons.folder_outlined, size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        items: _modules.map((m) {
                          return DropdownMenuItem<int>(
                            value: safeInt(m['id']),
                            child: Text(
                              safeString(m['title']),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) =>
                            setModalState(() => selectedModId = val),
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF6366F1).withOpacity(0.2)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                color: Color(0xFF6366F1), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No modules exist yet. "Module 1: Core Curriculum" will be auto-generated!',
                                style: TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    DropdownButtonFormField<String>(
                      value: source,
                      decoration: InputDecoration(
                        labelText: 'Video Source *',
                        prefixIcon: const Icon(Icons.movie_rounded, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'device',
                          child: Text(
                              'Upload Video From My Device (MP4, WebM, MOV)'),
                        ),
                        DropdownMenuItem(
                          value: 'url',
                          child: Text('Video Stream URL (CDN / MP4)'),
                        ),
                      ],
                      onChanged: (val) =>
                          setModalState(() => source = val ?? 'device'),
                    ),
                    const SizedBox(height: 14),
                    if (source == 'device')
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.movie_rounded,
                                    size: 18, color: Color(0xFF06B6D4)),
                                SizedBox(width: 8),
                                Text('Attach Video From Device',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppTheme.textPrimary)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Supports high-capacity video files (4 GB+ up to 50 GB) in .mp4, .webm, .mov, .mkv, .avi, .m4v, .ts — fast resumable chunked upload.',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted),
                            ),
                            const SizedBox(height: 12),
                            if (pickedVideo != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0xFF06B6D4)
                                          .withOpacity(0.4)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.videocam_rounded,
                                        color: Color(0xFF06B6D4), size: 22),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(pickedVideo!.name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.5),
                                              overflow: TextOverflow.ellipsis),
                                          Text(
                                              '${formatFileSize(pickedVideo!.size)} • Ready to publish',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppTheme.textMuted)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded,
                                          size: 18, color: Color(0xFFEF4444)),
                                      onPressed: isPublishing
                                          ? null
                                          : () {
                                              final activeUploader = uploader;
                                              setModalState(() {
                                                pickedVideo = null;
                                                uploader = null;
                                                uploadProgress = 0;
                                              });
                                              activeUploader
                                                  ?.cancel()
                                                  .catchError((_) {});
                                            },
                                    ),
                                  ],
                                ),
                              )
                            else
                              Center(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.file_upload_outlined,
                                      size: 18),
                                  label: const Text('Browse Device for Video'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF0891B2),
                                    side: const BorderSide(
                                        color: Color(0xFF06B6D4)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 12),
                                  ),
                                  onPressed: isPublishing ? null : pickVideo,
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      TextField(
                        controller: urlCtrl,
                        decoration: InputDecoration(
                          labelText: 'Video Stream URL * (MP4 / WebM / CDN)',
                          hintText:
                              'https://cdn.example.com/videos/lesson1.mp4',
                          prefixIcon: const Icon(Icons.link_rounded, size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    if (isPublishing) ...[
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        minHeight: 4,
                        value: uploadProgress > 0 ? uploadProgress : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Uploading ${formatFileSize(pickedVideo?.size ?? 0)}'
                        '${uploadProgress > 0 ? ' — ${(uploadProgress * 100).round()}%' : ''}'
                        ' (resumable, keep this window open).',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: durationCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Duration (Minutes) *',
                              prefixIcon:
                                  const Icon(Icons.timer_outlined, size: 20),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: minWatchCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Min Watch Target (%) *',
                              prefixIcon:
                                  const Icon(Icons.percent_rounded, size: 20),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Lesson Description / Summary',
                        hintText:
                            'Key practical engineering concepts taught in this video...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton.icon(
                icon: isPublishing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.rocket_launch_rounded, size: 16),
                label: Text(isPublishing ? 'Publishing...' : 'Publish Video'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onPressed: isPublishing
                    ? null
                    : () async {
                        if (titleCtrl.text.trim().isEmpty) {
                          showAppFeedback(
                              parentContext, 'Please enter a lesson title.',
                              isError: true);
                          return;
                        }
                        if (source == 'device' &&
                            (pickedVideo == null || uploader == null)) {
                          showAppFeedback(parentContext,
                              'Please choose a video file from your device.',
                              isError: true);
                          return;
                        }
                        if (source == 'url' && urlCtrl.text.trim().isEmpty) {
                          showAppFeedback(
                              parentContext, 'Please enter a video URL.',
                              isError: true);
                          return;
                        }
                        setModalState(() {
                          isPublishing = true;
                          uploadCancelRequested = false;
                          uploadProgress = 0;
                        });
                        try {
                          final int durationMins =
                              safeInt(durationCtrl.text, 10);
                          final int minPct = safeInt(minWatchCtrl.text, 80);

                          final body = <String, dynamic>{
                            'course_id': widget.courseId,
                            'module_id': selectedModId,
                            'title': titleCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                            'duration_seconds': durationMins * 60,
                            'min_watch_percentage': minPct,
                            'order_sequence': 1,
                          };
                          if (source == 'device') {
                            body['video_path'] = await uploader!.upload(
                              onProgress: (sent, total) {
                                setModalState(() {
                                  uploadProgress = total > 0 ? sent / total : 0;
                                });
                              },
                              isCancelled: () => uploadCancelRequested,
                            );
                          } else {
                            body['video_path'] = urlCtrl.text.trim();
                          }
                          await _api.post(
                              '${ApiConfig.hrCourses}/videos', body);
                          if (!mounted) return;
                          Navigator.pop(ctx);
                          _loadCourseDetails();
                          widget.onUpdated();
                          if (parentContext.mounted)
                            showAppFeedback(parentContext,
                                'Video lesson published successfully.');
                        } catch (e) {
                          if (mounted) {
                            setModalState(() {
                              isPublishing = false;
                              uploadProgress = 0;
                            });
                            showAppFeedback(
                                parentContext,
                                e is LargeUploadException ||
                                        e is LargeUploadCancelled
                                    ? '$e'
                                    : 'Failed to publish video: $e',
                                isError: true);
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _videoPresetChip(
    String label,
    String title,
    String url,
    String duration,
    String minPct,
    String desc,
    TextEditingController titleCtrl,
    TextEditingController urlCtrl,
    TextEditingController durationCtrl,
    TextEditingController minPctCtrl,
    TextEditingController descCtrl,
    VoidCallback? onApplied,
  ) {
    return InkWell(
      onTap: () {
        onApplied?.call();
        titleCtrl.text = title;
        urlCtrl.text = url;
        durationCtrl.text = duration;
        minPctCtrl.text = minPct;
        descCtrl.text = desc;
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF334155),
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showInternWatchTelemetryModal(Map<String, dynamic> video) {
    final List<dynamic> internProgress =
        (video['intern_progress'] as List?) ?? [];
    final String videoTitle = safeString(video['title']);
    final int totalViews = safeInt(video['total_views']);
    final int durationSeconds = safeInt(video['duration_seconds'], 600);
    final int durationMinutes = (durationSeconds / 60).round();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF818CF8)),
                    ),
                    child: const Text('📈 INTERN WATCH PROGRESS',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  IconButton(
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                videoTitle,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _telemetryBadge('⏱️ $durationMinutes mins duration',
                      const Color(0xFF06B6D4)),
                  const SizedBox(width: 8),
                  _telemetryBadge(
                      '🔥 $totalViews Total Views Across All Interns',
                      const Color(0xFFF59E0B)),
                  const SizedBox(width: 8),
                  _telemetryBadge(
                      '🎯 ${safeInt(video['min_watch_percentage'], 80)}% Min Target',
                      const Color(0xFF10B981)),
                ],
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 620,
          height: 420,
          child: internProgress.isEmpty
              ? const Center(
                  child: Text('No active interns registered in the system.'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: internProgress.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = internProgress[i];
                    final String name =
                        safeString(item['intern_name'], 'Intern');
                    final String email = safeString(item['intern_email']);
                    final String code = safeString(item['intern_code']);
                    final int watchCount = safeInt(item['watch_count']);
                    final double completionPct =
                        safeDouble(item['completion_percentage']);
                    final double watchedSec =
                        safeDouble(item['total_watched_seconds']);
                    final int watchedMins = (watchedSec / 60).floor();
                    final int watchedSecRemainder = (watchedSec % 60).round();
                    final bool isCompleted =
                        safeInt(item['is_completed']) == 1 ||
                            completionPct >= 80;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: watchCount > 0
                                ? const Color(0xFF6366F1)
                                : const Color(0xFFCBD5E1),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'I',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(code,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF64748B),
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(email,
                                    style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 11)),
                                const SizedBox(height: 6),

                                // Progress Bar
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value:
                                        (completionPct / 100).clamp(0.0, 1.0),
                                    backgroundColor: const Color(0xFFE2E8F0),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isCompleted
                                          ? const Color(0xFF10B981)
                                          : watchCount > 0
                                              ? const Color(0xFFF59E0B)
                                              : const Color(0xFFCBD5E1),
                                    ),
                                    minHeight: 6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),

                          // Watch Count & Status Pill
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: watchCount > 0
                                      ? const Color(0xFF6366F1)
                                          .withOpacity(0.12)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: watchCount > 0
                                        ? const Color(0xFF6366F1)
                                            .withOpacity(0.3)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      watchCount > 0
                                          ? Icons.remove_red_eye
                                          : Icons.visibility_off_outlined,
                                      size: 13,
                                      color: watchCount > 0
                                          ? const Color(0xFF6366F1)
                                          : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      watchCount > 0
                                          ? 'Watched $watchCount times'
                                          : 'Not watched yet',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: watchCount > 0
                                            ? const Color(0xFF6366F1)
                                            : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isCompleted
                                    ? 'Completed (${completionPct.toStringAsFixed(0)}%)'
                                    : watchCount > 0
                                        ? '${completionPct.toStringAsFixed(0)}% (${watchedMins}m ${watchedSecRemainder}s)'
                                        : '0% Unseen',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isCompleted
                                      ? const Color(0xFF10B981)
                                      : watchCount > 0
                                          ? const Color(0xFFD97706)
                                          : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _telemetryBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Future<void> _deleteVideo(int videoId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Video Lesson?'),
        content: const Text(
            'Are you sure you want to delete this video lesson? Watch progress logs will also be cleared.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.delete('${ApiConfig.hrCourses}/videos/$videoId');
        _loadCourseDetails();
        widget.onUpdated();
        if (mounted) showAppFeedback(context, 'Video lesson deleted.');
      } catch (e) {
        if (mounted) {
          showAppFeedback(context, 'Failed to delete video: $e', isError: true);
        }
      }
    }
  }

  void _openModuleTestEditor({int? specificModuleId, String? specificModuleTitle}) {
    if (_modules.isEmpty) {
      showAppFeedback(context, 'Please create a module first before adding a test.', isError: true);
      return;
    }
    if (specificModuleId != null) {
      showDialog<void>(
        context: context,
        builder: (_) => CourseModuleTestEditorDialog(
          moduleId: specificModuleId,
          moduleTitle: specificModuleTitle ?? 'Module Test',
          onSaved: _loadCourseDetails,
        ),
      );
      return;
    }
    if (_modules.length == 1) {
      final m = _modules.first;
      showDialog<void>(
        context: context,
        builder: (_) => CourseModuleTestEditorDialog(
          moduleId: safeInt(m['id']),
          moduleTitle: safeString(m['title']),
          onSaved: _loadCourseDetails,
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Module for Test',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        children: _modules.map((m) {
          final int mId = safeInt(m['id']);
          final String mTitle = safeString(m['title']);
          final test = m['test'];
          final bool hasTest = test != null;
          return SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              showDialog<void>(
                context: context,
                builder: (_) => CourseModuleTestEditorDialog(
                  moduleId: mId,
                  moduleTitle: mTitle,
                  onSaved: _loadCourseDetails,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    hasTest ? Icons.check_circle_rounded : Icons.quiz_outlined,
                    color: hasTest ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(mTitle,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(
                          hasTest
                              ? 'Quiz: ${safeString(test['title'], 'Module Quiz')} (Score ≥${safeInt(test['passing_score'], 60)}%)'
                              : 'No test configured yet (Click to create)',
                          style: TextStyle(
                            fontSize: 11,
                            color: hasTest
                                ? const Color(0xFF10B981)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String courseTitle = _course != null
        ? safeString(_course!['title'], widget.initialTitle)
        : widget.initialTitle;
    final String courseDesc = _course != null
        ? safeString(_course!['description'], 'Course Curriculum')
        : 'Course Curriculum';
    final String courseDepartment =
        _course != null ? safeString(_course!['department_name']) : '';
    final int activeInterns =
        _course != null ? safeInt(_course!['total_active_interns'], 3) : 3;

    int totalCourseVideos = 0;
    int totalCourseViews = 0;
    for (final m in _modules) {
      final vids = (m['videos'] as List?) ?? [];
      totalCourseVideos += vids.length;
      for (final v in vids) {
        totalCourseViews += safeInt(v['total_views']);
      }
    }

    final size = MediaQuery.of(context).size;
    final dialogWidth =
        size.width > 1050 ? 940.0 : (size.width * 0.94).clamp(320.0, 940.0);
    final dialogHeight = (size.height * 0.92).clamp(480.0, 840.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white,
        ),
        child: Column(
          children: [
            // Gen-Z Top Banner
            Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF818CF8)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.bolt,
                                color: Color(0xFFFBBF24), size: 14),
                            SizedBox(width: 4),
                            Text('ACTIVE CURRICULUM TRACK',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _watchingNow > 0
                              ? const Color(0xFFEF4444).withOpacity(0.2)
                              : Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _watchingNow > 0
                                  ? const Color(0xFFF87171)
                                  : Colors.white24),
                        ),
                        child: Row(
                          children: [
                            Icon(_watchingNow > 0 ? Icons.sensors : Icons.bolt,
                                color: _watchingNow > 0
                                    ? const Color(0xFFFCA5A5)
                                    : const Color(0xFF34D399),
                                size: 13),
                            const SizedBox(width: 5),
                            Text(
                                _watchingNow > 0
                                    ? '$_watchingNow WATCHING NOW'
                                    : 'LIVE PROGRESS',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.white70, size: 20),
                        tooltip: 'Refresh',
                        onPressed: _loadCourseDetails,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    courseTitle,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.apartment_outlined,
                          color: Colors.white70, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        courseDepartment.isEmpty
                            ? 'Department: Not set'
                            : 'Department: $courseDepartment',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    courseDesc,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),

                  // Quick Badges & Action Buttons (Responsive for all resolutions)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _headerStatBadge(
                                  '🎬 $totalCourseVideos Videos',
                                  const Color(0xFF06B6D4)),
                              _headerStatBadge(
                                  '🔥 $totalCourseViews Total Plays',
                                  const Color(0xFFF59E0B)),
                              _headerStatBadge(
                                  '👥 $activeInterns Interns Tracking',
                                  const Color(0xFF10B981)),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Action: Add Video Lesson Button
                              ElevatedButton.icon(
                                icon: const Icon(
                                    Icons.play_circle_fill_rounded,
                                    size: 18),
                                label: const Text('Add Video Lesson'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                ),
                                onPressed: () => _showAddVideoDialog(),
                              ),
                              // Action: Create Course Test (Module Quiz inside course)
                              ElevatedButton.icon(
                                icon: const Icon(
                                    Icons.quiz_rounded,
                                    size: 16,
                                    color: Colors.white),
                                label: const Text('Create Course Test',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                ),
                                onPressed: () => _openModuleTestEditor(),
                              ),
                              // Action: Create Module Button
                              OutlinedButton.icon(
                                icon: const Icon(
                                    Icons.create_new_folder_outlined,
                                    size: 16,
                                    color: Colors.white),
                                label: const Text('New Module',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                      color: Colors.white.withOpacity(0.3)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                                onPressed: _showAddModuleDialog,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _modules.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: _modules.length,
                          itemBuilder: (context, i) {
                            final m = _modules[i];
                            final int moduleId = safeInt(m['id']);
                            final String modTitle = safeString(m['title']);
                            final String modDesc = safeString(m['description']);
                            final List<dynamic> videos =
                                (m['videos'] as List?) ?? [];
                            final test = m['test'];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border:
                                    Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.02),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Module Header
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 14),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(18),
                                        topRight: Radius.circular(18),
                                      ),
                                      border: Border(
                                          bottom: BorderSide(
                                              color: Color(0xFFE2E8F0))),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6366F1)
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'MODULE 0${i + 1}',
                                            style: const TextStyle(
                                                color: Color(0xFF6366F1),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(modTitle,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15)),
                                              if (modDesc.isNotEmpty)
                                                Text(modDesc,
                                                    style: const TextStyle(
                                                        color:
                                                            Color(0xFF64748B),
                                                        fontSize: 11)),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          icon: Icon(
                                            test == null
                                                ? Icons.add_task_rounded
                                                : Icons.edit_note_rounded,
                                            size: 14,
                                          ),
                                          label: Text(
                                            test == null
                                                ? '+ Create Test'
                                                : 'Edit Test',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: test == null
                                                ? const Color(0xFF6366F1)
                                                : const Color(0xFF059669),
                                            foregroundColor: Colors.white,
                                            elevation: 1,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                          ),
                                          onPressed: moduleId <= 0
                                              ? null
                                              : () => _openModuleTestEditor(
                                                    specificModuleId: moduleId,
                                                    specificModuleTitle: modTitle,
                                                  ),
                                        ),
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.add, size: 14),
                                          label: const Text(
                                              'Add Video to Module',
                                              style: TextStyle(fontSize: 11)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            foregroundColor:
                                                const Color(0xFF6366F1),
                                            elevation: 0,
                                            side: const BorderSide(
                                                color: Color(0xFFCBD5E1)),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10)),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                          ),
                                          onPressed: () => _showAddVideoDialog(
                                              preselectedModuleId: moduleId),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Module Video List
                                  if (videos.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Center(
                                        child: Column(
                                          children: [
                                            const Icon(
                                                Icons.video_collection_outlined,
                                                size: 36,
                                                color: Color(0xFFCBD5E1)),
                                            const SizedBox(height: 8),
                                            const Text(
                                                'No video lessons in this module yet.',
                                                style: TextStyle(
                                                    color: Color(0xFF64748B),
                                                    fontSize: 13)),
                                            const SizedBox(height: 10),
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.add,
                                                  size: 14),
                                              label: const Text(
                                                  'Drop First Video Here',
                                                  style:
                                                      TextStyle(fontSize: 12)),
                                              onPressed: () =>
                                                  _showAddVideoDialog(
                                                      preselectedModuleId:
                                                          moduleId),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  else
                                    ListView.separated(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      padding: const EdgeInsets.all(14),
                                      itemCount: videos.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 10),
                                      itemBuilder: (context, vIndex) {
                                        final v = videos[vIndex];
                                        final int vidId = safeInt(v['id']);
                                        final String vTitle =
                                            safeString(v['title']);
                                        final String vPath =
                                            safeString(v['video_path']);
                                        final int durationSec =
                                            safeInt(v['duration_seconds'], 600);
                                        final int durationMin =
                                            (durationSec / 60).round();
                                        final int minPct = safeInt(
                                            v['min_watch_percentage'], 80);
                                        final int totalViews =
                                            safeInt(v['total_views']);
                                        final int uniqueWatchers =
                                            safeInt(v['unique_viewers']);
                                        final int completedCount =
                                            safeInt(v['completed_count']);

                                        return Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                                color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: Row(
                                            children: [
                                              // Thumbnail Accent
                                              Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  gradient:
                                                      const LinearGradient(
                                                    colors: [
                                                      Color(0xFF6366F1),
                                                      Color(0xFFA855F7)
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: const Icon(
                                                    Icons.play_arrow_rounded,
                                                    color: Colors.white,
                                                    size: 28),
                                              ),
                                              const SizedBox(width: 14),

                                              // Video Info
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            'Lesson ${vIndex + 1}: $vTitle',
                                                            style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 14),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 7,
                                                                  vertical: 2),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                0xFFF1F5F9),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        6),
                                                            border: Border.all(
                                                                color: const Color(
                                                                    0xFFE2E8F0)),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              const Icon(
                                                                  Icons
                                                                      .timer_outlined,
                                                                  size: 12,
                                                                  color: Color(
                                                                      0xFF64748B)),
                                                              const SizedBox(
                                                                  width: 3),
                                                              Text(
                                                                  '$durationMin mins',
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      color: Color(
                                                                          0xFF64748B),
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold)),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 6),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 7,
                                                                  vertical: 2),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                    0xFF10B981)
                                                                .withOpacity(
                                                                    0.12),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        6),
                                                          ),
                                                          child: Text(
                                                              'Target: $minPct%',
                                                              style: const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Color(
                                                                      0xFF10B981),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold)),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      vPath,
                                                      style: const TextStyle(
                                                          color:
                                                              Color(0xFF94A3B8),
                                                          fontSize: 11),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 10),

                                                    // Watch Progress & Telemetry Strip
                                                    Row(
                                                      children: [
                                                        // Views Badge
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 3),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                    0xFFF59E0B)
                                                                .withOpacity(
                                                                    0.15),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              const Icon(
                                                                  Icons
                                                                      .local_fire_department_rounded,
                                                                  size: 13,
                                                                  color: Color(
                                                                      0xFFD97706)),
                                                              const SizedBox(
                                                                  width: 4),
                                                              Text(
                                                                '$totalViews Total Plays',
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: Color(
                                                                        0xFFD97706)),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),

                                                        // Interns Completed
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 3),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                    0xFF10B981)
                                                                .withOpacity(
                                                                    0.12),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              const Icon(
                                                                  Icons
                                                                      .check_circle_rounded,
                                                                  size: 13,
                                                                  color: Color(
                                                                      0xFF10B981)),
                                                              const SizedBox(
                                                                  width: 4),
                                                              Text(
                                                                '$completedCount/$activeInterns Completed',
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: Color(
                                                                        0xFF10B981)),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const Spacer(),

                                                        // View Intern Telemetry Button
                                                        ElevatedButton.icon(
                                                          icon: const Icon(
                                                              Icons
                                                                  .query_stats_rounded,
                                                              size: 14),
                                                          label: Text(
                                                              'Intern Watch Logs ($uniqueWatchers)',
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          11)),
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                const Color(
                                                                    0xFF6366F1),
                                                            foregroundColor:
                                                                Colors.white,
                                                            elevation: 0,
                                                            shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8)),
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical:
                                                                        6),
                                                          ),
                                                          onPressed: () =>
                                                              _showInternWatchTelemetryModal(
                                                                  v),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),

                                                        // Delete Video
                                                        IconButton(
                                                          icon: const Icon(
                                                              Icons
                                                                  .delete_outline_rounded,
                                                              color: AppTheme
                                                                  .danger,
                                                              size: 18),
                                                          tooltip:
                                                              'Delete Video',
                                                          onPressed: () =>
                                                              _deleteVideo(
                                                                  vidId),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),

                                  // Fixed Checkpoint Quiz Test (Between this module & next module)
                                  Container(
                                    margin: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: test != null
                                          ? const Color(0xFFF0FDF4)
                                          : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: test != null
                                            ? const Color(0xFF86EFAC)
                                            : const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: test != null
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFF6366F1),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            test != null
                                                ? Icons.verified_outlined
                                                : Icons.quiz_outlined,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    test != null
                                                        ? 'Module Checkpoint Quiz: ${safeString(test['title'], 'Module Test')}'
                                                        : 'Module Checkpoint Quiz (Gates Next Module)',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12.5,
                                                      color: test != null
                                                          ? const Color(0xFF166534)
                                                          : const Color(0xFF1E293B),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: test != null
                                                          ? const Color(0xFF16A34A).withOpacity(0.15)
                                                          : const Color(0xFF6366F1).withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      test != null
                                                          ? 'GATE ACTIVE (≥${safeInt(test["passing_score"], 60)}%)'
                                                          : 'NO TEST CONFIGURED',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: test != null
                                                            ? const Color(0xFF15803D)
                                                            : const Color(0xFF4F46E5),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                test != null
                                                    ? 'Interns must score ≥${safeInt(test['passing_score'], 60)}% on this quiz to unlock ${i + 1 < _modules.length ? 'Module 0${i + 2}' : 'completion'}. (${safeInt(test['question_count'])} questions configured).'
                                                    : 'Create a customizable quiz test here. Interns will take this test after videos 1-${videos.length} before advancing.',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                           icon: Icon(
                                             test != null
                                                 ? Icons.edit_outlined
                                                : Icons.add,
                                            size: 13,
                                          ),
                                          label: Text(
                                            test != null
                                                ? 'Edit Quiz Test'
                                                : 'Create Quiz Test',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: test != null
                                                ? const Color(0xFF15803D)
                                                : const Color(0xFF6366F1),
                                            side: BorderSide(
                                              color: test != null
                                                  ? const Color(0xFF86EFAC)
                                                  : const Color(0xFFCBD5E1),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                          ),
                                          onPressed: moduleId <= 0
                                              ? null
                                              : () => showDialog<void>(
                                                    context: context,
                                                    builder: (_) =>
                                                        CourseModuleTestEditorDialog(
                                                      moduleId: moduleId,
                                                      moduleTitle: modTitle,
                                                      onSaved:
                                                          _loadCourseDetails,
                                                    ),
                                                  ),
                                        ),
                                      ],
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
    );
  }

  Widget _headerStatBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing Rocket & Video Icon
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: const Icon(Icons.rocket_launch_rounded,
                    color: Colors.white, size: 38),
              ),
              const SizedBox(height: 20),
              const Text(
                'No Video Lessons Dropped Yet 🚀',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add your first video lesson from your device to start building this course.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                label: const Text('Add Video Lesson'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onPressed: () => _showAddVideoDialog(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
