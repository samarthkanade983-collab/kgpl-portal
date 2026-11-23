import { Router, raw } from 'express';
import { authenticateToken, requireRole } from '../middleware/auth.js';
import { loginRateLimit, apiRateLimit, registrationRateLimit } from '../middleware/rateLimit.js';
import * as authController from '../controllers/auth.controller.js';
import * as hrController from '../controllers/hr.controller.js';
import * as tlController from '../controllers/team_leader.controller.js';
import * as internController from '../controllers/intern.controller.js';
import * as announcementController from '../controllers/announcement.controller.js';
import * as questionsController from '../controllers/questions.controller.js';
import * as videoUploadController from '../controllers/video_upload.controller.js';
import * as courseModuleTestController from '../controllers/courseModuleTest.controller.js';
const router = Router();
// =============================================================================
// RESUMABLE VIDEO UPLOADS (chunked, disk-backed)
// Mounted before the generic limiter: a single 30 GB upload legitimately sends
// hundreds of chunk requests and must not trip the 600/min API budget.
// =============================================================================
const mediaUploadAccess = [authenticateToken, requireRole(['hr_admin', 'team_leader'])];
router.post('/uploads/videos', ...mediaUploadAccess, videoUploadController.initVideoUpload);
router.get('/uploads/videos/:id', ...mediaUploadAccess, videoUploadController.getVideoUploadStatus);
router.put('/uploads/videos/:id/chunk', ...mediaUploadAccess, raw({ type: 'application/octet-stream', limit: '40mb' }), videoUploadController.putVideoChunk);
router.post('/uploads/videos/:id/complete', ...mediaUploadAccess, videoUploadController.finishVideoUpload);
router.delete('/uploads/videos/:id', ...mediaUploadAccess, videoUploadController.cancelVideoUpload);
router.get('/intern/video/:video_id/stream', internController.streamVideo);
router.use(apiRateLimit);
// =============================================================================
// AUTHENTICATION ROUTES (Public & Profile)
// =============================================================================
router.post('/auth/login', loginRateLimit, authController.login);
router.post('/auth/register', registrationRateLimit, authController.register);
router.get('/auth/departments', authController.getPublicDepartments);
router.get('/auth/me', authenticateToken, authController.me);
// =============================================================================
// MODULE 1: HR ADMIN ROUTES
// =============================================================================
const hrOnly = [authenticateToken, requireRole(['hr_admin'])];
const tlAccess = [authenticateToken, requireRole(['team_leader', 'hr_admin'])];
// Dashboard & Analytics
router.get('/hr/dashboard', ...hrOnly, hrController.getDashboardMetrics);
// User Accounts Management
router.get('/hr/users', ...hrOnly, hrController.getUsers);
router.post('/hr/users', ...hrOnly, hrController.createUser);
router.put('/hr/users/:id', ...hrOnly, hrController.updateUser);
router.patch('/hr/users/:id/toggle-status', ...hrOnly, hrController.toggleUserStatus);
router.post('/hr/users/:id/reset-password', ...hrOnly, hrController.resetUserPassword);
router.delete('/hr/users/:id', ...hrOnly, hrController.deleteUser);
// Batches & Departments
router.get('/hr/batches', ...tlAccess, hrController.getBatches);
router.post('/hr/batches', ...hrOnly, hrController.createBatch);
router.put('/hr/batches/:id', ...hrOnly, hrController.updateBatch);
router.delete('/hr/batches/:id', ...hrOnly, hrController.deleteBatch);
router.get('/hr/departments', ...tlAccess, hrController.getDepartments);
router.post('/hr/departments', ...hrOnly, hrController.createDepartment);
router.delete('/hr/departments/:id', ...hrOnly, hrController.deleteDepartment);
router.post('/hr/assign-interns', ...hrOnly, hrController.assignInternsToTL);
// Training Courses, Videos & Materials (HR admins and Team Leaders can author content)
router.get('/hr/courses/templates', ...tlAccess, hrController.getCourseTemplates);
router.get('/hr/courses/live-watch', ...tlAccess, hrController.getLiveWatch);
router.get('/hr/courses', ...tlAccess, hrController.getCourses);
router.get('/hr/courses/:id', ...tlAccess, hrController.getCourseDetails);
router.post('/hr/courses/:id/apply-template', ...tlAccess, hrController.applyCourseTemplate);
router.post('/hr/courses', ...tlAccess, hrController.createCourse);
router.delete('/hr/courses/:id', ...tlAccess, hrController.deleteCourse);
router.post('/hr/courses/modules', ...tlAccess, hrController.addModule);
router.delete('/hr/courses/modules/:id', ...tlAccess, hrController.deleteModule);
router.get('/hr/courses/modules/:moduleId/test', ...tlAccess, courseModuleTestController.getModuleTestForAuthoring);
router.put('/hr/courses/modules/:moduleId/test', ...tlAccess, courseModuleTestController.saveModuleTest);
router.post('/hr/courses/videos', ...tlAccess, hrController.addVideo);
router.delete('/hr/courses/videos/:id', ...tlAccess, hrController.deleteVideo);
router.post('/hr/courses/materials', ...tlAccess, hrController.addMaterial);
// Announcements
router.get('/hr/announcements', ...hrOnly, hrController.getAnnouncements);
router.post('/hr/announcements', ...hrOnly, hrController.createAnnouncement);
router.delete('/hr/announcements/:id', ...hrOnly, hrController.deleteAnnouncement);
// Reports & Audit Logs
router.get('/hr/reports', ...hrOnly, hrController.getReports);
router.get('/hr/reports/export-csv', ...hrOnly, hrController.exportReportsCsv);
router.get('/hr/feedback', ...hrOnly, hrController.getFeedback);
router.patch('/hr/interns/:id/name', ...hrOnly, hrController.updateInternName);
// Certificate content editing
router.get('/hr/certificates', ...hrOnly, hrController.listCertificates);
router.put('/hr/certificates/:internId', ...hrOnly, hrController.updateCertificate);
router.delete('/hr/certificates/:internId', ...hrOnly, hrController.resetCertificate);
router.get('/hr/audit-logs', ...hrOnly, hrController.getAuditLogs);
router.get('/hr/telemetry/nosql-usage', ...tlAccess, hrController.getNoSqlUsageStats);
// =============================================================================
// MODULE 2: TEAM LEADER ROUTES
// =============================================================================
// Dashboard (6 KPIs)
router.get('/tl/dashboard', ...tlAccess, tlController.getTLDashboardMetrics);
// Assigned Interns & Detailed Dossier
router.get('/tl/interns', ...tlAccess, tlController.getAssignedInterns);
router.get('/tl/interns/:intern_id', ...tlAccess, tlController.getInternDossier);
router.post('/tl/assign-course', ...tlAccess, tlController.assignCourse);
// Quizzes & Question Banks (Question Paper Studio)
router.get('/tl/quizzes', ...tlAccess, tlController.getQuizzes);
router.get('/tl/quizzes/:id', ...tlAccess, tlController.getQuizDetails);
router.post('/tl/quizzes', ...tlAccess, tlController.createQuiz);
router.put('/tl/quizzes/:id', ...tlAccess, tlController.updateQuiz);
router.delete('/tl/quizzes/:id', ...tlAccess, tlController.deleteQuiz);
router.post('/tl/quizzes/questions', ...tlAccess, tlController.addQuizQuestion);
router.put('/tl/quizzes/questions/:question_id', ...tlAccess, tlController.updateQuizQuestion);
router.delete('/tl/quizzes/questions/:question_id', ...tlAccess, tlController.deleteQuizQuestion);
router.post('/tl/quizzes/:id/reorder-questions', ...tlAccess, tlController.reorderQuizQuestions);
// Online Test Scheduling & Results
router.get('/tl/schedules', ...tlAccess, tlController.getTestSchedules);
router.post('/tl/schedules', ...tlAccess, tlController.createTestSchedule);
router.delete('/tl/schedules/:schedule_id', ...tlAccess, tlController.deleteTestSchedule);
router.get('/tl/schedules/:schedule_id/attempts', ...tlAccess, tlController.getScheduleAttempts);
router.post('/tl/attempts/:attempt_id/review', ...tlAccess, tlController.reviewQuizAttempt);
router.get('/tl/quiz-results', ...tlAccess, tlController.getQuizResults);
// Practical Tasks & Submissions Evaluation
router.get('/tl/tasks', ...tlAccess, tlController.getTasks);
router.post('/tl/tasks', ...tlAccess, tlController.createTask);
router.post('/tl/tasks/:id/assign', ...tlAccess, tlController.assignTaskToInterns);
router.delete('/tl/tasks/:id', ...tlAccess, tlController.deleteTask);
router.get('/tl/tasks/:task_id/submissions', ...tlAccess, tlController.getTaskSubmissions);
router.post('/tl/submissions/:submission_id/grade', ...tlAccess, tlController.gradeTaskSubmission);
// Feedback
router.post('/tl/feedback', ...tlAccess, tlController.submitFeedback);
router.get('/tl/questions', authenticateToken, requireRole(['team_leader']), questionsController.getTeamLeaderQuestions);
router.post('/tl/questions/:id/replies', authenticateToken, requireRole(['team_leader']), questionsController.replyToQuestion);
// SOP Management & Direct File Upload (PDF, Excel, Photo, Doc)
router.get('/tl/sops', ...tlAccess, tlController.getSops);
router.post('/tl/sops', ...tlAccess, tlController.uploadSop);
router.delete('/tl/sops/:id', ...tlAccess, tlController.deleteSop);
// Video Posting to Intern Curriculum
router.post('/tl/courses/videos', ...tlAccess, tlController.uploadVideo);
// =============================================================================
// MODULE 3: INTERN ROUTES & LEARNING SUITE
// =============================================================================
const internAccess = [authenticateToken, requireRole(['intern'])];
const sopAccess = [authenticateToken, requireRole(['intern', 'team_leader', 'hr_admin'])];
// Dashboard
router.get('/intern/dashboard', ...internAccess, internController.getInternDashboardMetrics);
// Courses & Video Player Tracking
router.get('/intern/courses', ...internAccess, internController.getAssignedCourses);
router.get('/intern/courses/:course_id', ...internAccess, internController.getCoursePlaybackData);
router.post('/intern/course-module-tests/:testId/start', ...internAccess, courseModuleTestController.startInternModuleTest);
router.post('/intern/course-module-tests/:testId/submit', ...internAccess, courseModuleTestController.submitInternModuleTest);
router.post('/intern/video/init', ...internAccess, internController.initVideoSession);
router.post('/intern/video/heartbeat', ...internAccess, internController.recordVideoHeartbeat);
// Online MCQ Quizzes
router.get('/intern/tests', ...internAccess, internController.getAvailableTests);
router.post('/intern/tests/start', ...internAccess, internController.startTestAttempt);
router.post('/intern/tests/submit', ...internAccess, internController.submitTestAttempt);
// Tasks & Submissions
router.get('/intern/tasks', ...internAccess, internController.getAssignedTasks);
router.post('/intern/tasks/submit', ...internAccess, internController.submitTaskSolution);
// SOP Documents & Compliance (Accessible by intern, TL, and HR)
router.get('/intern/sops', ...sopAccess, internController.getSopMaterials);
router.get('/intern/sops/:id/preview', ...sopAccess, internController.getSopPreview);
router.post('/intern/sops/mark-read', ...internAccess, internController.markSopRead);
// Q&A with TL & Certificate
router.post('/intern/question', ...internAccess, internController.postQuestionToTL);
router.get('/intern/questions', ...internAccess, questionsController.getInternQuestions);
router.get('/intern/certificate', ...internAccess, internController.getCertificateData);
// =============================================================================
// MODULE 4: ANNOUNCEMENTS & NOTIFICATIONS (All authenticated roles)
// =============================================================================
router.get('/announcements', authenticateToken, announcementController.getActiveAnnouncements);
router.get('/notifications', authenticateToken, announcementController.getMyNotifications);
router.post('/notifications/mark-read', authenticateToken, announcementController.markNotificationsRead);
// Express 4 ignores rejected promises from async handlers, which would crash the
// process; forward them to the global error handler instead.
for (const layer of router.stack) {
    for (const routeLayer of layer.route?.stack ?? []) {
        const handler = routeLayer.handle;
        routeLayer.handle = (req, res, next) => {
            try {
                const result = handler(req, res, next);
                if (result && typeof result.catch === 'function')
                    result.catch(next);
            }
            catch (err) {
                next(err);
            }
        };
    }
}
export default router;
