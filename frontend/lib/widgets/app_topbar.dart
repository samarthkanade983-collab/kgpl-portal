import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/config/api_config.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import 'announcements_dialog.dart';

class AppTopbar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const AppTopbar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final notifications = Provider.of<NotificationProvider>(context);
    final user = auth.currentUser;

    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1526),
        border: const Border(
            bottom: BorderSide(color: Color(0xFF1E293B), width: 1.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(
          children: [
            // View title with indicator
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.4),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    title,
                    key: ValueKey(title),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),

            const Spacer(),

                  // Notification Bell with Badge
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF131D31),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF24324D)),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.notifications_none_rounded,
                              color: Color(0xFF94A3B8), size: 20),
                          tooltip: 'Announcements & Notifications',
                          splashRadius: 20,
                          onPressed: () => AnnouncementsDialog.show(context),
                        ),
                      ),
                      if (notifications.hasUnread)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            constraints: const BoxConstraints(minWidth: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: notifications.unreadCount > 0
                                ? Text(
                                    notifications.unreadCount > 9
                                        ? '9+'
                                        : '${notifications.unreadCount}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold),
                                  )
                                : const SizedBox(width: 6, height: 6),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(width: 14),

                  // User info capsule
                  if (user != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131D31),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF24324D)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor:
                                AppTheme.primaryBlue.withOpacity(0.15),
                            child: (user.profilePhoto ?? '').isNotEmpty
                                ? ClipOval(
                                    child: Image.network(
                                      '${ApiConfig.serverOrigin}${user.profilePhoto}',
                                      width: 26,
                                      height: 26,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _initial(
                                          user.name),
                                    ),
                                  )
                                : _initial(user.name),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                user.name,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              Text(
                                user.role.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: user.role == 'hr_admin'
                                      ? const Color(0xFF2563EB)
                                      : user.role == 'team_leader'
                                          ? const Color(0xFFD97706)
                                          : const Color(0xFF059669),
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
          ],
        ),
      ),
    );
  }

  Widget _initial(String name) {
    return Text(
      name.isNotEmpty ? name[0].toUpperCase() : 'U',
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        color: AppTheme.primaryBlue,
      ),
    );
  }
}
