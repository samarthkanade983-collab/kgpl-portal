-- Demo data for the testing package.
-- No employee or intern personal records are included: only the HR sign-in
-- account and two departments so the portal can be explored immediately.

INSERT INTO departments (name, code, description, is_active, created_at, updated_at) VALUES
  ('Hr', 'HR', 'People operations', 1, NOW(), NOW()),
  ('It Infrastructure', 'IT-INFRA', 'Systems and network infrastructure', 1, NOW(), NOW())
ON DUPLICATE KEY UPDATE name = VALUES(name), is_active = 1;

INSERT INTO users (name, email, password, role, is_active, created_at, updated_at) VALUES
  ('HR Administrator', 'hr@kgpl.com', '$2a$10$9axLxCdh//lHvhBRcEGzw.nIUNe1PMUbAW0tiQaxd2SRyKPMvbZzi', 'hr_admin', 1, NOW(), NOW())
ON DUPLICATE KEY UPDATE password = VALUES(password), role = 'hr_admin', is_active = 1, deleted_at = NULL;
