import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/safe_convert.dart';
import '../../providers/auth_provider.dart';

class CourseModuleTestRunnerView extends StatefulWidget {
  final int testId;

  const CourseModuleTestRunnerView({super.key, required this.testId});

  @override
  State<CourseModuleTestRunnerView> createState() =>
      _CourseModuleTestRunnerViewState();
}

class _CourseModuleTestRunnerViewState
    extends State<CourseModuleTestRunnerView> {
  final ApiService _api = ApiService();
  final Map<int, dynamic> _answers = {};
  final Map<int, TextEditingController> _shortAnswerControllers = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  Map<String, dynamic>? _test;
  List<Map<String, dynamic>> _questions = [];

  @override
  void initState() {
    super.initState();
    _startOrResume();
  }

  @override
  void dispose() {
    for (final controller in _shortAnswerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _startOrResume() async {
    if (widget.testId <= 0) {
      setState(() {
        _error = 'The selected module test is unavailable.';
        _isLoading = false;
      });
      return;
    }
    try {
      final response = await _api.post(
        ApiConfig.internCourseModuleTestStart(widget.testId),
        const {},
      );
      final test = Map<String, dynamic>.from(response['test'] as Map);
      final questions = ((test['questions'] as List?) ?? [])
          .map((question) => Map<String, dynamic>.from(question as Map))
          .toList();
      for (final question in questions) {
        if (question['question_type'] == 'short_answer') {
          final id = safeInt(question['id']);
          _shortAnswerControllers[id] = TextEditingController();
        }
      }
      if (!mounted) return;
      setState(() {
        _test = test;
        _questions = questions;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _returnToCourse() {
    context.read<AuthProvider>().setActiveView('course_player');
  }

  bool _hasAnswer(Map<String, dynamic> question) {
    final id = safeInt(question['id']);
    if (!_answers.containsKey(id)) return false;
    final answer = _answers[id];
    if (question['question_type'] == 'short_answer') {
      return answer is String && answer.trim().isNotEmpty;
    }
    if (question['question_type'] == 'multiple_choice') {
      return answer is List && answer.isNotEmpty;
    }
    return answer is String && answer.isNotEmpty;
  }

  Future<void> _submit() async {
    if (_questions.any((question) => !_hasAnswer(question))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Answer every question before submitting.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final answers = <String, dynamic>{};
      _answers.forEach((id, answer) => answers['$id'] = answer);
      final response = await _api.post(
        ApiConfig.internCourseModuleTestSubmit(widget.testId),
        {'answers': answers},
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final passed = response['passed'] == true;
          final score = safeString(response['score'], '0');
          final totalMarks = safeString(response['total_marks'], '0');
          final percent = safeString(response['percentage'], '0');
          final message = safeString(response['message']);
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  passed ? Icons.check_circle : Icons.cancel,
                  color: passed ? AppTheme.success : AppTheme.danger,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(passed ? 'Test passed' : 'Test not passed'),
                ),
              ],
            ),
            content: Text(
              '$score / $totalMarks marks ($percent%). $message',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Return to course'),
              ),
            ],
          );
        },
      );
      if (mounted) _returnToCourse();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildQuestion(Map<String, dynamic> question, int index) {
    final id = safeInt(question['id']);
    final type = safeString(question['question_type']);
    final options = ((question['options'] as List?) ?? [])
        .map((option) => option.toString())
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Question ${index + 1}  •  ${safeString(question['marks'], '1')} mark(s)',
              style: const TextStyle(
                color: AppTheme.primaryBlue,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              safeString(question['question_text']),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (type == 'short_answer')
              TextField(
                controller: _shortAnswerControllers[id],
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Type your answer',
                ),
                onChanged: (value) => _answers[id] = value,
              )
            else
              ...options.map((option) {
                if (type == 'multiple_choice') {
                  final selected = List<String>.from(
                    (_answers[id] as List?) ?? const [],
                  );
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(option),
                    value: selected.contains(option),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          selected.add(option);
                        } else {
                          selected.remove(option);
                        }
                        if (selected.isEmpty) {
                          _answers.remove(id);
                        } else {
                          _answers[id] = selected;
                        }
                      });
                    },
                  );
                }
                return RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(option),
                  value: option,
                  groupValue: _answers[id] as String?,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _answers[id] = value);
                  },
                );
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.danger, size: 36),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _returnToCourse,
                child: const Text('Return to course'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Return to course',
                onPressed: _returnToCourse,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      safeString(_test?['title'], 'Module test'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${safeInt(_test?['passing_score'], 60)}% required to pass • One attempt',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (safeString(_test?['instructions']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                safeString(_test?['instructions']),
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            itemCount: _questions.length,
            itemBuilder: (context, index) =>
                _buildQuestion(_questions[index], index),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSubmitting ? 'Submitting...' : 'Submit test'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
