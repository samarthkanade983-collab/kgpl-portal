import { Response } from 'express';
import { pool } from '../config/db.js';
import { AuthenticatedRequest } from '../middleware/auth.js';
import {
  computeCourseModuleGates,
  CourseModuleQuestion,
  CourseModuleQuestionType,
  getCourseModuleProgress,
  gradeCourseModuleTest,
  parseJsonValue,
} from '../utils/courseModuleTests.js';

const QUESTION_TYPES = new Set<CourseModuleQuestionType>([
  'single_choice',
  'multiple_choice',
  'short_answer',
]);

type NormalizedQuestion = Omit<CourseModuleQuestion, 'options'> & {
  options: string[] | null;
};

function parseId(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

function normalizeQuestions(value: unknown): NormalizedQuestion[] | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > 100) {
    return null;
  }

  const questions: NormalizedQuestion[] = [];
  for (const raw of value) {
    if (!raw || typeof raw !== 'object') return null;
    const item = raw as Record<string, unknown>;
    const questionText =
      typeof item.question_text === 'string' ? item.question_text.trim() : '';
    const type = item.question_type as CourseModuleQuestionType;
    const marks = Number(item.marks);
    if (
      !questionText ||
      questionText.length > 4000 ||
      !QUESTION_TYPES.has(type) ||
      !Number.isFinite(marks) ||
      marks <= 0 ||
      marks > 100
    ) {
      return null;
    }

    if (type === 'short_answer') {
      const correct =
        typeof item.correct_answer === 'string'
          ? item.correct_answer.trim()
          : '';
      if (!correct || correct.length > 2000) return null;
      questions.push({
        question_text: questionText,
        question_type: type,
        options: null,
        correct_answer: correct,
        marks,
      });
      continue;
    }

    const options = Array.isArray(item.options)
      ? item.options
          .filter((option): option is string => typeof option === 'string')
          .map((option) => option.trim())
      : [];
    if (
      options.length < 2 ||
      options.length > 20 ||
      options.some((option) => !option || option.length > 250) ||
      new Set(options.map((option) => option.toLocaleLowerCase())).size !==
        options.length
    ) {
      return null;
    }

    if (type === 'single_choice') {
      const correct =
        typeof item.correct_answer === 'string'
          ? item.correct_answer.trim()
          : '';
      if (!options.includes(correct)) return null;
      questions.push({
        question_text: questionText,
        question_type: type,
        options,
        correct_answer: correct,
        marks,
      });
      continue;
    }

    const correct = Array.isArray(item.correct_answer)
      ? item.correct_answer.filter(
          (answer): answer is string => typeof answer === 'string'
        )
      : [];
    const uniqueCorrect = [...new Set(correct.map((answer) => answer.trim()))];
    if (
      uniqueCorrect.length === 0 ||
      uniqueCorrect.some((answer) => !options.includes(answer))
    ) {
      return null;
    }
    questions.push({
      question_text: questionText,
      question_type: type,
      options,
      correct_answer: uniqueCorrect,
      marks,
    });
  }

  return questions;
}

function publicQuestion(question: any): Record<string, unknown> {
  return {
    id: Number(question.id),
    question_text: question.question_text,
    question_type: question.question_type,
    options: parseJsonValue(question.options) ?? [],
    marks: Number(question.marks),
  };
}

async function loadInternTestContext(
  executor: { query: (...args: any[]) => Promise<any> },
  testId: number,
  userId: number
): Promise<any | null> {
  const [rows]: any = await executor.query(
    `SELECT t.id, t.module_id, t.title, t.instructions, t.passing_score,
            cm.title AS module_title, cm.course_id,
            c.department_id
     FROM course_module_tests t
     JOIN course_modules cm ON cm.id = t.module_id
     JOIN courses c ON c.id = cm.course_id
     JOIN intern_profiles ip
       ON ip.user_id = ? AND ip.department_id = c.department_id
     JOIN course_assignments ca
       ON ca.course_id = c.id AND ca.user_id = ip.user_id
     WHERE t.id = ? AND c.is_published = 1
     LIMIT 1`,
    [userId, testId]
  );
  return rows[0] ?? null;
}

