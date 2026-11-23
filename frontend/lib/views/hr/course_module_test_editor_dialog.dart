import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/safe_convert.dart';

class CourseModuleTestEditorDialog extends StatefulWidget {
  final int moduleId;
  final String moduleTitle;
  final Future<void> Function()? onSaved;

  const CourseModuleTestEditorDialog({
    super.key,
    required this.moduleId,
    required this.moduleTitle,
    this.onSaved,
  });

  @override
  State<CourseModuleTestEditorDialog> createState() =>
      _CourseModuleTestEditorDialogState();
}

class _CourseModuleTestEditorDialogState
    extends State<CourseModuleTestEditorDialog> {
  final ApiService _api = ApiService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _instructionsController =
      TextEditingController();
  final TextEditingController _passingScoreController =
      TextEditingController(text: '60');
  final List<_QuestionDraft> _questions = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasAttempts = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTest();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _instructionsController.dispose();
    _passingScoreController.dispose();
    for (final question in _questions) {
      question.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTest() async {
    try {
      final response = await _api.get(
        ApiConfig.hrCourseModuleTest(widget.moduleId),
      );
      final test = response['test'];
      if (test is Map) {
        _titleController.text = safeString(test['title']);
        _instructionsController.text = safeString(test['instructions']);
        _passingScoreController.text =
            safeString(test['passing_score'], '60');
        _hasAttempts = safeInt(test['attempt_count']) > 0;
        for (final question in (test['questions'] as List?) ?? []) {
          _questions.add(
            _QuestionDraft.fromJson(
              Map<String, dynamic>.from(question as Map),
            ),
          );
        }
      } else {
        _titleController.text = '${widget.moduleTitle} Test';
      }
      if (_questions.isEmpty) _questions.add(_QuestionDraft());
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _showMessage(String message, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  Map<String, dynamic>? _serializeQuestion(_QuestionDraft draft) {
    final text = draft.textController.text.trim();
    final marks = double.tryParse(draft.marksController.text.trim());
    if (text.isEmpty || marks == null || marks <= 0) return null;

    if (draft.type == 'short_answer') {
      final answer = draft.correctAnswerController.text.trim();
      if (answer.isEmpty) return null;
      return {
        'question_text': text,
        'question_type': draft.type,
        'correct_answer': answer,
        'marks': marks,
      };
    }

    final options = draft.options
        .map((option) => option.textController.text.trim())
        .toList();
    if (options.length < 2 || options.any((option) => option.isEmpty)) {
      return null;
    }
    if (draft.type == 'single_choice') {
      final selected = draft.correctOptionIndex;
      if (selected == null || selected >= options.length) return null;
      return {
        'question_text': text,
        'question_type': draft.type,
        'options': options,
        'correct_answer': options[selected],
        'marks': marks,
      };
    }

    final correct = draft.correctOptionIndexes
        .where((index) => index >= 0 && index < options.length)
        .map((index) => options[index])
        .toList();
    if (correct.isEmpty) return null;
    return {
      'question_text': text,
      'question_type': draft.type,
      'options': options,
      'correct_answer': correct,
      'marks': marks,
    };
  }

  Future<void> _save() async {
    if (_hasAttempts) {
      _showMessage(
        'This test cannot be edited because an intern has already started it.',
      );
      return;
    }
    final title = _titleController.text.trim();
    final passingScore = int.tryParse(_passingScoreController.text.trim());
    final questions =
        _questions.map(_serializeQuestion).toList(growable: false);
    if (title.isEmpty || title.length > 255) {
      _showMessage('Enter a test title of 1 to 255 characters.');
      return;
    }
    if (passingScore == null || passingScore < 1 || passingScore > 100) {
      _showMessage('Passing score must be between 1 and 100%.');
      return;
    }
    if (questions.isEmpty || questions.any((question) => question == null)) {
      _showMessage(
        'Complete every question, option, answer key, and mark value before saving.',
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _api.put(
        ApiConfig.hrCourseModuleTest(widget.moduleId),
        {
          'title': title,
          'instructions': _instructionsController.text.trim(),
          'passing_score': passingScore,
          'questions': questions,
        },
      );
      await widget.onSaved?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addQuestion() {
    setState(() => _questions.add(_QuestionDraft()));
  }

  Widget _buildChoiceOptions(_QuestionDraft question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < question.options.length; index++)
          Row(
            children: [
              if (question.type == 'single_choice')
                Radio<int>(
                  value: index,
                  groupValue: question.correctOptionIndex,
                  onChanged: (value) => setState(
                    () => question.correctOptionIndex = value,
                  ),
                )
              else
                Checkbox(
                  value: question.correctOptionIndexes.contains(index),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        question.correctOptionIndexes.add(index);
                      } else {
                        question.correctOptionIndexes.remove(index);
                      }
                    });
                  },
                ),
              Expanded(
                child: TextField(
                  controller: question.options[index].textController,
                  decoration: InputDecoration(
                    labelText: 'Option ${index + 1}',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove option',
                onPressed: question.options.length <= 2
                    ? null
                    : () => setState(() => question.removeOption(index)),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: question.options.length >= 20
                ? null
                : () => setState(question.addOption),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add option'),
          ),
        ),
        Text(
          question.type == 'single_choice'
              ? 'Select the radio button beside the correct answer.'
              : 'Select every correct answer.',
          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
      ],
    );
  }

  Widget _buildQuestion(_QuestionDraft question, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Question ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryNavy,
                    ),
                  ),
                ),
                SizedBox(
                  width: 168,
                  child: DropdownButtonFormField<String>(
                    value: question.type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Question type',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'single_choice',
                        child: Text('Single choice'),
                      ),
                      DropdownMenuItem(
                        value: 'multiple_choice',
                        child: Text('Multiple choice'),
                      ),
                      DropdownMenuItem(
                        value: 'short_answer',
                        child: Text('Short answer'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        question.type = value;
                        if (value != 'short_answer' &&
                            question.options.length < 2) {
                          question.addOption();
                          question.addOption();
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: question.marksController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Marks',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove question',
                  onPressed: () {
                    setState(() {
                      _questions.removeAt(index);
                      question.dispose();
                    });
                  },
                  icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: question.textController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Question text',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            if (question.type == 'short_answer')
              TextField(
                controller: question.correctAnswerController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Correct answer key (automatic checking)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  helperText:
                      'Answers are checked without regard to case or extra spaces.',
                ),
              )
            else
              _buildChoiceOptions(question),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      child: SizedBox(
        width: width > 980 ? 900 : width * 0.94,
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.quiz_outlined, color: AppTheme.primaryBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Module test: ${widget.moduleTitle}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'Manually author questions for this course module.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    if (_hasAttempts)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: const Text(
                          'An intern has already started this test. Its questions and answer keys are locked to protect that attempt.',
                          style: TextStyle(
                            color: Color(0xFF9A3412),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _titleController,
                            decoration: const InputDecoration(
                              labelText: 'Test title',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 150,
                          child: TextField(
                            controller: _passingScoreController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Pass score (%)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _instructionsController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Instructions (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (var index = 0; index < _questions.length; index++)
                      _buildQuestion(_questions[index], index),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _addQuestion,
                        icon: const Icon(Icons.add),
                        label: const Text('Add question'),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isLoading || _error != null || _isSaving
                        ? null
                        : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_isSaving ? 'Saving...' : 'Save module test'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionDraft {
  String type = 'single_choice';
  int? correctOptionIndex;
  final Set<int> correctOptionIndexes = {};
  final TextEditingController textController = TextEditingController();
  final TextEditingController marksController =
      TextEditingController(text: '1');
  final TextEditingController correctAnswerController =
      TextEditingController();
  final List<_OptionDraft> options = [];

  _QuestionDraft() {
    for (var index = 0; index < 4; index++) {
      addOption();
    }
  }

  factory _QuestionDraft.fromJson(Map<String, dynamic> json) {
    final draft = _QuestionDraft();
    draft.type = safeString(json['question_type'], 'single_choice');
    draft.textController.text = safeString(json['question_text']);
    draft.marksController.text = safeString(json['marks'], '1');
    for (final option in draft.options) {
      option.dispose();
    }
    draft.options.clear();
    final rawOptions = (json['options'] as List?) ?? [];
    for (final option in rawOptions) {
      draft.options.add(_OptionDraft(option.toString()));
    }
    if (draft.type == 'short_answer') {
      draft.correctAnswerController.text =
          safeString(json['correct_answer']);
    } else if (draft.type == 'multiple_choice') {
      final correct = (json['correct_answer'] as List?) ?? [];
      for (var index = 0; index < draft.options.length; index++) {
        if (correct.contains(draft.options[index].textController.text)) {
          draft.correctOptionIndexes.add(index);
        }
      }
    } else {
      final correct = safeString(json['correct_answer']);
      final index = draft.options.indexWhere(
        (option) => option.textController.text == correct,
      );
      if (index >= 0) draft.correctOptionIndex = index;
    }
    return draft;
  }

  void addOption() => options.add(_OptionDraft());

  void removeOption(int index) {
    options.removeAt(index).dispose();
    if (correctOptionIndex == index) {
      correctOptionIndex = null;
    } else if (correctOptionIndex != null && correctOptionIndex! > index) {
      correctOptionIndex = correctOptionIndex! - 1;
    }
    final adjusted = correctOptionIndexes
        .where((selected) => selected != index)
        .map((selected) => selected > index ? selected - 1 : selected)
        .toSet();
    correctOptionIndexes
      ..clear()
      ..addAll(adjusted);
  }

  void dispose() {
    textController.dispose();
    marksController.dispose();
    correctAnswerController.dispose();
    for (final option in options) {
      option.dispose();
    }
  }
}

class _OptionDraft {
  final TextEditingController textController;

  _OptionDraft([String initialText = ''])
      : textController = TextEditingController(text: initialText);

  void dispose() => textController.dispose();
}
