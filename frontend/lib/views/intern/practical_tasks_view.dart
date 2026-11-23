import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/device_file_picker.dart';
import '../../core/utils/picked_file.dart';
import '../../core/utils/safe_convert.dart';
import '../../core/utils/date_time_format.dart';

class PracticalTasksView extends StatefulWidget {
  const PracticalTasksView({super.key});

  @override
  State<PracticalTasksView> createState() => _PracticalTasksViewState();
}

class _PracticalTasksViewState extends State<PracticalTasksView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _tasks = [];
  String _selectedFilter = 'all'; // 'all', 'pending', 'under_review', 'graded'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTasks() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final res = await _api.get(ApiConfig.internTasks);
      if (!mounted) return;
      setState(() {
        _tasks = res['tasks'] ?? [];
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  List<dynamic> get _filteredTasks {
    return _tasks.where((t) {
      final status = t['submission_status'];
      final bool isSubmitted = status != null;

      // Filter by status tab
      if (_selectedFilter == 'pending' && isSubmitted) return false;
      if (_selectedFilter == 'under_review' && (!isSubmitted || status != 'pending')) return false;
      if (_selectedFilter == 'graded' && (!isSubmitted || status != 'graded')) return false;

      // Search query
      if (_searchQuery.isNotEmpty) {
        final title = (t['title'] ?? '').toString().toLowerCase();
        final desc = (t['description'] ?? '').toString().toLowerCase();
        final q = _searchQuery.toLowerCase();
        return title.contains(q) || desc.contains(q);
      }

      return true;
    }).toList();
  }

  bool _isImageAttachment(String? value) {
    if (value == null || value.isEmpty || !value.startsWith('/uploads/')) return false;
    return RegExp(r'\.(png|jpe?g|webp|gif)$', caseSensitive: false).hasMatch(value);
  }

  void _showSubmitTaskDialog(Map<String, dynamic> task) {
    final int taskId = task['id'];
    final String title = task['title'] ?? 'Task';
    final existingSubmission = task['submission_text'] ?? '';
    final existingLink = task['submission_attachment'] ?? '';

    final submissionTextController = TextEditingController(text: existingSubmission);
    PickedFile? pickedScreenshot;
    bool isSubmitting = false;

    String? existingShotUrl;
    if (_isImageAttachment(existingLink)) {
      existingShotUrl = '${ApiConfig.serverOrigin}$existingLink';
    }

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
                child: const Icon(Icons.code_rounded, color: AppTheme.primaryBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task['submission_status'] != null ? 'Resubmit Practical Solution' : 'Submit Practical Solution',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted, fontWeight: FontWeight.normal),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your submission will be immediately routed to your designated Team Leader for review, feedback, and grading.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  const Text(
                    'Work Screenshot (Optional)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: isSubmitting
                        ? null
                        : () async {
                            final file = await pickDeviceFile(
                              allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
                            );
                            if (file == null) return;
                            if (!const ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(file.extension)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please choose a PNG, JPG, WEBP or GIF image.'), backgroundColor: AppTheme.danger),
                              );
                              return;
                            }
                            if (file.size > 5 * 1024 * 1024) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Screenshot must be 5 MB or smaller.'), backgroundColor: AppTheme.danger),
                              );
                              return;
                            }
                            if (file.bytes == null || file.bytes!.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Could not read the selected image. Please try again.'), backgroundColor: AppTheme.danger),
                              );
                              return;
                            }
                            setDialogState(() => pickedScreenshot = file);
                          },
                    child: Container(
                      width: double.infinity,
                      height: 160,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: pickedScreenshot != null
                          ? Stack(
                              children: [
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: Image.memory(pickedScreenshot!.bytes!, fit: BoxFit.contain),
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Material(
                                    color: Colors.black54,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => setDialogState(() => pickedScreenshot = null),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.close, size: 16, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(9)),
                                    ),
                                    child: Text(
                                      pickedScreenshot!.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : existingShotUrl != null
                              ? Stack(
                                  children: [
                                    Positioned.fill(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(9),
                                        child: Image.network(existingShotUrl, fit: BoxFit.contain),
                                      ),
                                    ),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(9)),
                                        ),
                                        child: const Text(
                                          'Current screenshot - tap to replace',
                                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.add_photo_alternate_outlined, size: 34, color: AppTheme.primaryBlue),
                                    SizedBox(height: 8),
                                    Text(
                                      'Click to upload a screenshot',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'PNG, JPG or WEBP - up to 5 MB',
                                      style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Description / Notes *',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: submissionTextController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Summarize what you did, how it works, and anything the reviewer should know...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(isSubmitting ? 'Submitting...' : 'Submit Assignment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (submissionTextController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please add a short description of your solution.'), backgroundColor: AppTheme.danger),
                        );
                        return;
                      }

                      setDialogState(() => isSubmitting = true);

                      try {
                        final payload = <String, dynamic>{
                          'task_id': taskId,
                          'submission_text': submissionTextController.text.trim(),
                        };
                        if (pickedScreenshot?.bytes != null) {
                          payload['screenshot_base64'] = base64Encode(pickedScreenshot!.bytes!);
                        } else if (existingLink.isNotEmpty) {
                          payload['attachment_path'] = existingLink;
                        }

                        await _api.post(ApiConfig.internTaskSubmit, payload);

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Task solution submitted successfully to Team Leader!'),
                              backgroundColor: AppTheme.success,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          _fetchTasks();
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
                          );
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _showSubmissionDetailsDialog(Map<String, dynamic> task) {
    final String title = task['title'] ?? 'Task';
    final String submissionText = task['submission_text'] ?? 'No written notes provided.';
    final String? link = task['submission_attachment'];
    final String? submittedAt = task['submitted_at'];
    final String? status = task['submission_status'];
    final score = task['score'];
    final feedback = (task['tl_feedback'] ?? '').toString().trim();
    final showReview = (status == 'graded' || status == 'resubmission_required') &&
        (score != null || feedback.isNotEmpty);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.assignment_turned_in_rounded, color: AppTheme.primaryBlue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Submission Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text(title, style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status & Date row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: status == 'graded' ? AppTheme.successLight : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status == 'graded'
                            ? 'GRADED & EVALUATED'
                            : status == 'resubmission_required'
                                ? 'RESUBMISSION REQUIRED'
                                : 'UNDER TEAM LEADER REVIEW',
                        style: TextStyle(
                          color: status == 'graded' ? AppTheme.success : const Color(0xFFB45309),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (submittedAt != null)
                      Text(
                        'Submitted: ${formatTimestampMinutes(submittedAt)}',
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Work screenshot
                if (link != null && link.isNotEmpty) ...[
                  const Text('Work Screenshot:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (_isImageAttachment(link))
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 260),
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
                            padding: EdgeInsets.all(14),
                            child: Text('Screenshot could not be loaded.', style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link, color: AppTheme.primaryBlue, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              link,
                              style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                ],

                // Submitted Notes
                const Text('Implementation Notes:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: SelectableText(
                    submissionText,
                    style: const TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textPrimary),
                  ),
                ),

                // Show only the current review, not stale data after resubmission.
                if (showReview) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (score != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, color: Color(0xFF059669), size: 22),
                              const SizedBox(width: 8),
                              Text(
                                'Score Awarded: $score / ${task['max_score']}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF065F46)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          'TL Review Feedback:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          feedback.isNotEmpty ? '"$feedback"' : 'No written feedback provided.',
                          style: const TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic, color: Color(0xFF047857), height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton.icon(
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: const Text('Resubmit Solution'),
            onPressed: () {
              Navigator.pop(ctx);
              _showSubmitTaskDialog(task);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int totalTasks = _tasks.length;
    final int gradedCount = _tasks.where((t) => t['submission_status'] == 'graded').length;
    final int underReviewCount = _tasks.where((t) => t['submission_status'] == 'pending').length;
    final int pendingCount = _tasks.where((t) => t['submission_status'] == null).length;

    // Average each graded task's percentage, excluding invalid maximum scores.
    final gradedTasks = _tasks.where((t) =>
        t['submission_status'] == 'graded' &&
        t['score'] != null &&
        safeDouble(t['max_score']) > 0).toList();
    final double avgScore = gradedTasks.isNotEmpty
        ? (gradedTasks
                .map((t) => safeDouble(t['score']) / safeDouble(t['max_score']) * 100)
                .reduce((a, b) => a + b) /
            gradedTasks.length)
        : 0.0;

    return RefreshIndicator(
      onRefresh: _fetchTasks,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header
            Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assigned Practical Tasks',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Submit your solutions, working links, and notes for review and grading by your designated Team Leader.',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _fetchTasks,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 4 Summary Metric Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth > 950 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
                return GridView.count(
                  crossAxisCount: count,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStatCard('Total Assigned Tasks', '$totalTasks', Icons.assignment_outlined, AppTheme.primaryBlue, 'All Modules'),
                    _buildStatCard('Graded & Approved', '$gradedCount', Icons.verified_outlined, AppTheme.success, 'Evaluated by TL'),
                    _buildStatCard('Under TL Review', '$underReviewCount', Icons.hourglass_top_outlined, const Color(0xFFD97706), 'Awaiting Review'),
                    _buildStatCard('Avg Practical Score', gradedTasks.isNotEmpty ? '${avgScore.toStringAsFixed(0)}%' : 'N/A', Icons.stars_rounded, const Color(0xFF7C3AED), 'Overall Performance'),
                  ],
                );
              },
            ),

            const SizedBox(height: 28),

            // Toolbar with Filters & Search
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Row(
                children: [
                  // Filter Chips
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildFilterChip('all', 'All Tasks ($totalTasks)'),
                      _buildFilterChip('pending', 'Pending ($pendingCount)'),
                      _buildFilterChip('under_review', 'Under Review ($underReviewCount)'),
                      _buildFilterChip('graded', 'Graded ($gradedCount)'),
                    ],
                  ),
                  const Spacer(),
                  // Search Field
                  SizedBox(
                    width: 260,
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Search tasks...',
                        hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                        prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Tasks List
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_filteredTasks.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 48),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.task_alt, size: 36, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 14),
                    const Text('No tasks found in this view', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    const Text('Try changing the filter or search query above.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _filteredTasks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 18),
                itemBuilder: (ctx, i) {
                  final t = _filteredTasks[i];
                  return _buildTaskCard(t);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;

    return InkWell(
      onTap: () => setState(() => _selectedFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primaryBlue : AppTheme.borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textSecondary,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final String title = task['title'] ?? 'Task';
    final String desc = task['description'] ?? '';
    final String? status = task['submission_status'];
    final bool isSubmitted = status != null;
    final score = task['score'];
    final feedback = (task['tl_feedback'] ?? '').toString().trim();
    final showReview = (status == 'graded' || status == 'resubmission_required') &&
        (score != null || feedback.isNotEmpty);
    final String? attachment = task['attachment_path'];
    final String? dueDateStr = task['due_date'];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'graded' ? const Color(0xFFA7F3D0) : AppTheme.borderColor,
          width: status == 'graded' ? 1.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Category tag, Due Date, and Status Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'PRACTICAL LAB',
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (dueDateStr != null) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event_note_rounded, size: 14, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      'Due: ${formatDateOnly(dueDateStr)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Max: ${task['max_score'] ?? 100} pts',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                ),
              ),
              const Spacer(),

              // Status Badge
              _buildStatusPill(status),
            ],
          ),

          const SizedBox(height: 14),

          // Title
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),

          // Description
          Text(
            desc,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),

          // Starter specifications / repository reference (if present)
          if (attachment != null && attachment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.folder_zip_outlined, size: 16, color: Color(0xFF475569)),
                const SizedBox(width: 6),
                Text(
                  'Task Specifications: ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                ),
                InkWell(
                  onTap: () {},
                  child: Text(
                    attachment,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // Current review or pending-review banner.
          if (showReview) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star_rounded, color: Color(0xFF047857), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (score != null) ...[
                              Text(
                                'Score: $score / ${task['max_score']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'TL REVIEW',
                                style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          feedback.isNotEmpty
                              ? 'TL Feedback: "$feedback"'
                              : 'No written feedback provided.',
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                            color: Color(0xFF047857),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Evaluated by Designated Team Leader',
                          style: TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else if (status == 'pending') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Solution submitted and currently under review by your Team Leader. Scores and detailed code feedback will appear here once evaluation is complete.',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isSubmitted) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View Submission Details'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: () => _showSubmissionDetailsDialog(task),
                ),
                const SizedBox(width: 10),
              ],
              ElevatedButton.icon(
                icon: Icon(isSubmitted ? Icons.edit_rounded : Icons.file_upload_rounded, size: 16),
                label: Text(isSubmitted ? 'Resubmit Solution' : 'Submit Solution'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSubmitted ? const Color(0xFF2563EB) : const Color(0xFF059669),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () => _showSubmitTaskDialog(task),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String? status) {
    if (status == 'graded') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFD1FAE5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF059669)),
            SizedBox(width: 5),
            Text(
              'GRADED',
              style: TextStyle(
                color: Color(0xFF059669),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    } else if (status == 'pending' || status == 'resubmission_required') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              status == 'resubmission_required' ? Icons.edit_rounded : Icons.access_time_filled_rounded,
              size: 14,
              color: const Color(0xFFD97706),
            ),
            const SizedBox(width: 5),
            Text(
              status == 'resubmission_required' ? 'RESUBMISSION REQUIRED' : 'UNDER REVIEW',
              style: const TextStyle(
                color: Color(0xFFB45309),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file_rounded, size: 14, color: Color(0xFF64748B)),
            SizedBox(width: 5),
            Text(
              'PENDING SUBMISSION',
              style: TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }
  }
}
