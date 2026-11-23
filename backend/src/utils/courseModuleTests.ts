import { pool } from '../config/db.js';

export type CourseModuleQuestionType =
  | 'single_choice'
  | 'multiple_choice'
  | 'short_answer';

export interface CourseModuleQuestion {
  id?: number;
  question_text: string;
  question_type: CourseModuleQuestionType;
  options?: string[];
  correct_answer: string | string[];
  marks: number;
}

export interface CourseModuleProgressRow {
  module_id: number | string;
  module_title: string;
  total_videos: number | string;
  completed_videos: number | string;
  test_id: number | string | null;
  test_title: string | null;
  passing_score: number | string | null;
  question_count: number | string;
  attempt_id: number | string | null;
  attempt_status: string | null;
  score: number | string | null;
  is_passed: number | boolean | null;
}

export interface CourseModuleGate {
  moduleId: number;
  isUnlocked: boolean;
  videosComplete: boolean;
  hasTest: boolean;
  testPassed: boolean;
  canTakeTest: boolean;
  canResumeTest: boolean;
  attemptStatus: string | null;
  score: number | null;
  lockReason: string | null;
  testLockReason: string | null;
}

export async function getCourseModuleProgress(
  userId: number,
  courseId: number
): Promise<CourseModuleProgressRow[]> {
  const [rows]: any = await pool.query(
    `SELECT cm.id AS module_id, cm.title AS module_title,
            COUNT(DISTINCT v.id) AS total_videos,
            COUNT(DISTINCT CASE WHEN vwl.is_completed = 1 THEN v.id END) AS completed_videos,
            t.id AS test_id, t.title AS test_title, t.passing_score,
            COUNT(DISTINCT q.id) AS question_count,
            a.id AS attempt_id, a.status AS attempt_status, a.score, a.is_passed
     FROM course_modules cm
     LEFT JOIN videos v ON v.module_id = cm.id
     LEFT JOIN video_watch_logs vwl
       ON vwl.video_id = v.id AND vwl.user_id = ?
     LEFT JOIN course_module_tests t ON t.module_id = cm.id
     LEFT JOIN course_module_test_questions q ON q.test_id = t.id
     LEFT JOIN course_module_test_attempts a
       ON a.test_id = t.id AND a.user_id = ?
     WHERE cm.course_id = ?
     GROUP BY cm.id, cm.title, t.id, t.title, t.passing_score,
              a.id, a.status, a.score, a.is_passed
     ORDER BY cm.order_sequence ASC, cm.id ASC`,
    [userId, userId, courseId]
  );
  return rows;
}

function isPassed(value: unknown): boolean {
  return value === true || Number(value) === 1;
}

export function computeCourseModuleGates(
  modules: CourseModuleProgressRow[]
): Map<number, CourseModuleGate> {
  const gates = new Map<number, CourseModuleGate>();
  let priorModulesComplete = true;
  let firstBlocker: string | null = null;

  for (const module of modules) {
    const moduleId = Number(module.module_id);
    const totalVideos = Number(module.total_videos) || 0;
    const completedVideos = Number(module.completed_videos) || 0;
    const videosComplete = completedVideos >= totalVideos;
    const hasTest = Number(module.test_id) > 0 && Number(module.question_count) > 0;
    const testPassed = isPassed(module.is_passed);
    const attemptStatus = module.attempt_status || null;
    const isUnlocked = priorModulesComplete;
    const canResumeTest = attemptStatus === 'in_progress';
    const canTakeTest =
      isUnlocked &&
      videosComplete &&
      hasTest &&
      attemptStatus !== 'submitted';

    let lockReason: string | null = null;
    if (!isUnlocked) {
      lockReason = firstBlocker ?? 'Pass the previous module test to unlock this module.';
    } else if (!videosComplete) {
      lockReason = `Complete all ${totalVideos} video lessons in this module to unlock its test.`;
    } else if (!hasTest) {
      lockReason = 'This module test has not been configured yet.';
    }

    let testLockReason: string | null = null;
    if (!isUnlocked) {
      testLockReason = lockReason;
    } else if (!videosComplete) {
      testLockReason = lockReason;
    } else if (!hasTest) {
      testLockReason = lockReason;
    } else if (attemptStatus === 'submitted' && !testPassed) {
      testLockReason =
        'Your one attempt was not passed. Contact your course manager for help.';
    } else if (!testPassed && !canResumeTest) {
      testLockReason = 'Pass this module test to unlock the next module.';
    }

    gates.set(moduleId, {
      moduleId,
      isUnlocked,
      videosComplete,
      hasTest,
      testPassed,
      canTakeTest,
      canResumeTest,
      attemptStatus,
      score: module.score == null ? null : Number(module.score),
      lockReason,
      testLockReason,
    });

    const moduleComplete = videosComplete && hasTest && testPassed;
    if (priorModulesComplete && !moduleComplete) {
      if (!videosComplete) {
        firstBlocker = `Complete the videos in "${module.module_title}" to continue.`;
      } else if (!hasTest) {
        firstBlocker = `A test must be configured for "${module.module_title}" before continuing.`;
      } else {
        firstBlocker = `Pass the test for "${module.module_title}" to continue.`;
      }
    }
    priorModulesComplete = priorModulesComplete && moduleComplete;
  }

  return gates;
}

