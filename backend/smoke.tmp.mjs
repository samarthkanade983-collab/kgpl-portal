import 'dotenv/config';
import jwt from 'jsonwebtoken';
const tok = (id, role) => jwt.sign({ id, role }, process.env.JWT_SECRET, { expiresIn: '1h', algorithm: 'HS256' });
const T = { hr: tok(78,'hr_admin'), tl: tok(80,'team_leader'), in: tok(81,'intern') };
const B = 'http://localhost:5001/api/v1';
const gets = {
  hr: ['/auth/me','/hr/dashboard','/hr/users','/hr/batches','/hr/departments','/hr/courses','/hr/courses/templates','/hr/courses/live-watch','/hr/announcements','/hr/reports','/hr/reports/export-csv','/hr/feedback','/hr/audit-logs','/hr/telemetry/nosql-usage','/tl/dashboard','/tl/interns','/tl/quizzes','/tl/schedules','/tl/quiz-results','/tl/tasks','/tl/sops','/intern/sops','/intern/ai-chat/history','/announcements','/notifications'],
  tl: ['/auth/me','/tl/dashboard','/tl/interns','/tl/interns/81','/tl/interns/82','/tl/quizzes','/tl/schedules','/tl/quiz-results','/tl/tasks','/tl/questions','/tl/sops','/hr/courses','/hr/batches','/hr/departments','/hr/courses/live-watch','/intern/sops','/announcements','/notifications'],
  in: ['/auth/me','/intern/dashboard','/intern/courses','/intern/tests','/intern/tasks','/intern/sops','/intern/questions','/intern/certificate','/intern/ai-chat/history','/announcements','/notifications'],
};
for (const [r, paths] of Object.entries(gets)) for (const p of paths) {
  const res = await fetch(B + p, { headers: { Authorization: 'Bearer ' + T[r] } });
  const body = await res.text();
  console.log(`${res.status} ${r.padEnd(2)} ${p}  ${res.ok ? body.length + 'b' : body.slice(0, 200)}`);
}
