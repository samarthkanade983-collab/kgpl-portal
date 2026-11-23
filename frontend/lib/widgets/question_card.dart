import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme/app_theme.dart';

class QuestionCard extends StatelessWidget {
  const QuestionCard({
    super.key,
    required this.question,
    this.showIntern = false,
    this.onReply,
  });

  final Map<String, dynamic> question;
  final bool showIntern;
  final VoidCallback? onReply;

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null
        ? 'Date unavailable'
        : DateFormat('MMM d, yyyy • h:mm a').format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final replies = (question['replies'] as List?) ?? [];
    final answered = replies.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (showIntern)
                  Text(question['intern_name']?.toString() ?? 'Intern',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(_date(question['created_at']),
                    style: const TextStyle(color: AppTheme.textSecondary)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: answered
                        ? AppTheme.successLight
                        : AppTheme.warningLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(answered ? 'Answered' : 'Pending',
                      style: TextStyle(
                        color: answered ? AppTheme.success : AppTheme.warning,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SelectableText(question['question']?.toString() ?? '',
                semanticsLabel: question['question']?.toString() ?? ''),
            if (replies.isEmpty) ...[
              const SizedBox(height: 12),
              const Text('Awaiting a Team Leader reply.',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ],
            for (final reply in replies) ...[
              const Divider(height: 28),
              Text(question['team_leader_name']?.toString() ?? 'Team Leader',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_date(reply['created_at']),
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              SelectableText(reply['reply']?.toString() ?? '',
                  semanticsLabel: reply['reply']?.toString() ?? ''),
            ],
            if (showIntern) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onReply,
                icon: const Icon(Icons.reply, size: 18),
                label: Text(answered ? 'Reply Again' : 'Reply'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
