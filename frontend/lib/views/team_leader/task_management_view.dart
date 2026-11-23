import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/safe_convert.dart';
import '../../core/utils/date_time_format.dart';

class TaskManagementView extends StatefulWidget {
  const TaskManagementView({super.key});

  @override
  State<TaskManagementView> createState() => _TaskManagementViewState();
}

class _TaskManagementViewState extends State<TaskManagementView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _tasks = [];

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  Future<void> _fetchTasks() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get(ApiConfig.tlTasks);
      setState(() {
        _tasks = res['tasks'] ?? [];
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<List<int>?> _selectInterns({
    required String title,
    required String buttonLabel,
  }) async {
    try {
      final response = await _api.get(ApiConfig.tlInterns);
      final rawInterns = response['interns'];
      final interns = <Map<String, dynamic>>[];
      if (rawInterns is List) {
        for (final value in rawInterns) {
          if (value is! Map) continue;
          final intern = Map<String, dynamic>.from(value);
          final isActive = intern['is_active'] == true ||
              safeInt(intern['is_active']) == 1;
          if (safeInt(intern['id']) > 0 && isActive) interns.add(intern);
        }
      }

      if (!mounted) return null;
      if (interns.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active interns are assigned to your team.'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return null;
      }

      final selectedInternIds = <int>{};
      return showDialog<List<int>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 440,
              height: 380,
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
                    title: Text((intern['name'] ?? 'Intern').toString()),
                    subtitle: Text((intern['email'] ?? '').toString()),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  );
                },
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
                label: Text('$buttonLabel (${selectedInternIds.length})'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load your active interns: $error'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _assignInternsToTask(int taskId, String title) async {
    final internIds = await _selectInterns(
      title: 'Assign "$title" to interns',
      buttonLabel: 'Assign',
    );
    if (internIds == null || internIds.isEmpty) return;

    try {
      final response = await _api.post('${ApiConfig.tlTasks}/$taskId/assign', {
        'intern_ids': internIds,
      });
      await _fetchTasks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                (response['message'] ?? 'Task assignment updated.').toString()),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not assign task: $error'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteTask(int taskId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this activity?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Text('"$title" and all intern submissions for this activity will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Activity'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.delete('${ApiConfig.tlTasks}/$taskId');
      _fetchTasks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activity deleted.'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete activity: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _showCreateTaskDialog() async {
    final internIds = await _selectInterns(
      title: 'Select interns for this task',
      buttonLabel: 'Continue',
    );
    if (internIds == null || internIds.isEmpty || !mounted) return;

    final titleController = TextEditingController();
    final descController = TextEditingController();
    final linkController = TextEditingController();
    final scoreController = TextEditingController(text: '100');
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add_task_rounded, color: AppTheme.primaryBlue, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('Assign Practical Task', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Task Title *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      hintText: 'Enter the task title',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text('Instructions & Deliverables *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Explain what the intern must do, expected outcome, and submission format...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Reference Link (Optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: linkController,
                              decoration: InputDecoration(
                                hintText: 'Paste any reference link',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 130,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Max Score', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: scoreController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: '100',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (titleController.text.trim().isEmpty || descController.text.trim().isEmpty) return;
                      setDialogState(() => isSubmitting = true);
                      try {
                        await _api.post(ApiConfig.tlTasks, {
                          'intern_ids': internIds,
                          'title': titleController.text.trim(),
                          'description': descController.text.trim(),
                          'attachment_path': linkController.text.trim(),
                          'max_score': int.tryParse(scoreController.text) ?? 100,
                          'due_date': DateTime.now().add(const Duration(days: 7)).toIso8601String().substring(0, 10),
                        });
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _fetchTasks();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Task assigned to ${internIds.length} intern(s).'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not assign task: $e'),
                              backgroundColor: AppTheme.danger,
                            ),
                          );
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Assign Task'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSubmissionsModal(int taskId, String title) async {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder(
        future: _api.get('${ApiConfig.tlTasks}/$taskId/submissions'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const AlertDialog(
              content: SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
            );
          }
          final submissions = (snapshot.data['submissions'] as List?) ?? [];

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.rate_review_rounded, color: AppTheme.primaryBlue, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Intern Submissions Review', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      Text(title, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 720,
              height: 480,
              child: submissions.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 40, color: AppTheme.textMuted),
                        SizedBox(height: 12),
                        Text('No submissions received for this task yet', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: submissions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (ctx, i) {
                      final s = submissions[i];
                      final int subId = s['id'];
                      final String intern = s['intern_name'] ?? 'Intern';
                      final String code = s['intern_code'] ?? '';
                      final String text = s['submission_text'] ?? '';
                      final String? link = s['attachment_path'];
                      final String status = s['status'] ?? 'pending';
                      final score = s['score'];
                      final feedback = s['tl_feedback'];

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: status == 'graded' ? const Color(0xFFA7F3D0) : AppTheme.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppTheme.primaryBlue.withOpacity(0.15),
                                  child: Text(
                                    intern.isNotEmpty ? intern[0] : 'I',
                                    style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('$intern ($code)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      Text(
                                        'Submitted: ${formatTimestampMinutes(s['submitted_at'], fallback: 'Recently')}',
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: status == 'graded' ? AppTheme.successLight : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    status == 'graded' ? 'GRADED ($score/${s['max_score']})' : 'NEEDS EVALUATION',
                                    style: TextStyle(
                                      color: status == 'graded' ? AppTheme.success : const Color(0xFFB45309),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (link != null && link.isNotEmpty) ...[
                              if (RegExp(r'^/uploads/.*\.(png|jpe?g|webp|gif)$', caseSensitive: false).hasMatch(link))
                                Container(
                                  width: double.infinity,
                                  constraints: const BoxConstraints(maxHeight: 240),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.borderColor),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      '${ApiConfig.serverOrigin}$link',
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Padding(
                                        padding: EdgeInsets.all(10),
                                        child: Text('Screenshot could not be loaded.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    const Icon(Icons.link, size: 16, color: AppTheme.primaryBlue),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: SelectableText(
                                        link,
                                        style: const TextStyle(color: AppTheme.primaryBlue, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 6),
                            ],
                            SelectableText(text, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4)),
                            if (feedback != null && feedback.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('Your Feedback: "$feedback"', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF047857))),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                icon: Icon(status == 'graded' ? Icons.edit_note : Icons.grade_rounded, size: 16),
                                label: Text(status == 'graded' ? 'Update Grade & Feedback' : 'Grade & Provide Feedback'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: status == 'graded' ? const Color(0xFF475569) : AppTheme.primaryBlue,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _showGradeDialog(subId, intern, s['max_score'] ?? 100, score?.toString() ?? '', feedback ?? '');
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  void _showGradeDialog(int submissionId, String internName, int maxScore, String currentScore, String currentFeedback) {
    final scoreController = TextEditingController(text: currentScore);
    final feedbackController = TextEditingController(text: currentFeedback);
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.successLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.star_rounded, color: AppTheme.success, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Evaluate Submission: $internName', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    Text('Maximum Points: $maxScore', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  ],
                ),
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
                  const Text('Awarded Score *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: scoreController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'e.g. 95',
                      suffixText: '/ $maxScore',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('Team Leader Feedback & Recommendations *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: feedbackController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Provide constructive feedback on code readability, tests, patterns, and areas of excellence...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Quick Feedback Preset Chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _feedbackChip('Clean code architecture & separation of concerns', feedbackController),
                      _feedbackChip('Excellent test coverage and documentation', feedbackController),
                      _feedbackChip('Great work! Keep up the high standard.', feedbackController),
                      _feedbackChip('Consider adding more unit test assertions', feedbackController),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (scoreController.text.trim().isEmpty) return;
                      setDialogState(() => isSubmitting = true);
                      try {
                        await _api.post('${ApiConfig.baseUrl}/tl/submissions/$submissionId/grade', {
                          'score': int.tryParse(scoreController.text) ?? 0,
                          'tl_feedback': feedbackController.text.trim(),
                          'status': 'graded',
                        });
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _fetchTasks();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Grade and feedback saved successfully!'), backgroundColor: AppTheme.success),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save & Publish Grade'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feedbackChip(String text, TextEditingController controller) {
    return InkWell(
      onTap: () {
        controller.text = text;
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int totalTasks = _tasks.length;
    final int totalSubs = _tasks.fold(0, (acc, t) => acc + safeInt(t['total_submissions']));
    final int pendingSubs = _tasks.fold(0, (acc, t) => acc + safeInt(t['pending_submissions']));

    return RefreshIndicator(
      onRefresh: _fetchTasks,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header & Action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Practical Tasks & Assignment Reviews',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Create and manage practical assignments, review intern submissions, and award grades.',
                          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_task_rounded, size: 18),
                  label: const Text('Assign New Task'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onPressed: _showCreateTaskDialog,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 3 Stat Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  _buildStatCard('Active Tasks', '$totalTasks', Icons.assignment_outlined, AppTheme.primaryBlue),
                  _buildStatCard('Total Submissions', '$totalSubs', Icons.folder_shared_outlined, AppTheme.success),
                  _buildStatCard('Pending Evaluations', '$pendingSubs', Icons.pending_actions_rounded, const Color(0xFFD97706)),
                ];
                if (constraints.maxWidth > 800) {
                  return Row(
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 16),
                      Expanded(child: cards[1]),
                      const SizedBox(width: 16),
                      Expanded(child: cards[2]),
                    ],
                  );
                }
                return Column(
                  children: [
                    cards[0],
                    const SizedBox(height: 16),
                    cards[1],
                    const SizedBox(height: 16),
                    cards[2],
                  ],
                );
              },
            ),

            const SizedBox(height: 28),

            // Tasks List
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_tasks.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 48),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.assignment_outlined, size: 40, color: AppTheme.textMuted),
                    SizedBox(height: 12),
                    Text('No practical tasks created yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _tasks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (ctx, i) {
                  final t = _tasks[i];
                  final int id = t['id'];
                  final String title = t['title'] ?? 'Task';
                  final String desc = t['description'] ?? '';
                  final int submissions = t['total_submissions'] ?? 0;
                  final int pending = t['pending_submissions'] ?? 0;
                  final int assignedInterns = safeInt(t['assigned_intern_count']);
                  final String? dueDate = t['due_date'];

                  return Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.assignment_turned_in_rounded, color: AppTheme.primaryBlue, size: 28),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  if (dueDate != null) ...[
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Due: ${formatDateOnly(dueDate)}',
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(desc, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: assignedInterns > 0 ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      assignedInterns > 0 ? 'Assigned to $assignedInterns interns' : 'Not assigned',
                                      style: TextStyle(
                                        color: assignedInterns > 0 ? const Color(0xFF047857) : AppTheme.danger,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('$submissions Submissions', style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 11)),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: pending > 0 ? const Color(0xFFFEF3C7) : const Color(0xFFD1FAE5),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$pending Pending Evaluation',
                                      style: TextStyle(
                                        color: pending > 0 ? const Color(0xFFB45309) : const Color(0xFF047857),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              TextButton.icon(
                                onPressed: () => _assignInternsToTask(id, title),
                                icon: const Icon(Icons.person_add_alt_1, size: 16),
                                label: const Text('Assign interns'),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.rate_review_rounded, size: 16),
                          label: const Text('Review Submissions'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                          onPressed: () => _showSubmissionsModal(id, title),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Delete Activity', style: TextStyle(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: BorderSide(color: AppTheme.danger.withOpacity(0.55)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          onPressed: () => _confirmDeleteTask(id, title),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.textPrimary)),
              Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
