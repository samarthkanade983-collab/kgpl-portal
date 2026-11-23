import { pool } from '../config/db.js';

export interface CertificateFields {
  recipient_name: string;
  intern_code: string;
  department: string;
  body_text: string;
  signer_name: string;
  signer_title: string;
  organization: string;
  issue_date: string;
  serial: string;
}

export interface CertificateDefaults {
  recipientName: string;
  internCode: string;
  department: string;
  serial: string;
}

export type CertificateOverride = {
  [K in keyof CertificateFields]: string | null;
};

const DEFAULT_SIGNER_NAME = 'Sarah Jenkins';
const DEFAULT_SIGNER_TITLE = 'Head of Talent & Human Resources';
const DEFAULT_ORGANIZATION = 'KuhuGrantha Pvt Ltd';

export function buildDefaultCertificate(defaults: CertificateDefaults): CertificateFields {
  return {
    recipient_name: defaults.recipientName || '',
    intern_code: defaults.internCode || '',
    department: defaults.department || '',
    body_text:
      `for outstanding dedication and successfully fulfilling all curriculum requirements, ` +
      `practical assignments, interactive SOP certifications, and video training modules in the ` +
      `${defaults.department} Department.`,
    signer_name: DEFAULT_SIGNER_NAME,
    signer_title: DEFAULT_SIGNER_TITLE,
    organization: DEFAULT_ORGANIZATION,
    issue_date: new Date().toISOString().slice(0, 10),
    serial: defaults.serial,
  };
}

export function mergeCertificate(
  defaults: CertificateFields,
  override: Partial<CertificateOverride> | null | undefined
): CertificateFields {
  const merged = { ...defaults };
  if (!override) return merged;
  for (const key of Object.keys(defaults) as (keyof CertificateFields)[]) {
    const value = override[key];
    if (typeof value === 'string' && value.trim() !== '') {
      merged[key] = value.trim();
    }
  }
  return merged;
}

export async function ensureCertificateTable(): Promise<void> {
  await pool.query(`CREATE TABLE IF NOT EXISTS certificates (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    intern_user_id BIGINT UNSIGNED NOT NULL,
    recipient_name VARCHAR(100) DEFAULT NULL,
    intern_code VARCHAR(50) DEFAULT NULL,
    department VARCHAR(100) DEFAULT NULL,
    body_text TEXT,
    signer_name VARCHAR(100) DEFAULT NULL,
    signer_title VARCHAR(150) DEFAULT NULL,
    organization VARCHAR(150) DEFAULT NULL,
    issue_date DATE DEFAULT NULL,
    serial VARCHAR(100) DEFAULT NULL,
    updated_by BIGINT UNSIGNED DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY certificates_intern_user_id_unique (intern_user_id),
    CONSTRAINT certificates_intern_user_id_foreign FOREIGN KEY (intern_user_id)
      REFERENCES users (id) ON DELETE CASCADE
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`);
}

export async function getCertificateOverride(internUserId: number): Promise<CertificateOverride | null> {
  const [rows]: any = await pool.query(
    `SELECT recipient_name, intern_code, department, body_text, signer_name, signer_title,
            organization, DATE_FORMAT(issue_date, '%Y-%m-%d') AS issue_date, serial
     FROM certificates WHERE intern_user_id = ?`,
    [internUserId]
  );
  return rows.length > 0 ? (rows[0] as CertificateOverride) : null;
}

export function defaultSerial(internProfileId: number): string {
  return `KGPL-CERT-${new Date().getFullYear()}-${String(internProfileId).padStart(4, '0')}`;
}
