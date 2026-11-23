import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../providers/notification_provider.dart';

class AnnouncementsDialog extends StatelessWidget {
  const AnnouncementsDialog({super.key});

  static Future<void> show(BuildContext context) {
    final notifications = Provider.of<NotificationProvider>(context, listen: false);
    notifications.markAllRead();
    return showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: notifications,
        child: const AnnouncementsDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifications = Provider.of<NotificationProvider>(context);
    final items = notifications.announcements;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: AppTheme.primaryNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.campaign_outlined, color: AppTheme.accentGold, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Announcements & Notices',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text('No announcements right now', style: TextStyle(color: AppTheme.textMuted)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _AnnouncementCard(item: items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _AnnouncementCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final priority = (item['priority'] ?? 'normal').toString();
    Color bg = AppTheme.infoLight;
    Color fg = AppTheme.info;
    if (priority == 'urgent') {
      bg = AppTheme.dangerLight;
      fg = AppTheme.danger;
    } else if (priority == 'high') {
      bg = AppTheme.warningLight;
      fg = AppTheme.warning;
    }

    String dateLabel = '';
    final created = item['created_at'];
    if (created != null) {
      final dt = DateTime.tryParse(created.toString());
      if (dt != null) dateLabel = DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: priority == 'urgent' ? AppTheme.danger.withOpacity(0.4) : AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
                child: Text(priority.toUpperCase(),
                    style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item['title'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item['content'] ?? '',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            '${item['author_name'] ?? 'HR'}${dateLabel.isNotEmpty ? '  •  $dateLabel' : ''}',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = Provider.of<NotificationProvider>(context);
    final banner = notifications.bannerAnnouncement;
    if (banner == null) return const SizedBox.shrink();

    final priority = (banner['priority'] ?? 'normal').toString();
    final isUrgent = priority == 'urgent';
    final color = isUrgent ? AppTheme.danger : AppTheme.primaryBlue;

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.campaign_outlined, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'New announcement: ',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12.5),
                  ),
                  TextSpan(
                    text: banner['title'] ?? '',
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12.5),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => AnnouncementsDialog.show(context),
            child: const Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
            splashRadius: 16,
            tooltip: 'Dismiss',
            onPressed: notifications.dismissBanner,
          ),
        ],
      ),
    );
  }
}