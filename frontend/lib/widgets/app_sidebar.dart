import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'ui_effects.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final role = user.role;

    return Container(
      width: 285,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0C1324), Color(0xFF070B14)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          right: BorderSide(color: Color(0xFF1E293B), width: 1.2),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -110,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.accentGold.withOpacity(0.07),
                      AppTheme.accentGold.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Column(
            children: [
              // Official Brand Header with Logo
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF070B14),
                  border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                ),
                child: Row(
                  children: [
                    // KuhuGrantha Logo Container
                    Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFFD4AF37), width: 1.5),
                      ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.school,
                                    size: 22,
                                    color: Color(0xFF0F172A)),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'KuhuGrantha',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      _roleBadgeColor(role).withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: _roleBadgeColor(role)
                                          .withOpacity(0.4),
                                      width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: _roleBadgeColor(role),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _roleDisplayName(role),
                                      style: TextStyle(
                                        color: _roleBadgeColor(role),
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
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

              // Menu Navigation Items
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                  children: [
                    if (role == 'hr_admin') ...[
                      _sectionHeader('HR ADMINISTRATION'),
                      _navItem(context, auth, 'dashboard', 'Overview Dashboard',
                          Icons.dashboard_rounded),
                      _navItem(context, auth, 'users', 'User Accounts',
                          Icons.manage_accounts_rounded),
                      _navItem(context, auth, 'departments', 'Departments',
                          Icons.domain_rounded),
                      _navItem(context, auth, 'courses', 'Training Courses',
                          Icons.menu_book_rounded),
                      _navItem(context, auth, 'certificates', 'Certificates',
                          Icons.workspace_premium_rounded),
                      _navItem(context, auth, 'announcements', 'Announcements',
                          Icons.campaign_rounded),
                      _sectionHeader('ANALYTICS & AUDIT'),
                      _navItem(context, auth, 'reports', 'Performance Reports',
                          Icons.insert_chart_rounded),
                      _navItem(context, auth, 'audit_logs', 'System Audit Logs',
                          Icons.receipt_long_rounded),
                    ] else if (role == 'team_leader') ...[
                      _sectionHeader('LEADER WORKSPACE'),
                      _navItem(context, auth, 'dashboard', 'Leader Overview',
                          Icons.dashboard_rounded),
                      _navItem(context, auth, 'interns', 'Assigned Interns',
                          Icons.group_rounded),
                      _navItem(context, auth, 'questions', 'Intern Questions',
                          Icons.forum_rounded),
                      _navItem(
                          context,
                          auth,
                          'sop_reader',
                          'SOP Guidelines & Upload',
                          Icons.auto_stories_rounded),
                      _navItem(
                          context,
                          auth,
                          'curriculum_studio',
                          'Post Videos & Curriculum',
                          Icons.video_library_rounded),
                      _navItem(context, auth, 'quizzes',
                          'Assessments & Question Bank', Icons.quiz_rounded),
                      _navItem(
                          context,
                          auth,
                          'tasks',
                          'Practical Tasks & Reviews',
                          Icons.assignment_rounded),
                    ] else ...[
                      _sectionHeader('LEARNING SUITE'),
                      _navItem(context, auth, 'dashboard', 'Intern Dashboard',
                          Icons.dashboard_rounded),
                      _navItem(context, auth, 'my_courses',
                          'My Courses & Lessons', Icons.play_lesson_rounded),
                      _navItem(context, auth, 'sop_reader',
                          'SOP Documents Reader', Icons.auto_stories_rounded),
                      _navItem(context, auth, 'tests', 'Online Assessments',
                          Icons.assignment_turned_in_rounded),
                      _navItem(context, auth, 'tasks', 'Practical Tasks',
                          Icons.task_rounded),
                      _navItem(context, auth, 'qa', 'Ask Team Leader',
                          Icons.forum_rounded),
                      _navItem(context, auth, 'certificate',
                          'Certificate of Completion', Icons.verified_rounded),
                    ],
                  ],
                ),
              ),

              // User Profile Card & Logout
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF070B14),
                  border: Border(top: BorderSide(color: Color(0xFF1E293B))),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: AppTheme.primaryBlue.withOpacity(0.25),
                      child: Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                        style: const TextStyle(
                            color: Color(0xFF93C5FD),
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            user.email,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 10.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded,
                          color: Color(0xFFEF4444), size: 19),
                      tooltip: 'Logout',
                      splashRadius: 18,
                      onPressed: () => auth.logout(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, top: 18, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    AuthProvider auth,
    String viewId,
    String label,
    IconData icon,
  ) {
    return _SidebarNavItem(
      label: label,
      icon: icon,
      isActive: auth.activeView == viewId,
      delay: Duration(milliseconds: (label.hashCode.abs() % 9) * 35),
      onTap: () => auth.setActiveView(viewId),
    );
  }

  String _roleDisplayName(String role) {
    switch (role) {
      case 'hr_admin':
        return 'HR ADMIN';
      case 'team_leader':
        return 'TEAM LEADER';
      case 'intern':
        return 'INTERN';
      default:
        return role.toUpperCase();
    }
  }

  Color _roleBadgeColor(String role) {
    switch (role) {
      case 'hr_admin':
        return const Color(0xFF60A5FA); // Blue
      case 'team_leader':
        return const Color(0xFFFBBF24); // Amber/Gold
      case 'intern':
        return const Color(0xFF34D399); // Green
      default:
        return Colors.white;
    }
  }
}

class _SidebarNavItem extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Duration delay;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.delay,
    required this.onTap,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final textColor = active
        ? Colors.white
        : (_hovered ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1));

    return FadeSlideIn(
      delay: widget.delay,
      offsetY: 10,
      duration: const Duration(milliseconds: 380),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2.5),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : (_hovered
                    ? LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.07),
                          Colors.white.withOpacity(0.02),
                        ],
                      )
                    : null),
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      width: active ? 3.5 : 0,
                      height: 16,
                      margin: EdgeInsets.only(right: active ? 10 : 0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    AnimatedScale(
                      scale: _hovered && !active ? 1.12 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: Icon(
                        widget.icon,
                        color: active
                            ? Colors.white
                            : (_hovered
                                ? const Color(0xFFBFDBFE)
                                : const Color(0xFF94A3B8)),
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: textColor,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 12.5,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: Text(widget.label),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: active ? 16 : 0,
                      child: active
                          ? const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: Colors.white70,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