function validateSubmittedAnswers(
  questions: CourseModuleQuestion[],
  rawAnswers: unknown
): Record<string, unknown> | null {
  if (!rawAnswers || typeof rawAnswers !== 'object' || Array.isArray(rawAnswers)) {
    return null;
  }
  const submitted = rawAnswers as Record<string, unknown>;
  const answers: Record<string, unknown> = {};

  for (const question of questions) {
    const id = String(question.id);
    const answer = submitted[id];
    if (question.question_type === 'multiple_choice') {
      if (
        !Array.isArray(answer) ||
        answer.length === 0 ||
        answer.length > 20 ||
        answer.some((value) => typeof value !== 'string')
      ) {
        return null;
      }
      const options = question.options ?? [];
      const selected = answer as string[];
      if (
        selected.some((value) => !options.includes(value)) ||
        new Set(selected).size !== selected.length
      ) {
        return null;
      }
      answers[id] = selected;
    } else {
      if (typeof answer !== 'string' || !answer.trim() || answer.length > 2000) {
        return null;
      }
      if (
        question.question_type === 'single_choice' &&
        !(question.options ?? []).includes(answer)
      ) {
        return null;
      }
      answers[id] = answer;
    }
  }
  return answers;
}

export async function getModuleTestForAuthoring(
  req: AuthenticatedRequest,
  res: Response
): Promise<void> {
  const moduleId = parseId(req.params.moduleId);
  if (!moduleId) {
    res.status(400).json({ error: 'A valid module id is required.' });
    return;
  }

  try {
    const [modules]: any = await pool.query(
      'SELECT id, title FROM course_modules WHERE id = ?',
      [moduleId]
    );
    if (modules.length === 0) {
      res.status(404).json({ error: 'Course module not found.' });
      return;
    }

    const [tests]: any = await pool.query(
      `SELECT t.*,
              (SELECT COUNT(*) FROM course_module_test_attempts a
               WHERE a.test_id = t.id) AS attempt_count
       FROM course_module_tests t
       WHERE t.module_id = ?
       LIMIT 1`,
      [moduleId]
    );
    if (tests.length === 0) {
      res.json({ test: null, module: modules[0] });
      return;
    }

    const [questions]: any = await pool.query(
      `SELECT id, question_text, question_type, options, correct_answer, marks
       FROM course_module_test_questions
       WHERE test_id = ?
       ORDER BY order_sequence ASC, id ASC`,
      [tests[0].id]
    );
    res.json({
      module: modules[0],
      test: {
        ...tests[0],
        questions: questions.map((question: any) => ({
          ...question,
          options: parseJsonValue(question.options) ?? [],
          correct_answer: parseJsonValue(question.correct_answer),
        })),
      },
    });
  } catch (error) {
    console.error('Get course module test error:', error);
    res.status(500).json({ error: 'Failed to load this module test.' });
  }
}

