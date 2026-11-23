import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/kgpl_brand_badge.dart';
import '../../widgets/question_card.dart';

class QuestionInboxView extends StatefulWidget {
  const QuestionInboxView({super.key});

  @override
  State<QuestionInboxView> createState() => _QuestionInboxViewState();
}

class _QuestionInboxViewState extends State<QuestionInboxView> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;
  bool _replyOpen = false;
  String _filter = 'All';
  String? _loadError;
  String? _success;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final data = await _api.get(ApiConfig.tlQuestions);
      final questions = (data['questions'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (!mounted) return;
      setState(() => _questions = questions);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not refresh the question inbox. $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reply(Map<String, dynamic> question) async {
    if (_replyOpen || _isLoading) return;
    setState(() => _replyOpen = true);
    final reply = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReplyDialog(question: question),
    );
    if (!mounted) return;
    setState(() {
      _replyOpen = false;
      if (reply != null) {
        // A confirmed POST is authoritative; don't depend on another fetch.
        question['replies'] = [...(question['replies'] as List? ?? []), reply];
        _success = 'Reply sent successfully.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _questions.where((question) {
      final answered = (question['replies'] as List? ?? []).isNotEmpty;
      return _filter == 'All' || (_filter == 'Answered' ? answered : !answered);
    }).toList();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const KgplPageHeader(
              title: 'Intern Questions',
              subtitle:
                  'Review questions from your assigned interns and reply directly.',
              icon: Icons.forum_outlined,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final filter in ['All', 'Pending', 'Answered'])
                  ChoiceChip(
                    label: Text(filter),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
                OutlinedButton.icon(
                  onPressed: _isLoading || _replyOpen ? null : _loadQuestions,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_success != null) ...[
              Text(_success!, style: const TextStyle(color: AppTheme.success)),
              const SizedBox(height: 12),
            ],
            if (_isLoading) const LinearProgressIndicator(),
            if (_loadError != null) ...[
              Text(_loadError!, style: const TextStyle(color: AppTheme.danger)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _isLoading || _replyOpen ? null : _loadQuestions,
                  child: const Text('Retry'),
                ),
              ),
            ],
            if (!_isLoading && _loadError == null && visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(_questions.isEmpty
                    ? 'No questions from your assigned interns yet.'
                    : 'No ${_filter.toLowerCase()} questions.'),
              ),
            const SizedBox(height: 12),
            for (final question in visible)
              QuestionCard(
                key: ValueKey(question['id']),
                question: question,
                showIntern: true,
                onReply:
                    _isLoading || _replyOpen ? null : () => _reply(question),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReplyDialog extends StatefulWidget {
  const _ReplyDialog({required this.question});

  final Map<String, dynamic> question;

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  final _controller = TextEditingController();
  bool _isSending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reply = _controller.text.trim();
    if (_isSending || reply.isEmpty || reply.length > 4000) return;
    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      final data = await ApiService().post(
        '${ApiConfig.tlQuestions}/${widget.question['id']}/replies',
        {'reply': reply},
      );
      if (!mounted) return;
      Navigator.of(context)
          .pop(Map<String, dynamic>.from(data['reply'] as Map));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error = 'Could not send your reply. $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _controller.text.trim();
    return PopScope(
      canPop: !_isSending,
      child: AlertDialog(
        title: Text('Reply to ${widget.question['intern_name'] ?? 'Intern'}'),
        scrollable: true,
        content: SizedBox(
          width: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(widget.question['question']?.toString() ?? '',
                  semanticsLabel:
                      widget.question['question']?.toString() ?? ''),
              const SizedBox(height: 20),
              Semantics(
                  container: true,
                  child: TextField(
                    controller: _controller,
                    enabled: !_isSending,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 4000,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Your reply',
                      hintText: 'Write a helpful response...',
                    ),
                  )),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSending ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: _isSending || draft.isEmpty || draft.length > 4000
                ? null
                : _send,
            icon: _isSending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send, size: 16),
            label: Text(_isSending ? 'Sending...' : 'Send Reply'),
          ),
        ],
      ),
    );
  }
}
