import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_format.dart';
import '../../widgets/kgpl_brand_badge.dart';

class AuditLogsView extends StatefulWidget {
  const AuditLogsView({super.key});

  @override
  State<AuditLogsView> createState() => _AuditLogsViewState();
}

class _AuditLogsViewState extends State<AuditLogsView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get(ApiConfig.hrAuditLogs);
      setState(() {
        _logs = res['audit_logs'] ?? [];
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
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
            title: 'Security Audit Trail & Governance Log',
            subtitle: 'Monitor all system actions, logins, and data changes',
            icon: Icons.security_outlined,
            actions: [
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                tooltip: 'Refresh Logs',
                onPressed: _fetchLogs,
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
                  : _logs.isEmpty
                      ? const Center(child: Text('No audit logs recorded'))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                                    columns: const [
                                      DataColumn(label: Text('Timestamp', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('Actor', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold))),
                                    ],
                                    rows: _logs.map((l) {
                                      final action = l['action'] ?? 'ACTION';
                                      return DataRow(cells: [
                                        DataCell(Text(formatTimestamp(l['created_at']))),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEFF6FF),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              action,
                                              style: const TextStyle(
                                                color: AppTheme.primaryBlue,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(Text(l['user_name'] ?? 'System', style: const TextStyle(fontWeight: FontWeight.w600))),
                                        DataCell(Text(l['user_role'] ?? 'system')),
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
