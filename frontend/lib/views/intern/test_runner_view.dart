import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/safe_convert.dart';
import '../../widgets/kgpl_brand_badge.dart';

class TestRunnerView extends StatefulWidget {
  final int? initialScheduleId;

  const TestRunnerView({super.key, this.initialScheduleId});

  @override
  State<TestRunnerView> createState() => _TestRunnerViewState();
}

class _TestRunnerViewState extends State<TestRunnerView> {
  final ApiService _api = ApiService();

  bool _isLoading = true;
  List<dynamic> _availableTests = [];

  // Active Test State
  bool _isTakingTest = false;
  int? _activeAttemptId;
  Map<String, dynamic>? _activeQuiz;
  List<dynamic> _questions = [];
  final Map<int, String> _userAnswers = {};
  final Map<int, TextEditingController> _writtenControllers = {};
  int _currentQuestionIndex = 0;
  int _remainingSeconds = 1800;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialScheduleId != null) {
      _startTest(widget.initialScheduleId!);
    } else {
      _fetchTests();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    for (final c in _writtenControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchTests() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get(ApiConfig.internTests);
      setState(() {
        _availableTests = res['tests'] ?? [];
        _isLoading = false;
        _isTakingTest = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startTest(int scheduleId) async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.post(ApiConfig.internTestStart, {
        'test_schedule_id': scheduleId,
      });

      final quiz = res['quiz'];
      final questions = (res['questions'] as List?) ?? [];
      final int durationMins = quiz['duration_minutes'] ?? 30;

      for (final c in _writtenControllers.values) {
        c.dispose();
      }
      _writtenControllers.clear();
      setState(() {
        _activeAttemptId = res['attempt_id'];
        _activeQuiz = quiz;
        _questions = questions;
        _userAnswers.clear();
        _currentQuestionIndex = 0;
        _remainingSeconds = durationMins * 60;
        _isTakingTest = true;
        _isLoading = false;
      });

      _startTimer();
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
      );
      _fetchTests();
    }
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
        _submitTest();
      }
    });
  }

  Future<void> _submitTest() async {
    _countdownTimer?.cancel();

    // Map answers by question_id
    final Map<String, String> answersPayload = {};
    _userAnswers.forEach((qId, ans) {
      answersPayload[qId.toString()] = ans;
    });

    try {
      final res = await _api.post(ApiConfig.internTestSubmit, {
        'attempt_id': _activeAttemptId,
        'answers': answersPayload,
      });

      final score = res['score'];
      final totalMarks = res['total_marks'];
      final passingMarks = res['passing_marks'];
      final bool needsReview = res['needs_review'] == true;
      final bool isPassed = res['is_passed'] == true;

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(
                  needsReview
                      ? Icons.rate_review_rounded
                      : (isPassed ? Icons.check_circle : Icons.cancel),
                  color: needsReview
                      ? AppTheme.primaryBlue
                      : (isPassed ? AppTheme.success : AppTheme.danger),
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(needsReview
                    ? 'Answers Submitted for Review'
                    : (isPassed
                        ? 'Assessment Passed!'
                        : 'Assessment Not Cleared')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  needsReview
                      ? 'Multiple-choice score: $score / $totalMarks'
                      : 'Your Score: $score / $totalMarks ($passingMarks% required to pass)',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  needsReview
                      ? 'Your written answers have been sent to your Team Leader. Your final result will be updated once they review those answers.'
                      : (isPassed
                          ? 'Congratulations! Your score has been recorded and submitted to your Team Leader.'
                          : 'You did not meet the passing threshold. Please review the training material and consult your Team Leader.'),
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _fetchTests();
                },
                child: const Text('Return to Tests'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
      );
    }
  }

  String _formatTimer(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isTakingTest && _questions.isNotEmpty) {
      return _buildTestRunner();
    }

    return _buildTestsList();
  }

  Widget _buildTestsList() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KgplPageHeader(
            title: 'Scheduled Online MCQ Assessments',
            subtitle:
                'Tests are timed and scheduled by your Team Leader. Ensure an uninterrupted connection before starting.',
            icon: Icons.quiz_outlined,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _availableTests.isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: const Center(
                        child: Text(
                            'No assessments currently scheduled for your department')),
                  )
                : ListView.separated(
                    itemCount: _availableTests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (ctx, i) {
                      final t = _availableTests[i];
                      final int scheduleId = safeInt(t['id']);
                      final String title = t['quiz_title'] ?? 'Assessment';
                      final int duration = safeInt(t['duration_minutes'], 30);
                      final int passing = safeInt(t['passing_marks'], 60);
                      final int totalMarks = safeInt(t['total_marks'], 100);
                      final String? status = t['attempt_status'];
                      final bool hasAttempt = status == 'submitted';
                      final bool isPassed =
                          t['is_passed'] == 1 || t['is_passed'] == true;
                      final int attemptsMade = safeInt(t['user_attempt_count']);
                      final int maxAttempts = safeInt(t['max_attempts'], 1);
                      final bool canAttempt = attemptsMade < maxAttempts;

                      return Container(
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
                                color: hasAttempt
                                    ? (isPassed
                                        ? AppTheme.successLight
                                        : AppTheme.dangerLight)
                                    : AppTheme.primaryNavy.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                hasAttempt
                                    ? (isPassed
                                        ? Icons.check_circle
                                        : Icons.cancel)
                                    : Icons.quiz_outlined,
                                color: hasAttempt
                                    ? (isPassed
                                        ? AppTheme.success
                                        : AppTheme.danger)
                                    : AppTheme.primaryNavy,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Duration: $duration minutes • Passing Marks: $passing%',
                                    style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12),
                                  ),
                                  if (hasAttempt) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Score: ${safeInt(t['total_score'])} / $totalMarks • ${isPassed ? 'PASSED' : 'FAILED'} (Attempts: $attemptsMade/$maxAttempts)',
                                      style: TextStyle(
                                        color: isPassed
                                            ? AppTheme.success
                                            : AppTheme.danger,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Max Attempts: $maxAttempts • Ready to start',
                                      style: const TextStyle(
                                          color: AppTheme.primaryBlue,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10,
                              children: [
                                if (hasAttempt)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isPassed
                                          ? AppTheme.successLight
                                          : AppTheme.dangerLight,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      isPassed ? 'PASSED' : 'FAILED',
                                      style: TextStyle(
                                        color: isPassed
                                            ? AppTheme.success
                                            : AppTheme.danger,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                if (canAttempt)
                                  ElevatedButton.icon(
                                    icon: Icon(
                                        attemptsMade == 0
                                            ? Icons.play_arrow
                                            : Icons.refresh_rounded,
                                        size: 18),
                                    label: Text(attemptsMade == 0
                                        ? 'Start Assessment'
                                        : 'Retake ($attemptsMade/$maxAttempts)'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryBlue,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => _startTest(scheduleId),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestRunner() {
    final currentQ = _questions[_currentQuestionIndex];
    final int qId = currentQ['id'];
    final String qText = currentQ['question_text'] ?? '';
    final dynamic optionsRaw = currentQ['options'];
    List<String> options = [];

    if (optionsRaw is List) {
      options = optionsRaw.map((e) => e.toString()).toList();
    } else if (optionsRaw is Map) {
      options = optionsRaw.values.map((e) => e.toString()).toList();
    }

    final selectedAnswer = _userAnswers[qId];
    final bool isWritten = currentQ['question_type'] == 'short_answer';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar with Test Title, Timer, and Progress
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _activeQuiz?['title'] ?? 'Online Assessment',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _remainingSeconds < 300
                      ? AppTheme.dangerLight
                      : AppTheme.primaryNavy.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.alarm,
                      color: _remainingSeconds < 300
                          ? AppTheme.danger
                          : AppTheme.primaryNavy,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Time Remaining: ${_formatTimer(_remainingSeconds)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _remainingSeconds < 300
                            ? AppTheme.danger
                            : AppTheme.primaryNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Question progress indicator
          LinearProgressIndicator(
            value: (_currentQuestionIndex + 1) / _questions.length,
            backgroundColor: AppTheme.borderColor,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
          ),
          const SizedBox(height: 8),
          Text(
            'Question ${_currentQuestionIndex + 1} of ${_questions.length}',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),

          const SizedBox(height: 20),

          // Question Card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isWritten
                                ? AppTheme.warningLight
                                : AppTheme.successLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isWritten ? 'WRITTEN ANSWER' : 'MCQ',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isWritten
                                  ? AppTheme.warning
                                  : AppTheme.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      qText,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 24),
                    if (isWritten)
                      TextField(
                        controller: _writtenControllers.putIfAbsent(
                          qId,
                          () =>
                              TextEditingController(text: selectedAnswer ?? ''),
                        ),
                        minLines: 6,
                        maxLines: 12,
                        onChanged: (val) => _userAnswers[qId] = val,
                        decoration: InputDecoration(
                          hintText: 'Type your answer here...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      )
                    else
                      ...options.map((opt) {
                        final bool isSelected = selectedAnswer == opt;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFEFF6FF)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryBlue
                                  : AppTheme.borderColor,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: RadioListTile<String>(
                            value: opt,
                            groupValue: selectedAnswer,
                            title: Text(opt,
                                style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal)),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _userAnswers[qId] = val);
                              }
                            },
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Action navigation buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_currentQuestionIndex > 0)
                OutlinedButton(
                  onPressed: () => setState(() => _currentQuestionIndex--),
                  child: const Text('Previous Question'),
                )
              else
                const SizedBox.shrink(),
              if (_currentQuestionIndex < _questions.length - 1)
                ElevatedButton(
                  onPressed: () => setState(() => _currentQuestionIndex++),
                  child: const Text('Next Question'),
                )
              else
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Submit Assessment'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success),
                  onPressed: _submitTest,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
