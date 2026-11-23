import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/safe_convert.dart';
import '../../core/utils/date_time_format.dart';
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

}
