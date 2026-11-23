import assert from 'node:assert/strict';
import test from 'node:test';
import {
  computeCourseModuleGates,
  CourseModuleProgressRow,
  gradeCourseModuleTest,
} from './courseModuleTests.js';

function moduleProgress(
  overrides: Partial<CourseModuleProgressRow> = {}
): CourseModuleProgressRow {
  return {
    module_id: 1,
    module_title: 'Module 1',
    total_videos: 1,
    completed_videos: 0,
    test_id: 10,
    test_title: 'Module 1 Test',
    passing_score: 60,
    question_count: 1,
    attempt_id: null,
    attempt_status: null,
    score: null,
    is_passed: null,
    ...overrides,
  };
}

test('only the first module is unlocked before its videos and test are complete', () => {
  const gates = computeCourseModuleGates([
    moduleProgress(),
    moduleProgress({
      module_id: 2,
      module_title: 'Module 2',
      completed_videos: 1,
    }),
  ]);

  assert.equal(gates.get(1)?.isUnlocked, true);
  assert.equal(gates.get(1)?.canTakeTest, false);
  assert.equal(gates.get(2)?.isUnlocked, false);
  assert.match(gates.get(2)?.lockReason ?? '', /Module 1/);
});

test('a configured test is available only after all module videos are complete', () => {
  const gates = computeCourseModuleGates([
    moduleProgress({ completed_videos: 1 }),
  ]);

  assert.equal(gates.get(1)?.canTakeTest, true);
  assert.equal(gates.get(1)?.testPassed, false);
});

test('a missing module test keeps every later module locked', () => {
  const gates = computeCourseModuleGates([
    moduleProgress({
      test_id: null,
      test_title: null,
      passing_score: null,
      question_count: 0,
      completed_videos: 1,
    }),
    moduleProgress({
      module_id: 2,
      module_title: 'Module 2',
      completed_videos: 1,
    }),
  ]);

  assert.equal(gates.get(2)?.isUnlocked, false);
  assert.match(gates.get(2)?.lockReason ?? '', /test must be configured/i);
});

test('passing a module test unlocks the following module', () => {
  const gates = computeCourseModuleGates([
    moduleProgress({
      completed_videos: 1,
      attempt_status: 'submitted',
      is_passed: 1,
    }),
    moduleProgress({
      module_id: 2,
      module_title: 'Module 2',
      completed_videos: 0,
    }),
  ]);

  assert.equal(gates.get(2)?.isUnlocked, true);
});

test('a submitted failed attempt keeps following modules locked', () => {
  const gates = computeCourseModuleGates([
    moduleProgress({
      completed_videos: 1,
      attempt_status: 'submitted',
      is_passed: 0,
    }),
    moduleProgress({
      module_id: 2,
      module_title: 'Module 2',
      completed_videos: 1,
    }),
  ]);

  assert.equal(gates.get(1)?.canTakeTest, false);
  assert.equal(gates.get(2)?.isUnlocked, false);
});

test('test grading normalizes short answers and ignores multiple-choice order', () => {
  const result = gradeCourseModuleTest(
    [
      {
        id: 1,
        question_text: 'Short answer',
        question_type: 'short_answer',
        correct_answer: 'Course   Module',
        marks: 2,
      },
      {
        id: 2,
        question_text: 'Multiple choice',
        question_type: 'multiple_choice',
        options: ['A', 'B', 'C'],
        correct_answer: ['A', 'C'],
        marks: 3,
      },
    ],
    {
      '1': '  COURSE Module ',
      '2': ['C', 'A'],
    },
    60
  );

  assert.equal(result.score, 5);
  assert.equal(result.totalMarks, 5);
  assert.equal(result.percentage, 100);
  assert.equal(result.passed, true);
});

test('the configured passing threshold is applied to weighted marks', () => {
  const result = gradeCourseModuleTest(
    [
      {
        id: 1,
        question_text: 'Question 1',
        question_type: 'single_choice',
        options: ['yes', 'no'],
        correct_answer: 'yes',
        marks: 3,
      },
      {
        id: 2,
        question_text: 'Question 2',
        question_type: 'short_answer',
        correct_answer: 'right',
        marks: 2,
      },
    ],
    { '1': 'yes', '2': 'wrong' },
    60
  );

  assert.equal(result.percentage, 60);
  assert.equal(result.passed, true);
});
