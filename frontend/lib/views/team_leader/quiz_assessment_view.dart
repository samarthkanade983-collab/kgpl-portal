import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/safe_convert.dart';
import '../../core/utils/date_time_format.dart';

class QuizAssessmentView extends StatefulWidget {
  const QuizAssessmentView({super.key});

  @override
  State<QuizAssessmentView> createState() => _QuizAssessmentViewState();
}

class _QuizAssessmentViewState extends State<QuizAssessmentView>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  bool _isLoading = true;
  List<dynamic> _quizzes = [];
  List<dynamic> _schedules = [];
  List<dynamic> _interns = [];
  List<dynamic> _courses = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _tryLoad(String path) async {
    try {
      final res = await _api.get(path);
      return res is Map<String, dynamic> ? res : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final qRes = await _tryLoad(ApiConfig.tlQuizzes);
    final sRes = await _tryLoad(ApiConfig.tlSchedules);
    final iRes = await _tryLoad(ApiConfig.tlInterns);
    final cRes = await _tryLoad(ApiConfig.hrCourses);
    if (!mounted) return;
    setState(() {
      if (qRes != null) _quizzes = qRes['quizzes'] ?? [];
      if (sRes != null) _schedules = sRes['schedules'] ?? [];
      if (iRes != null) _interns = iRes['interns'] ?? [];
      if (cRes != null) _courses = cRes['courses'] ?? [];
      _isLoading = false;
    });
    if (qRes == null || sRes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Could not refresh question papers and schedules. Please try again.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // CREATE / SET NEW QUESTION PAPER MODAL
  // ---------------------------------------------------------------------------
  void _showCreateQuizDialog() {
    final titleController = TextEditingController();
    final passMarksController = TextEditingController(text: '60');
    final durationController = TextEditingController(text: '30');
    final totalMarksController = TextEditingController(text: '100');
    final instructionsController = TextEditingController(
      text:
          'Read each question carefully. Answer every multiple-choice and written question. Ensure stable connectivity before commencing assessment.',
    );
    int? selectedCourseId = _courses.isNotEmpty ? _courses[0]['id'] : null;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assignment_add,
                    color: AppTheme.primaryBlue, size: 22),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Set New Question Paper',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text(
                      'Establish evaluation criteria, target course, and passing score',
                      style:
                          TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            ],
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Question Paper Title *',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      hintText:
                          'e.g. Modern Full Stack & REST Architecture Assessment',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_courses.isNotEmpty) ...[
                    const Text('Associated Training Course *',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      value: selectedCourseId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      items: _courses.map<DropdownMenuItem<int>>((c) {
                        return DropdownMenuItem<int>(
                          value: c['id'],
                          child: Text(c['title'] ?? 'Course'),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setModalState(() => selectedCourseId = val),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Duration (Minutes) *',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: durationController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                prefixIcon:
                                    const Icon(Icons.timer_outlined, size: 18),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Passing Score (%) *',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: passMarksController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.percent, size: 18),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Marks',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: totalMarksController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Instructions for Interns',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: instructionsController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Create & Arrange Questions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (titleController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Enter a title for the question paper'),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                        return;
                      }
                      setModalState(() => isSubmitting = true);
                      try {
                        final res = await _api.post(ApiConfig.tlQuizzes, {
                          'course_id': selectedCourseId,
                          'title': titleController.text.trim(),
                          'instructions': instructionsController.text.trim(),
                          'passing_marks':
                              int.tryParse(passMarksController.text) ?? 60,
                          'duration_minutes':
                              int.tryParse(durationController.text) ?? 30,
                          'total_marks':
                              int.tryParse(totalMarksController.text) ?? 100,
                        });
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _fetchData();
                          final newId = res['quiz_id'];
                          if (newId != null) {
                            _showQuestionPaperStudio(
                                newId, titleController.text.trim());
                          }
                        }
                      } catch (e) {
                        setModalState(() => isSubmitting = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('Could not create the question paper. $e'),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // QUESTION PAPER STUDIO (ARRANGE, REORDER, ADD, EDIT QUESTIONS)
  // ---------------------------------------------------------------------------
  void _showQuestionPaperStudio(int quizId, String quizTitle) {
    showDialog(
      context: context,
      builder: (ctx) => _QuestionPaperStudioDialog(
        quizId: quizId,
        quizTitle: quizTitle,
        onQuestionsUpdated: _fetchData,
        onScheduleTest: () {
          _showScheduleModal(preselectedQuizId: quizId);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TEST SCHEDULING MODAL
  // ---------------------------------------------------------------------------
  void _showScheduleModal({int? preselectedQuizId}) {
    if (_quizzes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Create a question paper first, then you can schedule it for interns.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }
    int? selectedQuizId =
        preselectedQuizId ?? (_quizzes.isNotEmpty ? _quizzes[0]['id'] : null);
    int? selectedInternId; // Default to null: "All Interns (Global Access)"

    DateTime startDate = DateTime.now();
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);

    DateTime endDate = DateTime.now().add(const Duration(days: 7));
    TimeOfDay endTime = const TimeOfDay(hour: 18, minute: 0);

    int maxAttempts = 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final startStr =
              '${startDate.toIso8601String().substring(0, 10)} ${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:00';
          final endStr =
              '${endDate.toIso8601String().substring(0, 10)} ${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00';

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.alarm_add_rounded,
                      color: AppTheme.primaryBlue, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Set & Schedule Online Test for Interns',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 17)),
                      Text(
                          'Select intern, testing window, and attempt allowance',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quiz selection
                    const Text('Target Question Paper *',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: selectedQuizId,
                      decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                      items: _quizzes.map<DropdownMenuItem<int>>((q) {
                        return DropdownMenuItem<int>(
                          value: q['id'],
                          child: Text(
                              '${q['title']} (${q['mcq_count'] ?? 0} MCQ • ${q['qa_count'] ?? 0} written • ${q['duration_minutes']}m)',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setModalState(() => selectedQuizId = val),
                    ),
                    const SizedBox(height: 14),

                    // Target Intern
                    const Text('Assign To Intern *',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: selectedInternId,
                      decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                      items: [
                        const DropdownMenuItem<int>(
                            value: null,
                            child: Text('All Interns (Global Access)')),
                        ..._interns.map<DropdownMenuItem<int>>((it) {
                          return DropdownMenuItem<int>(
                            value: it['id'],
                            child: Text(
                                '${it['name']} (${it['intern_code'] ?? 'Intern'})',
                                overflow: TextOverflow.ellipsis),
                          );
                        }),
                      ],
                      onChanged: (val) =>
                          setModalState(() => selectedInternId = val),
                    ),
                    const SizedBox(height: 16),

                    // Start Window Date & Time Pickers
                    const Text('Exam Window Start Time *',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(
                                startDate.toIso8601String().substring(0, 10)),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime.now()
                                    .subtract(const Duration(days: 1)),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)),
                              );
                              if (picked != null)
                                setModalState(() => startDate = picked);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time, size: 16),
                            label: Text(startTime.format(context)),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                  context: context, initialTime: startTime);
                              if (picked != null)
                                setModalState(() => startTime = picked);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // End Window Date & Time Pickers
                    const Text('Exam Window Deadline *',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(
                                endDate.toIso8601String().substring(0, 10)),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: endDate,
                                firstDate: startDate,
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)),
                              );
                              if (picked != null)
                                setModalState(() => endDate = picked);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time, size: 16),
                            label: Text(endTime.format(context)),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                  context: context, initialTime: endTime);
                              if (picked != null)
                                setModalState(() => endTime = picked);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Max Attempts
                    const Text('Attempt Policy',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      value: maxAttempts,
                      decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                      items: const [
                        DropdownMenuItem(
                            value: 1,
                            child: Text('1 Attempt (Official Proctored Exam)')),
                        DropdownMenuItem(
                            value: 2,
                            child: Text('2 Attempts (Retake Allowed)')),
                        DropdownMenuItem(
                            value: 3,
                            child: Text('3 Attempts (Practice Drill)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setModalState(() => maxAttempts = val);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton.icon(
                icon: const Icon(Icons.publish_rounded, size: 18),
                label: const Text('Set & Publish Schedule for Interns'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
                onPressed: () async {
                  if (selectedQuizId == null) return;
                  Navigator.pop(ctx);
                  try {
                    await _api.post(ApiConfig.tlSchedules, {
                      'quiz_id': selectedQuizId,
                      if (selectedInternId != null)
                        'intern_ids': [selectedInternId],
                      'start_window': startStr,
                      'end_window': endStr,
                      'max_attempts': maxAttempts,
                    });

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Test successfully scheduled and set for interns!'),
                          backgroundColor: AppTheme.success,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      _fetchData();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(e.toString()),
                            backgroundColor: AppTheme.danger),
                      );
                    }
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAttemptsReviewDialog({
    required int scheduleId,
    required int quizId,
    required String quizTitle,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _AttemptReviewDialog(
        scheduleId: scheduleId,
        quizId: quizId,
        quizTitle: quizTitle,
        onReviewed: _fetchData,
      ),
    );
  }

  Future<void> _deleteSchedule(int scheduleId) async {
    try {
      await _api.delete('${ApiConfig.baseUrl}/tl/schedules/$scheduleId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Schedule removed successfully'),
              backgroundColor: AppTheme.success),
        );
      }
      _fetchData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not remove the schedule. $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _deleteQuiz(int quizId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Question Paper?'),
        content: Text(
            'Are you sure you want to permanently delete "$title" and all its questions?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Paper'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _api.delete('${ApiConfig.baseUrl}/tl/quizzes/$quizId');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Question paper deleted'),
                backgroundColor: AppTheme.success),
          );
        }
        _fetchData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Could not delete the question paper. $e'),
                backgroundColor: AppTheme.danger),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.alarm_add_rounded, size: 18),
                label: const Text('Schedule Test for Interns'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onPressed: () => _showScheduleModal(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Tabs
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppTheme.primaryBlue,
              unselectedLabelColor: AppTheme.textSecondary,
              indicatorColor: AppTheme.primaryBlue,
              indicatorWeight: 3,
              tabs: [
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.quiz_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text('Question Papers & Banks (${_quizzes.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text('Scheduled Tests for Interns (${_schedules.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Tab Views
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildQuizzesTab(),
                      _buildSchedulesTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizzesTab() {
    if (_quizzes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.ballot_outlined,
                size: 48, color: AppTheme.textMuted),
            const SizedBox(height: 14),
            const Text('No question papers available yet',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
                'Once a question paper is available, click "Schedule Test for Interns" above to set an online test for your interns.',
                style: TextStyle(color: AppTheme.textMuted)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _quizzes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (ctx, i) {
        final q = _quizzes[i];
        final int id = safeInt(q['id']);
        final String title = q['title'] ?? 'Question Paper';
        final String? course = q['course_title'];
        final int questionCount = safeInt(q['question_count']);
        final int mcqCount = safeInt(q['mcq_count'], questionCount);
        final int qaCount = safeInt(q['qa_count']);
        final int duration = safeInt(q['duration_minutes'], 30);
        final int passing = safeInt(q['passing_marks'], 60);
        final int totalMarks = safeInt(q['total_marks'], 100);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFD4AF37).withOpacity(0.2),
                          const Color(0xFFD4AF37).withOpacity(0.05)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.ballot_rounded,
                        color: Color(0xFFB45309), size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 6,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16.5,
                                  color: AppTheme.textPrimary),
                            ),
                            if (course != null && course.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFFBFDBFE)),
                                ),
                                child: Text(
                                  course,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.primaryBlue,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: questionCount > 0
                                    ? AppTheme.successLight
                                    : AppTheme.warningLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$questionCount Questions Arranged',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: questionCount > 0
                                      ? AppTheme.success
                                      : AppTheme.warning,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$mcqCount MCQ',
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryBlue),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.warningLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$qaCount Written',
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.warning),
                              ),
                            ),
                            Text('Total: $totalMarks pts',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary)),
                            Text('Duration: ${duration}m',
                                style: const TextStyle(
                                    fontSize: 12, color: AppTheme.textMuted)),
                            Text('Passing: $passing%',
                                style: const TextStyle(
                                    fontSize: 12, color: AppTheme.textMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Delete question paper',
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppTheme.danger),
                      onPressed: () => _deleteQuiz(id, title),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSchedulesTab() {
    if (_schedules.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(
            child: Text(
                'No active test schedules found. Click "Schedule Test for Interns" above.')),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                  columns: const [
                    DataColumn(
                        label: Text('Assessment Paper',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Assigned To',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Start Window',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('End Window',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Attempts',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Intern Answers',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Actions',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: _schedules.map((s) {
                    final int schedId = safeInt(s['id']);
                    final String title = s['quiz_title'] ?? 'Assessment';
                    final String assignedTo =
                        (s['assigned_interns'] as String?) ??
                            (s['batch_code'] != null
                                ? '${s['batch_code']} (${s['batch_name']})'
                                : 'All Interns');
                    final String start =
                        formatTimestampMinutes(s['start_window']);
                    final String end = formatTimestampMinutes(s['end_window']);
                    final int attempts = safeInt(s['max_attempts'], 1);
                    final int pending = safeInt(s['pending_reviews']);
                    final int quizId = safeInt(s['quiz_id']);

                    return DataRow(
                      cells: [
                        DataCell(Text(title,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(assignedTo)),
                        DataCell(Text(start)),
                        DataCell(Text(end)),
                        DataCell(Text('$attempts Max')),
                        DataCell(
                          pending > 0
                              ? TextButton.icon(
                                  icon: const Icon(Icons.rate_review_rounded,
                                      size: 16, color: AppTheme.warning),
                                  label: Text('$pending to review',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.warning)),
                                  onPressed: () => _showAttemptsReviewDialog(
                                    scheduleId: schedId,
                                    quizId: quizId,
                                    quizTitle: title,
                                  ),
                                )
                              : TextButton.icon(
                                  icon: const Icon(Icons.visibility_outlined,
                                      size: 16),
                                  label: const Text('View answers'),
                                  onPressed: () => _showAttemptsReviewDialog(
                                    scheduleId: schedId,
                                    quizId: quizId,
                                    quizTitle: title,
                                  ),
                                ),
                        ),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: AppTheme.danger),
                            tooltip: 'Cancel & Delete Schedule',
                            onPressed: () => _deleteSchedule(schedId),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// QUESTION PAPER STUDIO DIALOG (FULL AUTHORITY TO ARRANGE & SET QUESTIONS)
// =============================================================================
class _QuestionPaperStudioDialog extends StatefulWidget {
  final int quizId;
  final String quizTitle;
  final VoidCallback onQuestionsUpdated;
  final VoidCallback onScheduleTest;

  const _QuestionPaperStudioDialog({
    required this.quizId,
    required this.quizTitle,
    required this.onQuestionsUpdated,
    required this.onScheduleTest,
  });

  @override
  State<_QuestionPaperStudioDialog> createState() =>
      _QuestionPaperStudioDialogState();
}

class _QuestionPaperStudioDialogState
    extends State<_QuestionPaperStudioDialog> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _questions = [];

  // Question Form State
  int? _editingQuestionId;
  final _questionTextController = TextEditingController();
  final _optAController = TextEditingController();
  final _optBController = TextEditingController();
  final _optCController = TextEditingController();
  final _optDController = TextEditingController();
  final _expectedAnswerController = TextEditingController();
  final _explanationController = TextEditingController();
  final _marksController = TextEditingController(text: '10');
  String _selectedCorrectChoice = 'A';
  String _selectedQuestionType = 'single_choice';
  bool _isSaving = false;

  bool get _isWrittenQuestion => _selectedQuestionType == 'short_answer';

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  @override
  void dispose() {
    _questionTextController.dispose();
    _optAController.dispose();
    _optBController.dispose();
    _optCController.dispose();
    _optDController.dispose();
    _expectedAnswerController.dispose();
    _explanationController.dispose();
    _marksController.dispose();
    super.dispose();
  }

  Future<void> _fetchQuestions() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get('${ApiConfig.tlQuizzes}/${widget.quizId}');
      setState(() {
        _questions = res['questions'] ?? [];
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // AUTHORITY TO ARRANGE: MOVE UP & MOVE DOWN
  // ---------------------------------------------------------------------------
  void _moveQuestionUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _questions.removeAt(index);
      _questions.insert(index - 1, item);
    });
    _saveArrangedOrder();
  }

  void _moveQuestionDown(int index) {
    if (index >= _questions.length - 1) return;
    setState(() {
      final item = _questions.removeAt(index);
      _questions.insert(index + 1, item);
    });
    _saveArrangedOrder();
  }

  Future<void> _saveArrangedOrder() async {
    final orderedIds = _questions.map((q) => q['id']).toList();
    try {
      await _api.post(
          '${ApiConfig.baseUrl}/tl/quizzes/${widget.quizId}/reorder-questions',
          {
            'ordered_ids': orderedIds,
          });
      widget.onQuestionsUpdated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Question sequence re-arranged & saved!'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // ADD OR UPDATE QUESTION
  // ---------------------------------------------------------------------------
  void _startEditing(Map<String, dynamic> q) {
    setState(() {
      _editingQuestionId = q['id'];
      _questionTextController.text = q['question_text'] ?? '';
      _marksController.text = (q['marks'] ?? 10).toString();
      _explanationController.text = q['explanation'] ?? '';
      _selectedQuestionType = q['question_type'] == 'short_answer'
          ? 'short_answer'
          : 'single_choice';
      _expectedAnswerController.text = _selectedQuestionType == 'short_answer'
          ? (q['correct_answer'] ?? '')
          : '';

      final dynamic optsRaw = q['options'];
      List<String> options = [];
      if (optsRaw is List) {
        options = optsRaw.map((e) => e.toString()).toList();
      }

      _optAController.text = options.isNotEmpty ? options[0] : '';
      _optBController.text = options.length > 1 ? options[1] : '';
      _optCController.text = options.length > 2 ? options[2] : '';
      _optDController.text = options.length > 3 ? options[3] : '';

      final String correct = q['correct_answer'] ?? '';
      if (options.isNotEmpty && correct == options[0]) {
        _selectedCorrectChoice = 'A';
      } else if (options.length > 1 && correct == options[1]) {
        _selectedCorrectChoice = 'B';
      } else if (options.length > 2 && correct == options[2]) {
        _selectedCorrectChoice = 'C';
      } else if (options.length > 3 && correct == options[3]) {
        _selectedCorrectChoice = 'D';
      } else {
        _selectedCorrectChoice = 'A';
      }
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingQuestionId = null;
      _questionTextController.clear();
      _optAController.clear();
      _optBController.clear();
      _optCController.clear();
      _optDController.clear();
      _expectedAnswerController.clear();
      _explanationController.clear();
      _marksController.text = '10';
      _selectedCorrectChoice = 'A';
      _selectedQuestionType = 'single_choice';
    });
  }

  Future<void> _saveQuestion() async {
    final text = _questionTextController.text.trim();
    final optA = _optAController.text.trim();
    final optB = _optBController.text.trim();
    final optC = _optCController.text.trim();
    final optD = _optDController.text.trim();

    final bool isWritten = _isWrittenQuestion;
    final String expectedAnswer = _expectedAnswerController.text.trim();

    if (isWritten) {
      if (text.isEmpty || expectedAnswer.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Question statement and expected answer are required for a written question'),
              backgroundColor: AppTheme.danger),
        );
        return;
      }
    } else if (text.isEmpty || optA.isEmpty || optB.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Question statement and at least Options A and B are required'),
            backgroundColor: AppTheme.danger),
      );
      return;
    }

    final options = <String>[];
    String correctAnswer = expectedAnswer;
    if (!isWritten) {
      options.add(optA);
      options.add(optB);
      if (optC.isNotEmpty) options.add(optC);
      if (optD.isNotEmpty) options.add(optD);

      correctAnswer = optA;
      if (_selectedCorrectChoice == 'B') correctAnswer = optB;
      if (_selectedCorrectChoice == 'C' && optC.isNotEmpty)
        correctAnswer = optC;
      if (_selectedCorrectChoice == 'D' && optD.isNotEmpty)
        correctAnswer = optD;
    }

    setState(() => _isSaving = true);
    try {
      if (_editingQuestionId != null) {
        // Update existing question
        await _api.put(
            '${ApiConfig.baseUrl}/tl/quizzes/questions/$_editingQuestionId', {
          'question_text': text,
          'question_type': _selectedQuestionType,
          'options': options,
          'correct_answer': correctAnswer,
          'marks': int.tryParse(_marksController.text) ?? 10,
          'explanation': _explanationController.text.trim(),
        });
      } else {
        // Add new question
        await _api.post('${ApiConfig.baseUrl}/tl/quizzes/questions', {
          'quiz_id': widget.quizId,
          'question_text': text,
          'question_type': _selectedQuestionType,
          'options': options,
          'correct_answer': correctAnswer,
          'marks': int.tryParse(_marksController.text) ?? 10,
          'explanation': _explanationController.text.trim(),
        });
      }

      if (!mounted) return;
      setState(() => _isSaving = false);
      _cancelEditing();
      _fetchQuestions();
      widget.onQuestionsUpdated();
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _deleteQuestion(int questionId) async {
    try {
      await _api
          .delete('${ApiConfig.baseUrl}/tl/quizzes/questions/$questionId');
      _fetchQuestions();
      widget.onQuestionsUpdated();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final int totalPoints =
        _questions.fold(0, (sum, q) => sum + safeInt(q['marks'], 10));
    final screen = MediaQuery.of(context).size;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: Color(0xFFB45309), size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Question Paper Arranger Studio',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.successLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('TL FULL AUTHORITY',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.success)),
                      ),
                    ],
                  ),
                  Text(widget.quizTitle,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppTheme.textMuted)),
                ],
              ),
            ],
          ),
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: const Text('Set & Schedule for Interns'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onScheduleTest();
                },
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: math.min(1050, screen.width - 80),
        height: math.min(640, screen.height - 160),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left 55%: Arranger & Reordering Paper View
            Expanded(
              flex: 55,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Banner
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.format_list_numbered_rounded,
                                size: 18, color: AppTheme.primaryBlue),
                            const SizedBox(width: 8),
                            Text(
                              'Arranged Questions (${_questions.length})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Text(
                            'Paper Total: $totalPoints pts',
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryBlue),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Use the ▲ and ▼ buttons on each question to arrange the exact sequence for interns.',
                      style:
                          TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 14),

                    // Questions List
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _questions.isEmpty
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.quiz_outlined,
                                          size: 40, color: AppTheme.textMuted),
                                      SizedBox(height: 10),
                                      Text('No questions in paper yet',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      SizedBox(height: 4),
                                      Text(
                                          'Compose questions using the form on the right.',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textMuted)),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _questions.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (ctx, idx) {
                                    final q = _questions[idx];
                                    final int qId = q['id'];
                                    final String text =
                                        q['question_text'] ?? '';
                                    final String correct =
                                        q['correct_answer'] ?? '';
                                    final bool isWritten =
                                        q['question_type'] == 'short_answer';
                                    final int marks = q['marks'] ?? 10;
                                    final dynamic optsRaw = q['options'];
                                    List<String> options = [];
                                    if (optsRaw is List) {
                                      options = optsRaw
                                          .map((e) => e.toString())
                                          .toList();
                                    }

                                    final bool isBeingEdited =
                                        _editingQuestionId == qId;

                                    return Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: isBeingEdited
                                            ? const Color(0xFFEFF6FF)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isBeingEdited
                                              ? AppTheme.primaryBlue
                                              : const Color(0xFFE2E8F0),
                                          width: isBeingEdited ? 1.8 : 1.2,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Question Order Badge
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFF0F172A),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  'Q${idx + 1}',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 11),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  text,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 13,
                                                      height: 1.3),
                                                ),
                                              ),
                                              const SizedBox(width: 8),

                                              // Marks Badge
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 7,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFEFF6FF),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text('$marks pts',
                                                    style: const TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: AppTheme
                                                            .primaryBlue)),
                                              ),
                                              const SizedBox(width: 8),

                                              // Reorder UP button
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.arrow_upward_rounded,
                                                    size: 18),
                                                tooltip: 'Move Up in Paper',
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                color: idx > 0
                                                    ? AppTheme.primaryBlue
                                                    : Colors.grey.shade300,
                                                onPressed: idx > 0
                                                    ? () => _moveQuestionUp(idx)
                                                    : null,
                                              ),
                                              const SizedBox(width: 6),

                                              // Reorder DOWN button
                                              IconButton(
                                                icon: const Icon(
                                                    Icons
                                                        .arrow_downward_rounded,
                                                    size: 18),
                                                tooltip: 'Move Down in Paper',
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                color:
                                                    idx < _questions.length - 1
                                                        ? AppTheme.primaryBlue
                                                        : Colors.grey.shade300,
                                                onPressed: idx <
                                                        _questions.length - 1
                                                    ? () =>
                                                        _moveQuestionDown(idx)
                                                    : null,
                                              ),
                                              const SizedBox(width: 8),

                                              // Edit Question
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 18,
                                                    color: Color(0xFF475569)),
                                                tooltip: 'Edit Question',
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                onPressed: () =>
                                                    _startEditing(q),
                                              ),
                                              const SizedBox(width: 6),

                                              // Delete Question
                                              IconButton(
                                                icon: const Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    size: 18,
                                                    color: AppTheme.danger),
                                                tooltip: 'Delete Question',
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                onPressed: () =>
                                                    _deleteQuestion(qId),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          if (isWritten)
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: AppTheme.warningLight,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Row(
                                                    children: [
                                                      Icon(
                                                          Icons
                                                              .edit_note_rounded,
                                                          size: 14,
                                                          color:
                                                              AppTheme.warning),
                                                      SizedBox(width: 6),
                                                      Text('WRITTEN ANSWER',
                                                          style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: AppTheme
                                                                  .warning)),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    'Expected answer: ${correct.isEmpty ? 'Not specified' : correct}',
                                                    style: const TextStyle(
                                                        fontSize: 11.5,
                                                        color: AppTheme
                                                            .textSecondary),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else
                                            // Options display with Correct Answer green highlight
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              children: options
                                                  .asMap()
                                                  .entries
                                                  .map((entry) {
                                                final int optIdx = entry.key;
                                                final String optText =
                                                    entry.value;
                                                final String letter =
                                                    String.fromCharCode(
                                                        65 + optIdx);
                                                final bool isCorrect = optText
                                                        .trim()
                                                        .toLowerCase() ==
                                                    correct
                                                        .trim()
                                                        .toLowerCase();

                                                return Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: isCorrect
                                                        ? const Color(
                                                            0xFFD1FAE5)
                                                        : const Color(
                                                            0xFFF1F5F9),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                    border: Border.all(
                                                        color: isCorrect
                                                            ? const Color(
                                                                0xFFA7F3D0)
                                                            : const Color(
                                                                0xFFE2E8F0)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text('$letter. ',
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 11,
                                                              color: isCorrect
                                                                  ? const Color(
                                                                      0xFF065F46)
                                                                  : Colors
                                                                      .black87)),
                                                      Text(optText,
                                                          style: TextStyle(
                                                              fontSize: 11.5,
                                                              fontWeight: isCorrect
                                                                  ? FontWeight
                                                                      .bold
                                                                  : FontWeight
                                                                      .normal,
                                                              color: isCorrect
                                                                  ? const Color(
                                                                      0xFF065F46)
                                                                  : AppTheme
                                                                      .textSecondary)),
                                                      if (isCorrect) ...[
                                                        const SizedBox(
                                                            width: 6),
                                                        const Icon(
                                                            Icons
                                                                .check_circle_rounded,
                                                            size: 13,
                                                            color: Color(
                                                                0xFF059669)),
                                                      ],
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 20),

            // Right 45%: Authoring / Editing Question Form
            Expanded(
              flex: 45,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _editingQuestionId != null
                              ? 'Edit Question Details'
                              : 'Add New Question to Paper',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        if (_editingQuestionId != null)
                          TextButton(
                            onPressed: _cancelEditing,
                            child: const Text('Cancel Edit',
                                style: TextStyle(
                                    color: AppTheme.danger, fontSize: 12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Question prompt
                    TextField(
                      controller: _questionTextController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Question Statement *',
                        hintText:
                            'Enter technical problem statement or code snippet...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Question Type Selector
                    const Text('Question Type *',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'single_choice',
                          icon: Icon(Icons.check_circle_outline_rounded,
                              size: 16),
                          label: Text('MCQ'),
                        ),
                        ButtonSegment(
                          value: 'short_answer',
                          icon: Icon(Icons.edit_note_rounded, size: 16),
                          label: Text('Question & Answer'),
                        ),
                      ],
                      selected: {_selectedQuestionType},
                      onSelectionChanged: (val) {
                        setState(() => _selectedQuestionType = val.first);
                      },
                    ),
                    const SizedBox(height: 14),

                    if (_isWrittenQuestion) ...[
                      TextField(
                        controller: _expectedAnswerController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'Expected Answer *',
                          hintText:
                              'The model answer you will grade written responses against',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.warningLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.rate_review_rounded,
                                size: 16, color: AppTheme.warning),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Interns type their answer. You award the marks while reviewing their attempt.',
                                style: TextStyle(
                                    fontSize: 11.5, color: AppTheme.warning),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      // Options A & B
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _optAController,
                              decoration: InputDecoration(
                                labelText: 'Option A *',
                                prefixText: 'A. ',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _optBController,
                              decoration: InputDecoration(
                                labelText: 'Option B *',
                                prefixText: 'B. ',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Options C & D
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _optCController,
                              decoration: InputDecoration(
                                labelText: 'Option C',
                                prefixText: 'C. ',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _optDController,
                              decoration: InputDecoration(
                                labelText: 'Option D',
                                prefixText: 'D. ',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Correct Answer Selector
                      const Text('Designated Correct Answer *',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'A', label: Text('Option A')),
                          ButtonSegment(value: 'B', label: Text('Option B')),
                          ButtonSegment(value: 'C', label: Text('Option C')),
                          ButtonSegment(value: 'D', label: Text('Option D')),
                        ],
                        selected: {_selectedCorrectChoice},
                        onSelectionChanged: (val) {
                          setState(() => _selectedCorrectChoice = val.first);
                        },
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Marks & Explanation
                    Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _marksController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Question Marks',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _explanationController,
                            decoration: InputDecoration(
                              labelText: 'Model Answer Explanation',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Icon(
                                _editingQuestionId != null
                                    ? Icons.save_rounded
                                    : Icons.add_circle_rounded,
                                size: 18),
                        label: Text(_editingQuestionId != null
                            ? 'Update Question in Paper'
                            : 'Insert Question into Paper'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _editingQuestionId != null
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF059669),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isSaving ? null : _saveQuestion,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// WRITTEN ANSWER REVIEW DIALOG (TEAM LEADER GRADING)
// =============================================================================
class _AttemptReviewDialog extends StatefulWidget {
  final int scheduleId;
  final int quizId;
  final String quizTitle;
  final VoidCallback onReviewed;

  const _AttemptReviewDialog({
    required this.scheduleId,
    required this.quizId,
    required this.quizTitle,
    required this.onReviewed,
  });

  @override
  State<_AttemptReviewDialog> createState() => _AttemptReviewDialogState();
}

class _AttemptReviewDialogState extends State<_AttemptReviewDialog> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  String? _loadError;
  List<dynamic> _attempts = [];
  List<dynamic> _questions = [];
  final Map<int, Map<int, TextEditingController>> _markControllers = {};
  final Set<int> _savingAttempts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final perAttempt in _markControllers.values) {
      for (final c in perAttempt.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _api.get(
            '${ApiConfig.baseUrl}/tl/schedules/${widget.scheduleId}/attempts'),
        _api.get('${ApiConfig.tlQuizzes}/${widget.quizId}'),
      ]);
      if (!mounted) return;
      setState(() {
        _attempts = results[0]['attempts'] ?? [];
        _questions = results[1]['questions'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _writtenQuestions =>
      _questions.where((q) => q['question_type'] == 'short_answer').toList();

  int get _paperTotal =>
      _questions.fold(0, (sum, q) => sum + safeInt(q['marks'], 10));

  TextEditingController _controllerFor(int attemptId, int questionId,
      int maxMarks, Map<String, dynamic>? reviewData) {
    final perAttempt = _markControllers.putIfAbsent(
        attemptId, () => <int, TextEditingController>{});
    return perAttempt.putIfAbsent(questionId, () {
      final existing = reviewData?[questionId.toString()];
      final initial = existing is Map ? safeInt(existing['marks_awarded']) : 0;
      return TextEditingController(text: initial.clamp(0, maxMarks).toString());
    });
  }

  void _disposeAttemptControllers(int attemptId) {
    final perAttempt = _markControllers.remove(attemptId);
    if (perAttempt == null) return;
    for (final c in perAttempt.values) {
      c.dispose();
    }
  }

  Map<String, dynamic>? _attemptById(int attemptId) {
    for (final a in _attempts) {
      if (safeInt(a['id']) == attemptId) {
        return Map<String, dynamic>.from(a as Map);
      }
    }
    return null;
  }

  Future<void> _saveReview(int attemptId) async {
    final reviewData = _attemptById(attemptId)?['review_data'];
    final reviews = <Map<String, dynamic>>[];
    for (final q in _writtenQuestions) {
      final qid = safeInt(q['id']);
      final maxMarks = safeInt(q['marks'], 10);
      final ctrl = _controllerFor(attemptId, qid, maxMarks,
          reviewData is Map ? Map<String, dynamic>.from(reviewData) : null);
      final raw = ctrl.text.trim();
      final int marks = int.tryParse(raw) ?? -1;
      if (marks < 0 || marks > maxMarks) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Enter marks between 0 and $maxMarks for every written answer'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }
      reviews.add({'question_id': qid, 'marks': marks});
    }

    setState(() => _savingAttempts.add(attemptId));
    try {
      await _api.post('${ApiConfig.baseUrl}/tl/attempts/$attemptId/review',
          {'reviews': reviews});
      if (!mounted) return;
      _disposeAttemptControllers(attemptId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review saved. Final score updated.'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onReviewed();
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAttempts.remove(attemptId));
    }
  }

  String _submittedAt(dynamic value) => formatTimestampMinutes(value);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.warningLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.rate_review_rounded,
                color: AppTheme.warning, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Answer Review',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                Text(widget.quizTitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMuted)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.min(620, math.max(120, screen.height - 160)),
        ),
        child: SizedBox(
          width: math.min(840, math.max(0, screen.width - 80)),
          child: _isLoading
              ? const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                )
              : _loadError != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Unable to load answer review.'),
                        const SizedBox(height: 8),
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    )
                  : _attempts.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('No intern has attempted this test yet.'),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _attempts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 14),
                          itemBuilder: (ctx, i) {
                            final a = _attempts[i];
                            final int attemptId = safeInt(a['id']);
                            final bool submitted = a['status'] == 'submitted';
                            final bool timedOut = a['status'] == 'timed_out';
                            final bool needsReview =
                                submitted && safeInt(a['needs_review']) == 1;
                            final String statusLabel = !submitted
                                ? (timedOut ? 'Timed out' : 'In progress')
                                : needsReview
                                    ? 'Awaiting review'
                                    : a['reviewed_at'] != null
                                        ? 'Reviewed'
                                        : 'Automatically graded';
                            final Color statusColor = !submitted
                                ? AppTheme.textSecondary
                                : needsReview
                                    ? AppTheme.warning
                                    : AppTheme.success;
                            final Color statusBackground = !submitted
                                ? const Color(0xFFF1F5F9)
                                : needsReview
                                    ? AppTheme.warningLight
                                    : AppTheme.successLight;
                            final Map<String, dynamic>? reviewData =
                                a['review_data'] is Map
                                    ? Map<String, dynamic>.from(
                                        a['review_data'])
                                    : null;
                            final Map<String, dynamic> answers =
                                a['submitted_answers'] is Map
                                    ? Map<String, dynamic>.from(
                                        a['submitted_answers'])
                                    : {};
                            final bool saving =
                                _savingAttempts.contains(attemptId);

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: needsReview
                                      ? AppTheme.warning
                                      : const Color(0xFFE2E8F0),
                                  width: needsReview ? 1.6 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a['intern_name'] ?? 'Intern',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14),
                                  ),
                                  Text(
                                    '${a['intern_code'] ?? ''} • ${submitted ? 'Submitted' : 'Started'} ${_submittedAt(submitted ? a['end_time'] : a['start_time'])}',
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppTheme.textMuted),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusBackground,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          statusLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                      if (submitted)
                                        Text(
                                          '${safeInt(a['total_score'])} / $_paperTotal pts${needsReview ? ' (provisional)' : ''}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: AppTheme.primaryNavy),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (_questions.isEmpty)
                                    const Text(
                                      'This paper has no questions.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textMuted),
                                    )
                                  else
                                    ..._questions.map((q) {
                                      final int qid = safeInt(q['id']);
                                      final int maxMarks =
                                          safeInt(q['marks'], 10);
                                      final bool isWritten =
                                          q['question_type'] == 'short_answer';
                                      final String answer =
                                          (answers[qid.toString()] ?? '')
                                              .toString();
                                      final bool answered =
                                          answer.trim().isNotEmpty;
                                      final List<dynamic> options =
                                          q['options'] is List
                                              ? q['options'] as List<dynamic>
                                              : const [];
                                      final String correct =
                                          (q['correct_answer'] ?? '')
                                              .toString();
                                      final bool mcqCorrect = !isWritten &&
                                          answered &&
                                          correct.isNotEmpty &&
                                          answer.trim().toLowerCase() ==
                                              correct.trim().toLowerCase();

                                      return Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    q['question_text'] ?? '',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12.5),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isWritten
                                                        ? const Color(
                                                            0xFFFEF3C7)
                                                        : const Color(
                                                            0xFFEFF6FF),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                    isWritten
                                                        ? 'Written • $maxMarks pts'
                                                        : 'MCQ • $maxMarks pts',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isWritten
                                                          ? const Color(
                                                              0xFFB45309)
                                                          : AppTheme
                                                              .primaryBlue,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color: const Color(
                                                        0xFFE2E8F0)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    "Intern's answer",
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: AppTheme
                                                          .textSecondary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    answered
                                                        ? (options.isEmpty
                                                            ? answer
                                                            : 'Selected: $answer')
                                                        : (submitted
                                                            ? 'No answer submitted'
                                                            : 'Not submitted'),
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight: answered
                                                          ? FontWeight.w600
                                                          : FontWeight.normal,
                                                      color: answered
                                                          ? AppTheme.textPrimary
                                                          : AppTheme.textMuted,
                                                    ),
                                                  ),
                                                  if (!isWritten &&
                                                      correct.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Correct answer: $correct'
                                                      '${answered ? (mcqCorrect ? '  (Correct)' : '  (Incorrect)') : ''}',
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: !answered
                                                            ? AppTheme.textMuted
                                                            : (mcqCorrect
                                                                ? AppTheme
                                                                    .success
                                                                : AppTheme
                                                                    .danger),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (isWritten) ...[
                                              const SizedBox(height: 8),
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: SizedBox(
                                                  width: 170,
                                                  child: TextField(
                                                    controller: _controllerFor(
                                                        attemptId,
                                                        qid,
                                                        maxMarks,
                                                        reviewData),
                                                    enabled:
                                                        needsReview && !saving,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    decoration: InputDecoration(
                                                      isDense: true,
                                                      labelText:
                                                          'Marks awarded',
                                                      suffixText: '/ $maxMarks',
                                                      border:
                                                          OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8)),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }),
                                  if (needsReview &&
                                      _writtenQuestions.isNotEmpty)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: ElevatedButton.icon(
                                        icon: saving
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 2))
                                            : const Icon(Icons.save_rounded,
                                                size: 16),
                                        label: const Text('Save Review'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryBlue,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 10),
                                        ),
                                        onPressed: saving
                                            ? null
                                            : () => _saveReview(attemptId),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
        ),
      ),
    );
  }
}
