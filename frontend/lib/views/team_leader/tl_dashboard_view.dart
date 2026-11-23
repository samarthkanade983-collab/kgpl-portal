import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/safe_convert.dart';
import '../../core/utils/date_time_format.dart';
import '../../core/utils/large_video_uploader.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/ui_effects.dart';

class TlDashboardView extends StatefulWidget {
  const TlDashboardView({super.key});

  @override
  State<TlDashboardView> createState() => _TlDashboardViewState();
}

class _TlDashboardViewState extends State<TlDashboardView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchDashboard();
  }

  Future<void> _fetchDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _api.get(ApiConfig.tlDashboard);
      setState(() {
        _data = res;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _fetchDashboard, child: const Text('Retry')),
          ],
        ),
      );
    }

    final metrics = _data?['metrics'] ?? {};
    final recentActivities = (_data?['recent_activities'] as List?) ?? [];

    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 1300;
      final pagePad = compact ? 18.0 : 28.0;
      final sectionGap = compact ? 16.0 : 24.0;
      return RefreshIndicator(
        onRefresh: _fetchDashboard,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(pagePad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leadership Welcome Banner with Logo
              FadeSlideIn(
                offsetY: 16,
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: compact ? 20 : 28,
                      vertical: compact ? 16 : 24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF090D16), Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Logo container
                      Container(
                        width: 58,
                        height: 58,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFFD4AF37), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD4AF37).withOpacity(0.35),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.school,
                                size: 30,
                                color: Color(0xFF0F172A)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text(
                                  'KuhuGrantha Leadership Workspace',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  '• TEAM LEADER',
                                  style: TextStyle(
                                    color: Color(0xFFFBBF24),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Welcome back, ${auth.currentUser?.name}! Supervising ${metrics['assigned_interns'] ?? 0} assigned ${(metrics['assigned_interns'] ?? 0) == 1 ? 'intern' : 'interns'} across learning & assessments.',
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            icon:
                                const Icon(Icons.video_call_rounded, size: 16),
                            label: const Text('+ Post Video to Interns',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _showPostVideoModal,
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.auto_stories_rounded,
                                size: 16, color: Colors.white),
                            label: const Text('SOP & Runbooks',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12.5)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF475569)),
                              backgroundColor: Colors.white.withOpacity(0.06),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => auth.setActiveView('sop_reader'),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.video_library_rounded,
                                size: 16, color: Colors.white),
                            label: const Text('Curriculum Studio',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12.5)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF475569)),
                              backgroundColor: Colors.white.withOpacity(0.06),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () =>
                                auth.setActiveView('curriculum_studio'),
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.quiz_rounded, size: 16),
                            label: const Text('Question Bank & Tests',
                                style: TextStyle(fontSize: 12.5)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryNavy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => auth.setActiveView('quizzes'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: sectionGap),

              // 6 KPIs for Team Leader
              LayoutBuilder(
                builder: (context, constraints) {
                  // Keep all six KPIs on one row from laptop widths upward so the
                  // whole dashboard stays visible on 1366x768 screens.
                  final sixAcross = constraints.maxWidth >= 1040;
                  final crossAxisCount =
                      sixAcross ? 6 : (constraints.maxWidth > 650 ? 3 : 2);
                  final aspectRatio = sixAcross
                      ? (constraints.maxWidth < 1300 ? 1.22 : 1.35)
                      : (constraints.maxWidth > 650 ? 1.6 : 1.3);
                  final gridGap = compact ? 12.0 : 16.0;
                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: gridGap,
                    mainAxisSpacing: gridGap,
                    childAspectRatio: aspectRatio,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      MetricCard(
                        title: 'Assigned Interns',
                        value: '${metrics['assigned_interns'] ?? 0}',
                        icon: Icons.people_outline,
                        iconColor: AppTheme.primaryBlue,
                        trendBadge: 'Active',
                      ),
                      MetricCard(
                        title: 'Avg Course Completion',
                        value:
                            '${metrics['average_completion_percentage'] ?? 0}%',
                        icon: Icons.pie_chart_outline,
                        iconColor: AppTheme.success,
                      ),
                      MetricCard(
                        title: 'Total Watch Time',
                        value: '${metrics['total_watch_minutes'] ?? 0}m',
                        icon: Icons.timer_outlined,
                        iconColor: const Color(0xFFD97706),
                      ),
                      MetricCard(
                        title: 'Upcoming Tests',
                        value: '${metrics['upcoming_tests'] ?? 0}',
                        icon: Icons.assignment_outlined,
                        iconColor: const Color(0xFF7C3AED),
                      ),
                      MetricCard(
                        title: 'Pending Assignments',
                        value: '${metrics['pending_assignments'] ?? 0}',
                        icon: Icons.pending_actions_outlined,
                        iconColor: AppTheme.danger,
                      ),
                      MetricCard(
                        title: 'Average Quiz Score',
                        value: '${metrics['average_quiz_score'] ?? 0}%',
                        icon: Icons.grade_outlined,
                        iconColor: AppTheme.info,
                      ),
                    ],
                  );
                },
              ),

              SizedBox(height: sectionGap),

              // Recent Intern Video Progress Activity Stream
              Container(
                padding: EdgeInsets.all(compact ? 16 : 22),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 3.5,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Assigned Interns Real-Time Watch Activity',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Recent video activity from your assigned interns',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 18),
                    if (recentActivities.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: Text(
                                'No intern playback activities recorded yet')),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: recentActivities.length,
                        separatorBuilder: (_, __) => const Divider(height: 16),
                        itemBuilder: (ctx, i) {
                          final act = recentActivities[i];
                          final intern = act['intern_name'] ?? 'Intern';
                          final video = act['video_title'] ?? 'Training Lesson';
                          final pct = safeDouble(act['completion_percentage']);
                          final String time =
                              formatTimestamp(act['updated_at']);

                          return Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: pct >= 90
                                      ? AppTheme.successLight
                                      : AppTheme.infoLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  pct >= 90
                                      ? Icons.check_circle_outline
                                      : Icons.play_arrow_outlined,
                                  color: pct >= 90
                                      ? AppTheme.success
                                      : AppTheme.info,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$intern watched $video',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                    ),
                                    Text(
                                      'Logged at $time',
                                      style: const TextStyle(
                                          color: AppTheme.textMuted,
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: pct >= 90
                                      ? AppTheme.successLight
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${pct.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: pct >= 90
                                        ? AppTheme.success
                                        : AppTheme.textSecondary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showPostVideoModal() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '8');
    int selectedCourseId = 2; // IT Infra
    String selectedPreset = 'device';
    final urlCtrl = TextEditingController();
    SelectedLargeVideo? pickedVideo;
    LargeVideoUploader? uploader;
    bool isPosting = false;
    bool uploadCancelRequested = false;
    double uploadProgress = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> pickVideo() async {
            try {
              final file = await pickLargeVideo(
                allowedExtensions: ['mp4', 'webm', 'mov', 'mkv', 'avi', 'm4v'],
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Could not read the video: $e'),
                      backgroundColor: AppTheme.danger),
                );
              }
            }
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.video_library_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Post Video to Intern Curriculum',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                        'Publishes directly to intern learning tracks & video player',
                        style:
                            TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedCourseId,
                      decoration: InputDecoration(
                        labelText: 'Target Intern Course Track *',
                        prefixIcon: const Icon(Icons.school_rounded, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 2,
                            child: Text(
                                'Track 2: IT Infrastructure & Cloud DevOps')),
                        DropdownMenuItem(
                            value: 1,
                            child: Text(
                                'Track 1: Full Stack Web Engineering & Architecture')),
                      ],
                      onChanged: (val) =>
                          setModalState(() => selectedCourseId = val ?? 2),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Video Lesson Title *',
                        hintText: 'e.g. Zabbix 7.0 Deployment Walkthrough',
                        prefixIcon:
                            const Icon(Icons.subtitles_rounded, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedPreset,
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
                          value: '/uploads/videos/zabbix_deployment_guide.mp4',
                          child: Text(
                              'Library Video 1: Zabbix Deployment Guide (MP4)'),
                        ),
                        DropdownMenuItem(
                          value:
                              '/uploads/videos/commvault_metallic_overview.mp4',
                          child: Text(
                              'Library Video 2: Commvault Metallic Overview (MP4)'),
                        ),
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text('Custom Video Stream URL (CDN / MP4)'),
                        ),
                      ],
                      onChanged: (val) {
                        setModalState(() {
                          selectedPreset = val ?? 'device';
                          if (selectedPreset == 'device') {
                            urlCtrl.clear();
                          } else if (selectedPreset == 'custom') {
                            urlCtrl.text =
                                'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
                          } else {
                            urlCtrl.text = selectedPreset;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    if (selectedPreset == 'device')
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
                                    size: 18, color: Color(0xFF6366F1)),
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
                              'Supports .mp4, .webm, .mov, .mkv, .avi, .m4v up to 50 GB — resumable chunked upload.',
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
                                      color: const Color(0xFF6366F1)
                                          .withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.videocam_rounded,
                                        color: Color(0xFF6366F1), size: 22),
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
                                          size: 18, color: AppTheme.danger),
                                      onPressed: () {
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
                                    foregroundColor: const Color(0xFF4F46E5),
                                    side: const BorderSide(
                                        color: Color(0xFF6366F1)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 12),
                                  ),
                                  onPressed: pickVideo,
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      TextField(
                        controller: urlCtrl,
                        decoration: InputDecoration(
                          labelText: 'Video Stream URL / File Path *',
                          prefixIcon: const Icon(Icons.link_rounded, size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    if (isPosting) ...[
                      const SizedBox(height: 12),
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
                        const Expanded(
                          child: Text(
                            'Required Completion: 80%\nAnti-cheat tracking active',
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Lesson Description & Objectives',
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
                onPressed: isPosting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.publish_rounded, size: 16),
                label: isPosting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Publish Video to Interns',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isPosting
                    ? null
                    : () async {
                        if (titleCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Please enter a video title'),
                                backgroundColor: AppTheme.danger),
                          );
                          return;
                        }
                        if (selectedPreset == 'device') {
                          if (pickedVideo == null || uploader == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Please choose a video file from your device first'),
                                  backgroundColor: AppTheme.danger),
                            );
                            return;
                          }
                        } else if (urlCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Please enter a video URL'),
                                backgroundColor: AppTheme.danger),
                          );
                          return;
                        }

                        setModalState(() {
                          isPosting = true;
                          uploadCancelRequested = false;
                          uploadProgress = 0;
                        });
                        try {
                          final body = <String, dynamic>{
                            'course_id': selectedCourseId,
                            'title': titleCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                            'duration_minutes':
                                int.tryParse(durationCtrl.text) ?? 10,
                          };
                          if (selectedPreset == 'device') {
                            body['video_url'] = await uploader!.upload(
                              onProgress: (sent, total) {
                                setModalState(() {
                                  uploadProgress = total > 0 ? sent / total : 0;
                                });
                              },
                              isCancelled: () => uploadCancelRequested,
                            );
                          } else {
                            body['video_url'] = urlCtrl.text.trim();
                          }
                          await _api.post(ApiConfig.tlPostVideo, body);

                          if (context.mounted) {
                            Navigator.pop(ctx);
                            _fetchDashboard();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Video lesson successfully published to intern curriculum!'),
                                backgroundColor: AppTheme.success,
                              ),
                            );
                          }
                        } catch (e) {
                          setModalState(() {
                            isPosting = false;
                            uploadProgress = 0;
                          });
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(e is LargeUploadException ||
                                          e is LargeUploadCancelled
                                      ? '$e'
                                      : 'Failed to publish video: $e'),
                                  backgroundColor: AppTheme.danger),
                            );
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
}
