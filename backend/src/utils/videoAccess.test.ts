import assert from 'node:assert/strict';
import test from 'node:test';
import {
  applyModuleSequentialVideoAccess,
  applySequentialAccess,
  isVideoWatchComplete,
} from './videoAccess.js';
import {
  computeCourseModuleGates,
  CourseModuleProgressRow,
} from './courseModuleTests.js';

test('only the next unfinished lesson unlocks in a 10-video course', () => {
  for (let completedCount = 0; completedCount <= 10; completedCount += 1) {
    const lessons = Array.from({ length: 10 }, (_, index) => ({
      id: index + 1,
      title: `Lesson ${index + 1}`,
      is_completed: index < completedCount ? 1 : 0,
    }));

    const access = applySequentialAccess(lessons);
    for (let index = 0; index < access.length; index += 1) {
      assert.equal(
        access[index].is_unlocked,
        index <= completedCount,
        `lesson ${index + 1} with ${completedCount} completed`
      );
    }
  }
});

test('a 100% lesson completes when playback is at the end within duration tolerance', () => {
  assert.equal(isVideoWatchComplete(136, 100, 135.39, 135.39), true);
});

test('a 100% lesson does not complete before playback reaches the end', () => {
  assert.equal(isVideoWatchComplete(136, 100, 135.39, 133), false);
});

test('a 100% lesson still requires watched time within the end tolerance', () => {
  assert.equal(isVideoWatchComplete(136, 100, 132, 135.39), false);
});

test('lower watch thresholds retain their configured requirement', () => {
  assert.equal(isVideoWatchComplete(100, 80, 79, 99), false);
  assert.equal(isVideoWatchComplete(100, 80, 80, 80), true);
});

test('video authorization keeps the next module locked until its test is passed', () => {
  const moduleProgress: CourseModuleProgressRow[] = [
    {
      module_id: 11,
      module_title: 'Module 1',
      total_videos: 1,
      completed_videos: 1,
      test_id: 21,
      test_title: 'Module 1 Test',
      passing_score: 60,
      question_count: 1,
      attempt_id: null,
      attempt_status: null,
      score: null,
      is_passed: null,
    },
    {
      module_id: 22,
      module_title: 'Module 2',
      total_videos: 1,
      completed_videos: 0,
      test_id: 23,
      test_title: 'Module 2 Test',
      passing_score: 60,
      question_count: 1,
      attempt_id: null,
      attempt_status: null,
      score: null,
      is_passed: null,
    },
  ];
  const modules = [
    {
      id: 11,
      videos: [{ id: 1, title: 'Lesson 1', is_completed: 1 }],
    },
    {
      id: 22,
      videos: [{ id: 2, title: 'Lesson 2', is_completed: 0 }],
    },
  ];
  const blocked = applyModuleSequentialVideoAccess(
    modules,
    computeCourseModuleGates(moduleProgress)
  );

  assert.equal(blocked[1].videos[0].is_unlocked, false);
  assert.match(
    String(blocked[1].videos[0].required_unlock_reason),
    /Module 1/
  );

  moduleProgress[0].attempt_status = 'submitted';
  moduleProgress[0].is_passed = 1;
  const unlocked = applyModuleSequentialVideoAccess(
    modules,
    computeCourseModuleGates(moduleProgress)
  );
  assert.equal(unlocked[1].videos[0].is_unlocked, true);
});

test('completed videos in a locked module remain available for rewatching', () => {
  const gates = computeCourseModuleGates([
    {
      module_id: 11,
      module_title: 'Module 1',
      total_videos: 1,
      completed_videos: 0,
      test_id: 21,
      test_title: 'Module 1 Test',
      passing_score: 60,
      question_count: 1,
      attempt_id: null,
      attempt_status: null,
      score: null,
      is_passed: null,
    },
    {
      module_id: 22,
      module_title: 'Module 2',
      total_videos: 1,
      completed_videos: 1,
      test_id: 23,
      test_title: 'Module 2 Test',
      passing_score: 60,
      question_count: 1,
      attempt_id: null,
      attempt_status: null,
      score: null,
      is_passed: null,
    },
  ]);
  const access = applyModuleSequentialVideoAccess(
    [
      { id: 11, videos: [{ id: 1, title: 'Lesson 1', is_completed: 0 }] },
      { id: 22, videos: [{ id: 2, title: 'Lesson 2', is_completed: 1 }] },
    ],
    gates
  );

  assert.equal(access[1].videos[0].is_unlocked, true);
});
