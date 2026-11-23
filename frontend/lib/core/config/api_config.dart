import 'package:flutter/foundation.dart';

class ApiConfig {
  // Automatically detects current domain in Web/Browser, falls back to localhost in dev/mobile
  static String get baseUrl {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) return defined;
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && !origin.startsWith('file:') && origin != 'null') {
        return '$origin/api/v1';
      }
    }
    return 'http://localhost:5001/api/v1';
  }

  // Origin that serves static /uploads files (baseUrl without the /api/v1 suffix)
  static String get serverOrigin => baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');

  // Auth endpoints
  static String get login => '$baseUrl/auth/login';
  static String get register => '$baseUrl/auth/register';
  static String get publicDepartments => '$baseUrl/auth/departments';
  static String get me => '$baseUrl/auth/me';

  // Announcements & notifications (all authenticated roles)
  static String get announcements => '$baseUrl/announcements';
  static String get notifications => '$baseUrl/notifications';
  static String get notificationsMarkRead => '$baseUrl/notifications/mark-read';

  // HR endpoints
  static String get hrDashboard => '$baseUrl/hr/dashboard';
  static String get hrUsers => '$baseUrl/hr/users';
  static String get hrBatches => '$baseUrl/hr/batches';
  static String get hrDepartments => '$baseUrl/hr/departments';
  static String get hrCourses => '$baseUrl/hr/courses';
  static String get hrAnnouncements => '$baseUrl/hr/announcements';
  static String get hrReports => '$baseUrl/hr/reports';
  static String get hrReportsExport => '$baseUrl/hr/reports/export-csv';
  static String get hrFeedback => '$baseUrl/hr/feedback';

  static String hrInternName(int id) => '$baseUrl/hr/interns/$id/name';
  static String get hrCertificates => '$baseUrl/hr/certificates';
  static String hrCertificate(int internUserId) => '$baseUrl/hr/certificates/$internUserId';
  static String get hrAuditLogs => '$baseUrl/hr/audit-logs';
  static String get hrAssignInterns => '$baseUrl/hr/assign-interns';

  // Team Leader endpoints
  static String get tlDashboard => '$baseUrl/tl/dashboard';
  static String get tlInterns => '$baseUrl/tl/interns';
  static String get tlAssignCourse => '$baseUrl/tl/assign-course';
  static String get tlQuizzes => '$baseUrl/tl/quizzes';
  static String get tlSchedules => '$baseUrl/tl/schedules';
  static String get tlTasks => '$baseUrl/tl/tasks';
  static String get tlFeedback => '$baseUrl/tl/feedback';
  static String get tlQuestions => '$baseUrl/tl/questions';

  // Intern endpoints
  static String get internDashboard => '$baseUrl/intern/dashboard';
  static String get internCourses => '$baseUrl/intern/courses';
  static String get internVideoInit => '$baseUrl/intern/video/init';
  static String get internVideoHeartbeat => '$baseUrl/intern/video/heartbeat';
  static String get internTests => '$baseUrl/intern/tests';
  static String get internTestStart => '$baseUrl/intern/tests/start';
  static String get internTestSubmit => '$baseUrl/intern/tests/submit';
  static String get internTasks => '$baseUrl/intern/tasks';
  static String get internTaskSubmit => '$baseUrl/intern/tasks/submit';
  static String get internQuestion => '$baseUrl/intern/question';
  static String get internQuestions => '$baseUrl/intern/questions';
  static String get internCertificate => '$baseUrl/intern/certificate';
  static String get internSops => '$baseUrl/intern/sops';
  static String internSopPreview(int id) => '$baseUrl/intern/sops/$id/preview';
  static String get internMarkSopRead => '$baseUrl/intern/sops/mark-read';
  static String hrCourseModuleTest(int moduleId) =>
      '$baseUrl/hr/courses/modules/$moduleId/test';
  static String internCourseModuleTestStart(int testId) =>
      '$baseUrl/intern/course-module-tests/$testId/start';
  static String internCourseModuleTestSubmit(int testId) =>
      '$baseUrl/intern/course-module-tests/$testId/submit';

  // Team Leader SOP & Video Upload
  static String get tlSops => '$baseUrl/tl/sops';
  static String get tlPostVideo => '$baseUrl/tl/courses/videos';

  // Resumable chunked video uploads (init, status, chunk, complete, abort)
  static String get videoUploads => '$baseUrl/uploads/videos';

}
