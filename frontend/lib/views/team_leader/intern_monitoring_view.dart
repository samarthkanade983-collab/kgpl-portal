import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/safe_convert.dart';
import '../../widgets/kgpl_brand_badge.dart';

class InternMonitoringView extends StatefulWidget {
  const InternMonitoringView({super.key});

  @override
  State<InternMonitoringView> createState() => _InternMonitoringViewState();
}

class _InternMonitoringViewState extends State<InternMonitoringView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _interns = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchInterns();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchInterns([String? search]) async {
    setState(() => _isLoading = true);
    try {
      String url = ApiConfig.tlInterns;
      if (search != null && search.isNotEmpty) {
        url += '?search=${Uri.encodeComponent(search)}';
      }
      final res = await _api.get(url);
      setState(() {
        _interns = res['interns'] ?? [];
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _showInternDossier(int internId) async {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder(
        future: _api.get('${ApiConfig.tlInterns}/$internId'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const AlertDialog(
                content: SizedBox(
                    height: 150,
                    child: Center(child: CircularProgressIndicator())));
          }
          final intern = snapshot.data['intern'];
          final videoLogs = (snapshot.data['video_logs'] as List?) ?? [];
          final quizAttempts = (snapshot.data['quiz_attempts'] as List?) ?? [];

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.person_pin, color: AppTheme.primaryBlue),
                const SizedBox(width: 10),
                Text('Intern Progress Dossier: ${intern['name']}'),
              ],
            ),
            content: SizedBox(
              width: 650,
              height: 480,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile details header
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.scaffoldBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Code: ${intern['intern_code']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                              'Department: ${intern['department_name'] ?? 'Not set'}'),
                          Text(
                              'College: ${intern['college_name'] ?? 'KGPL Academy'}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Video Lessons Progress
                    const Text('Video Lessons & Watch Verification',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    if (videoLogs.isEmpty)
                      const Text('No video watch logs recorded',
                          style: TextStyle(color: AppTheme.textMuted))
                    else
                      ...videoLogs.map((vl) {
                        final pct = safeDouble(vl['completion_percentage']);
                        final isComp = vl['is_completed'] == 1 ||
                            vl['is_completed'] == true;
                        final watched = safeInt(vl['total_watched_seconds']);
                        final duration = safeInt(vl['duration_seconds']);
                        return ListTile(
                          dense: true,
                          leading: Icon(
                              isComp ? Icons.check_circle : Icons.play_circle,
                              color: isComp
                                  ? AppTheme.success
                                  : AppTheme.primaryBlue),
                          title: Text(vl['video_title'] ?? ''),
                          subtitle: Text('${watched}s watched of ${duration}s'),
                          trailing: Text('${pct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isComp
                                      ? AppTheme.success
                                      : AppTheme.textSecondary)),
                        );
                      }),

                    const SizedBox(height: 16),

                    // Quiz assessments
                    const Text('Online Quiz & Test Attempts',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    if (quizAttempts.isEmpty)
                      const Text('No test attempts recorded',
                          style: TextStyle(color: AppTheme.textMuted))
                    else
                      ...quizAttempts.map((qa) {
                        final isPassed =
                            qa['is_passed'] == 1 || qa['is_passed'] == true;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                              isPassed ? Icons.verified : Icons.cancel,
                              color: isPassed
                                  ? AppTheme.success
                                  : AppTheme.danger),
                          title: Text(qa['quiz_title'] ?? 'Assessment'),
                          subtitle: Text('Status: ${qa['status']}'),
                          trailing: Text(
                              '${qa['total_score']} / ${qa['total_marks']}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isPassed
                                      ? AppTheme.success
                                      : AppTheme.danger)),
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  void _showGiveFeedbackDialog(int internId, String name) {
    final commentController = TextEditingController();
    int rating = 5;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('Provide Feedback: $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      color: const Color(0xFFFBBF24),
                      size: 32,
                    ),
                    onPressed: () => setDialogState(() => rating = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: commentController,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Feedback Comments & Guidance *'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                if (commentController.text.trim().isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(
                        content: Text('Please enter your feedback comments.'),
                        backgroundColor: AppTheme.danger),
                  );
                  return;
                }
                final comments = commentController.text.trim();
                Navigator.pop(ctx);
                try {
                  await _api.post(ApiConfig.tlFeedback, {
                    'to_user_id': internId,
                    'rating': rating,
                    'comments': comments,
                  });
                  messenger.showSnackBar(
                    const SnackBar(
                        content: Text('Feedback submitted successfully'),
                        backgroundColor: AppTheme.success),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                        content: Text('Could not submit feedback: $e'),
                        backgroundColor: AppTheme.danger),
                  );
                }
              },
              child: const Text('Submit Feedback'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool searching = _searchController.text.trim().isNotEmpty;
    return Center(
      child: SingleChildScrollView(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.scale(scale: 0.96 + 0.04 * value, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primaryBlue.withOpacity(0.16),
                      AppTheme.accentIndigo.withOpacity(0.10),
                    ],
                  ),
                  border:
                      Border.all(color: AppTheme.primaryBlue.withOpacity(0.25)),
                ),
                child: Icon(
                  searching ? Icons.search_off : Icons.people_outline,
                  size: 42,
                  color: AppTheme.primaryBlue,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                searching ? 'No matching interns' : 'No interns assigned yet',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 430,
                child: Text(
                  searching
                      ? 'No assigned interns match "${_searchController.text.trim()}". Try a different name or code.'
                      : 'Interns are assigned to your team by HR. Ask your HR admin to assign interns to you — they will appear here automatically.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
                ),
              ),
              const SizedBox(height: 22),
              if (searching)
                OutlinedButton.icon(
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear Search'),
                  onPressed: () {
                    _searchController.clear();
                    _fetchInterns();
                  },
                )
              else
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                  onPressed: () => _fetchInterns(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KgplPageHeader(
            title: 'Assigned Interns Monitoring',
            subtitle: 'Track progress and performance of your assigned interns',
            icon: Icons.people_outlined,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Refresh assigned interns',
                onPressed: _isLoading
                    ? null
                    : () => _fetchInterns(_searchController.text.trim()),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Search bar
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Search assigned interns by name or code...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onSubmitted: (val) => _fetchInterns(val.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              ElevatedButton.icon(
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Search'),
                onPressed: () => _fetchInterns(_searchController.text.trim()),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _interns.isEmpty
                      ? _buildEmptyState()
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    minWidth: constraints.maxWidth),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(
                                        const Color(0xFFF8FAFC)),
                                    columns: const [
                                      DataColumn(
                                          label: Text('Intern Name',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      DataColumn(
                                          label: Text('Code',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      DataColumn(
                                          label: Text('Department',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      DataColumn(
                                          label: Text('Watch Time',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      DataColumn(
                                          label: Text('Tests (Passed / Taken)',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      DataColumn(
                                          label: Text('Actions',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                    ],
                                    rows: _interns.map((i) {
                                      final int id = safeInt(i['id']);
                                      final String name = i['name'] ?? '';
                                      final String code =
                                          i['intern_code'] ?? '';
                                      final String dept =
                                          i['department_name'] ?? 'Not set';
                                      final int watchSec =
                                          safeInt(i['total_watch_seconds']);
                                      final int mins = watchSec ~/ 60;
                                      final int testsPassed =
                                          safeInt(i['tests_passed']);
                                      final int testsCompleted =
                                          safeInt(i['tests_completed']);

                                      return DataRow(cells: [
                                        DataCell(Text(name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600))),
                                        DataCell(Text(code)),
                                        DataCell(Text(dept)),
                                        DataCell(
                                            Text('${mins}m ${watchSec % 60}s')),
                                        DataCell(Text(
                                            '$testsPassed / $testsCompleted')),
                                        DataCell(
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.analytics_outlined,
                                                    color: AppTheme.primaryNavy,
                                                    size: 20),
                                                tooltip:
                                                    'View Progress Dossier',
                                                onPressed: () =>
                                                    _showInternDossier(id),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.rate_review_outlined,
                                                    color: AppTheme.primaryBlue,
                                                    size: 20),
                                                tooltip: 'Give Feedback',
                                                onPressed: () =>
                                                    _showGiveFeedbackDialog(
                                                        id, name),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ]);
                                    }).toList(),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
