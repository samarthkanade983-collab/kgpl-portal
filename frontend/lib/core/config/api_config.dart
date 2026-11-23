class ApiConfig {
  // Override at build time with: --dart-define=API_BASE_URL=http://host:port/api/v1
  static const String baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:5001/api/v1');

  // Origin that serves static /uploads files (baseUrl without the /api/v1 suffix)
  static String get serverOrigin => baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');

  // Auth endpoints
  static const String login = '$baseUrl/auth/login';
  static const String register = '$baseUrl/auth/register';
  static const String publicDepartments = '$baseUrl/auth/departments';
  static const String me = '$baseUrl/auth/me';

  // Announcements & notifications (all authenticated roles)
  static const String announcements = '$baseUrl/announcements';
  static const String notifications = '$baseUrl/notifications';
  static const String notificationsMarkRead = '$baseUrl/notifications/mark-read';

  // HR endpoints
  static const String hrDashboard = '$baseUrl/hr/dashboard';
  static const String hrUsers = '$baseUrl/hr/users';
  static const String hrBatches = '$baseUrl/hr/batches';
  static const String hrDepartments = '$baseUrl/hr/departments';
  static const String hrCourses = '$baseUrl/hr/courses';
  static const String hrAnnouncements = '$baseUrl/hr/announcements';
  static const String hrReports = '$baseUrl/hr/reports';
  static const String hrReportsExport = '$baseUrl/hr/reports/export-csv';
  static const String hrFeedback = '$baseUrl/hr/feedback';

  static String hrInternName(int id) => '$baseUrl/hr/interns/$id/name';
  static const String hrCertificates = '$baseUrl/hr/certificates';
  static String hrCertificate(int internUserId) => '$baseUrl/hr/certificates/$internUserId';
  static const String hrAuditLogs = '$baseUrl/hr/audit-logs';
  static const String hrAssignInterns = '$baseUrl/hr/assign-interns';

  // Team Leader endpoints
  static const String tlDashboard = '$baseUrl/tl/dashboard';
  static const String tlInterns = '$baseUrl/tl/interns';
  static const String tlAssignCourse = '$baseUrl/tl/assign-course';
  static const String tlQuizzes = '$baseUrl/tl/quizzes';
  static const String tlSchedules = '$baseUrl/tl/schedules';
  static const String tlTasks = '$baseUrl/tl/tasks';
  static const String tlFeedback = '$baseUrl/tl/feedback';
  static const String tlQuestions = '$baseUrl/tl/questions';

  // Intern endpoints
  static const String internDashboard = '$baseUrl/intern/dashboard';
  static const String internCourses = '$baseUrl/intern/courses';
  static const String internVideoInit = '$baseUrl/intern/video/init';
  static const String internVideoHeartbeat = '$baseUrl/intern/video/heartbeat';
  static const String internTests = '$baseUrl/intern/tests';
  static const String internTestStart = '$baseUrl/intern/tests/start';
  static const String internTestSubmit = '$baseUrl/intern/tests/submit';
  static const String internTasks = '$baseUrl/intern/tasks';
  static const String internTaskSubmit = '$baseUrl/intern/tasks/submit';
  static const String internQuestion = '$baseUrl/intern/question';
  static const String internQuestions = '$baseUrl/intern/questions';
  static const String internCertificate = '$baseUrl/intern/certificate';
  static const String internSops = '$baseUrl/intern/sops';
  static String internSopPreview(int id) => '$baseUrl/intern/sops/$id/preview';
  static const String internMarkSopRead = '$baseUrl/intern/sops/mark-read';
  static String hrCourseModuleTest(int moduleId) =>
      '$baseUrl/hr/courses/modules/$moduleId/test';
  static String internCourseModuleTestStart(int testId) =>
      '$baseUrl/intern/course-module-tests/$testId/start';
  static String internCourseModuleTestSubmit(int testId) =>
      '$baseUrl/intern/course-module-tests/$testId/submit';

  // Team Leader SOP & Video Upload
  static const String tlSops = '$baseUrl/tl/sops';
  static const String tlPostVideo = '$baseUrl/tl/courses/videos';

  // Resumable chunked video uploads (init, status, chunk, complete, abort)
  static const String videoUploads = '$baseUrl/uploads/videos';

}
