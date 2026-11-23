import path from 'path';
import { pool } from '../config/db.js';
import {
  computeCourseModuleGates,
  getCourseModuleProgress,
} from './courseModuleTests.js';

type Lesson = {
  id: number;
  title: string;
  is_completed?: number | boolean;
};

export const VIDEO_COMPLETION_END_TOLERANCE_SECONDS = 2;

export function isVideoWatchComplete(
  durationSeconds: number,
  minWatchPercentage: number,
  totalWatchedSeconds: number,
  lastPositionSeconds: number,
  isCompleted: number | boolean = false
): boolean {
  if (Number(isCompleted) === 1) return true;
  if (
    !Number.isFinite(durationSeconds) ||
    durationSeconds <= 0 ||
    !Number.isFinite(minWatchPercentage) ||
    minWatchPercentage <= 0 ||
    !Number.isFinite(totalWatchedSeconds) ||
    totalWatchedSeconds < 0 ||
    !Number.isFinite(lastPositionSeconds) ||
    lastPositionSeconds < 0
  ) {
    return false;
  }

  const requiredWatchedSeconds = durationSeconds * minWatchPercentage / 100;
  const completionPercentage = Math.min(
    100,
    Math.round((totalWatchedSeconds / durationSeconds) * 10000) / 100
  );
  if (completionPercentage >= minWatchPercentage) return true;
  if (minWatchPercentage !== 100) return false;

  const tolerance = Math.min(
    VIDEO_COMPLETION_END_TOLERANCE_SECONDS,
    durationSeconds * 0.02
  );
  return totalWatchedSeconds >= requiredWatchedSeconds - tolerance &&
    lastPositionSeconds >= durationSeconds - tolerance;
}

export async function reconcileNearCompleteVideoLogs(
  userId: number,
  courseId: number
): Promise<boolean> {
  const tolerance = `LEAST(${VIDEO_COMPLETION_END_TOLERANCE_SECONDS}, v.duration_seconds * 0.02)`;
  const [result]: any = await pool.query(
    `UPDATE video_watch_logs vwl
     JOIN videos v ON v.id = vwl.video_id
     JOIN course_modules cm ON cm.id = v.module_id
     SET vwl.is_completed = 1,
         vwl.completion_percentage = 100,
         vwl.updated_at = NOW()
     WHERE vwl.user_id = ?
       AND cm.course_id = ?
       AND vwl.is_completed = 0
       AND v.min_watch_percentage = 100
       AND v.duration_seconds > 0
       AND vwl.total_watched_seconds >= v.duration_seconds - ${tolerance}
       AND vwl.last_position_seconds >= v.duration_seconds - ${tolerance}`,
    [userId, courseId]
  );

  if (result.affectedRows === 0) return false;

  await pool.query(
    `INSERT INTO learning_progress
       (user_id, course_id, module_id, item_type, item_id, is_completed, completed_at, created_at, updated_at)
     SELECT vwl.user_id, cm.course_id, cm.id, 'video', v.id, 1, NOW(), NOW(), NOW()
     FROM video_watch_logs vwl
     JOIN videos v ON v.id = vwl.video_id
     JOIN course_modules cm ON cm.id = v.module_id
     WHERE vwl.user_id = ?
       AND cm.course_id = ?
       AND vwl.is_completed = 1
       AND v.min_watch_percentage = 100
       AND v.duration_seconds > 0
       AND vwl.total_watched_seconds >= v.duration_seconds - ${tolerance}
       AND vwl.last_position_seconds >= v.duration_seconds - ${tolerance}
     ON DUPLICATE KEY UPDATE
       is_completed = 1,
       completed_at = COALESCE(completed_at, NOW()),
       updated_at = NOW()`,
    [userId, courseId]
  );
  return true;
}

export function applySequentialAccess<T extends Lesson>(videos: T[]) {
  let firstIncomplete: T | undefined;
  return videos.map((video) => {
    const completed = Number(video.is_completed) === 1;
    const unlocked = completed || firstIncomplete === undefined;
    const lesson = {
      ...video,
      is_unlocked: unlocked,
      required_video_id: unlocked ? null : firstIncomplete!.id,
      required_video_title: unlocked ? null : firstIncomplete!.title,
    };
    if (!completed && firstIncomplete === undefined) firstIncomplete = video;
    return lesson;
  });
}

