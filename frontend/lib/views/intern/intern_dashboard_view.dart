import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/ui_effects.dart';

class InternDashboardView extends StatefulWidget {
  const InternDashboardView({super.key});

  @override
  State<InternDashboardView> createState() => _InternDashboardViewState();
}

class _InternDashboardViewState extends State<InternDashboardView> {
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
      final res = await _api.get(ApiConfig.internDashboard);
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
    final courses = (_data?['assigned_courses'] as List?) ?? [];
    final announcements = (_data?['announcements'] as List?) ?? [];
    final profile = _data?['profile'] ?? {};

    return RefreshIndicator(
      onRefresh: _fetchDashboard,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header Card with Official Logo
            FadeSlideIn(
              offsetY: 16,
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
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
                      // KuhuGrantha Logo Emblem
                      Container(
                        width: 58,
                        height: 58,
                        margin: const EdgeInsets.only(right: 20),
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Welcome back, ${auth.currentUser?.name}!',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  '• KUHUGRANTHA INTERN',
                                  style: TextStyle(
                                    color: Color(0xFF34D399),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Intern Code: ${profile['intern_code'] ?? '-'} • Department: ${profile['department_name'] ?? 'Not set'} • Assigned TL: ${profile['team_leader_name'] ?? 'Unassigned'}',
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.auto_stories_rounded,
                                size: 16, color: Colors.white),
                            label: const Text('Read SOPs',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF475569)),
                              backgroundColor: Colors.white.withOpacity(0.06),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                            onPressed: () => auth.setActiveView('sop_reader'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.play_circle_fill_rounded,
                                size: 16),
                            label: const Text('Resume Learning',
                                style: TextStyle(fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
                            ),
                            onPressed: () {
                              if (courses.isNotEmpty) {
                                auth.openCoursePlayer(courses[0]['id']);
                              } else {
                                auth.setActiveView('my_courses');
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ),

            const SizedBox(height: 24),

            // 4 KPI Metric Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth > 900 ? 4 : 2;
                final aspectRatio = constraints.maxWidth > 900
                    ? 1.35
                    : (constraints.maxWidth > 600 ? 1.5 : 1.3);
                return GridView.count(
                  crossAxisCount: count,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: aspectRatio,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    MetricCard(
                      title: 'Available Courses',
                      value: '${metrics['assigned_courses_count'] ?? 0}',
                      icon: Icons.menu_book,
                      iconColor: AppTheme.primaryBlue,
                    ),
                    MetricCard(
                      title: 'Watch Time',
                      value: '${metrics['total_watch_minutes'] ?? 0}m',
                      icon: Icons.timer,
                      iconColor: const Color(0xFFD97706),
                    ),
                    MetricCard(
                      title: 'Upcoming Tests',
                      value: '${metrics['upcoming_tests_count'] ?? 0}',
                      icon: Icons.assignment_turned_in,
                      iconColor: const Color(0xFF7C3AED),
                    ),
                    MetricCard(
                      title: 'Pending Tasks',
                      value: '${metrics['pending_tasks_count'] ?? 0}',
                      icon: Icons.task,
                      iconColor: AppTheme.danger,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 28),

            // Assigned Courses Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'My Active Courses',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary),
                ),
                TextButton(
                  onPressed: () => auth.setActiveView('my_courses'),
                  child: const Text('View All Courses'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (courses.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child:
                    const Center(child: Text('No courses currently assigned')),
              )
            else
              ...courses.map((c) {
                final int totalVideos = c['total_videos'] ?? 0;
                final int completedVideos = c['completed_videos'] ?? 0;
                final int totalMaterials = c['total_materials'] ?? 0;
                final int completedMaterials = c['completed_materials'] ?? 0;
                final int totalItems = totalVideos + totalMaterials;
                final double progress = totalItems == 0
                    ? 0.0
                    : ((completedVideos + completedMaterials) / totalItems)
                        .clamp(0.0, 1.0);
                final bool isDone = progress >= 1.0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNavy.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.school,
                            color: AppTheme.primaryNavy, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c['title'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              c['description'] ?? '',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 6,
                                      backgroundColor: AppTheme.borderColor,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isDone
                                            ? const Color(0xFFD4AF37)
                                            : AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  isDone
                                      ? 'Completed'
                                      : '${(progress * 100).toInt()}% completed',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDone
                                        ? const Color(0xFF92400E)
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () => auth.openCoursePlayer(c['id']),
                        child: const Text('Continue'),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 28),

            // Announcements
            const Text(
              'Company Bulletins & Announcements',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            if (announcements.isEmpty)
              const Text('No recent announcements')
            else
              ...announcements.map((a) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign,
                          color: AppTheme.primaryBlue, size: 24),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a['title'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(a['content'] ?? '',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
