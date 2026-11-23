import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/notification_provider.dart';
import 'widgets/app_sidebar.dart';
import 'widgets/app_topbar.dart';
import 'widgets/announcements_dialog.dart';
import 'widgets/ui_effects.dart';

// Auth View
import 'views/auth/login_view.dart';

// HR Admin Views
import 'views/hr/hr_dashboard_view.dart';
import 'views/hr/user_management_view.dart';
import 'views/hr/department_management_view.dart';
import 'views/hr/course_management_view.dart';
import 'views/hr/announcement_view.dart';
import 'views/hr/report_analytics_view.dart';
import 'views/hr/audit_logs_view.dart';
import 'views/hr/certificates_view.dart';

// Team Leader Views
import 'views/team_leader/tl_dashboard_view.dart';
import 'views/team_leader/intern_monitoring_view.dart';
import 'views/team_leader/quiz_assessment_view.dart';
import 'views/team_leader/task_management_view.dart';
import 'views/team_leader/question_inbox_view.dart';

// Intern Views
import 'views/intern/intern_dashboard_view.dart';
import 'views/intern/my_courses_view.dart';
import 'views/intern/course_player_view.dart';
import 'views/intern/course_module_test_runner_view.dart';
import 'views/intern/sop_reader_view.dart';
import 'views/intern/test_runner_view.dart';
import 'views/intern/practical_tasks_view.dart';
import 'views/intern/intern_qa_view.dart';
import 'views/intern/certificate_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..initAuth()),
        ChangeNotifierProxyProvider<AuthProvider, NotificationProvider>(
          create: (_) => NotificationProvider(),
          update: (_, auth, notifications) => notifications!..syncAuth(auth),
        ),
      ],
      child: const KgplPortalApp(),
    ),
  );
}

class KgplPortalApp extends StatelessWidget {
  const KgplPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KGPL Intern Training & Management Portal',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const PortalRootRouter(),
    );
  }
}

class PortalRootRouter extends StatelessWidget {
  const PortalRootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    if (!auth.isAuthenticated) {
      return const LoginView();
    }

    final user = auth.currentUser!;
    final role = user.role;
    final activeView = auth.activeView;

    // Determine current view widget and title
    Widget contentWidget;
    String topbarTitle = 'Dashboard';

    if (role == 'hr_admin') {
      switch (activeView) {
        case 'users':
          topbarTitle = 'User Account Management';
          contentWidget = const UserManagementView();
          break;
        case 'departments':
          topbarTitle = 'Departments';
          contentWidget = const DepartmentManagementView();
          break;
        case 'courses':
          topbarTitle = 'Training Courses & Curriculum';
          contentWidget = const CourseManagementView();
          break;
        case 'certificates':
          topbarTitle = 'Intern Completion Certificates';
          contentWidget = const CertificateManagementView();
          break;
        case 'announcements':
          topbarTitle = 'Company Bulletins & Announcements';
          contentWidget = const AnnouncementView();
          break;
        case 'reports':
          topbarTitle = 'Intern Performance Reports & Analytics';
          contentWidget = const ReportAnalyticsView();
          break;
        case 'audit_logs':
          topbarTitle = 'Security Audit Trail & Governance Log';
          contentWidget = const AuditLogsView();
          break;
        case 'dashboard':
        default:
          topbarTitle = 'HR Executive Overview Dashboard';
          contentWidget = const HrDashboardView();
          break;
      }
    } else if (role == 'team_leader') {
      switch (activeView) {
        case 'questions':
          topbarTitle = 'Intern Questions';
          contentWidget = const QuestionInboxView();
          break;
        case 'interns':
          topbarTitle = 'Assigned Intern Progress & Monitoring';
          contentWidget = const InternMonitoringView();
          break;
        case 'sop_reader':
          topbarTitle = 'Standard Operating Procedures (SOP)';
          contentWidget = const SopReaderView();
          break;
        case 'quizzes':
          topbarTitle = 'Quizzes, Question Banks & Online Tests';
          contentWidget = const QuizAssessmentView();
          break;
        case 'tasks':
          topbarTitle = 'Practical Tasks & Submission Evaluation';
          contentWidget = const TaskManagementView();
          break;
        case 'curriculum_studio':
          topbarTitle = 'Video Curriculum & Intern Lessons Studio';
          contentWidget = const CourseManagementView();
          break;
        case 'dashboard':
        default:
          topbarTitle = 'Team Leader Dashboard';
          contentWidget = const TlDashboardView();
          break;
      }
    } else {
      // Intern
      switch (activeView) {
        case 'my_courses':
          topbarTitle = 'My Assigned Learning Courses';
          contentWidget = const MyCoursesView();
          break;
        case 'sop_reader':
          topbarTitle = 'SOP Documents & Interactive Reader';
          contentWidget = const SopReaderView();
          break;
        case 'course_player':
          topbarTitle = 'Video Lessons';
          contentWidget = CoursePlayerView(courseId: auth.activeCourseId ?? 1);
          break;
        case 'course_module_test':
          topbarTitle = 'Course Module Test';
          contentWidget = CourseModuleTestRunnerView(
            testId: auth.activeCourseModuleTestId ?? 0,
          );
          break;
        case 'tests':
          topbarTitle = 'Online Assessments';
          contentWidget = const TestRunnerView();
          break;
        case 'test_runner':
          topbarTitle = 'Online Assessment';
          contentWidget =
              TestRunnerView(initialScheduleId: auth.activeTestScheduleId);
          break;
        case 'tasks':
          topbarTitle = 'Practical Tasks & Assignments';
          contentWidget = const PracticalTasksView();
          break;
        case 'qa':
          topbarTitle = 'Ask Team Leader (Direct Q&A)';
          contentWidget = const InternQaView();
          break;
        case 'certificate':
          topbarTitle = 'Internship Completion Certificate';
          contentWidget = const CertificateView();
          break;
        case 'dashboard':
        default:
          topbarTitle = 'Intern Learning Portal Dashboard';
          contentWidget = const InternDashboardView();
          break;
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              const AppSidebar(),
              Expanded(
                child: Column(
                  children: [
                    AppTopbar(title: topbarTitle),
                    const AnnouncementBanner(),
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const Positioned(
                            right: -80,
                            bottom: -110,
                            child: ExcludeSemantics(
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: 0.06,
                                  child: Image(
                                    image: AssetImage('assets/images/logo.png'),
                                    width: 540,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          AppPageTransition(
                            viewKey: '${role}_$activeView',
                            child: contentWidget,
                          ),
                        ],
                      ),
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
}
