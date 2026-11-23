import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/feedback.dart';
import '../../widgets/kgpl_brand_badge.dart';

class DepartmentManagementView extends StatefulWidget {
  const DepartmentManagementView({super.key});

  @override
  State<DepartmentManagementView> createState() =>
      _DepartmentManagementViewState();
}

class _DepartmentManagementViewState extends State<DepartmentManagementView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _departments = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get(ApiConfig.hrDepartments);
      if (!mounted) return;
      setState(() {
        _departments = res['departments'] ?? [];
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteDepartment(dynamic department) async {
    final id = department['id'];
    final label = [department['code'], department['name']]
        .where((v) => v != null && v.toString().isNotEmpty)
        .join(' - ');
    var isDeleting = false;
    String? error;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Delete Department'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('"$label" will be permanently removed.',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'A department can only be deleted when no interns, team leaders or courses are linked to it.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style: const TextStyle(
                          color: AppTheme.danger, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isDeleting
                  ? null
                  : () async {
                      setDialogState(() {
                        isDeleting = true;
                        error = null;
                      });
                      try {
                        await _api.delete('${ApiConfig.hrDepartments}/$id');
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on ApiException catch (e) {
                        setDialogState(() {
                          isDeleting = false;
                          error = e.message;
                        });
                      } catch (_) {
                        setDialogState(() {
                          isDeleting = false;
                          error = 'Could not delete. Please try again.';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
              ),
              child: Text(isDeleting ? 'Deleting...' : 'Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      showAppFeedback(context, 'Department deleted.');
      _fetchData();
    }
  }

  void _showCreateDepartmentDialog() {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final descController = TextEditingController();
    var isSaving = false;
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Create Department'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                      labelText: 'Department Name *',
                      hintText: 'e.g. IT Infrastructure')),
              const SizedBox(height: 14),
              TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                      labelText: 'Department Code *', hintText: 'e.g. IT')),
              const SizedBox(height: 14),
              TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description')),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!,
                    style:
                        const TextStyle(color: AppTheme.danger, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final code = codeController.text.trim();
                      if (name.isEmpty || code.isEmpty) {
                        setDialogState(
                            () => error = 'Enter a name and a code.');
                        return;
                      }
                      setDialogState(() {
                        isSaving = true;
                        error = null;
                      });
                      try {
                        await _api.post(ApiConfig.hrDepartments, {
                          'name': name,
                          'code': code,
                          'description': descController.text.trim(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          showAppFeedback(context, 'Department created.');
                          _fetchData();
                        }
                      } on ApiException catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          error = e.message;
                        });
                      } catch (_) {
                        setDialogState(() {
                          isSaving = false;
                          error = 'Could not create the department.';
                        });
                      }
                    },
              child: Text(isSaving ? 'Creating...' : 'Create Department'),
            ),
          ],
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
            title: 'Departments',
            subtitle: 'The departments interns and training courses belong to',
            icon: Icons.corporate_fare_outlined,
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create Department'),
                onPressed: _showCreateDepartmentDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentGold,
                  foregroundColor: AppTheme.primaryNavy,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _departments.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.business_outlined,
                                  size: 56, color: AppTheme.textMuted),
                              SizedBox(height: 12),
                              Text('No departments yet',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              SizedBox(height: 6),
                              Text(
                                  'Use Create Department to add the first one.',
                                  style:
                                      TextStyle(color: AppTheme.textSecondary)),
                            ],
                          ),
                        )
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
                                          label: Text('Code',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      DataColumn(
                                          label: Text('Department Name',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      DataColumn(
                                          label: SizedBox(
                                              width: 320,
                                              child: Text('Description',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)))),
                                      DataColumn(
                                          label: Text('Interns',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      DataColumn(
                                          label: Text('Team Leaders',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      DataColumn(
                                          label: Text('Courses',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      DataColumn(
                                          label: Text('Actions',
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                    ],
                                    rows: _departments.map((d) {
                                      return DataRow(cells: [
                                        DataCell(Text(d['code'] ?? '',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold))),
                                        DataCell(Text(d['name'] ?? '',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600))),
                                        DataCell(SizedBox(
                                            width: 320,
                                            child: Text(d['description'] ?? '-',
                                                overflow:
                                                    TextOverflow.ellipsis))),
                                        DataCell(
                                            Text('${d['intern_count'] ?? 0}')),
                                        DataCell(Text(
                                            '${d['team_leader_count'] ?? 0}')),
                                        DataCell(
                                            Text('${d['course_count'] ?? 0}')),
                                        DataCell(
                                          IconButton(
                                            tooltip: 'Delete department',
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: AppTheme.danger),
                                            onPressed: () =>
                                                _deleteDepartment(d),
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
