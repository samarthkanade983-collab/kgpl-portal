import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/safe_convert.dart';
import '../../core/utils/device_file_downloader.dart';
import '../../core/utils/pdf_performance.dart';
import '../../widgets/kgpl_brand_badge.dart';

class ReportAnalyticsView extends StatefulWidget {
  const ReportAnalyticsView({super.key});

  @override
  State<ReportAnalyticsView> createState() => _ReportAnalyticsViewState();
}

class _ReportAnalyticsViewState extends State<ReportAnalyticsView>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late final TabController _tabController;
  bool _isLoading = true;
  bool _feedbackLoading = true;
  String? _feedbackError;
  List<dynamic> _reports = [];
  List<dynamic> _feedback = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    _fetchReports();
    _fetchFeedback();
  }

  int _lastTabIndex = 0;

  void _handleTabChange() {
    if (_tabController.index == _lastTabIndex) return;
    _lastTabIndex = _tabController.index;
    // Re-read feedback whenever HR opens the tab so newly submitted entries
    // appear without reloading the whole portal.
    if (_lastTabIndex == 1) _fetchFeedback();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchReports() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get(ApiConfig.hrReports);
      setState(() {
        _reports = res['reports'] ?? [];
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchFeedback() async {
    setState(() {
      _feedbackLoading = true;
      _feedbackError = null;
    });
    try {
      final res = await _api.get(ApiConfig.hrFeedback);
      if (!mounted) return;
      setState(() {
        _feedback = res['feedback'] ?? [];
        _feedbackLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _feedbackError = e.message;
        _feedbackLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _feedbackError = 'Could not load feedback. Please try again.';
        _feedbackLoading = false;
      });
    }
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '-';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    return DateFormat('dd MMM yyyy').format(parsed.toLocal());
  }

  void _downloadCsv() async {
    try {
      final bytes = await _api.getBytes(ApiConfig.hrReportsExport);
      await downloadBytes('KGPL_Performance_Report.csv', bytes,
          mime: 'text/csv');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Performance report saved as KGPL_Performance_Report.csv'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to export CSV: $e'),
            backgroundColor: AppTheme.danger),
      );
    }
  }

  void _downloadPdf() async {
    if (_reports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No performance data to export yet.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }
    try {
      final pdf = buildPerformancePdf(
        rows: _reports,
        generatedAt: DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now()),
      );
      await downloadBytes('KGPL_Performance_Report.pdf', pdf,
          mime: 'application/pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Performance report saved as KGPL_Performance_Report.pdf'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to export PDF: $e'),
            backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KgplPageHeader(
            title: 'Intern Batch Performance & Feedback',
            subtitle:
                'Track quiz scores, watch progress and team leader feedback',
            icon: Icons.analytics_outlined,
            actions: [
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Download PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primaryNavy,
                  side:
                      const BorderSide(color: AppTheme.accentGold, width: 1.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _downloadPdf,
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Export to CSV'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentGold,
                  foregroundColor: AppTheme.primaryNavy,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _downloadCsv,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 420,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Performance'),
                Tab(text: 'Team Leader Feedback'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _reports.isEmpty
                          ? const Center(
                              child: Text('No performance metrics available'))
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
                                        columnSpacing: 14,
                                        horizontalMargin: 16,
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                                const Color(0xFFF8FAFC)),
                                        columns: const [
                                          DataColumn(
                                              label: Text('Intern Name',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Intern Code',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Department',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Team Leader',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Videos Completed',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Watch Time',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text(
                                                  'Tests (Passed / Taken)',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Avg Quiz Score',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Tasks Submitted',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                        ],
                                        rows: _reports.map((r) {
                                          final int watchSec = safeInt(
                                              r['total_watched_seconds']);
                                          final double score =
                                              safeDouble(r['avg_test_score']);
                                          final int testsPassed =
                                              safeInt(r['tests_passed']);
                                          final int testsTaken =
                                              safeInt(r['tests_attempted']);
                                          final int videosCompleted =
                                              safeInt(r['videos_completed']);
                                          final int tasksSubmitted =
                                              safeInt(r['tasks_submitted']);

                                          return DataRow(cells: [
                                            DataCell(Text(r['name'] ?? '',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600))),
                                            DataCell(
                                                Text(r['intern_code'] ?? '')),
                                            DataCell(Text(
                                                r['department_name'] ??
                                                    'Not set')),
                                            DataCell(Text(
                                                r['team_leader_name'] ??
                                                    'Unassigned')),
                                            DataCell(Text('$videosCompleted')),
                                            DataCell(
                                                Text(watchTimeLabel(watchSec))),
                                            DataCell(Text(
                                                '$testsPassed / $testsTaken')),
                                            DataCell(
                                              testsTaken == 0
                                                  ? const Text('—',
                                                      style: TextStyle(
                                                          color: AppTheme
                                                              .textMuted,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 11))
                                                  : Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8,
                                                          vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: score >= 60
                                                            ? AppTheme
                                                                .successLight
                                                            : AppTheme
                                                                .dangerLight,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text(
                                                        '${score.toStringAsFixed(1)}%',
                                                        style: TextStyle(
                                                          color: score >= 60
                                                              ? AppTheme.success
                                                              : AppTheme.danger,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ),
                                            ),
                                            DataCell(Text('$tasksSubmitted')),
                                          ]);
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
                _buildFeedbackTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackTab() {
    Widget content;
    if (_feedbackLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_feedbackError != null) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_feedbackError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _fetchFeedback, child: const Text('Retry')),
          ],
        ),
      );
    } else if (_feedback.isEmpty) {
      content = const Center(child: Text('No team leader feedback yet.'));
    } else {
      content = LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  columnSpacing: 16,
                  horizontalMargin: 16,
                  dataRowMinHeight: 72,
                  dataRowMaxHeight: 96,
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                  columns: const [
                    DataColumn(
                        label: Text('Intern Name',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Department',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Team Leader',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Rating / Score',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: SizedBox(
                            width: 380,
                            child: Text('Feedback',
                                style:
                                    TextStyle(fontWeight: FontWeight.bold)))),
                    DataColumn(
                        label: Text('Date',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: _feedback.map((f) {
                    final rating = safeInt(f['rating']);
                    final isTaskReview = f['source'] == 'task_submission';
                    final comments = f['comments']?.toString().trim() ?? '';
                    final feedbackText = comments.isEmpty
                        ? 'No written feedback provided.'
                        : comments;
                    final taskTitle = f['task_title']?.toString() ?? '';
                    return DataRow(cells: [
                      DataCell(Text(f['intern_name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text(f['department_name'] ?? 'Not set')),
                      DataCell(Text(f['team_leader_name'] ?? 'Unassigned')),
                      DataCell(isTaskReview
                          ? Text(
                              f['score'] == null
                                  ? 'Not scored'
                                  : '${f['score']} / ${f['max_score']} pts',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(5, (index) {
                                return Icon(
                                  index < rating
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  size: 16,
                                  color: const Color(0xFFFBBF24),
                                );
                              }),
                            )),
                      DataCell(SizedBox(
                        width: 380,
                        child: Tooltip(
                          message: isTaskReview
                              ? '$taskTitle\n$feedbackText'
                              : feedbackText,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isTaskReview) ...[
                                Text('Task: $taskTitle',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                if (f['submission_status'] ==
                                    'resubmission_required')
                                  const Text('Resubmission required',
                                      style: TextStyle(
                                          color: AppTheme.warning,
                                          fontSize: 11)),
                                const SizedBox(height: 4),
                              ],
                              Text(feedbackText,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      )),
                      DataCell(Text(_formatDate(f['created_at']))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              _feedback.isEmpty
                  ? 'Team leader feedback'
                  : '${_feedback.length} feedback ${_feedback.length == 1 ? 'entry' : 'entries'}',
              style: const TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _feedbackLoading ? null : _fetchFeedback,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: content,
          ),
        ),
      ],
    );
  }
}