export function parseJsonValue(value: unknown): unknown {
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function normalizedText(value: unknown): string {
  return String(value ?? '')
    .trim()
    .replace(/\s+/g, ' ')
    .toLocaleLowerCase();
}

function answerList(value: unknown): string[] {
  const parsed = parseJsonValue(value);
  const values = Array.isArray(parsed) ? parsed : [parsed];
  return values.map(normalizedText).filter(Boolean).sort();
}

export function gradeCourseModuleTest(
  questions: CourseModuleQuestion[],
  answers: Record<string, unknown>,
  passingScore: number
): { score: number; totalMarks: number; percentage: number; passed: boolean } {
  let score = 0;
  let totalMarks = 0;

  for (const question of questions) {
    const marks = Number(question.marks);
    if (!Number.isFinite(marks) || marks <= 0) {
      throw new Error('Question marks must be a positive number.');
    }
    totalMarks += marks;

    const submitted = answers[String(question.id)];
    const expected = question.correct_answer;
    const correct =
      question.question_type === 'multiple_choice'
        ? JSON.stringify(answerList(submitted)) ===
          JSON.stringify(answerList(expected))
        : normalizedText(submitted) === normalizedText(expected);
    if (correct) score += marks;
  }

  const percentage = totalMarks === 0 ? 0 : (score / totalMarks) * 100;
  return {
    score,
    totalMarks,
    percentage,
    passed: percentage >= passingScore,
  };
}

export async function ensureCourseModuleTestTables(): Promise<void> {
  await pool.query(`CREATE TABLE IF NOT EXISTS course_module_tests (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    module_id BIGINT UNSIGNED NOT NULL,
    title VARCHAR(255) NOT NULL,
    instructions TEXT NULL,
    passing_score TINYINT UNSIGNED NOT NULL DEFAULT 60,
    created_by BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY course_module_tests_module_unique (module_id),
    CONSTRAINT course_module_tests_module_fk FOREIGN KEY (module_id)
      REFERENCES course_modules (id) ON DELETE CASCADE,
    CONSTRAINT course_module_tests_author_fk FOREIGN KEY (created_by)
      REFERENCES users (id) ON DELETE RESTRICT
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`);

  await pool.query(`CREATE TABLE IF NOT EXISTS course_module_test_questions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    test_id BIGINT UNSIGNED NOT NULL,
    question_text TEXT NOT NULL,
    question_type ENUM('single_choice', 'multiple_choice', 'short_answer') NOT NULL,
    options JSON NULL,
    correct_answer JSON NOT NULL,
    marks DECIMAL(8,2) NOT NULL DEFAULT 1,
    order_sequence INT UNSIGNED NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY course_module_test_questions_order_idx (test_id, order_sequence, id),
    CONSTRAINT course_module_test_questions_test_fk FOREIGN KEY (test_id)
      REFERENCES course_module_tests (id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`);

  await pool.query(`CREATE TABLE IF NOT EXISTS course_module_test_attempts (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    test_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    status ENUM('in_progress', 'submitted') NOT NULL DEFAULT 'in_progress',
    score DECIMAL(8,2) NULL,
    total_marks DECIMAL(8,2) NULL,
    is_passed TINYINT(1) NULL,
    answers JSON NULL,
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    submitted_at TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY course_module_test_attempts_user_unique (test_id, user_id),
    CONSTRAINT course_module_test_attempts_test_fk FOREIGN KEY (test_id)
      REFERENCES course_module_tests (id) ON DELETE CASCADE,
    CONSTRAINT course_module_test_attempts_user_fk FOREIGN KEY (user_id)
      REFERENCES users (id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`);
}
