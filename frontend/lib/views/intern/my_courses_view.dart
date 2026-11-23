import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/kgpl_brand_badge.dart';

class MyCoursesView extends StatefulWidget {
  const MyCoursesView({super.key});

  @override
  State<MyCoursesView> createState() => _MyCoursesViewState();
}

class _MyCoursesViewState extends State<MyCoursesView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _courses = [];
  bool _certificateReady = false;

  @override
  void initState() {
    super.initState();
    _fetchCourses();
  }

  Future<void> _fetchCourses() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get(ApiConfig.internCourses);
      bool ready = false;
      try {
        final cert = await _api.get(ApiConfig.internCertificate);
        ready = cert['eligible'] == true;
      } catch (_) {}
      setState(() {
        _courses = res['courses'] ?? [];
        _certificateReady = ready;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KgplPageHeader(
            title: 'My Assigned Learning Courses',
            subtitle: 'Complete all required video lessons and SOP study materials to qualify for completion certificate.',
            icon: Icons.school_outlined,
          ),
          const SizedBox(height: 20),

          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            child: _certificateReady
                ? Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFCCB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA3E635)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_rounded, color: Color(0xFF4D7C0F), size: 22),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'All courses completed — your certificate is unlocked.',
                            style: TextStyle(color: Color(0xFF3F6212), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () => auth.setActiveView('certificate'),
                          child: const Text('View Certificate'),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _courses.isEmpty
                    ? const Center(child: Text('No courses currently assigned'))
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.18,
                        ),
                        itemCount: _courses.length,
                        itemBuilder: (ctx, i) {
                          final c = _courses[i];
                          final int id = c['id'];
                          final String title = c['title'] ?? 'Course';
                          final String desc = c['description'] ?? '';
                          final int videos = c['video_count'] ?? 0;
                          final int sops = c['material_count'] ?? 0;
                          final int doneVideos = c['completed_videos'] ?? 0;
                          final int doneSops = c['completed_materials'] ?? 0;
                          final int percent = (c['progress_percent'] ?? 0).toDouble().round();
                          final bool isDone = c['is_completed'] == true;

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppTheme.cardBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDone ? const Color(0xFFD4AF37) : AppTheme.borderColor, width: isDone ? 1.6 : 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isDone ? const Color(0xFFFEF3C7) : AppTheme.primaryNavy.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        isDone ? Icons.workspace_premium_rounded : Icons.school,
                                        color: isDone ? const Color(0xFFB45309) : AppTheme.primaryNavy,
                                        size: 22,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDone ? const Color(0xFFFEF3C7) : AppTheme.infoLight,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isDone ? 'COMPLETED' : 'ENROLLED',
                                        style: TextStyle(
                                          color: isDone ? const Color(0xFF92400E) : AppTheme.info,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  desc,
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 10),
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: (percent / 100).clamp(0.0, 1.0)),
                                  duration: const Duration(milliseconds: 700),
                                  curve: Curves.easeOutCubic,
                                  builder: (ctx, animValue, _) => ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: animValue,
                                      minHeight: 6,
                                      backgroundColor: AppTheme.borderColor,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isDone ? const Color(0xFFD4AF37) : AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isDone
                                      ? 'All lessons & SOPs finished'
                                      : '$doneVideos/$videos videos • $doneSops/$sops SOPs • $percent%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                                    color: isDone ? const Color(0xFF92400E) : AppTheme.textMuted,
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '$videos Videos • $sops SOPs',
                                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => auth.openCoursePlayer(id),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isDone ? const Color(0xFFB45309) : null,
                                      ),
                                      child: Text(isDone ? 'Review Course' : 'Play Course', style: const TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
