import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/kgpl_brand_badge.dart';
import '../../widgets/question_card.dart';

class InternQaView extends StatefulWidget {
  const InternQaView({super.key});

  @override
  State<InternQaView> createState() => _InternQaViewState();
}

class _InternQaViewState extends State<InternQaView> {
  final ApiService _api = ApiService();
  final _questionController = TextEditingController();
  List<Map<String, dynamic>> _questions = [];
  bool _isSending = false;
  bool _isLoading = true;
  String? _loadError;
  String? _sendError;
  String? _success;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final data = await _api.get(ApiConfig.internQuestions);
      final questions = (data['questions'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (!mounted) return;
      setState(() => _questions = questions);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not refresh question history. $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitQuestion() async {
    final text = _questionController.text.trim();
    if (_isSending || _isLoading || text.isEmpty || text.length > 4000) return;

    setState(() {
      _isSending = true;
      _sendError = null;
      _success = null;
    });
    dynamic result;
    try {
      result = await _api.post(ApiConfig.internQuestion, {'question': text});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _sendError = 'Could not send your question. $e';
      });
      return;
    }
    if (!mounted) return;
    _questionController.clear();
    setState(() {
      _isSending = false;
      _success = 'Question submitted to your Team Leader successfully!';
      // Keep the confirmed send visible even if the following refresh fails.
      _questions.insert(0, {
        'id': result['feedback_id'],
        'question': text,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'team_leader_name': null,
        'replies': <dynamic>[],
      });
    });
    await _loadQuestions();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _questionController.text.trim();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const KgplPageHeader(
              title: 'Ask Your Team Leader (Direct Q&A)',
              subtitle:
                  'Raise questions about training videos, practical assignments, or technical blockers.',
              icon: Icons.quiz_outlined,
            ),
            const SizedBox(height: 24),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Post a New Question',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    Semantics(
                        container: true,
                        child: TextField(
                          controller: _questionController,
                          enabled: !_isSending,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 4000,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Question',
                            hintText:
                                'Type your question or query here in detail...',
                          ),
                        )),
                    if (_sendError != null)
                      Text(_sendError!,
                          style: const TextStyle(color: AppTheme.danger)),
                    if (_success != null)
                      Text(_success!,
                          style: const TextStyle(color: AppTheme.success)),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        icon: _isSending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send, size: 16),
                        label:
                            Text(_isSending ? 'Sending...' : 'Send Question'),
                        onPressed: _isSending ||
                                _isLoading ||
                                draft.isEmpty ||
                                draft.length > 4000
                            ? null
                            : _submitQuestion,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              children: [
                const Text('Question History',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                OutlinedButton.icon(
                  onPressed: _isLoading || _isSending ? null : _loadQuestions,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading) const LinearProgressIndicator(),
            if (_loadError != null) ...[
              Text(_loadError!, style: const TextStyle(color: AppTheme.danger)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _isLoading || _isSending ? null : _loadQuestions,
                  child: const Text('Retry'),
                ),
              ),
            ],
            if (!_isLoading && _loadError == null && _questions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child:
                    Text('No questions yet. Send your first question above.'),
              ),
            const SizedBox(height: 12),
            for (final question in _questions)
              QuestionCard(key: ValueKey(question['id']), question: question),
          ],
        ),
      ),
    );
  }
}