export async function saveModuleTest(
  req: AuthenticatedRequest,
  res: Response
): Promise<void> {
  const moduleId = parseId(req.params.moduleId);
  const title = typeof req.body?.title === 'string' ? req.body.title.trim() : '';
  const instructions =
    typeof req.body?.instructions === 'string'
      ? req.body.instructions.trim()
      : '';
  const passingScore = Number(req.body?.passing_score ?? 60);
  const questions = normalizeQuestions(req.body?.questions);

  if (
    !moduleId ||
    !title ||
    title.length > 255 ||
    instructions.length > 5000 ||
    !Number.isInteger(passingScore) ||
    passingScore < 1 ||
    passingScore > 100 ||
    !questions
  ) {
    res.status(400).json({
      error:
        'Provide a test title, passing score from 1 to 100, and at least one valid question.',
    });
    return;
  }

  const connection = await pool.getConnection();
  let testId: number | null = null;
  try {
    await connection.beginTransaction();
    const [modules]: any = await connection.query(
      'SELECT id FROM course_modules WHERE id = ? FOR UPDATE',
      [moduleId]
    );
    if (modules.length === 0) {
      await connection.rollback();
      res.status(404).json({ error: 'Course module not found.' });
      return;
    }

    const [existingTests]: any = await connection.query(
      'SELECT id FROM course_module_tests WHERE module_id = ? FOR UPDATE',
      [moduleId]
    );
    const existingTestId = existingTests[0]?.id;
    if (existingTestId) {
      testId = Number(existingTestId);
      const [attempts]: any = await connection.query(
        'SELECT id FROM course_module_test_attempts WHERE test_id = ? LIMIT 1 FOR UPDATE',
        [existingTestId]
      );
      if (attempts.length > 0) {
        await connection.rollback();
        res.status(409).json({
          error:
            'This test already has an intern attempt and cannot be changed.',
        });
        return;
      }
      await connection.query(
        `UPDATE course_module_tests
         SET title = ?, instructions = ?, passing_score = ?, created_by = ?
         WHERE id = ?`,
        [title, instructions || null, passingScore, req.user!.id, existingTestId]
      );
      await connection.query(
        'DELETE FROM course_module_test_questions WHERE test_id = ?',
        [existingTestId]
      );
    } else {
      const [result]: any = await connection.query(
        `INSERT INTO course_module_tests
           (module_id, title, instructions, passing_score, created_by)
         VALUES (?, ?, ?, ?, ?)`,
        [moduleId, title, instructions || null, passingScore, req.user!.id]
      );
      testId = Number(result.insertId);
    }

    for (const [index, question] of questions.entries()) {
      await connection.query(
        `INSERT INTO course_module_test_questions
           (test_id, question_text, question_type, options, correct_answer, marks, order_sequence)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [
          testId,
          question.question_text,
          question.question_type,
          question.options ? JSON.stringify(question.options) : null,
          JSON.stringify(question.correct_answer),
          question.marks,
          index + 1,
        ]
      );
    }

    if (testId == null) {
      throw new Error('Could not allocate an id for the course module test.');
    }
    await connection.commit();
    res.json({ message: 'Module test saved.', test_id: testId });
  } catch (error: any) {
    await connection.rollback();
    if (error?.code === 'ER_DUP_ENTRY') {
      res.status(409).json({ error: 'A test already exists for this module.' });
      return;
    }
    console.error('Save course module test error:', error);
    res.status(500).json({ error: 'Failed to save this module test.' });
  } finally {
    connection.release();
  }
}

export async function startInternModuleTest(
  req: AuthenticatedRequest,
  res: Response
): Promise<void> {
  const userId = req.user!.id;
  const testId = parseId(req.params.testId);
  if (!testId) {
    res.status(400).json({ error: 'A valid module test id is required.' });
    return;
  }

  try {
    const test = await loadInternTestContext(pool, testId, userId);
    if (!test) {
      res.status(404).json({ error: 'Module test not found for this intern.' });
      return;
    }
    const gates = computeCourseModuleGates(
      await getCourseModuleProgress(userId, Number(test.course_id))
    );
    const gate = gates.get(Number(test.module_id));
    if (!gate?.isUnlocked || !gate.videosComplete || !gate.hasTest) {
      res.status(409).json({
        error: gate?.lockReason ?? 'Complete the previous module before starting this test.',
      });
      return;
    }

    const [questions]: any = await pool.query(
      `SELECT id, question_text, question_type, options, marks
       FROM course_module_test_questions
       WHERE test_id = ?
       ORDER BY order_sequence ASC, id ASC`,
      [testId]
    );
    if (questions.length === 0) {
      res.status(409).json({ error: 'This module test has no questions yet.' });
      return;
    }

    const [existingAttempts]: any = await pool.query(
      `SELECT id, status, score, total_marks, is_passed, started_at, submitted_at
       FROM course_module_test_attempts
       WHERE test_id = ? AND user_id = ?
       LIMIT 1`,
      [testId, userId]
    );
    if (existingAttempts[0]?.status === 'submitted') {
      res.status(409).json({
        error: 'Your one attempt for this module test has already been submitted.',
        attempt: existingAttempts[0],
      });
      return;
    }

    if (existingAttempts.length === 0) {
      try {
        await pool.query(
          `INSERT INTO course_module_test_attempts (test_id, user_id, status)
           VALUES (?, ?, 'in_progress')`,
          [testId, userId]
        );
      } catch (error: any) {
        if (error?.code !== 'ER_DUP_ENTRY') throw error;
      }
    }

    const [attempts]: any = await pool.query(
      `SELECT id, status, score, total_marks, is_passed, started_at, submitted_at
       FROM course_module_test_attempts
       WHERE test_id = ? AND user_id = ?
       LIMIT 1`,
      [testId, userId]
    );
    if (attempts[0]?.status !== 'in_progress') {
      res.status(409).json({
        error: 'Your one attempt for this module test has already been submitted.',
        attempt: attempts[0],
      });
      return;
    }

    res.json({
      test: {
        id: Number(test.id),
        module_id: Number(test.module_id),
        title: test.title,
        instructions: test.instructions,
        passing_score: Number(test.passing_score),
        attempt: attempts[0],
        questions: questions.map(publicQuestion),
      },
    });
  } catch (error) {
    console.error('Start course module test error:', error);
    res.status(500).json({ error: 'Failed to start this module test.' });
  }
}

export async function submitInternModuleTest(
  req: AuthenticatedRequest,
  res: Response
): Promise<void> {
  const userId = req.user!.id;
  const testId = parseId(req.params.testId);
  if (!testId) {
    res.status(400).json({ error: 'A valid module test id is required.' });
    return;
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const test = await loadInternTestContext(connection, testId, userId);
    if (!test) {
      await connection.rollback();
      res.status(404).json({ error: 'Module test not found for this intern.' });
      return;
    }

    const [attempts]: any = await connection.query(
      `SELECT id, status
       FROM course_module_test_attempts
       WHERE test_id = ? AND user_id = ?
       LIMIT 1 FOR UPDATE`,
      [testId, userId]
    );
    const attempt = attempts[0];
    if (!attempt) {
      await connection.rollback();
      res.status(409).json({ error: 'Start this test before submitting answers.' });
      return;
    }
    if (attempt.status !== 'in_progress') {
      await connection.rollback();
      res.status(409).json({ error: 'This one-attempt test has already been submitted.' });
      return;
    }

    const gates = computeCourseModuleGates(
      await getCourseModuleProgress(userId, Number(test.course_id))
    );
    const gate = gates.get(Number(test.module_id));
    if (!gate?.isUnlocked || !gate.videosComplete || !gate.hasTest) {
      await connection.rollback();
      res.status(409).json({
        error: gate?.lockReason ?? 'Complete the previous module before submitting this test.',
      });
      return;
    }

    const [questions]: any = await connection.query(
      `SELECT id, question_text, question_type, options, correct_answer, marks
       FROM course_module_test_questions
       WHERE test_id = ?
       ORDER BY order_sequence ASC, id ASC`,
      [testId]
    );
    const normalizedQuestions: CourseModuleQuestion[] = questions.map(
      (question: any) => ({
        ...question,
        id: Number(question.id),
        options: (parseJsonValue(question.options) as string[] | null) ?? [],
        correct_answer: parseJsonValue(question.correct_answer) as
          | string
          | string[],
        marks: Number(question.marks),
      })
    );
    const answers = validateSubmittedAnswers(
      normalizedQuestions,
      req.body?.answers
    );
    if (!answers) {
      await connection.rollback();
      res.status(400).json({
        error: 'Answer every question using one of its provided options.',
      });
      return;
    }

    const result = gradeCourseModuleTest(
      normalizedQuestions,
      answers,
      Number(test.passing_score)
    );
    const [updateResult]: any = await connection.query(
      `UPDATE course_module_test_attempts
       SET status = 'submitted', score = ?, total_marks = ?, is_passed = ?,
           answers = ?, submitted_at = NOW()
       WHERE id = ? AND status = 'in_progress'`,
      [
        result.score,
        result.totalMarks,
        result.passed ? 1 : 0,
        JSON.stringify(answers),
        attempt.id,
      ]
    );
    if (updateResult.affectedRows !== 1) {
      await connection.rollback();
      res.status(409).json({ error: 'This test attempt was already submitted.' });
      return;
    }
    await connection.commit();

    const updatedProgress = await getCourseModuleProgress(
      userId,
      Number(test.course_id)
    );
    const updatedGates = computeCourseModuleGates(updatedProgress);
    const moduleIndex = updatedProgress.findIndex(
      (module) => Number(module.module_id) === Number(test.module_id)
    );
    const nextModuleId =
      moduleIndex >= 0 ? updatedProgress[moduleIndex + 1]?.module_id : null;
    const nextModuleUnlocked =
      nextModuleId == null
        ? false
        : updatedGates.get(Number(nextModuleId))?.isUnlocked ?? false;
    res.json({
      message: result.passed
        ? nextModuleUnlocked
          ? 'Module test passed. The next module is now unlocked.'
          : 'Module test passed.'
        : 'Module test not passed. Contact your course manager for help.',
      score: result.score,
      total_marks: result.totalMarks,
      percentage: Math.round(result.percentage * 100) / 100,
      passed: result.passed,
      next_module_unlocked: nextModuleUnlocked,
    });
  } catch (error) {
    await connection.rollback();
    console.error('Submit course module test error:', error);
    res.status(500).json({ error: 'Failed to submit this module test.' });
  } finally {
    connection.release();
  }
}