type ModuleWithVideos<T extends Lesson> = {
  id: number | string;
  videos: T[];
};

export function applyModuleSequentialVideoAccess<T extends Lesson>(
  modules: ModuleWithVideos<T>[],
  gates: ReturnType<typeof computeCourseModuleGates>
): Array<ModuleWithVideos<T> & { videos: Array<T & Record<string, unknown>> }> {
  return modules.map((module) => {
    const moduleId = Number(module.id);
    const gate = gates.get(moduleId);
    const videos = applySequentialAccess(module.videos).map((video) => {
      const completed = Number(video.is_completed) === 1;
      const isUnlocked =
        completed || (gate?.isUnlocked === true && video.is_unlocked === true);
      const blockedByModule = gate?.isUnlocked !== true && !completed;
      return {
        ...video,
        is_unlocked: isUnlocked,
        required_video_id: isUnlocked || blockedByModule
          ? null
          : video.required_video_id,
        required_video_title: isUnlocked || blockedByModule
          ? null
          : video.required_video_title,
        required_unlock_reason: isUnlocked
          ? null
          : blockedByModule
            ? gate?.lockReason ?? 'Pass the previous module test to unlock this module.'
            : `Complete ${video.required_video_title ?? 'the previous video'} to unlock this lesson.`,
      };
    });
    return { ...module, videos };
  });
}

export async function getVideoAccess(userId: number, videoId: number) {
  const [rows]: any = await pool.query(
    `SELECT v.*, cm.course_id
     FROM videos v
     JOIN course_modules cm ON cm.id = v.module_id
     JOIN courses c ON c.id = cm.course_id AND c.is_published = 1
     JOIN intern_profiles ip ON ip.department_id = c.department_id AND ip.user_id = ?
     WHERE v.id = ?
       AND EXISTS (
         SELECT 1 FROM course_assignments ca
         WHERE ca.course_id = c.id AND ca.user_id = ip.user_id
       )`,
    [userId, videoId]
  );
  if (rows.length === 0) return null;
  const loadCourseVideos = () => pool.query(
    `SELECT v.id, v.title, v.module_id, COALESCE(vwl.is_completed, 0) AS is_completed
     FROM videos v
     JOIN course_modules cm ON cm.id = v.module_id
     LEFT JOIN video_watch_logs vwl ON vwl.video_id = v.id AND vwl.user_id = ?
     WHERE cm.course_id = ?
     ORDER BY cm.order_sequence ASC, cm.id ASC, v.order_sequence ASC, v.id ASC`,
    [userId, rows[0].course_id]
  );
  const loadAccess = async () => {
    const [videoResult, moduleProgress] = await Promise.all([
      loadCourseVideos(),
      getCourseModuleProgress(userId, Number(rows[0].course_id)),
    ]);
    const [videos] = videoResult as [any[], unknown];
    const gates = computeCourseModuleGates(moduleProgress);
    const modules = moduleProgress.map((module) => ({
      id: module.module_id,
      videos: videos.filter(
        (video: any) => Number(video.module_id) === Number(module.module_id)
      ),
    }));
    return applyModuleSequentialVideoAccess(modules, gates)
      .flatMap((module) => module.videos)
      .find((video) => Number(video.id) === videoId);
  };
  let access = await loadAccess();
  if (access && !access.is_unlocked &&
      await reconcileNearCompleteVideoLogs(userId, Number(rows[0].course_id))) {
    access = await loadAccess();
  }
  return access ? { ...rows[0], ...access } : null;
}

export function resolveVideoUploadPath(videoPath: string): string | null {
  if (!videoPath.startsWith('/uploads/')) return null;
  const root = path.resolve('uploads');
  const file = path.resolve(root, decodeURIComponent(videoPath.slice('/uploads/'.length)));
  const relative = path.relative(root, file);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative) || relative.includes('\0')) {
    throw new Error('Invalid video upload path');
  }
  return file;
}
