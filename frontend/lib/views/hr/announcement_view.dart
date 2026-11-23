import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/feedback.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/kgpl_brand_badge.dart';
import '../../widgets/ui_effects.dart';

class AnnouncementView extends StatefulWidget {
  const AnnouncementView({super.key});

  @override
  State<AnnouncementView> createState() => _AnnouncementViewState();
}

class _AnnouncementViewState extends State<AnnouncementView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _announcements = [];

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
  }

  Future<void> _fetchAnnouncements() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get(ApiConfig.hrAnnouncements);
      setState(() {
        _announcements = res['announcements'] ?? [];
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _showCreateDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final scaffoldContext = context;
    String priority = 'normal';
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Post Announcement'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Title *')),
                const SizedBox(height: 14),
                TextField(
                    controller: contentController,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Content *')),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => priority = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (titleController.text.trim().isEmpty ||
                          contentController.text.trim().isEmpty) {
                        showAppFeedback(scaffoldContext,
                            'Please enter both a title and content.',
                            isError: true);
                        return;
                      }
                      setDialogState(() => submitting = true);
                      final notifications = Provider.of<NotificationProvider>(
                          scaffoldContext,
                          listen: false);
                      try {
                        await _api.post(ApiConfig.hrAnnouncements, {
                          'title': titleController.text.trim(),
                          'content': contentController.text.trim(),
                          'priority': priority,
                          'is_global': 1,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _fetchAnnouncements();
                        notifications.refresh();
                        if (scaffoldContext.mounted)
                          showAppFeedback(scaffoldContext,
                              'Announcement published successfully.');
                      } catch (e) {
                        if (ctx.mounted)
                          setDialogState(() => submitting = false);
                        if (scaffoldContext.mounted)
                          showAppFeedback(
                              scaffoldContext, 'Failed to publish: $e',
                              isError: true);
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Publish'),
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
            title: 'Company Announcements & Notices',
            subtitle: 'Post and manage organization-wide communications',
            icon: Icons.campaign_outlined,
            actions: [
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Post Announcement'),
                onPressed: _showCreateDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentGold,
                  foregroundColor: AppTheme.primaryNavy,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _announcements.isEmpty
                    ? const Center(child: Text('No announcements posted yet'))
                    : ListView.separated(
                        itemCount: _announcements.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          final a = _announcements[i];
                          final priority = a['priority'] ?? 'normal';

                          return FadeSlideIn(
                            delay: Duration(milliseconds: 60 * i),
                            child: HoverLift(
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: AppTheme.cardBackground,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: priority == 'urgent'
                                        ? AppTheme.danger.withOpacity(0.4)
                                        : AppTheme.borderColor,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        _priorityBadge(priority),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            a['title'] ?? '',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15),
                                          ),
                                        ),
                                        Text(
                                          'Posted by ${a['author_name'] ?? 'HR'}',
                                          style: const TextStyle(
                                              color: AppTheme.textMuted,
                                              fontSize: 11),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      a['content'] ?? '',
                                      style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _priorityBadge(String priority) {
    Color bg = AppTheme.infoLight;
    Color fg = AppTheme.info;

    if (priority == 'urgent') {
      bg = AppTheme.dangerLight;
      fg = AppTheme.danger;
    } else if (priority == 'high') {
      bg = AppTheme.warningLight;
      fg = AppTheme.warning;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(priority.toUpperCase(),
          style:
              TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
