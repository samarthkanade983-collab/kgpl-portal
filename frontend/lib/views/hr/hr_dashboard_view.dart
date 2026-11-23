import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/device_file_downloader.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/ui_effects.dart';

class HrDashboardView extends StatefulWidget {
  const HrDashboardView({super.key});

  @override
  State<HrDashboardView> createState() => _HrDashboardViewState();
}

class _HrDashboardViewState extends State<HrDashboardView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  bool _isExporting = false;
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
      final res = await _api.get(ApiConfig.hrDashboard);
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

  Future<void> _exportReports() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final bytes = await _api.getBytes(ApiConfig.hrReportsExport);
      await downloadBytes('KGPL_Performance_Report.csv', bytes,
          mime: 'text/csv');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Performance report saved as KGPL_Performance_Report.csv'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to export report: $e'),
            backgroundColor: AppTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
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
    final departments = (_data?['charts']?['departments'] as List?) ?? [];

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
              // Executive Welcome Banner with Official Logo
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
                                  'KuhuGrantha HR Administration',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  '• EXECUTIVE PORTAL',
                                  style: TextStyle(
                                    color: Color(0xFFD4AF37),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Welcome back, ${auth.currentUser?.name}! Real-time monitoring across ${metrics['total_interns'] ?? 0} active ${(metrics['total_interns'] ?? 0) == 1 ? 'intern' : 'interns'} & ${metrics['total_team_leaders'] ?? 0} ${(metrics['total_team_leaders'] ?? 0) == 1 ? 'team leader' : 'team leaders'}.',
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: _isExporting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.file_download_outlined,
                                    size: 16, color: Colors.white),
                            label: Text(
                                _isExporting ? 'Exporting…' : 'Export Reports',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF475569)),
                              backgroundColor: Colors.white.withOpacity(0.06),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                            onPressed: _isExporting ? null : _exportReports,
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            icon:
                                const Icon(Icons.person_add_rounded, size: 16),
                            label: const Text('Manage Users',
                                style: TextStyle(fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
                            ),
                            onPressed: () => auth.setActiveView('users'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: sectionGap),

              // 6 KPI Metric Cards
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
                        title: 'Total Interns',
                        index: 0,
                        value: '${metrics['total_interns'] ?? 0}',
                        icon: Icons.people_outline,
                        iconColor: AppTheme.primaryBlue,
                        trendBadge: 'Live',
                      ),
                      MetricCard(
                        title: 'Active Interns',
                        index: 1,
                        value: '${metrics['active_interns'] ?? 0}',
                        icon: Icons.person_outline,
                        iconColor: AppTheme.success,
                        trendBadge: 'Active',
                      ),
                      MetricCard(
                        title: 'Team Leaders',
                        index: 2,
                        value: '${metrics['total_team_leaders'] ?? 0}',
                        icon: Icons.supervisor_account_outlined,
                        iconColor: const Color(0xFFD97706),
                      ),
                      MetricCard(
                        title: 'Training Courses',
                        index: 3,
                        value: '${metrics['total_courses'] ?? 0}',
                        icon: Icons.menu_book_outlined,
                        iconColor: const Color(0xFF7C3AED),
                      ),
                      MetricCard(
                        title: 'Training Completed',
                        index: 4,
                        value: '${metrics['completed_internships'] ?? 0}',
                        icon: Icons.verified_outlined,
                        iconColor: AppTheme.success,
                      ),
                      MetricCard(
                        title: 'Training Pending',
                        index: 5,
                        value: '${metrics['pending_training'] ?? 0}',
                        icon: Icons.hourglass_top_outlined,
                        iconColor: AppTheme.danger,
                      ),
                    ],
                  );
                },
              ),

              SizedBox(height: sectionGap),

              // Department distribution
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Department distribution
                  Expanded(
                    flex: 2,
                    child: Container(
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
                                'Interns by Department',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 10 : 18),
                          if (departments.isEmpty)
                            const Text('No department data available')
                          else
                            ...departments.map((dept) {
                              final name = dept['name'] ?? 'Not set';
                              final count = dept['intern_count'] ?? 0;
                              final total = metrics['total_interns'] ?? 1;
                              final double pct =
                                  (count / (total == 0 ? 1 : total))
                                      .clamp(0.0, 1.0);

                              return Padding(
                                padding: EdgeInsets.symmetric(
                                    vertical: compact ? 5 : 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13)),
                                        Text(
                                            '$count ${count == 1 ? 'intern' : 'interns'} (${(pct * 100).toStringAsFixed(0)}%)',
                                            style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 12)),
                                      ],
                                    ),
                                    SizedBox(height: compact ? 5 : 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: pct,
                                        minHeight: 7,
                                        backgroundColor:
                                            const Color(0xFFF1F5F9),
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                                AppTheme.primaryBlue),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}
