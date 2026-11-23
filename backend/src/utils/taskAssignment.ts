import { pool } from '../config/db.js';

export async function ensureTaskAssignmentsTable(): Promise<void> {
  await pool.query(`CREATE TABLE IF NOT EXISTS task_assignments (
    task_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    assigned_by BIGINT UNSIGNED DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (task_id, user_id),
    KEY task_assignments_user_id_idx (user_id),
    CONSTRAINT task_assignments_task_fk FOREIGN KEY (task_id)
      REFERENCES tasks (id) ON DELETE CASCADE,
    CONSTRAINT task_assignments_user_fk FOREIGN KEY (user_id)
      REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT task_assignments_assigned_by_fk FOREIGN KEY (assigned_by)
      REFERENCES users (id) ON DELETE SET NULL
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`);
}
